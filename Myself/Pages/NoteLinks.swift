import SwiftUI

// Links between notes. A link is `[[label|note id]]` in a block's text: typed with "[[" or ⇧⌘L (`NoteLinkPickerView`),
// parsed by `NoteMarkdown`, and listed under the note as "Linked notes" and "Mentioned in" (`NoteLinksSection`).

/// The "[[" picker while it's open on a block.
struct NoteLinkPicker: Equatable {
    var blockID: ID
    /// What the link replaces (UTF-16): the "[[" just typed, or the selected text.
    var range: NSRange
    /// The link's text when it was made from a selection; otherwise the picked note's title is used.
    var label: String

    /// A label can't hold the characters that end one.
    static func cleanLabel(_ text: String) -> String {
        text.replacing(/[\[\]|\n]/, with: "").trimmingCharacters(in: .whitespaces)
    }
}

/// A note link the pointer is resting on, in the editor scroll area's coordinates.
struct NoteLinkHover: Equatable {
    var id: ID
    var rect: CGRect
}

/// The reader view's position in the scroll area; a class so tracking it doesn't redraw the editor.
final class NoteLinkOrigin {
    var point = CGPoint.zero
}

/// Where a block's note links were last drawn, written by `NoteLinkRenderer` and read for hover and clicks. Drawing can
/// happen off the main thread, hence the lock. Rects are relative to the text, and `origin` places the text in the
/// editor's scroll area.
nonisolated final class NoteLinkRects: @unchecked Sendable {
    private let lock = NSLock()
    private var rects: [(id: String, rect: CGRect)] = []
    private var origin = CGPoint.zero

    func set(_ rects: [(id: String, rect: CGRect)]) {
        lock.withLock { self.rects = rects }
    }

    func setOrigin(_ origin: CGPoint) {
        lock.withLock { self.origin = origin }
    }

    /// The link at a point in the scroll area, and all of its rect there (the part on the line under the pointer).
    func hit(at point: CGPoint) -> (id: String, rect: CGRect)? {
        lock.withLock {
            let inner = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            guard let found = rects.first(where: { $0.rect.contains(inner) }) else { return nil }
            return (found.id, found.rect.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    func link(at point: CGPoint) -> String? { hit(at: point)?.id }
}

/// Draws text as usual and records where its note links ended up. `Text` has no per-run hover or tap.
struct NoteLinkRenderer: TextRenderer {
    let rects: NoteLinkRects

    nonisolated func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var found: [(id: String, rect: CGRect)] = []
        for line in layout {
            for run in line {
                if let link = run[NoteLinkAttribute.self] { found.append((link.id, run.typographicBounds.rect)) }
            }
            context.draw(line)
        }
        rects.set(found)
    }
}

/// Follows the pointer over a block's rendered text, for link previews and the hand cursor. Blocks without links skip it.
struct NoteLinkTracking: ViewModifier {
    var active: Bool
    var rects: NoteLinkRects
    var onHover: (ID?, CGRect) -> Void
    @State private var current: ID?

    func body(content: Content) -> some View {
        if active {
            content
                .textRenderer(NoteLinkRenderer(rects: rects))
                .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(NoteEditor.linkSpace)).origin } action: { rects.setOrigin($0) }
                .onContinuousHover(coordinateSpace: .named(NoteEditor.linkSpace)) { phase in
                    switch phase {
                    case .active(let point):
                        let hit = rects.hit(at: point)
                        guard hit?.id != current else { return }
                        current = hit?.id
                        setCursor(hit != nil)
                        onHover(hit?.id, hit?.rect ?? .zero)
                    case .ended:
                        guard current != nil else { return }
                        current = nil
                        setCursor(false)
                        onHover(nil, .zero)
                    }
                }
        } else {
            content
        }
    }

    private func setCursor(_ onLink: Bool) {
        #if os(macOS)
        if onLink { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        #endif
    }
}

// MARK: - Picker

/// The search popover opened by "[[": existing notes matching the query, then a row to create one.
struct NoteLinkPickerView: View {
    var picker: NoteLinkPicker
    var noteID: ID
    /// Where a new note would go; nil hides the row that creates one.
    var home: NoteCategory?
    var onPick: (ID, String) -> Void
    var onCreate: (String) -> Void
    var onCancel: () -> Void

    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private enum Row: Identifiable {
        case note(NoteSummary), create(String)
        var id: String {
            switch self {
            case .note(let note): note.id
            case .create: "@new"
            }
        }
    }

    /// Titles starting with the query first, then ordinary notes before reading notes, then the most recently edited.
    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let lower = q.lowercased()
        let others = store.noteSummaries.filter { $0.id != noteID && store.isNoteVisible($0) }
        func prefixRank(_ note: NoteSummary) -> Int { note.title.lowercased().hasPrefix(lower) ? 0 : 1 }
        let matches = others
            .filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }
            .sorted { a, b in
                (prefixRank(a), a.bookID == nil ? 0 : 1, b.editedAt) < (prefixRank(b), b.bookID == nil ? 0 : 1, a.editedAt)
            }
        var out = matches.prefix(8).map(Row.note)
        let exists = others.contains { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == lower }
        if !q.isEmpty, home != nil, !exists, store.isEnabled(.notes) { out.append(.create(q)) }
        return out
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "link").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink3)
                TextField("Link to a note\u{2026}", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { if rows.indices.contains(index) { pick(rows[index]) } }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(picker.label.isEmpty ? "Notes" : "Link \u{201C}\(picker.label)\u{201D} to")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                if rows.isEmpty {
                    Text("No other notes yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    rowView(row, on: i == index)
                        .onHover { if $0 { index = i } }
                        .onTapGesture { pick(row) }
                }
            }
            .padding(5)
        }
        .frame(width: 324)
        .onAppear {
            query = picker.label
            focused = true
        }
        .onChange(of: query) { index = 0 }
        .onKeyPress(.downArrow) { index = min(rows.count - 1, index + 1); return .handled }
        .onKeyPress(.upArrow) { index = max(0, index - 1); return .handled }
        .onKeyPress(.escape) { onCancel(); return .handled }
    }

    private func rowView(_ row: Row, on: Bool) -> some View {
        HStack(spacing: 8) {
            switch row {
            case .note(let note):
                let origin = store.noteOrigin(of: note)
                Image(systemName: note.bookID == nil ? "note.text" : "book.pages").font(.system(size: 12)).frame(width: 16)
                Text(note.displayTitle).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    ColorDot(color: origin.color, size: 6)
                    Text(origin.name).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(on ? .white.opacity(0.85) : Palette.ink3)
                .frame(maxWidth: 120, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
            case .create(let title):
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 16)
                Text("Create \u{201C}\(title)\u{201D}").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text("in \(home?.name ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? .white.opacity(0.85) : Palette.ink3)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(on ? .white : .primary)
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(on ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func pick(_ row: Row) {
        switch row {
        case .note(let note): onPick(note.id, note.title)
        case .create(let title): onCreate(title)
        }
    }
}

// MARK: - Preview

/// Puts the preview under the hovered link, or above it when there's no room, kept inside the scroll area.
struct NoteLinkPreviewPlacement: View {
    var hover: NoteLinkHover

    private static let width: CGFloat = 290
    /// The preview's tallest: three lines of text plus the header and hint.
    private static let tallest: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            let x = max(10, min(hover.rect.minX - 10, geo.size.width - Self.width - 10))
            if hover.rect.maxY + 6 + Self.tallest > geo.size.height {
                NoteLinkPreview(id: hover.id)
                    .frame(width: Self.width)
                    .frame(height: max(0, hover.rect.minY - 6), alignment: .bottom)
                    .offset(x: x)
            } else {
                NoteLinkPreview(id: hover.id)
                    .frame(width: Self.width)
                    .offset(x: x, y: hover.rect.maxY + 6)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The card shown while the pointer rests on a link: where the note lives, its title and the start of its text.
private struct NoteLinkPreview: View {
    var id: ID
    @Environment(AppStore.self) private var store

    var body: some View {
        let note = store.notes.first { $0.id == id }
        VStack(alignment: .leading, spacing: 3) {
            if let note {
                let origin = store.noteOrigin(of: NoteSummary(note))
                HStack(spacing: 5) {
                    ColorDot(color: origin.color, size: 6)
                    Text(origin.name).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                Text(note.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(excerpt(note))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(3)
                #if os(macOS)
                Text("Click to open beside this note").font(.system(size: 11)).foregroundStyle(Palette.ink3).padding(.top, 4)
                #endif
            } else {
                Text("Note not found").font(.system(size: 14, weight: .semibold))
                Text("The linked note was deleted.").font(.system(size: 12.5)).foregroundStyle(Palette.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.clear).shadow(color: .black.opacity(0.16), radius: 15, y: 10))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func excerpt(_ note: Note) -> String {
        let lines = note.blocks.lazy.filter { $0.kind.isText && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3).map(\.text)
        let text = NoteText.plain(lines.joined(separator: " · "))
        return text.isEmpty ? "Empty note" : text
    }
}

// MARK: - Under the note

/// "Linked notes" (what this note links to) and "Mentioned in" (what links to it), at the foot of the page.
struct NoteLinksSection: View {
    var noteID: ID
    var onOpen: (ID) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let all = store.noteSummaries
        let links = all.first { $0.id == noteID }?.linkIDs ?? []
        let outgoing = links.compactMap { id in all.first { $0.id == id } }
        let backlinks = all.filter { $0.id != noteID && $0.linkIDs.contains(noteID) && store.isNoteVisible($0) }
        if !outgoing.isEmpty || !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.bottom, 16)
                if !outgoing.isEmpty {
                    heading("Linked notes · \(outgoing.count)")
                    FlowLayout(spacing: 6) {
                        ForEach(outgoing) { LinkChip(note: $0, origin: store.noteOrigin(of: $0)) { onOpen($0) } }
                    }
                    .padding(.bottom, 18)
                }
                if !backlinks.isEmpty {
                    heading("Mentioned in · \(backlinks.count)")
                    VStack(spacing: 4) {
                        ForEach(backlinks) { note in
                            BacklinkRow(note: note, origin: store.noteOrigin(of: note), excerpt: excerpt(in: note.id)) { onOpen(note.id) }
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).padding(.bottom, 8)
    }

    /// The first block of a note that mentions this one.
    private func excerpt(in id: ID) -> String {
        let block = store.notes.first { $0.id == id }?.blocks.first { NoteMarkdown.linkIDs($0.text).contains(noteID) }
        return NoteText.plain(block?.text ?? "")
    }
}

private struct LinkChip: View {
    var note: NoteSummary
    var origin: (name: String, color: Color)
    var onOpen: (ID) -> Void
    @State private var hover = HoverState()

    var body: some View {
        Button { onOpen(note.id) } label: {
            HStack(spacing: 6) {
                ColorDot(color: origin.color, size: 6)
                Text(note.displayTitle).lineLimit(1)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background { HoverFill(hover: hover, color: Color.accentColor.opacity(0.14)) }
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}

private struct BacklinkRow: View {
    var note: NoteSummary
    var origin: (name: String, color: Color)
    var excerpt: String
    var onOpen: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ColorDot(color: origin.color, size: 6)
                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(origin.name + (note.location.map { " · \($0)" } ?? ""))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
                Text(excerpt).font(.system(size: 12.5)).foregroundStyle(Palette.ink2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background { HoverFill(hover: hover, color: Color.accentColor.opacity(0.1)) }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}

/// A reading note's place in the book, in the line under its title.
struct NoteLocationField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "book.pages").foregroundStyle(Palette.ink2)
            TextField("Page or chapter", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(width: 110)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
        .help("Where in the book")
    }
}
