import SwiftUI

/// The block editor for one note: formatting bar, page (breadcrumb, title, blocks) and status bar.
///
/// Every block shows its rendered markdown until it's clicked; then it swaps to a `NoteTextView` with the raw text.
/// Code blocks are always editable, and math blocks show their LaTeX with a live preview while focused.
struct NoteEditor: View {
    var note: Note
    var isFresh: Bool
    /// The Notes page's list toggle; nil in a note's own window, which has no list.
    var showsBrowser: Binding<Bool>?
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @Environment(AppStore.self) private var store
    /// Block (or `titleID`) whose text view is showing.
    @State private var editingID: ID?
    /// Last block that had focus, for the toolbar's block buttons.
    @State private var activeID: ID?
    @State private var pendingFocus: PendingFocus?
    @State private var slash: SlashMenu?
    @State private var showsTypography = false
    @State private var textFocus = NoteTextFocus()
    @State private var paperWidth: CGFloat = 780

    private static let titleID = "title"

    private struct PendingFocus: Equatable {
        var id: ID
        var request: NoteFocusRequest
    }

    /// The "/" block menu under a text block.
    struct SlashMenu: Equatable {
        var id: ID
        var items: [NoteBlock.Kind]
        var index = 0
    }

    /// The note as the store has it now; `note` can lag behind within one event.
    private var current: Note { store.notes.first { $0.id == note.id } ?? note }
    private var typography: NoteFont { note.typography }
    private var size: CGFloat { typography.size.points }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                paper
                    .frame(maxWidth: 780)
                    .padding(.leading, paperWidth < 640 ? 52 : 64)
                    .padding(.trailing, paperWidth < 640 ? 36 : 64)
                    .padding(.top, 30)
                    .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paperWidth = $0 }
            Divider()
            statusBar
        }
        .onAppear { if isFresh { focus(Self.titleID, caret: nil) } }
    }

    // MARK: Page

    private var paper: some View {
        let category = store.noteCategory(note.categoryID)
        var number = 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ColorDot(color: category?.color ?? Palette.ink3, size: 8)
                Text(category?.name ?? "Uncategorized")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                Text(note.displayTitle).lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink3)
            .padding(.bottom, 12)

            NoteTextView(text: Binding(get: { current.title }, set: { title in store.editNote(note.id) { $0.title = title.replacingOccurrences(of: "\n", with: "") } }),
                         font: NoteTypeface.platformFont(typography, size: size * 2, weight: .bold),
                         lineSpacing: NoteText.hasBengali(note.title) ? size * 0.4 : size * 0.1,
                         placeholder: "Untitled",
                         focus: request(for: Self.titleID),
                         onKey: titleKey,
                         onFocusChange: { focusChanged(Self.titleID, $0) })
                .padding(.bottom, 6)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Edited \(NoteDates.ago(note.editedAt, now: context.date)) · \(note.wordCount) words")
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink3)
            .padding(.bottom, 20)

            ForEach(note.blocks) { block in
                let _ = (number = block.kind == .num ? number + 1 : 0)
                NoteBlockRow(block: block, number: number, editor: self)
                    .zIndex(slash?.id == block.id ? 1 : 0)
            }

            Color.clear
                .frame(height: 160)
                .contentShape(Rectangle())
                .onTapGesture(perform: tailClick)
        }
    }

    // MARK: Focus

    fileprivate func request(for id: ID) -> NoteFocusRequest? {
        pendingFocus?.id == id ? pendingFocus?.request : nil
    }

    fileprivate func isEditing(_ id: ID) -> Bool { editingID == id || pendingFocus?.id == id }

    /// Shows `id`'s text view and puts the caret at `caret` (UTF-16; `nil` = end).
    fileprivate func focus(_ id: ID, caret: Int?) {
        editingID = id
        if id != Self.titleID { activeID = id }
        pendingFocus = PendingFocus(id: id, request: NoteFocusRequest(caret: caret))
    }

    fileprivate func focusChanged(_ id: ID, _ focused: Bool) {
        if focused {
            editingID = id
            if id != Self.titleID { activeID = id }
        } else {
            if editingID == id { editingID = nil }
            if pendingFocus?.id == id { pendingFocus = nil }
            if slash?.id == id { slash = nil }
        }
    }

    private func blur() {
        editingID = nil
        pendingFocus = nil
        slash = nil
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    // MARK: Block changes

    private func setBlocks(_ change: (inout [NoteBlock]) -> Void) { store.editNote(note.id) { change(&$0.blocks) } }

    fileprivate func update(_ id: ID, _ change: (inout NoteBlock) -> Void) {
        setBlocks { blocks in
            if let i = blocks.firstIndex(where: { $0.id == id }) { change(&blocks[i]) }
        }
    }

    private func index(_ id: ID) -> Int? { current.blocks.firstIndex { $0.id == id } }

    private static let shortcuts: [(String, NoteBlock.Kind)] = [("### ", .h3), ("## ", .h2), ("# ", .h1), ("- ", .bullet), ("* ", .bullet),
                                                                ("1. ", .num), ("[] ", .todo), ("[ ] ", .todo), ("> ", .quote)]

    /// Text typed into a block. In a plain paragraph, markdown prefixes turn it into another kind and "/" opens the block menu.
    fileprivate func change(_ block: NoteBlock, to text: String) {
        if block.kind == .p {
            for (prefix, kind) in Self.shortcuts where text.hasPrefix(prefix) {
                update(block.id) { $0.kind = kind; $0.text = String(text.dropFirst(prefix.count)); if kind == .todo { $0.done = false } }
                focus(block.id, caret: 0)
                return
            }
            switch text {
            case "```": update(block.id) { $0.kind = .code; $0.text = ""; $0.lang = .python }; focus(block.id, caret: 0); return
            case "$$": update(block.id) { $0.kind = .math; $0.text = "" }; focus(block.id, caret: 0); return
            case "---": turnInto(block, .hr); return
            default: break
            }
            if let match = text.wholeMatch(of: /\/(\S*)/) {
                let q = match.1.lowercased()
                let items = NoteBlock.Kind.allCases.filter { $0.title.lowercased().contains(q) || $0.rawValue.hasPrefix(q) }
                slash = SlashMenu(id: block.id, items: items, index: slash?.id == block.id ? min(slash!.index, max(0, items.count - 1)) : 0)
            } else if slash?.id == block.id {
                slash = nil
            }
        }
        update(block.id) { $0.text = text }
    }

    fileprivate func turnInto(_ block: NoteBlock, _ kind: NoteBlock.Kind, clear: Bool = false) {
        slash = nil
        if kind == .hr {
            let next = NoteBlock()
            setBlocks { blocks in
                guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { return }
                blocks[i] = NoteBlock(id: block.id, .hr)
                blocks.insert(next, at: i + 1)
            }
            focus(next.id, caret: 0)
            return
        }
        update(block.id) { b in
            b.kind = kind
            if clear { b.text = "" }
            if kind == .code, b.lang == nil { b.lang = .python }
            if kind == .todo, b.done == nil { b.done = false }
        }
        focus(block.id, caret: nil)
    }

    /// Inserts a new block after `id` (at the end when `nil`) and focuses it. A divider gets an empty paragraph after it.
    fileprivate func insert(_ kind: NoteBlock.Kind, after id: ID?) {
        let block = NoteBlock(kind)
        let paragraph = NoteBlock()
        setBlocks { blocks in
            let at = id.flatMap { id in blocks.firstIndex { $0.id == id } }.map { $0 + 1 } ?? blocks.count
            blocks.insert(block, at: at)
            if kind == .hr { blocks.insert(paragraph, at: at + 1) }
        }
        focus(kind == .hr ? paragraph.id : block.id, caret: 0)
    }

    fileprivate func move(_ id: ID, by offset: Int) {
        setBlocks { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }), blocks.indices.contains(i + offset) else { return }
            blocks.swapAt(i, i + offset)
        }
    }

    fileprivate func duplicate(_ id: ID) {
        setBlocks { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            var copy = blocks[i]
            copy.id = newID()
            blocks.insert(copy, at: i + 1)
        }
    }

    fileprivate func remove(_ id: ID) {
        setBlocks { $0.removeAll { $0.id == id } }
    }

    /// Leaves a code or math block: focuses the next block, or adds a paragraph if there's none to edit.
    private func exitDown(_ id: ID) {
        let blocks = current.blocks
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if blocks.indices.contains(i + 1), blocks[i + 1].kind != .hr {
            focus(blocks[i + 1].id, caret: 0)
        } else {
            let paragraph = NoteBlock()
            setBlocks { $0.insert(paragraph, at: i + 1) }
            focus(paragraph.id, caret: 0)
        }
    }

    private func tailClick() {
        if let last = current.blocks.last, last.kind == .p, last.text.isEmpty {
            focus(last.id, caret: nil)
        } else {
            insert(.p, after: nil)
        }
    }

    // MARK: Keys

    private func titleKey(_ key: NoteKey, _ context: NoteKeyContext) -> Bool {
        switch key {
        case .return:
            enterFirstBlock()
            return true
        case .down where context.atEnd:
            enterFirstBlock()
            return true
        case .escape:
            blur()
            return true
        case .tab:
            return true
        default:
            return false
        }
    }

    private func enterFirstBlock() {
        if let first = current.blocks.first, first.kind != .hr {
            focus(first.id, caret: 0)
        } else {
            let paragraph = NoteBlock()
            setBlocks { $0.insert(paragraph, at: 0) }
            focus(paragraph.id, caret: 0)
        }
    }

    fileprivate func textKey(_ id: ID, _ key: NoteKey, _ context: NoteKeyContext) -> Bool {
        let blocks = current.blocks
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return false }
        let block = blocks[i]

        if var menu = slash, menu.id == id, !menu.items.isEmpty {
            switch key {
            case .down: menu.index = (menu.index + 1) % menu.items.count; slash = menu; return true
            case .up: menu.index = (menu.index - 1 + menu.items.count) % menu.items.count; slash = menu; return true
            case .return: turnInto(block, menu.items[menu.index], clear: true); return true
            case .escape: slash = nil; return true
            default: break
            }
        }

        switch key {
        case .return:
            if [.bullet, .num, .todo, .quote].contains(block.kind), block.text.isEmpty {
                update(id) { $0.kind = .p }
                focus(id, caret: 0)
                return true
            }
            let text = block.text as NSString
            let before = text.substring(to: context.selection.location)
            let after = text.substring(from: NSMaxRange(context.selection))
            let next = NoteBlock(block.kind.continues ? block.kind : .p, after)
            setBlocks { blocks in
                blocks[i].text = before
                blocks.insert(next, at: i + 1)
            }
            focus(next.id, caret: 0)
            return true
        case .backspace:
            guard context.atStart else { return false }
            if block.kind != .p {
                update(id) { $0.kind = .p }
                focus(id, caret: 0)
                return true
            }
            guard i > 0 else { return false }
            let previous = blocks[i - 1]
            if previous.kind.isText {
                let caret = (previous.text as NSString).length
                setBlocks { blocks in
                    blocks[i - 1].text += block.text
                    blocks.remove(at: i)
                }
                focus(previous.id, caret: caret)
            } else if previous.kind == .hr {
                setBlocks { $0.remove(at: i - 1) }
            } else if block.text.isEmpty {
                setBlocks { $0.remove(at: i) }
                focus(previous.id, caret: nil)
            }
            return true
        case .up:
            guard context.atStart, let previous = blocks[..<i].last(where: { $0.kind != .hr }) else { return false }
            focus(previous.id, caret: nil)
            return true
        case .down:
            guard context.atEnd, let next = blocks[(i + 1)...].first(where: { $0.kind != .hr }) else { return false }
            focus(next.id, caret: 0)
            return true
        case .escape:
            blur()
            return true
        case .tab:
            return true
        case .commandReturn:
            guard block.kind == .todo else { return false }
            update(id) { $0.done = !($0.done ?? false) }
            return true
        }
    }

    fileprivate func codeKey(_ id: ID, _ key: NoteKey, _ context: NoteKeyContext) -> Bool {
        guard let block = current.blocks.first(where: { $0.id == id }) else { return false }
        switch key {
        case .tab:
            #if os(macOS)
            textFocus.textView?.insertText("    ", replacementRange: context.selection)
            #endif
            return true
        case .escape:
            blur()
            return true
        case .commandReturn:
            exitDown(id)
            return true
        case .backspace where block.text.isEmpty:
            update(id) { $0.kind = .p }
            focus(id, caret: 0)
            return true
        case .down where context.atEnd && block.text.hasSuffix("\n"):
            exitDown(id)
            return true
        case .up where context.atStart:
            return textKey(id, .up, context)
        default:
            return false
        }
    }

    fileprivate func mathKey(_ id: ID, _ key: NoteKey, _ context: NoteKeyContext) -> Bool {
        guard let block = current.blocks.first(where: { $0.id == id }) else { return false }
        switch key {
        case .escape:
            blur()
            return true
        case .commandReturn:
            exitDown(id)
            return true
        case .backspace where block.text.isEmpty:
            update(id) { $0.kind = .p }
            focus(id, caret: 0)
            return true
        case .up where context.atStart, .down where context.atEnd:
            return textKey(id, key, context)
        default:
            return false
        }
    }

    // MARK: Toolbar

    private var activeBlock: NoteBlock? { current.blocks.first { $0.id == activeID } }

    /// A text block is being typed in, so inline formatting applies.
    private var textActive: Bool {
        guard let editingID, let block = current.blocks.first(where: { $0.id == editingID }) else { return false }
        return block.kind.isText
    }

    /// Toolbar block buttons: toggle a text block's kind, or insert code, math and dividers below the active block.
    private func setKind(_ kind: NoteBlock.Kind) {
        guard let block = activeBlock else { insert(kind, after: current.blocks.last?.id); return }
        if kind == .code || kind == .math || kind == .hr {
            if block.kind.isText, block.text.isEmpty, kind != .hr { turnInto(block, kind) } else { insert(kind, after: block.id) }
            return
        }
        guard block.kind.isText else { insert(kind, after: block.id); return }
        let caret = editingID == block.id ? textFocus.selectionStart : nil
        update(block.id) { b in
            b.kind = b.kind == kind && kind != .p ? .p : kind
            if b.kind == .todo, b.done == nil { b.done = false }
        }
        focus(block.id, caret: caret)
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            if let showsBrowser {
                toolButton("Show Note List", "sidebar.left", on: !showsBrowser.wrappedValue) { showsBrowser.wrappedValue.toggle() }
                    .help(showsBrowser.wrappedValue ? "Hide note list" : "Show note list")
                separator
            }
            Picker("Paragraph style", selection: Binding(
                get: { activeBlock.map { [.h1, .h2, .h3].contains($0.kind) ? $0.kind : .p } ?? .p },
                set: { setKind($0) }
            )) {
                Text("Body").tag(NoteBlock.Kind.p)
                Text("Heading 1").tag(NoteBlock.Kind.h1)
                Text("Heading 2").tag(NoteBlock.Kind.h2)
                Text("Heading 3").tag(NoteBlock.Kind.h3)
            }
            .labelsHidden()
            .frame(width: 112)
            .disabled(!(activeBlock?.kind.isText ?? false))
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    separator
                    Group {
                        toolButton("Bold (⌘B)", "bold") { textFocus.wrap("**", "**") }
                        toolButton("Italic (⌘I)", "italic") { textFocus.wrap("*", "*") }
                        toolButton("Strikethrough (⇧⌘X)", "strikethrough") { textFocus.wrap("~~", "~~") }
                        toolButton("Highlight (⇧⌘H)", "highlighter") { textFocus.wrap("==", "==") }
                        toolButton("Inline code (⌘E)", "chevron.left.forwardslash.chevron.right") { textFocus.wrap("`", "`", placeholder: "code") }
                        toolButton("Link (⌘K)", "link") { textFocus.wrap("[", "](https://)", placeholder: "link") }
                        Button { textFocus.wrap("$", "$", placeholder: "x^2") } label: {
                            Text("x²").font(.system(size: 15, design: .serif).italic()).frame(minWidth: 28, minHeight: 28)
                        }
                        .help("Inline math (⇧⌘M)")
                    }
                    .disabled(!textActive)
                    separator
                    toolButton("Bulleted list", NoteBlock.Kind.bullet.systemImage, on: activeBlock?.kind == .bullet) { setKind(.bullet) }
                    toolButton("Numbered list", NoteBlock.Kind.num.systemImage, on: activeBlock?.kind == .num) { setKind(.num) }
                    toolButton("Checklist", NoteBlock.Kind.todo.systemImage, on: activeBlock?.kind == .todo) { setKind(.todo) }
                    toolButton("Quote", NoteBlock.Kind.quote.systemImage, on: activeBlock?.kind == .quote) { setKind(.quote) }
                    separator
                    toolButton("Code block (```)", "curlybraces", on: activeBlock?.kind == .code) { setKind(.code) }
                    toolButton("Math block ($$)", NoteBlock.Kind.math.systemImage, on: activeBlock?.kind == .math) { setKind(.math) }
                    toolButton("Divider (---)", NoteBlock.Kind.hr.systemImage) { setKind(.hr) }
                }
                .padding(.trailing, 16)
            }
            .scrollIndicators(.never)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            separator
            Button { showsTypography.toggle() } label: {
                HStack(spacing: 2) {
                    Text("Aa").font(.system(size: 13, weight: .semibold))
                    Text("অ").font(NoteTypeface.sample(.notoSans, size: 14))
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 28)
                .background(showsTypography ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .help("Typography")
            .popover(isPresented: $showsTypography, arrowEdge: .bottom) { typographyMenu }
            pageMenu
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, 10)
        .frame(height: 42)
    }

    private var separator: some View {
        Rectangle().fill(Palette.border).frame(width: 1, height: 18).padding(.horizontal, 6)
    }

    private func toolButton(_ title: String, _ systemImage: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(on ? Color.accentColor : Palette.ink2)
                .background(on ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private var pageMenu: some View {
        Menu {
            Picker("Move to", selection: Binding(get: { note.categoryID }, set: { store.moveNotes([note.id], to: $0) })) {
                ForEach(store.noteCategories) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            Divider()
            Button(note.pinned ? "Unpin Note" : "Pin Note", systemImage: note.pinned ? "pin.slash" : "pin") { store.setPinned([note.id], !note.pinned) }
            Button("Duplicate Page", systemImage: "plus.square.on.square", action: onDuplicate)
            Button("Delete Page", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Page options")
    }

    private var typographyMenu: some View {
        let font = typography
        let set = { (change: (inout NoteFont) -> Void) in
            store.editNote(note.id) { n in
                var f = n.typography
                change(&f)
                n.font = f
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Latin text").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
            Picker("Latin text", selection: Binding(get: { font.latin }, set: { v in set { $0.latin = v } })) {
                ForEach(NoteFont.Latin.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Bengali typeface").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).padding(.top, 6)
            ForEach(NoteFont.Bengali.allCases) { option in
                Button { set { $0.bengali = option } } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("বাংলা লিপি · ক্ষ ত্র জ্ঞ").font(NoteTypeface.sample(option, size: 17))
                        Text(option.title).font(.system(size: 11)).foregroundStyle(Palette.ink3)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(font.bengali == option ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        if font.bengali == option { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor.opacity(0.5)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Size").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).padding(.top, 6)
            Picker("Size", selection: Binding(get: { font.size }, set: { v in set { $0.size = v } })) {
                ForEach(NoteFont.Size.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Bengali characters are detected automatically and set in the selected typeface with taller line spacing.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(14)
        .frame(width: 286)
    }

    // MARK: Status bar

    private var statusBar: some View {
        let characters = (note.title + " " + note.blocks.map(\.text).joined(separator: " ")).count
        let codeCount = note.blocks.filter { $0.kind == .code }.count
        return HStack(spacing: 14) {
            Text("\(note.wordCount) words")
            if paperWidth > 560 { Text("\(characters) characters") }
            Spacer()
            if note.hasBengali {
                HStack(spacing: 6) {
                    Text("অ")
                        .font(NoteTypeface.sample(typography.bengali, size: 11))
                        .frame(width: 16, height: 16)
                        .background(Palette.amber.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.primary)
                    Text("Bengali · \(typography.bengali.title)")
                }
                .foregroundStyle(Palette.ink2)
            }
            if paperWidth > 560 { Text("Markdown · LaTeX · \(codeCount) code").lineLimit(1) }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.ink3)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 26)
    }
}

// MARK: - Blocks

private struct NoteBlockRow: View {
    var block: NoteBlock
    /// Position in a run of numbered items.
    var number: Int
    var editor: NoteEditor
    @State private var hovering = false

    private var typography: NoteFont { editor.note.typography }
    private var size: CGFloat { typography.size.points }
    private var bengali: Bool { NoteText.hasBengali(block.text) }

    var body: some View {
        content
            .padding(.top, topMargin)
            .onHover { hovering = $0 }
            .overlay(alignment: .topLeading) {
                handles
                    .padding(.top, topMargin + handleOffset)
                    .offset(x: -54)
                    .opacity(hovering ? 1 : 0)
            }
            .overlay(alignment: .bottomLeading) {
                if let menu = editor.slashMenu, menu.id == block.id, !menu.items.isEmpty {
                    SlashMenuView(menu: menu) { editor.turnInto(block, $0, clear: true) }
                        .alignmentGuide(.bottom) { $0[.top] - 4 }
                }
            }
    }

    private var topMargin: CGFloat {
        switch block.kind {
        case .h1: 20
        case .h2: 16
        case .h3: 10
        case .code, .math: 8
        default: 0
        }
    }

    private var handleOffset: CGFloat {
        switch block.kind {
        case .h1: 9
        case .h2: 6
        case .hr: 4
        default: 2
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .hr:
            Rectangle().fill(Palette.border).frame(height: 1).padding(.vertical, 14)
        case .code:
            CodeBlockView(block: block, editor: editor).padding(.bottom, 8)
        case .math:
            MathBlockView(block: block, editor: editor).padding(.bottom, 8)
        default:
            textBlock
        }
    }

    private var textWeight: PlatformFont.Weight {
        switch block.kind {
        case .h1: .bold
        case .h2, .h3: .semibold
        default: .regular
        }
    }

    private var textSize: CGFloat {
        switch block.kind {
        case .h1: size * 1.6
        case .h2: size * 1.28
        case .h3: size * 1.06
        default: size
        }
    }

    private var textBlock: some View {
        let done = block.kind == .todo && block.done == true
        let lineSpacing = [.h1, .h2, .h3].contains(block.kind)
            ? (bengali ? textSize * 0.3 : textSize * 0.15)
            : NoteTypeface.lineSpacing(size: textSize, bengali: bengali)
        return HStack(alignment: .top, spacing: 6) {
            switch block.kind {
            case .bullet:
                Text("•").font(.system(size: size)).foregroundStyle(Palette.ink2).frame(width: 18).padding(.top, 3)
            case .num:
                Text("\(number).").font(.system(size: size)).monospacedDigit().foregroundStyle(Palette.ink2)
                    .frame(width: 22, alignment: .trailing).padding(.top, 3)
            case .todo:
                TodoBox(isOn: done) { editor.update(block.id) { $0.done = !done } }
                    .frame(width: 18)
                    .padding(.top, 3 + max(0, (size * 1.2 - 16) / 2))
            case .quote:
                Rectangle().fill(Palette.border).frame(width: 3).padding(.vertical, 4)
            default:
                EmptyView()
            }
            Group {
                if editor.isEditing(block.id) {
                    NoteTextView(text: Binding(get: { block.text }, set: { editor.change(block, to: $0) }),
                                 font: NoteTypeface.platformFont(typography, size: textSize, weight: textWeight),
                                 lineSpacing: lineSpacing,
                                 textColor: block.kind == .quote ? PlatformColor.secondaryLabelCompat : PlatformColor.labelCompat,
                                 placeholder: block.kind == .p ? "Type \u{201C}/\u{201D} for blocks, $x^2$ for inline math" : block.kind.title,
                                 formatting: true,
                                 focus: editor.request(for: block.id),
                                 focusTracker: editor.textFocusTracker,
                                 onKey: { editor.textKey(block.id, $0, $1) },
                                 onFocusChange: { editor.focusChanged(block.id, $0) })
                } else {
                    NoteMarkdown.text(block.text.isEmpty ? " " : block.text, typography: typography, size: textSize, weight: textWeight)
                        .lineSpacing(lineSpacing)
                        .strikethrough(done, color: Palette.ink3.opacity(0.6))
                        .foregroundStyle(done ? Palette.ink3 : block.kind == .quote ? Palette.ink2 : .primary)
                        .textSelection(.disabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { editor.focus(block.id, caret: nil) }
                }
            }
            .padding(.leading, block.kind == .quote ? 11 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, [.bullet, .num, .todo].contains(block.kind) ? 2 : 0)
        .padding(.vertical, block.kind == .quote ? 4 : 0)
    }

    private var handles: some View {
        HStack(spacing: 0) {
            Menu {
                Section("Insert below") {
                    ForEach(NoteBlock.Kind.allCases) { kind in
                        Button(kind.title, systemImage: kind.systemImage) { editor.insert(kind, after: block.id) }
                    }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 24)
            }
            .help("Insert block below")
            Menu {
                Menu("Turn into") {
                    ForEach(NoteBlock.Kind.allCases) { kind in
                        Button(kind.title, systemImage: kind.systemImage) { editor.turnInto(block, kind) }
                    }
                }
                Button("Move Up", systemImage: "chevron.up") { editor.move(block.id, by: -1) }
                Button("Move Down", systemImage: "chevron.down") { editor.move(block.id, by: 1) }
                Button("Duplicate", systemImage: "plus.square.on.square") { editor.duplicate(block.id) }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { editor.remove(block.id) }
            } label: {
                Image(systemName: "circle.grid.2x3.fill").font(.system(size: 10)).frame(width: 22, height: 24)
            }
            .help("Block options")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.ink3)
        .fixedSize()
    }
}

/// Square checklist box (the design uses a checkbox, not the round `CheckCircle`).
private struct TodoBox: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor : Color.primary.opacity(0.3), lineWidth: 1.2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(isOn ? Color.accentColor : .clear))
                .overlay {
                    if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct SlashMenuView: View {
    var menu: NoteEditor.SlashMenu
    var onPick: (NoteBlock.Kind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Blocks").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).padding(.horizontal, 8).padding(.vertical, 4)
            ForEach(Array(menu.items.enumerated()), id: \.element) { i, kind in
                let on = i == menu.index
                Button { onPick(kind) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .background(on ? Color.white.opacity(0.2) : Palette.surface, in: RoundedRectangle(cornerRadius: 5))
                        Text(kind.title)
                        Spacer(minLength: 16)
                        Text(kind.markdown).font(.system(size: 11, design: .monospaced)).foregroundStyle(on ? .white.opacity(0.8) : Palette.ink3)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(on ? .white : .primary)
                    .padding(.horizontal, 4)
                    .frame(height: 28)
                    .background(on ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(width: 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }
}

private struct CodeBlockView: View {
    var block: NoteBlock
    var editor: NoteEditor
    @State private var copied = false

    var body: some View {
        let lang = block.lang ?? .plaintext
        let lines = block.text.isEmpty ? 0 : block.text.components(separatedBy: "\n").count
        let editing = editor.isEditing(block.id)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Language", selection: Binding(get: { lang }, set: { v in editor.update(block.id) { $0.lang = v } })) {
                    ForEach(CodeLanguage.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("\(lines) \(lines == 1 ? "line" : "lines")")
                Button {
                    copyToPasteboard(block.text)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink3)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(height: 32)
            Divider()
            NoteTextView(text: Binding(get: { block.text }, set: { v in editor.update(block.id) { $0.text = v } }),
                         font: NoteTypeface.platformFont(editor.note.typography, size: 12.5, monospaced: true),
                         lineSpacing: 12.5 * 0.45,
                         placeholder: "// code",
                         code: lang,
                         focus: editor.request(for: block.id),
                         focusTracker: editor.textFocusTracker,
                         onKey: { editor.codeKey(block.id, $0, $1) },
                         onFocusChange: { editor.focusChanged(block.id, $0) })
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .background(NoteColors.codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(editing ? Color.accentColor.opacity(0.5) : Palette.border, lineWidth: editing ? 1.5 : 0.5)
        )
    }
}

private struct MathBlockView: View {
    var block: NoteBlock
    var editor: NoteEditor
    @State private var hovering = false

    private var size: CGFloat { editor.note.typography.size.points }

    var body: some View {
        if editor.isEditing(block.id) {
            VStack(spacing: 0) {
                HStack {
                    Text("LaTeX")
                    Spacer()
                    Text("esc or ⌘↵ to finish")
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                NoteTextView(text: Binding(get: { block.text }, set: { v in editor.update(block.id) { $0.text = v } }),
                             font: NoteTypeface.platformFont(editor.note.typography, size: 12.5, monospaced: true),
                             lineSpacing: 12.5 * 0.45,
                             placeholder: #"e.g. \int_0^1 x^2\,dx = \frac{1}{3}"#,
                             focus: editor.request(for: block.id),
                             focusTracker: editor.textFocusTracker,
                             onKey: { editor.mathKey(block.id, $0, $1) },
                             onFocusChange: { editor.focusChanged(block.id, $0) })
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                Divider()
                formula(placeholder: "Preview")
                    .padding(12)
                    .background(Palette.surface)
            }
            .background(NoteColors.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5))
        } else {
            formula(placeholder: "Empty equation \u{2014} click to add LaTeX")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture { editor.focus(block.id, caret: nil) }
                .help("Click to edit LaTeX")
        }
    }

    @ViewBuilder
    private func formula(placeholder: String) -> some View {
        Group {
            if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder).font(.system(size: 13)).foregroundStyle(Palette.ink3)
            } else if let math = MathRenderer.render(block.text, fontSize: size * 1.25, display: true) {
                let image = Image(platformImage: math.image).renderingMode(.template).foregroundStyle(.primary)
                // Centred when it fits; wide formulas scroll sideways instead of overflowing the page.
                ViewThatFits(in: .horizontal) {
                    image
                    ScrollView(.horizontal) { image }
                        .scrollIndicators(.never)
                }
            } else {
                Text(block.text).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Palette.red)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension NoteEditor {
    fileprivate var slashMenu: SlashMenu? { slash }
    fileprivate var textFocusTracker: NoteTextFocus { textFocus }
}

extension PlatformColor {
    static var labelCompat: PlatformColor {
        #if os(macOS)
        .labelColor
        #else
        .label
        #endif
    }

    static var secondaryLabelCompat: PlatformColor {
        #if os(macOS)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }
}

func copyToPasteboard(_ string: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #else
    UIPasteboard.general.string = string
    #endif
}
