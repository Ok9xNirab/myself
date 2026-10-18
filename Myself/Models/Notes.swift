import SwiftUI

/// A Notes category ("Notebook" in the design). Synced as `notecats/<id>.json`.
struct NoteCategory: Identifiable, Hashable, Codable, SyncRecord {
    static let folder = "notecats"

    let id: ID
    var name: String
    var hex: UInt32
    var sortOrder = 0
    var updatedAt = Date.distantPast
    var color: Color { Color(hex: hex) }

    /// Colours handed out to new categories in turn, from the design's `NT_COLORS`.
    static let palette: [UInt32] = [0xAF52DE, 0x007AFF, 0xFF9500, 0x34C759, 0xFF2D55, 0x5AC8FA, 0xA2845E, 0x8E8E93]
}

/// A notes page: a title and a list of blocks. Synced as `notes/<id>.json`, one file per page.
struct Note: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "notes"

    var id = newID()
    var categoryID: ID
    var title = ""
    var pinned = false
    var blocks: [NoteBlock] = [NoteBlock()]
    var font: NoteFont?
    var createdAt = Date.now
    /// Last change to the title, blocks or typography; shown and sorted as "Date edited".
    var editedAt = Date.now
    /// Last change of any kind, including pinning and moving. Decides which copy wins in sync.
    var updatedAt = Date.now

    var typography: NoteFont { font ?? NoteFont() }

    var displayTitle: String { title.isEmpty ? "Untitled" : title }

    /// Title and block text, lowercased, for search.
    var searchText: String { (title + " " + blocks.map(\.text).joined(separator: " ")).lowercased() }

    /// Second line of a list row: the first non-empty line of text, or what kind of content the page has.
    var snippet: String {
        if let block = blocks.first(where: { $0.kind.isText && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return NoteText.plain(block.text)
        }
        if blocks.contains(where: { $0.kind == .code }) { return "Code" }
        if blocks.contains(where: { $0.kind == .math }) { return "Equation" }
        return "No additional text"
    }

    var wordCount: Int {
        let text = title + " " + blocks.map(\.text).joined(separator: " ")
        return text.split { $0.isWhitespace || "$`*#=~\\{}()".contains($0) }.count
    }

    var hasBengali: Bool { NoteText.hasBengali(title) || blocks.contains { NoteText.hasBengali($0.text) } }
}

struct NoteBlock: Identifiable, Equatable, Codable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case p, h1, h2, h3, bullet, num, todo, quote, code, math, hr

        var id: Self { self }

        var title: String {
            switch self {
            case .p: "Text"
            case .h1: "Heading 1"
            case .h2: "Heading 2"
            case .h3: "Heading 3"
            case .bullet: "Bulleted list"
            case .num: "Numbered list"
            case .todo: "Checklist"
            case .quote: "Quote"
            case .code: "Code block"
            case .math: "Math block"
            case .hr: "Divider"
            }
        }

        var systemImage: String {
            switch self {
            case .p: "text.alignleft"
            case .h1: "textformat.size.larger"
            case .h2: "textformat.size"
            case .h3: "textformat.size.smaller"
            case .bullet: "list.bullet"
            case .num: "list.number"
            case .todo: "checklist"
            case .quote: "text.quote"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .math: "sum"
            case .hr: "minus"
            }
        }

        /// The markdown that turns a text block into this kind, shown in the block menus.
        var markdown: String {
            switch self {
            case .p: ""
            case .h1: "#"
            case .h2: "##"
            case .h3: "###"
            case .bullet: "-"
            case .num: "1."
            case .todo: "[]"
            case .quote: ">"
            case .code: "```"
            case .math: "$$"
            case .hr: "---"
            }
        }

        /// Blocks edited as one line of inline markdown (everything but code, math and dividers).
        var isText: Bool { self != .code && self != .math && self != .hr }
        /// Kinds that Return continues onto the next block.
        var continues: Bool { self == .bullet || self == .num || self == .todo }
    }

    var id: ID
    var kind: Kind
    var text: String
    var lang: CodeLanguage?
    var done: Bool?

    init(id: ID = newID(), _ kind: Kind = .p, _ text: String = "", lang: CodeLanguage? = nil, done: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.lang = lang ?? (kind == .code ? .python : nil)
        self.done = done ?? (kind == .todo ? false : nil)
    }
}

enum CodeLanguage: String, Codable, CaseIterable, Identifiable {
    case python, javascript, typescript, cpp, c, java, go, rust, sql, bash, json, xml, css, plaintext

    var id: Self { self }

    var title: String {
        switch self {
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .cpp: "C++"
        case .c: "C"
        case .java: "Java"
        case .go: "Go"
        case .rust: "Rust"
        case .sql: "SQL"
        case .bash: "Shell"
        case .json: "JSON"
        case .xml: "HTML"
        case .css: "CSS"
        case .plaintext: "Plain text"
        }
    }
}

/// Per-page typography from the editor's "Aa অ" menu.
struct NoteFont: Equatable, Codable {
    enum Latin: String, Codable, CaseIterable, Identifiable {
        case sans, serif, rounded
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var design: Font.Design {
            switch self {
            case .sans: .default
            case .serif: .serif
            case .rounded: .rounded
            }
        }
    }

    /// Bengali typefaces bundled in `Fonts/` (all SIL Open Font License).
    enum Bengali: String, Codable, CaseIterable, Identifiable {
        case notoSans = "noto-sans", hind, notoSerif = "noto-serif", tiro
        var id: Self { self }
        var title: String {
            switch self {
            case .notoSans: "Noto Sans Bengali"
            case .hind: "Hind Siliguri"
            case .notoSerif: "Noto Serif Bengali"
            case .tiro: "Tiro Bangla"
            }
        }
    }

    enum Size: String, Codable, CaseIterable, Identifiable {
        case s, m, l
        var id: Self { self }
        var title: String {
            switch self {
            case .s: "Small"
            case .m: "Medium"
            case .l: "Large"
            }
        }
        var points: CGFloat {
            switch self {
            case .s: 14
            case .m: 15.5
            case .l: 17
            }
        }
    }

    var latin = Latin.sans
    var bengali = Bengali.notoSans
    var size = Size.m
}

/// Plain-text helpers for inline note markdown.
enum NoteText {
    static func hasBengali(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) }
    }

    /// Strips inline markdown and LaTeX commands, for list snippets and search excerpts.
    static func plain(_ s: String) -> String {
        s.replacing(/\[([^\]]+)\]\([^)]+\)/) { String($0.1) }
            .replacing(/\\[a-zA-Z]+/, with: " ")
            .replacing(/[*~=`$#>{}\\_^]/, with: "")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
