#if os(macOS)
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Exports notes as a PDF: each note is laid out like reader mode (`NoteReaderText.build`) in the light appearance,
/// starts on a new page, and gets an outline entry when there are several.
///
/// Notes print in batches (`Batch`), each one print job holding up to `batchSize` notes, so a batch embeds its fonts
/// once and the main thread gets a moment between batches to update the progress sheet. The batches' files are then
/// merged into one document off the main thread.
enum NoteExport {
    /// Asks where to save, then writes the PDF. `name` is the suggested file name, without the extension.
    static func savePDF(_ notes: [Note], name: String, store: AppStore) {
        guard !notes.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = fileName(name)
        panel.title = notes.count == 1 ? "Export Note as PDF" : "Export \(notes.count) Notes as PDF"
        let window = NSApp.keyWindow
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await export(notes, to: url, store: store, window: window) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    /// Writes the PDF to `url`, showing a progress sheet with Cancel when it takes more than one batch.
    private static func export(_ notes: [Note], to url: URL, store: AppStore, window: NSWindow?) async {
        let known = Set(store.noteSummaries.map(\.id))
        let imageURL: (String) -> URL? = { name in
            if case .ready(let url) = store.sync.imageState(name) { url } else { nil }
        }
        let batches = batched(notes)
        let progress = batches.count > 1 ? ExportProgress(total: notes.count, window: window) : nil
        defer { progress?.close() }

        var parts: [Part] = []
        defer { for part in parts { try? FileManager.default.removeItem(at: part.file) } }
        var done = 0
        for batch in batches {
            if progress?.cancelled == true { return }
            guard let part = autoreleasepool(invoking: { printBatch(batch, imageURL: imageURL, isKnownNote: { known.contains($0) }) }) else {
                return fail(window)
            }
            parts.append(part)
            done += batch.count
            progress?.update(done: done)
            // Lets the run loop draw the sheet and handle Cancel before the next batch.
            try? await Task.sleep(for: .milliseconds(5))
        }
        if progress?.cancelled == true { return }
        progress?.saving()

        let merged = parts
        let outline = notes.count > 1
        let saved = await Task.detached(priority: .userInitiated) {
            let file = temporaryFile()
            defer { try? FileManager.default.removeItem(at: file) }
            guard merge(merged, outline: outline, to: file), let data = try? Data(contentsOf: file) else { return false }
            return (try? data.write(to: url, options: .atomic)) != nil
        }.value
        if !saved { fail(window) }
    }

    private static func fail(_ window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The PDF couldn't be saved."
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// One PDF holding every note, in order, each starting on a new page. The self-test uses it.
    static func pdf(_ notes: [Note], imageURL: (String) -> URL?, isKnownNote: (ID) -> Bool) -> Data? {
        var parts: [Part] = []
        defer { for part in parts { try? FileManager.default.removeItem(at: part.file) } }
        for batch in batched(notes) {
            guard let part = printBatch(batch, imageURL: imageURL, isKnownNote: isKnownNote) else { return nil }
            parts.append(part)
        }
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        guard merge(parts, outline: notes.count > 1, to: file) else { return nil }
        return try? Data(contentsOf: file)
    }

    // MARK: - Batches

    /// At most this many notes, or about this many blocks, print in one job.
    private static let batchSize = 20
    private static let batchBlocks = 1500

    private static func batched(_ notes: [Note]) -> [ArraySlice<Note>] {
        var batches: [ArraySlice<Note>] = []
        var start = 0, blocks = 0
        for (i, note) in notes.enumerated() {
            blocks += note.blocks.count
            if i + 1 - start >= batchSize || blocks >= batchBlocks || i == notes.count - 1 {
                batches.append(notes[start...i])
                start = i + 1
                blocks = 0
            }
        }
        return batches
    }

    /// A printed batch: its file, and each note's title and first page (counted within the file).
    nonisolated struct Part: Sendable {
        var file: URL
        var titles: [String]
        var firstPages: [Int]
    }

    nonisolated private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "MySelf-export-\(UUID().uuidString).pdf")
    }

