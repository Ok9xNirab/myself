import SwiftUI

/// Reader mode: the whole note as one read-only text view, so a selection can run across blocks with the cursor,
/// as on a web page, and ⌘C copies it. Clicking an image opens it in the viewer.
enum NoteReaderText {
    /// Marks an image's attachment character with its file name, so a click can open it.
    static let imageKey = NSAttributedString.Key("MySelfNoteImage")

    /// Builds the note for a text view `width` points wide. `imageURL` returns a downloaded image's file.
    static func build(_ note: Note, width: CGFloat, imageURL: (String) -> URL?) -> NSAttributedString {
        let size = NoteTypeface.bodySize
        let out = NSMutableAttributedString()

        func paragraph(_ text: NSAttributedString, _ style: NSParagraphStyle) {
            let line = NSMutableAttributedString(attributedString: text)
            line.append(NSAttributedString(string: "\n"))
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }

        func spacer(_ height: CGFloat) {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            out.append(NSAttributedString(string: "\n", attributes: [.font: PlatformFont.systemFont(ofSize: 1), .paragraphStyle: style]))
        }

        let title = NSAttributedString(string: note.displayTitle, attributes: [
            .font: NoteTypeface.platformFont(size: size * 2, weight: .bold), .foregroundColor: PlatformColor.labelCompat,
        ])
        paragraph(title, style(lineSpacing: NoteText.hasBengali(note.title) ? size * 0.4 : size * 0.1, after: 6))
        let meta = NSAttributedString(string: "Edited \(NoteDates.ago(note.editedAt, now: .now)) · \(note.wordCount) words", attributes: [
            .font: PlatformFont.systemFont(ofSize: 12), .foregroundColor: PlatformColor.tertiaryLabelCompat,
        ])
        paragraph(meta, style(lineSpacing: 0, after: 20))

        var number = 0
        for block in note.blocks {
            number = block.kind == .num ? number + 1 : 0
            let bengali = NoteText.hasBengali(block.text)
            switch block.kind {
            case .p, .quote:
                let spacing = NoteTypeface.lineSpacing(size: size, bengali: bengali)
                let color = block.kind == .quote ? PlatformColor.secondaryLabelCompat : PlatformColor.labelCompat
                var paragraphStyle = style(lineSpacing: spacing, after: 6, lineHeight: lineHeight(size))
                #if os(macOS)
                if block.kind == .quote { paragraphStyle = style(lineSpacing: spacing, after: 0, lineHeight: lineHeight(size), block: quoteBlock(width)) }
                #else
                if block.kind == .quote { paragraphStyle = style(lineSpacing: spacing, after: 6, indent: 14, lineHeight: lineHeight(size)) }
                #endif
                paragraph(inline(block.text, size: size, weight: .regular, color: color), paragraphStyle)
            case .h1, .h2, .h3:
                let (scale, weight, before): (CGFloat, PlatformFont.Weight, CGFloat) = switch block.kind {
                case .h1: (1.6, .bold, 20)
                case .h2: (1.28, .semibold, 16)
                default: (1.06, .semibold, 10)
                }
                let textSize = size * scale
                paragraph(inline(block.text, size: textSize, weight: weight, color: .labelCompat),
                          style(lineSpacing: textSize * (bengali ? 0.3 : 0.15), before: before, after: 6, lineHeight: lineHeight(textSize, weight: weight)))
            case .bullet, .num, .todo:
                let done = block.kind == .todo && block.done == true
                let markerFont = PlatformFont.systemFont(ofSize: size)
                let line: NSMutableAttributedString
                if block.kind == .todo {
                    // The editor's checkbox, centred on the text's x-height.
                    let box = checkbox(done)
                    let attachment = NSTextAttachment()
                    attachment.image = box
                    attachment.bounds = CGRect(x: 0, y: (markerFont.xHeight - box.size.height) / 2, width: box.size.width, height: box.size.height)
                    line = NSMutableAttributedString(attachment: attachment)
                    line.append(NSAttributedString(string: "\t", attributes: [.font: markerFont]))
                } else {
                    line = NSMutableAttributedString(string: (block.kind == .bullet ? "•" : "\(number).") + "\t", attributes: [
                        .font: markerFont, .foregroundColor: PlatformColor.secondaryLabelCompat,
                    ])
                }
                let text = inline(block.text, size: size, weight: .regular, color: done ? .tertiaryLabelCompat : .labelCompat)
                if done {
                    text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: text.length))
                }
                line.append(text)
                paragraph(line, style(lineSpacing: NoteTypeface.lineSpacing(size: size, bengali: bengali), after: 4, indent: 24, tab: 24,
                                      lineHeight: lineHeight(size)))
            case .code:
                let code = NSMutableAttributedString(string: block.text.isEmpty ? " " : block.text, attributes: [
                    .font: NoteTypeface.platformFont(size: 12.5, monospaced: true), .foregroundColor: PlatformColor.labelCompat,
                ])
                for (range, token) in CodeHighlighter.tokens(block.text, block.lang ?? .plaintext) where NSMaxRange(range) <= code.length {
                    code.addAttribute(.foregroundColor, value: NoteColors.token(token), range: range)
                }
                #if os(macOS)
                // Paragraph spacing inside a block becomes padding, and a block paints its margins with its background,
                // so empty lines of a set height space the box out.
                spacer(8)
                paragraph(code, style(lineSpacing: 12.5 * 0.45, after: 0, block: codeBlock(width)))
                spacer(14)
                #else
                code.addAttribute(.backgroundColor, value: codeBackground, range: NSRange(location: 0, length: code.length))
                paragraph(code, style(lineSpacing: 12.5 * 0.45, before: 8, after: 14))
                #endif
            case .math:
                let math: NSAttributedString
                if let rendered = MathRenderer.render(block.text, fontSize: size * 1.25, display: true) {
                    math = attachment(tinted(rendered.image), descent: rendered.descent, maxWidth: width)
                } else {
                    math = NSAttributedString(string: block.text, attributes: [
                        .font: NoteTypeface.platformFont(size: 12.5, monospaced: true), .foregroundColor: PlatformColor.systemRed,
                    ])
                }
                paragraph(math, style(lineSpacing: 0, before: 8, after: 14, alignment: .center))
            case .table:
                let table = NoteTable(block.text)
                let cellSize = size * 0.93
                #if os(macOS)
                // Each cell is a paragraph in its own NSTextTableBlock.
                let grid = tableGrid(table, width: width)
                spacer(8)
                for (r, row) in ([table.header] + table.rows).enumerated() {
                    for (c, cell) in row.enumerated() {
                        let text = inline(NoteTable.display(cell), size: cellSize, weight: r == 0 ? .semibold : .regular, color: .labelCompat)
                        if text.length == 0 { text.append(NSAttributedString(string: " ", attributes: [.font: PlatformFont.systemFont(ofSize: cellSize)])) }
                        paragraph(text, style(lineSpacing: NoteTypeface.lineSpacing(size: cellSize, bengali: NoteText.hasBengali(cell)), after: 0,
                                              lineHeight: lineHeight(cellSize), alignment: alignment(table.alignments[c]),
                                              block: tableCell(grid, row: r, column: c)))
                    }
                }
                spacer(14)
                #else
                // No text tables in UIKit: one tab-separated line per row, the header in bold.
                let stops = (1..<max(table.columnCount, 1)).map { NSTextTab(textAlignment: .natural, location: width / CGFloat(table.columnCount) * CGFloat($0)) }
                for (r, row) in ([table.header] + table.rows).enumerated() {
                    let line = NSMutableAttributedString()
                    for (c, cell) in row.enumerated() {
                        if c > 0 { line.append(NSAttributedString(string: "\t", attributes: [.font: PlatformFont.systemFont(ofSize: cellSize)])) }
                        line.append(inline(NoteTable.display(cell), size: cellSize, weight: r == 0 ? .semibold : .regular, color: .labelCompat))
                    }
                    let paragraphStyle = style(lineSpacing: 0, before: r == 0 ? 8 : 0, after: r == table.rows.count ? 14 : 4) as! NSMutableParagraphStyle
                    paragraphStyle.tabStops = stops
                    paragraph(line, paragraphStyle)
                }
                #endif
            case .image:
                guard let name = block.image else { continue }
                let picture: NSMutableAttributedString
                if let url = imageURL(name), let preview = NoteImages.preview(at: url) {
                    #if os(macOS)
                    let image = NSImage(cgImage: preview, size: NSSize(width: preview.width / 2, height: preview.height / 2))
                    #else
                    let image = UIImage(cgImage: preview, scale: 2, orientation: .up)
                    #endif
                    picture = NSMutableAttributedString(attributedString: attachment(image, descent: 0, maxWidth: width))
                    picture.addAttribute(imageKey, value: name, range: NSRange(location: 0, length: picture.length))
                } else {
                    picture = NSMutableAttributedString(string: "Image not available yet", attributes: [
                        .font: PlatformFont.systemFont(ofSize: 12.5), .foregroundColor: PlatformColor.tertiaryLabelCompat,
                    ])
                }
                paragraph(picture, style(lineSpacing: 0, before: 8, after: block.text.isEmpty ? 14 : 4, alignment: .center))
                if !block.text.isEmpty {
                    let caption = NSAttributedString(string: block.text, attributes: [
                        .font: PlatformFont.systemFont(ofSize: 12.5), .foregroundColor: PlatformColor.secondaryLabelCompat,
                    ])
                    paragraph(caption, style(lineSpacing: 0, after: 14, alignment: .center))
                }
            case .hr:
                #if os(macOS)
                paragraph(NSAttributedString(string: "\u{200B}", attributes: [.font: PlatformFont.systemFont(ofSize: 4)]),
                          style(lineSpacing: 0, after: 0, block: dividerBlock(width)))
                #else
                paragraph(NSAttributedString(string: "⁂", attributes: [.foregroundColor: PlatformColor.tertiaryLabelCompat]),
                          style(lineSpacing: 0, before: 10, after: 10, alignment: .center))
                #endif
            }
        }
        return out
    }

    /// Inline markdown as attributed text, matching `NoteMarkdown.text`.
    private static func inline(_ source: String, size: CGFloat, weight: PlatformFont.Weight, color: PlatformColor) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for run in NoteMarkdown.parse(source) {
            switch run {
            case let .text(string, style, link):
                let bold = style.contains(.bold) ? PlatformFont.Weight.bold : weight
                var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
                if style.contains(.code) {
                    attributes[.font] = NoteTypeface.platformFont(size: size * 0.86, weight: bold, monospaced: true)
                    attributes[.backgroundColor] = codeBackground
                } else {
                    attributes[.font] = NoteTypeface.platformFont(size: size, weight: bold, italic: style.contains(.italic))
                }
                if style.contains(.strike) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if style.contains(.highlight) { attributes[.backgroundColor] = PlatformColor.systemOrange.withAlphaComponent(0.28) }
                if let link { attributes[.link] = link }
                out.append(NSAttributedString(string: string, attributes: attributes))
            case let .math(latex):
                if let rendered = MathRenderer.render(latex, fontSize: size * 1.08, display: false) {
                    out.append(attachment(tinted(rendered.image), descent: rendered.descent, maxWidth: .greatestFiniteMagnitude))
                } else {
                    out.append(NSAttributedString(string: latex, attributes: [
                        .font: NoteTypeface.platformFont(size: size * 0.86, monospaced: true), .foregroundColor: PlatformColor.systemRed,
                    ]))
                }
            }
        }
        return out
    }

    private static func style(lineSpacing: CGFloat, before: CGFloat = 0, after: CGFloat, indent: CGFloat = 0, tab: CGFloat? = nil,
                              lineHeight: CGFloat? = nil, alignment: NSTextAlignment = .natural, block: AnyObject? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = before
        #if os(macOS)
        style.paragraphSpacing = after  // the line spacing after a paragraph's last line is dropped by `Coordinator`
        #else
        // UIKit adds the line spacing after a paragraph's last line too, so it counts towards the gap.
        style.paragraphSpacing = max(0, after - lineSpacing)
        #endif
        style.alignment = alignment
        style.headIndent = indent
        style.firstLineHeadIndent = tab == nil ? indent : 4
        if let tab { style.tabStops = [NSTextTab(textAlignment: .natural, location: tab)] }
        #if os(macOS)
        if let block = block as? NSTextBlock { style.textBlocks = [block] }
        #endif
        return style
    }

    /// The system font's line height at `size`. The editor's text takes its line height from the system font; a text
    /// view would use the tallest font on the line, and SF Bangla's is much taller.
    private static func lineHeight(_ size: CGFloat, weight: PlatformFont.Weight = .regular) -> CGFloat {
        let font = PlatformFont.systemFont(ofSize: size, weight: weight)
        #if os(macOS)
        return ceil(font.ascender - font.descender + font.leading)
        #else
        return ceil(font.lineHeight)
        #endif
    }

    /// An image scaled down to fit `maxWidth`, sitting `descent` below the baseline.
    private static func attachment(_ image: PlatformImage, descent: CGFloat, maxWidth: CGFloat) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        let scale = min(1, (maxWidth - 8) / max(image.size.width, 1))
        attachment.bounds = CGRect(x: 0, y: -descent * scale, width: image.size.width * scale, height: image.size.height * scale)
        return NSAttributedString(attachment: attachment)
    }

    private static func alignment(_ align: NoteTable.Alignment) -> NSTextAlignment {
        switch align {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }

    private static var codeBackground: PlatformColor { .dynamic(light: 0xF6F6F8, dark: 0x202023) }

    /// LaTeX images are black templates; draw them in the label colour, resolved for the current appearance.
    private static func tinted(_ image: PlatformImage) -> PlatformImage {
        #if os(macOS)
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        #else
        image.withTintColor(.label, renderingMode: .alwaysOriginal)
        #endif
    }

    /// The editor's `TodoBox`: a rounded square, filled with the accent colour and ticked when done.
    private static func checkbox(_ done: Bool) -> PlatformImage {
        let side: CGFloat = 15
        #if os(macOS)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: 4, yRadius: 4)
            if done {
                NSColor.controlAccentColor.setFill()
                box.fill()
                let tick = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 9, weight: .heavy).applying(.init(paletteColors: [.white])))
                if let tick { tick.draw(in: CGRect(x: (side - tick.size.width) / 2, y: (side - tick.size.height) / 2, width: tick.size.width, height: tick.size.height)) }
            } else {
                NSColor.labelColor.withAlphaComponent(0.3).setStroke()
                box.lineWidth = 1.2
                box.stroke()
            }
            return true
        }
        #else
        let name = done ? "checkmark.square.fill" : "square"
        let config = UIImage.SymbolConfiguration(pointSize: side, weight: .regular)
        return (UIImage(systemName: name, withConfiguration: config) ?? UIImage()).withTintColor(done ? .tintColor : .tertiaryLabel, renderingMode: .alwaysOriginal)
        #endif
    }

    #if os(macOS)
    /// A text block's content width must be set, or it shrinks to a letter per line. `width` is the text view's;
    /// the block's padding and border come off it, as does the line fragment padding on both sides.
    private static func sized(_ block: NSTextBlock, width: CGFloat, inset: CGFloat) -> NSTextBlock {
        block.setContentWidth(max(40, width - 4 - inset), type: .absoluteValueType)
        return block
    }

    private static func codeBlock(_ width: CGFloat) -> NSTextBlock {
        let block = NSTextBlock()
        block.backgroundColor = codeBackground
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setBorderColor(.separatorColor)
        return sized(block, width: width, inset: 2 * 12 + 2 * 0.5)
    }

    private static func tableGrid(_ table: NoteTable, width: CGFloat) -> NSTextTable {
        let grid = NSTextTable()
        grid.numberOfColumns = table.columnCount
        grid.collapsesBorders = true
        grid.hidesEmptyCells = false
        grid.layoutAlgorithm = .automaticLayoutAlgorithm
        grid.setWidth(1, type: .absoluteValueType, for: .border)
        grid.setBorderColor(.separatorColor)
        return sized(grid, width: width, inset: 2) as! NSTextTable
    }

    private static func tableCell(_ grid: NSTextTable, row: Int, column: Int) -> NSTextTableBlock {
        let cell = NSTextTableBlock(table: grid, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        cell.setWidth(1, type: .absoluteValueType, for: .border)
        cell.setBorderColor(.separatorColor)
        cell.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
        cell.setWidth(10, type: .absoluteValueType, for: .padding, edge: .maxX)
        cell.setWidth(6, type: .absoluteValueType, for: .padding, edge: .minY)
        cell.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxY)
        if row == 0 { cell.backgroundColor = .dynamic(light: 0xF0F0F2, dark: 0x323234) }
        return cell
    }

    private static func quoteBlock(_ width: CGFloat) -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(.separatorColor, for: .minX)
        block.setWidth(11, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(4, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
        return sized(block, width: width, inset: 3 + 11)
    }

    private static func dividerBlock(_ width: CGFloat) -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
        block.setBorderColor(.separatorColor, for: .minY)
        block.setWidth(14, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(10, type: .absoluteValueType, for: .margin, edge: .maxY)
        return sized(block, width: width, inset: 0)
    }
    #endif
}

