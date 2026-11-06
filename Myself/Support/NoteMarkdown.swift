import SwiftUI
import SwiftMath

/// Marks the part of a rendered block that links to a note, so `NoteLinkRenderer` can find where it was drawn.
nonisolated struct NoteLinkAttribute: TextAttribute {
    let id: String
}

/// Inline markdown inside a note block: `**bold**`, `*italic*`, `~~strike~~`, `==highlight==`, `` `code` ``,
/// `[link](https://…)`, `[[label|note id]]` and `$math$`. Markers without a closing partner stay as typed.
enum NoteMarkdown {
    struct Style: OptionSet, Hashable {
        let rawValue: Int
        static let bold = Style(rawValue: 1)
        static let italic = Style(rawValue: 2)
        static let strike = Style(rawValue: 4)
        static let highlight = Style(rawValue: 8)
        static let code = Style(rawValue: 16)
    }

    enum Run: Equatable {
        /// `note` is the ID of the note a `[[label|id]]` link points at.
        case text(String, Style, link: URL?, note: String?)
        case math(String)
    }

    static func parse(_ text: String) -> [Run] {
        let chars = Array(text)
        return parse(chars, chars.startIndex..<chars.endIndex, style: [], link: nil, note: nil)
    }

    /// The IDs of the notes a block's text links to, in order. Links in inline code don't count, since they don't render.
    static func linkIDs(_ text: String) -> [ID] {
        guard text.contains("[[") else { return [] }
        return parse(text).compactMap { run in
            if case let .text(_, style, _, note) = run, !style.contains(.code) { note } else { nil }
        }
    }

    /// Where a `[[label|id]]` starting at `start` ends: the end of its label and of its ID. Nil if it isn't one.
    private static func noteLink(_ c: [Character], at start: Int, before end: Int) -> (label: Int, id: Int)? {
        guard start + 1 < end, c[start] == "[", c[start + 1] == "[" else { return nil }
        var i = start + 2
        while i < end, c[i] != "]", c[i] != "|", c[i] != "\n" { i += 1 }
        guard i > start + 2, i < end, c[i] == "|" else { return nil }
        var j = i + 1
        while j < end, c[j].isLetter || c[j].isNumber || c[j] == "_" || c[j] == "-" { j += 1 }
        guard j > i + 1, j + 1 < end, c[j] == "]", c[j + 1] == "]" else { return nil }
        return (i, j)
    }

    private static let pairs: [(marker: [Character], style: Style)] = [(["*", "*"], .bold), (["~", "~"], .strike), (["=", "="], .highlight)]

    private static func parse(_ c: [Character], _ range: Range<Int>, style: Style, link: URL?, note: String?) -> [Run] {
        var out: [Run] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { out.append(.text(buffer, style, link: link, note: note)) }
            buffer = ""
        }
        /// Index of the next `char` on the same line, at or after `from`.
        func find(_ char: Character, from: Int) -> Int? {
            var j = from
            while j < range.upperBound, c[j] != "\n" {
                if c[j] == char { return j }
                j += 1
            }
            return nil
        }
        func find(_ seq: [Character], from: Int) -> Int? {
            var j = from
            while j + 1 < range.upperBound {
                if c[j] == seq[0], c[j + 1] == seq[1] { return j }
                j += 1
            }
            return nil
        }

