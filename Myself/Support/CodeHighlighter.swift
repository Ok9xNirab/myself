import SwiftUI

/// Colours for note code and math, from the design's `notes.css`.
enum NoteColors {
    static let codeBackground = Color.dynamic(light: 0xF6F6F8, dark: 0x202023)

    static func token(_ token: CodeHighlighter.Token) -> PlatformColor {
        switch token {
        case .keyword: .dynamic(light: 0xA1338E, dark: 0xF472B0)
        case .string: .dynamic(light: 0xC2351F, dark: 0xF7857A)
        case .number: .dynamic(light: 0x2F3FC6, dark: 0xD6C56F)
        case .comment: .dynamic(light: 0x7A828C, dark: 0x7D8792)
        case .function: .dynamic(light: 0x2F7480, dark: 0x6CC4B0)
        case .type: .dynamic(light: 0x6B36B5, dark: 0xB48AF0)
        case .attribute: .dynamic(light: 0x1A6AA3, dark: 0x6FD3F7)
        case .meta: .dynamic(light: 0x8A5A1C, dark: 0xF5A05A)
        }
    }
}

/// A small regex tokenizer for the code block languages. Good enough for notes; not a parser.
enum CodeHighlighter {
    enum Token { case keyword, string, number, comment, function, type, attribute, meta }

    private struct Grammar {
        var comment: String?
        var string = #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#
        var meta: String?
        var attribute: String?
        var keywords: Set<String> = []
        var types: Set<String> = []
        var caseInsensitive = false
        var regex: NSRegularExpression?
    }

    private static let cStyleComment = #"//[^\n]*|/\*[\s\S]*?\*/"#
    private static let number = #"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#

    private static var grammars: [CodeLanguage: Grammar] = [:]

    private static func grammar(_ lang: CodeLanguage) -> Grammar {
        if let g = grammars[lang] { return g }
        var g = Grammar()
        let words = { (s: String) in Set(s.split(separator: " ").map(String.init)) }
        switch lang {
        case .python:
            g.comment = "#[^\\n]*"
            g.string = #"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|[fbr]?"(?:\\.|[^"\\\n])*"|[fbr]?'(?:\\.|[^'\\\n])*'"#
            g.meta = "@\\w+"
            g.keywords = words("def class return if elif else for while in not and or is None True False import from as with try except finally raise lambda yield pass break continue global nonlocal assert async await del")
            g.types = words("int str float list dict set tuple bool bytes object print len range enumerate zip map filter sorted sum min max abs open super self")
        case .javascript, .typescript:
            g.comment = cStyleComment
            g.string = #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"#
            g.keywords = words("const let var function return if else for while do switch case break continue new class extends import from export default try catch finally throw typeof instanceof in of this null undefined true false async await yield delete void static get set super")
            if lang == .typescript { g.keywords.formUnion(words("interface type enum implements public private protected readonly as declare namespace abstract keyof")) }
            g.types = words("string number boolean any unknown never object Array Promise Map Set console Math JSON")
        case .c, .cpp, .java, .go, .rust:
            g.comment = cStyleComment
            g.meta = lang == .c || lang == .cpp ? "#[^\\n]*" : lang == .rust ? "#!?\\[[^\\]\\n]*\\]" : "@\\w+"
            switch lang {
            case .c: g.keywords = words("if else for while do switch case break continue return struct union enum typedef static const extern sizeof goto default volatile register NULL")
            case .cpp: g.keywords = words("if else for while do switch case break continue return struct union enum class public private protected virtual override template typename namespace using new delete const static auto constexpr nullptr this true false try catch throw operator inline friend explicit noexcept default")
            case .java: g.keywords = words("if else for while do switch case break continue return class interface enum extends implements public private protected static final abstract new this super null true false try catch finally throw throws import package void synchronized instanceof var record")
            case .go: g.keywords = words("if else for range switch case break continue return func package import var const type struct interface map chan go defer select fallthrough goto default nil true false")
            default: g.keywords = words("if else for while loop match break continue return fn let mut const static struct enum impl trait pub use mod crate self Self super where as in ref move async await dyn unsafe true false Some None Ok Err")
            }
            g.types = words("int long short char float double void bool unsigned signed size_t string vector map set pair auto String Integer Object List Map uint8 int32 int64 float64 error byte rune i32 i64 u8 u32 u64 usize f32 f64 str Vec Option Result Box")
        case .sql:
            g.comment = #"--[^\n]*|/\*[\s\S]*?\*/"#
            g.string = #"'(?:''|[^'])*'"#
            g.caseInsensitive = true
            g.keywords = words("select from where and or not in is null as join left right inner outer full on group by order having limit offset insert into values update set delete create table index view drop alter add primary key foreign references distinct union all case when then else end exists between like asc desc over partition with true false")
            g.types = words("count sum avg min max rank row_number dense_rank coalesce cast int integer varchar text boolean date timestamp")
        case .bash:
            g.comment = "#[^\\n]*"
            g.attribute = #"\$\{[^}\n]*\}|\$\w+"#
            g.keywords = words("if then else elif fi for in do done while until case esac function return export local echo exit source alias cd set unset readonly")
        case .json:
            g.attribute = #""(?:\\.|[^"\\\n])*"(?=\s*:)"#
            g.keywords = words("true false null")
        case .xml:
            g.comment = "<!--[\\s\\S]*?-->"
            g.meta = "</?[\\w:.-]+|/?>"
            g.attribute = "[\\w:.-]+(?==)"
        case .css:
            g.comment = #"/\*[\s\S]*?\*/"#
            g.meta = "@[\\w-]+"
            g.attribute = "[\\w-]+(?=\\s*:)"
        case .plaintext:
            break
        }
        if lang != .plaintext {
            // Order matters: earlier alternatives win where matches would overlap (a "#" inside a string, say).
            let parts: [(String, String?)] = [("comment", g.comment), ("attribute", g.attribute), ("string", g.string),
                                               ("meta", g.meta), ("number", number), ("word", "[A-Za-z_][A-Za-z0-9_]*")]
            let pattern = parts.compactMap { name, p in p.map { "(?<\(name)>\($0))" } }.joined(separator: "|")
            g.regex = try? NSRegularExpression(pattern: pattern)
        }
        grammars[lang] = g
        return g
    }