extension PlatformColor {
    static var tertiaryLabelCompat: PlatformColor {
        #if os(macOS)
        .tertiaryLabelColor
        #else
        .tertiaryLabel
        #endif
    }

    static var controlAccentCompat: PlatformColor {
        #if os(macOS)
        .controlAccentColor
        #else
        .tintColor
        #endif
    }
}

#if os(macOS)
import AppKit

struct NoteReaderView: NSViewRepresentable {
    var note: Note
    var imageURL: (String) -> URL?
    var onOpenImage: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 2
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.layoutManager?.delegate = context.coordinator
        view.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .cursor: NSCursor.pointingHand]
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.built != note { context.coordinator.rebuild(view) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width ?? 600
        if abs(width - context.coordinator.width) > 0.5 {
            context.coordinator.width = width
            context.coordinator.rebuild(view)
        }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).maxY))
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: NoteReaderView?
        var built: Note?
        var width: CGFloat = 600

        /// Line spacing goes between a paragraph's lines only, as in the editor; TextKit would also add it after the
        /// last line. Code lines are separate paragraphs in one block, so they keep it between them.
        func layoutManager(_ layoutManager: NSLayoutManager, lineSpacingAfterGlyphAt glyphIndex: Int,
                           withProposedLineFragmentRect rect: NSRect) -> CGFloat {
            guard let storage = layoutManager.textStorage, storage.length > 0 else { return 0 }
            let index = min(layoutManager.characterIndexForGlyph(at: glyphIndex), storage.length - 1)
            let style = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
            let spacing = style?.lineSpacing ?? 0
            // The line's last glyph can be the line break or the character before it.
            let text = storage.string as NSString
            let lineBreak = text.character(at: index) == 10 ? index : index + 1
            guard lineBreak >= storage.length || text.character(at: lineBreak) == 10 else { return spacing }  // wrapped line
            guard let block = style?.textBlocks.first, lineBreak + 1 < storage.length,
                  let next = storage.attribute(.paragraphStyle, at: lineBreak + 1, effectiveRange: nil) as? NSParagraphStyle,
                  next.textBlocks.first === block else { return 0 }
            return spacing
        }

        func rebuild(_ view: NSTextView) {
            guard let parent else { return }
            built = parent.note
            view.textStorage?.setAttributedString(NoteReaderText.build(parent.note, width: width, imageURL: parent.imageURL))
        }

        func textView(_ textView: NSTextView, clickedOn cell: any NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
            guard let name = textView.textStorage?.attribute(NoteReaderText.imageKey, at: charIndex, effectiveRange: nil) as? String else { return }
            parent?.onOpenImage(name)
        }
    }
}

#else

struct NoteReaderView: UIViewRepresentable {
    var note: Note
    var imageURL: (String) -> URL?
    var onOpenImage: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 2
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.built != note { context.coordinator.rebuild(view) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 360
        if abs(width - context.coordinator.width) > 0.5 {
            context.coordinator.width = width
            context.coordinator.rebuild(view)
        }
        return CGSize(width: width, height: ceil(view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteReaderView?
        var built: Note?
        var width: CGFloat = 360

        func rebuild(_ view: UITextView) {
            guard let parent else { return }
            built = parent.note
            view.attributedText = NoteReaderText.build(parent.note, width: width, imageURL: parent.imageURL)
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .textAttachment = textItem.content,
                  let name = textView.attributedText.attribute(NoteReaderText.imageKey, at: textItem.range.location, effectiveRange: nil) as? String
            else { return defaultAction }
            return UIAction { [weak self] _ in self?.parent?.onOpenImage(name) }
        }
    }
}

#endif
