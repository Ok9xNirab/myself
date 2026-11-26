import SwiftUI

/// Help › Markdown Guidelines: what the note editor understands, since its toolbar has no formatting buttons.
struct MarkdownGuideView: View {
    static let windowID = "markdownGuide"

    private struct Row: Identifiable {
        var syntax: String
        var meaning: String
        /// Rendered with the editor's inline markdown, to show the result.
        var example: String?
        var id: String { syntax + meaning }
    }

    private struct Section: Identifiable {
        var title: String
        var note: String?
        var rows: [Row]
        var id: String { title }
    }

    private let sections: [Section] = [
        Section(title: "Text", note: "Inside any text block. Select text first to wrap it with a shortcut.", rows: [
            Row(syntax: "**bold**", meaning: "Bold · ⌘B", example: "**bold**"),
            Row(syntax: "*italic*", meaning: "Italic · ⌘I", example: "*italic*"),
            Row(syntax: "~~strike~~", meaning: "Strikethrough · ⇧⌘X", example: "~~strike~~"),
            Row(syntax: "==highlight==", meaning: "Highlight · ⇧⌘H", example: "==highlight=="),
            Row(syntax: "`code`", meaning: "Inline code · ⌘E", example: "`code`"),
            Row(syntax: "[label](https://…)", meaning: "Web link · ⌘K", example: "[label](https://example.com)"),
            Row(syntax: "$x^2$", meaning: "Inline LaTeX math · ⇧⌘M", example: "$x^2 + y^2$"),
            Row(syntax: "[[", meaning: "Link to another note · ⇧⌘L", example: nil),
        ]),
        Section(title: "Blocks", note: "Type at the start of an empty line; the prefix turns the line into that block.", rows: [
            Row(syntax: "# ", meaning: "Heading 1"),
            Row(syntax: "## ", meaning: "Heading 2"),
            Row(syntax: "### ", meaning: "Heading 3"),
            Row(syntax: "- ", meaning: "Bulleted list (or * )"),
            Row(syntax: "1. ", meaning: "Numbered list"),
            Row(syntax: "[ ] ", meaning: "Checklist (or [] )"),
            Row(syntax: "> ", meaning: "Quote"),
            Row(syntax: "```", meaning: "Code block, with a language picker"),
            Row(syntax: "$$", meaning: "LaTeX math block"),
            Row(syntax: "---", meaning: "Divider"),
            Row(syntax: "| a | b |", meaning: "Table: paste lines like this; Tab moves to the next cell"),
            Row(syntax: "/", meaning: "Block menu: /image, /table, /code…"),
        ]),
        Section(title: "Editing", note: nil, rows: [
            Row(syntax: "Esc", meaning: "Select the current block"),
            Row(syntax: "⌘A  ⌘A", meaning: "Select the block's text, then every block"),
            Row(syntax: "⌘C  ⌘X  ⌫", meaning: "Copy, cut or delete selected blocks as markdown"),
            Row(syntax: "⇧⌘R", meaning: "Reader mode"),
            Row(syntax: "⌥⌘N", meaning: "New note"),
            Row(syntax: "Paste", meaning: "Markdown splits into blocks; an image becomes an image block"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Markdown in Notes")
                        .font(.system(size: 24, weight: .bold))
                    Text("Notes are written in markdown. Type the syntax and it renders when you leave the block.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink2)
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 15, weight: .semibold))
                        if let note = section.note {
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.ink3)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { Divider() }
                                rowView(row)
                            }
                        }
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 14) {
            Text(row.syntax)
                .font(.system(size: 12.5, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 170, alignment: .leading)
            Text(row.meaning)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let example = row.example {
                NoteMarkdown.text(example, size: 13.5, weight: .regular)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

#if os(macOS)
/// Replaces the Help menu's default item, which only says help isn't available.
struct HelpCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Markdown Guidelines") { openWindow(id: MarkdownGuideView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
    }
}
#endif

#Preview {
    MarkdownGuideView()
}