    /// Prints a batch of notes, one after another, each starting on a new page.
    private static func printBatch(_ notes: ArraySlice<Note>, imageURL: (String) -> URL?, isKnownNote: (ID) -> Bool) -> Part? {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 60
        info.rightMargin = 60
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.scalingFactor = 1
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let light = NSAppearance(named: .aqua)!
        let text = NSMutableAttributedString()
        var starts: [Int] = []
        // Colours resolved while building (the tinted LaTeX, the checkbox) follow the drawing appearance.
        light.performAsCurrentDrawingAppearance {
            for note in notes {
                starts.append(text.length)
                text.append(printable(NoteReaderText.build(note, width: width, imageURL: imageURL, isKnownNote: isKnownNote, absoluteDates: true)))
            }
        }

        // TextKit 1, as in reader mode: text blocks and tables need it.
        let view = PrintTextView(usingTextLayoutManager: false)
        view.appearance = light
        view.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 2
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.textStorage?.setAttributedString(text)
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        layout.ensureLayout(for: container)
        view.sizeToFit()

        let noteTops = starts.map { start in
            let glyph = layout.glyphIndexForCharacter(at: min(start, max(text.length - 1, 0)))
            return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + view.textContainerOrigin.y
        }
        view.paginate(pageHeight: info.paperSize.height - info.topMargin - info.bottomMargin, noteTops: noteTops)

        // A print job saved to a file, not `pdfOperation`, which writes one page the size of the view.
        let file = temporaryFile()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = file
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return Part(file: file, titles: notes.map(\.displayTitle), firstPages: noteTops.map(view.page(at:)))
    }

    /// Joins the batches into one PDF at `url`, with an outline entry per note when `outline` is set.
    nonisolated private static func merge(_ parts: [Part], outline: Bool, to url: URL) -> Bool {
        let document = PDFDocument()
        let root = PDFOutline()
        for part in parts {
            guard let source = PDFDocument(url: part.file) else { return false }
            let first = document.pageCount
            for i in 0..<source.pageCount {
                if let page = source.page(at: i) { document.insert(page, at: document.pageCount) }
            }
            guard outline else { continue }
            for (title, pageIndex) in zip(part.titles, part.firstPages) {
                guard let page = document.page(at: first + pageIndex) else { continue }
                let item = PDFOutline()
                item.label = title
                item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).maxY))
                root.insertChild(item, at: root.numberOfChildren)
            }
        }
        guard document.pageCount > 0 else { return false }
        if outline { document.outlineRoot = root }
        return document.write(to: url)
    }

    /// Note links (`myself-note:`) mean nothing outside the app, so they become plain accent-coloured text; web links stay.
    private static func printable(_ text: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        out.enumerateAttribute(.link, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            guard NoteReaderText.noteID(from: value) != nil else { return }
            out.removeAttribute(.link, range: range)
            out.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
        }
        out.removeAttribute(NoteReaderText.imageKey, range: NSRange(location: 0, length: out.length))
        // Attachments drawn by a handler (the tinted LaTeX, checkboxes) composite with `.sourceAtop`, which a PDF
        // context can't do, so they print as black boxes: draw each into a bitmap first.
        out.enumerateAttribute(.attachment, in: NSRange(location: 0, length: out.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }
            attachment.image = bitmap(image)
        }
        return out
    }

    /// The image drawn at 3× into a bitmap, in the current drawing appearance.
    private static func bitmap(_ image: NSImage) -> NSImage {
        let scale: CGFloat = 3
        let size = image.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * scale)), pixelsHigh: Int(ceil(size.height * scale)),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    // MARK: - Pagination

    /// A text view that lays out its own pages: each note starts a new one, a table row stays on one page when it
    /// fits, and other breaks fall in the gap between two lines. A break exactly at a line's top cuts Bengali vowel
    /// signs, which rise above the line into the spacing left under the line before.
    private final class PrintTextView: NSTextView {
        private struct Line { var rect: NSRect; var glyphBottom: CGFloat; var row: String? }
        private var pages: [NSRect] = []

        func paginate(pageHeight: CGFloat, noteTops: [CGFloat]) {
            pages = []
            let height = bounds.height
            var top: CGFloat = 0
            while top < height - 0.5 {
                var bottom = min(top + pageHeight, height)
                if let next = noteTops.first(where: { $0 > top + 0.5 }), next <= bottom + 0.5 {
                    bottom = next
                } else if bottom < height {
                    bottom = pageBreak(top: top, limit: bottom)
                }
                pages.append(NSRect(x: 0, y: top, width: bounds.width, height: bottom - top))
                top = bottom
            }
            if pages.isEmpty { pages = [bounds] }
        }

        /// The page (from 0) a point at `y` is printed on.
        func page(at y: CGFloat) -> Int {
            pages.firstIndex { y < $0.maxY - 0.5 } ?? max(pages.count - 1, 0)
        }

        override func knowsPageRange(_ range: NSRangePointer) -> Bool {
            range.pointee = NSRange(location: 1, length: pages.count)
            return true
        }

        override func rectForPage(_ page: Int) -> NSRect {
            pages[min(max(page - 1, 0), pages.count - 1)]
        }

        /// Where a page starting at `top` ends, at or above `limit`.
        private func pageBreak(top: CGFloat, limit: CGFloat) -> CGFloat {
            guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return limit }
            let origin = textContainerOrigin
            let rect = NSRect(x: 0, y: top - origin.y, width: container.size.width, height: limit - top + 1)
            let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)

            var lines: [Line] = []
            var rows: [String: (top: CGFloat, bottom: CGFloat)] = [:]
            layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
                let rect = rect.offsetBy(dx: origin.x, dy: origin.y)
                var line = Line(rect: rect, glyphBottom: rect.maxY, row: nil)
                let char = layout.characterIndexForGlyph(at: range.location)
                guard char < storage.length,
                      let style = storage.attribute(.paragraphStyle, at: char, effectiveRange: nil) as? NSParagraphStyle else {
                    lines.append(line)
                    return
                }
                // The line's own height comes first; its spacing and the paragraph's are the gap below it.
                if style.maximumLineHeight > 0 { line.glyphBottom = min(rect.maxY, rect.minY + style.maximumLineHeight) }
                if let cell = style.textBlocks.last as? NSTextTableBlock {
                    let key = "\(ObjectIdentifier(cell.table).hashValue)-\(cell.startingRow)"
                    let cellGlyphs = layout.glyphRange(forCharacterRange: storage.range(of: cell, at: char), actualCharacterRange: nil)
                    let bounds = layout.boundsRect(for: cell, glyphRange: cellGlyphs).offsetBy(dx: origin.x, dy: origin.y)
                    if bounds.height > 0 {
                        let row = rows[key] ?? (bounds.minY, bounds.maxY)
                        rows[key] = (min(row.top, bounds.minY), max(row.bottom, bounds.maxY))
                    }
                    line.row = key
                }
                lines.append(line)
            }

            // No line may cross the break: move it to the top of any that does (one taller than a page is cut).
            var bottom = limit
            var moved = true
            while moved {
                moved = false
                for line in lines where line.rect.minY < bottom - 0.5 && line.rect.maxY > bottom + 0.5 && line.rect.minY > top + 1 {
                    bottom = line.rect.minY
                    moved = true
                }
            }
            // A table row the break falls inside moves to the next page whole, if it fits on one.
            if let row = rows.values.first(where: { $0.top < bottom - 0.5 && $0.bottom > bottom + 0.5 }), row.top > top + 1 {
                return row.top
            }
            // A break at a line's top moves up into the gap under the line before.
            if let line = lines.first(where: { $0.row == nil && abs($0.rect.minY - bottom) < 0.5 }),
               let above = lines.last(where: { $0.row == nil && abs($0.rect.maxY - line.rect.minY) < 0.5 }) {
                let gap = above.glyphBottom + (above.rect.maxY - above.glyphBottom) * 0.35
                if gap > top + 1 { bottom = gap }
            }
            return bottom
        }
    }

    /// A title made safe for a file name.
    private static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>\n")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(cleaned.isEmpty ? "Notes" : String(cleaned.prefix(120))).pdf"
    }
}

