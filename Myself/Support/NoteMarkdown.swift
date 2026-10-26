import SwiftUI
import SwiftMath

/// Inline markdown inside a note block: `**bold**`, `*italic*`, `~~strike~~`, `==highlight==`, `` `code` ``,
/// `[link](https://…)` and `$math$`. Markers without a closing partner stay as typed.
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
        case text(String, Style, link: URL?)
        case math(String)
    }

    static func parse(_ text: String) -> [Run] {
        let chars = Array(text)
        return parse(chars, chars.startIndex..<chars.endIndex, style: [], link: nil)
    }

    private static let pairs: [(marker: [Character], style: Style)] = [(["*", "*"], .bold), (["~", "~"], .strike), (["=", "="], .highlight)]

    private static func parse(_ c: [Character], _ range: Range<Int>, style: Style, link: URL?) -> [Run] {
        var out: [Run] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { out.append(.text(buffer, style, link: link)) }
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
                out.append(.text(String(c[(i + 1)..<j]), style.union(.code), link: link))
                i = j + 1
                continue
            }
            if ch == "$", let j = find("$", from: i + 1), j > i + 1 {
                flush()
                out.append(.math(String(c[(i + 1)..<j])))
                i = j + 1
                continue
            }
            if ch == "[", let close = find("]", from: i + 1), close + 1 < range.upperBound, c[close + 1] == "(",
               let paren = find(")", from: close + 2), let url = URL(string: String(c[(close + 2)..<paren])),
               url.scheme == "http" || url.scheme == "https", close > i + 1 {
                flush()
                out += parse(c, (i + 1)..<close, style: style, link: url)
                i = paren + 1
                continue
            }
            for (marker, flag) in pairs where i + 1 < range.upperBound && c[i] == marker[0] && c[i + 1] == marker[1] {
                if let j = find(marker, from: i + 2), j > i + 2 {
                    flush()
                    out += parse(c, (i + 2)..<j, style: style.union(flag), link: link)
                    i = j + 2
                    continue scan
                }
            }
            if ch == "*", i + 1 < range.upperBound, !c[i + 1].isWhitespace, c[i + 1] != "*", let j = find("*", from: i + 1) {
                flush()
                out += parse(c, (i + 1)..<j, style: style.union(.italic), link: link)
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
    }

    /// Rendered blocks, so a block that's drawn again unchanged isn't parsed again.
    private static var textCache: [TextKey: Text] = [:]

    /// Read-mode rendering of a text block.
    static func text(_ source: String, size: CGFloat, weight: PlatformFont.Weight) -> Text {
        let key = TextKey(source: source, size: size, weight: weight.rawValue)
        if let hit = textCache[key] { return hit }
        let result = render(source, size: size, weight: weight)
        if textCache.count >= 2000 { textCache.removeAll(keepingCapacity: true) }
        textCache[key] = result
        return result
    }

    private static func render(_ source: String, size: CGFloat, weight: PlatformFont.Weight) -> Text {
        var result = Text("")
        for run in parse(source) {
            let piece: Text
            switch run {
            case let .text(string, style, link):
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
                piece = Text(attributed)
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
