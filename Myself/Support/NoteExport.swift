#if os(macOS)
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Exports notes as a PDF: each note is laid out like reader mode (`NoteReaderText.build`), printed onto its own
/// run of pages in the light appearance, and the notes are joined into one document with an outline entry per note.
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
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let known = Set(store.noteSummaries.map(\.id))
            let data = pdf(notes, imageURL: { name in
                if case .ready(let url) = store.sync.imageState(name) { url } else { nil }
            }, isKnownNote: { known.contains($0) })
            do {
                guard let data else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "The PDF couldn't be saved."
                alert.runModal()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    /// One PDF holding every note, in order, each starting on a new page.
    static func pdf(_ notes: [Note], imageURL: (String) -> URL?, isKnownNote: (ID) -> Bool) -> Data? {
        let document = PDFDocument()
        let outline = PDFOutline()
        for note in notes {
            guard let data = pdf(note, imageURL: imageURL, isKnownNote: isKnownNote), let part = PDFDocument(data: data) else { continue }
            let first = document.pageCount
            for i in 0..<part.pageCount {
                if let page = part.page(at: i) { document.insert(page, at: document.pageCount) }
            }
            if notes.count > 1, let page = document.page(at: first) {
                let item = PDFOutline()
                item.label = note.displayTitle
                item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).maxY))
                outline.insertChild(item, at: outline.numberOfChildren)
            }
        }
        guard document.pageCount > 0 else { return nil }
        if notes.count > 1 { document.outlineRoot = outline }
        return document.dataRepresentation()
    }

    /// One note's pages.
    private static func pdf(_ note: Note, imageURL: (String) -> URL?, isKnownNote: (ID) -> Bool) -> Data? {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 60
        info.rightMargin = 60
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let light = NSAppearance(named: .aqua)!
        var text = NSAttributedString()
        // Colours resolved while building (the tinted LaTeX, the checkbox) follow the drawing appearance.
        light.performAsCurrentDrawingAppearance {
            text = printable(NoteReaderText.build(note, width: width, imageURL: imageURL, isKnownNote: isKnownNote, absoluteDates: true))
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
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()

        // A print job saved to a file, not `pdfOperation`, which writes one page the size of the view.
        let file = FileManager.default.temporaryDirectory.appending(path: "MySelf-export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = file
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { return nil }
        return try? Data(contentsOf: file)
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

    /// A text view whose page breaks keep a table row on one page when it fits, and otherwise fall in the gap
    /// between two lines. A break exactly at a line's top, where the default pagination puts it, cuts Bengali
    /// vowel signs, which rise above the line into the spacing left under the line before.
    private final class PrintTextView: NSTextView {
        private struct Line { var rect: NSRect; var glyphBottom: CGFloat; var row: String? }

        override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat,
                                          bottom oldBottom: CGFloat, limit bottomLimit: CGFloat) {
            super.adjustPageHeightNew(newBottom, top: oldTop, bottom: oldBottom, limit: bottomLimit)
            guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return }
            let origin = textContainerOrigin
            let pageRect = NSRect(x: 0, y: oldTop - origin.y, width: container.size.width, height: oldBottom - oldTop)
            let glyphs = layout.glyphRange(forBoundingRect: pageRect, in: container)
            var bottom = newBottom.pointee

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

            // A table row the break falls inside moves to the next page whole, if it fits on one.
            if let row = rows.values.first(where: { $0.top < bottom - 0.5 && $0.bottom > bottom + 0.5 }), row.top > oldTop + 1 {
                newBottom.pointee = row.top
                return
            }
            // Otherwise the break goes above any line it crosses or that starts on it, into the gap under the line before.
            for line in lines.reversed() where line.row == nil && line.rect.minY < bottom + 0.5 && line.rect.maxY > bottom + 0.5 {
                bottom = line.rect.minY
                if let above = lines.last(where: { $0.row == nil && abs($0.rect.maxY - line.rect.minY) < 0.5 }) {
                    bottom = above.glyphBottom + (above.rect.maxY - above.glyphBottom) * 0.35
                }
                break
            }
            if bottom > oldTop + 1 { newBottom.pointee = bottom }
        }
    }

    /// A title made safe for a file name.
    private static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>\n")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(cleaned.isEmpty ? "Notes" : String(cleaned.prefix(120))).pdf"
    }
}
#endif