    /// Highlighted ranges in `code` (UTF-16 `NSRange`s).
    static func tokens(_ code: String, _ lang: CodeLanguage) -> [(NSRange, Token)] {
        let g = grammar(lang)
        guard let regex = g.regex else { return [] }
        let ns = code as NSString
        var out: [(NSRange, Token)] = []
        for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            func hit(_ name: String) -> NSRange? {
                let r = match.range(withName: name)
                return r.location == NSNotFound ? nil : r
            }
            if let r = hit("comment") { out.append((r, .comment)) }
            else if let r = hit("attribute") { out.append((r, .attribute)) }
            else if let r = hit("string") { out.append((r, .string)) }
            else if let r = hit("meta") { out.append((r, .meta)) }
            else if let r = hit("number") { out.append((r, .number)) }
            else if let r = hit("word") {
                let word = ns.substring(with: r)
                let key = g.caseInsensitive ? word.lowercased() : word
                if g.keywords.contains(key) {
                    out.append((r, .keyword))
                } else if g.types.contains(key) {
                    out.append((r, .type))
                } else if nextNonSpace(ns, after: NSMaxRange(r)) == "(" {
                    out.append((r, .function))
                } else if lang != .sql, word.first?.isUppercase == true, word.count > 1 {
                    out.append((r, .type))
                }
            }
        }
        return out
    }

    private static func nextNonSpace(_ s: NSString, after index: Int) -> Character? {
        var i = index
        while i < s.length {
            let c = Character(UnicodeScalar(s.character(at: i)) ?? " ")
            if c != " " { return c }
            i += 1
        }
        return nil
    }

    /// The code as styled text, for places that show it read-only.
    static func attributed(_ code: String, _ lang: CodeLanguage, font: Font) -> AttributedString {
        var out = AttributedString(code)
        out.font = font
        for (range, token) in tokens(code, lang) {
            if let r = Range(range, in: out) { out[r].foregroundColor = Color(NoteColors.token(token)) }
        }
        return out
    }
}
