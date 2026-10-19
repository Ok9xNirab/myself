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
    var createdAt = Date.now
    /// Last change to the title or blocks; shown and sorted as "Date edited".
    var editedAt = Date.now
    /// Last change of any kind, including pinning and moving. Decides which copy wins in sync.
    var updatedAt = Date.now

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
        if blocks.contains(where: { $0.kind == .image }) { return "Image" }
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
        case p, h1, h2, h3, bullet, num, todo, quote, code, math, image, hr

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
            case .image: "Image"
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
            case .image: "photo"
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
            case .image: ""
            case .hr: "---"
            }
        }

        /// Blocks edited as one line of inline markdown (everything but code, math, images and dividers).
        var isText: Bool { self != .code && self != .math && self != .image && self != .hr }
        /// Blocks with a text view that the arrow keys and Backspace can move the caret into.
        var hasCaret: Bool { self != .image && self != .hr }
        /// Kinds that Return continues onto the next block.
        var continues: Bool { self == .bullet || self == .num || self == .todo }
    }

    var id: ID
    var kind: Kind
    /// The line of markdown, code or LaTeX; an image block's caption.
    var text: String
    var lang: CodeLanguage?
    var done: Bool?
    /// An image block's file name in the sync folder's `noteimages/`; nil until an image is chosen.
    var image: String?

    init(id: ID = newID(), _ kind: Kind = .p, _ text: String = "", lang: CodeLanguage? = nil, done: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.lang = lang ?? (kind == .code ? .python : nil)
        self.done = done ?? (kind == .todo ? false : nil)
    }
}

extension NoteBlock {
    /// Splits pasted markdown into blocks: headings, lists, checklists, quotes, fenced code, `$$` math and dividers
    /// become their kinds, tables become a plain-text code block, other lines paragraphs. Blank lines only separate.
    /// Nested lists are flattened.
    static func blocks(fromMarkdown markdown: String) -> [NoteBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [NoteBlock] = []
        var i = 0
        /// Lines up to (not including) the closing `fence`, which is skipped; or to the end if it never comes.
        func body(until fence: (String) -> Bool) -> String {
            var collected: [String] = []
            while i < lines.count, !fence(lines[i].trimmingCharacters(in: .whitespaces)) {
                collected.append(lines[i])
                i += 1
            }
            i += 1
            return collected.joined(separator: "\n")
        }
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if line.isEmpty { continue }
            if line.hasPrefix("```") {
                let lang = CodeLanguage(fence: String(line.dropFirst(3)))
                blocks.append(NoteBlock(.code, body { $0.hasPrefix("```") }, lang: lang))
            } else if line == "$$" {
                blocks.append(NoteBlock(.math, body { $0 == "$$" }))
            } else if line.count > 4, line.hasPrefix("$$"), line.hasSuffix("$$") {
                blocks.append(NoteBlock(.math, String(line.dropFirst(2).dropLast(2))))
            } else if line.hasPrefix("|") {
                var rows = [line]
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[i].trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(NoteBlock(.code, rows.joined(separator: "\n"), lang: .plaintext))
            } else if line.wholeMatch(of: /(-\s*){3,}|(\*\s*){3,}|(_\s*){3,}/) != nil {
                blocks.append(NoteBlock(.hr))
            } else if let m = line.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                let kind: Kind = switch m.1.count { case 1: .h1; case 2: .h2; default: .h3 }
                blocks.append(NoteBlock(kind, String(m.2)))
            } else if let m = line.wholeMatch(of: /(?:[-*+]\s+)?\[([ xX])\]\s+(.*)/) {
                blocks.append(NoteBlock(.todo, String(m.2), done: m.1 != " "))
            } else if let m = line.wholeMatch(of: /[-*+]\s+(.*)/) {
                blocks.append(NoteBlock(.bullet, String(m.1)))
            } else if let m = line.wholeMatch(of: /\d+[.)]\s+(.*)/) {
                blocks.append(NoteBlock(.num, String(m.1)))
            } else if line.hasPrefix(">") {
                let quote = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !quote.isEmpty { blocks.append(NoteBlock(.quote, quote)) }
            } else {
                blocks.append(NoteBlock(.p, line))
            }
        }
        return blocks
    }
}

extension CodeLanguage {
    /// The language named after a markdown code fence (```js), plain text when it's missing or unknown.
    init(fence: String) {
        let name = fence.trimmingCharacters(in: .whitespaces).lowercased()
        let aliases: [String: CodeLanguage] = ["py": .python, "js": .javascript, "jsx": .javascript, "ts": .typescript, "tsx": .typescript,
                                               "c++": .cpp, "cc": .cpp, "sh": .bash, "shell": .bash, "zsh": .bash, "html": .xml,
                                               "golang": .go, "rs": .rust, "text": .plaintext, "txt": .plaintext]
        self = CodeLanguage(rawValue: name) ?? aliases[name] ?? .plaintext
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