        var i = range.lowerBound
        scan: while i < range.upperBound {
            let ch = c[i]
            if ch == "`", let j = find("`", from: i + 1), j > i + 1 {
                flush()
                out.append(.text(String(c[(i + 1)..<j]), style.union(.code), link: link, note: note))
                i = j + 1
                continue
            }
            if ch == "$", let j = find("$", from: i + 1), j > i + 1 {
                flush()
                out.append(.math(String(c[(i + 1)..<j])))
                i = j + 1
                continue
            }
            if let ends = noteLink(c, at: i, before: range.upperBound) {
                flush()
                out += parse(c, (i + 2)..<ends.label, style: style, link: link, note: String(c[(ends.label + 1)..<ends.id]))
                i = ends.id + 2
                continue
            }
            if ch == "[", let close = find("]", from: i + 1), close + 1 < range.upperBound, c[close + 1] == "(",
               let paren = find(")", from: close + 2), let url = URL(string: String(c[(close + 2)..<paren])),
               url.scheme == "http" || url.scheme == "https", close > i + 1 {
                flush()
                out += parse(c, (i + 1)..<close, style: style, link: url, note: note)
                i = paren + 1
                continue
            }
            for (marker, flag) in pairs where i + 1 < range.upperBound && c[i] == marker[0] && c[i + 1] == marker[1] {
                if let j = find(marker, from: i + 2), j > i + 2 {
                    flush()
                    out += parse(c, (i + 2)..<j, style: style.union(flag), link: link, note: note)
                    i = j + 2
                    continue scan
                }
            }
            if ch == "*", i + 1 < range.upperBound, !c[i + 1].isWhitespace, c[i + 1] != "*", let j = find("*", from: i + 1) {
                flush()
                out += parse(c, (i + 1)..<j, style: style.union(.italic), link: link, note: note)
                i = j + 1
                continue
            }
            buffer.append(ch)
            i += 1
        }
        flush()
        return out
    }

    private struct TextKey: Hashable {
        var source: String
        var size: CGFloat
        var weight: CGFloat
        var missing: Set<ID>
    }

    /// Rendered blocks, so a block that's drawn again unchanged isn't parsed again.
    private static var textCache: [TextKey: Text] = [:]

    /// Read-mode rendering of a text block. Links to the notes in `missing` show as broken.
    static func text(_ source: String, size: CGFloat, weight: PlatformFont.Weight, missing: Set<ID> = []) -> Text {
        let key = TextKey(source: source, size: size, weight: weight.rawValue, missing: missing)
        if let hit = textCache[key] { return hit }
        let result = render(source, size: size, weight: weight, missing: missing)
        if textCache.count >= 2000 { textCache.removeAll(keepingCapacity: true) }
        textCache[key] = result
        return result
    }

    private static func render(_ source: String, size: CGFloat, weight: PlatformFont.Weight, missing: Set<ID>) -> Text {
        var result = Text("")
        for run in parse(source) {
            let piece: Text
            switch run {
            case let .text(string, style, link, note):
                var attributed = AttributedString(string)
                let bold = style.contains(.bold) ? NoteTypeface.boldWeight(over: weight) : weight
                if style.contains(.code) {
                    attributed.font = NoteTypeface.font(size: size * 0.86, weight: bold, monospaced: true)
                    attributed.backgroundColor = NoteColors.codeBackground
                } else {
                    attributed.font = NoteTypeface.font(size: size, weight: bold, italic: style.contains(.italic))
                }
                if style.contains(.strike) { attributed.strikethroughStyle = .single }
                if style.contains(.highlight) { attributed.backgroundColor = Palette.amber.opacity(0.28) }
                if let link {
                    attributed.link = link
                    attributed.foregroundColor = .accentColor
                    attributed.underlineStyle = .single
                }
                if let note {
                    let color = missing.contains(note) ? Palette.ink3 : Color.accentColor
                    attributed.foregroundColor = color
                    if !missing.contains(note) { attributed.backgroundColor = color.opacity(0.09) }
                    attributed.underlineStyle = Text.LineStyle(pattern: .solid, color: color.opacity(0.45))
                    piece = Text(attributed).customAttribute(NoteLinkAttribute(id: note))
                } else {
                    piece = Text(attributed)
                }
            case let .math(latex):
                if let math = MathRenderer.render(latex, fontSize: size * 1.08, display: false) {
                    piece = Text(Image(platformImage: math.image).renderingMode(.template)).baselineOffset(-math.descent)
                } else {
                    piece = Text(latex).font(NoteTypeface.font(size: size * 0.86, monospaced: true)).foregroundStyle(Palette.red)
                }
            }
            result = Text("\(result)\(piece)")
        }
        return result
    }
}

/// LaTeX to images with SwiftMath, cached. Images are templates, so they take the surrounding text colour.
enum MathRenderer {
    struct Rendered {
        let image: PlatformImage
        /// Distance from the image's bottom edge to the baseline.
        let descent: CGFloat
    }

    private static var cache: [String: Rendered?] = [:]

    static func render(_ latex: String, fontSize: CGFloat, display: Bool) -> Rendered? {
        let key = "\(display ? "D" : "T")\(fontSize)|\(latex)"
        if let hit = cache[key] { return hit }
        let source = prepare(latex)
        let mode: MTMathUILabelMode = display ? .display : .text
        let maker = MTMathImage(latex: source, fontSize: fontSize, textColor: .black, labelMode: mode, textAlignment: .left)
        let (error, image) = maker.asImage()
        var rendered: Rendered?
        if error == nil, let image {
            // `MTMathImage` doesn't expose the baseline, so lay the same formula out in a label to read it.
            let label = MTMathUILabel()
            label.fontSize = fontSize
            label.labelMode = mode
            label.latex = source
            #if os(macOS)
            label.frame = CGRect(origin: .zero, size: label.fittingSize)
            label.layout()
            image.isTemplate = true
            rendered = Rendered(image: image, descent: label.displayList?.descent ?? 0)
            #else
            label.frame = CGRect(origin: .zero, size: label.sizeThatFits(.zero))
            label.layoutSubviews()
            rendered = Rendered(image: image.withRenderingMode(.alwaysTemplate), descent: label.displayList?.descent ?? 0)
            #endif
        }
        cache[key] = rendered
        return rendered
    }

    /// Rewrites commands SwiftMath doesn't know into ones it does.
    private static func prepare(_ latex: String) -> String {
        latex.replacing(/\\operatorname\{([^}]*)\}/) { "\\mathrm{\($0.1)}" }
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