/// The sheet shown while a long export runs: a progress bar, a count, and Cancel.
private final class ExportProgress: NSObject {
    private(set) var cancelled = false
    private let total: Int
    private let sheet: NSWindow
    private weak var parent: NSWindow?
    private let bar = NSProgressIndicator()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)

    init(total: Int, window: NSWindow?) {
        self.total = total
        parent = window
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()

        title.stringValue = "Exporting \(total.formatted()) notes…"
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = Double(total)
        bar.style = .bar
        cancel.target = self
        cancel.action = #selector(cancelExport)
        cancel.keyEquivalent = "\u{1b}"
        update(done: 0)

        let buttons = NSStackView(views: [NSView(), cancel])
        let stack = NSStackView(views: [title, bar, detail, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 320),
            buttons.widthAnchor.constraint(equalTo: bar.widthAnchor),
        ])
        sheet.contentView = content
        if let parent { parent.beginSheet(sheet) } else { sheet.center(); sheet.makeKeyAndOrderFront(nil) }
    }

    func update(done: Int) {
        bar.doubleValue = Double(done)
        detail.stringValue = "\(done.formatted()) of \(total.formatted())"
    }

    /// The last step, merging and writing the file, which can't report progress or be cancelled.
    func saving() {
        title.stringValue = "Saving PDF…"
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        detail.stringValue = ""
        cancel.isEnabled = false
    }

    func close() {
        if let parent, sheet.sheetParent != nil { parent.endSheet(sheet) } else { sheet.orderOut(nil) }
    }

    @objc private func cancelExport() {
        cancelled = true
        cancel.isEnabled = false
        detail.stringValue = "Cancelling…"
    }
}
#endif
