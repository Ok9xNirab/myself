import SwiftUI

enum NoteSort: String, CaseIterable, Identifiable {
    case edited, created, title

    var id: Self { self }

    var title: String {
        switch self {
        case .edited: "Date edited"
        case .created: "Date created"
        case .title: "Title"
        }
    }
}

/// Notes: category panel → note list → block editor (`NoteEditor`). Fills the detail column instead of using `PageScroll`.
struct NotesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    /// "all", "pinned" or a category ID.
    @AppStorage("notes.scope") private var scope = "all"
    @AppStorage("notes.sort") private var sort = NoteSort.edited
    @AppStorage("notes.open") private var openID = ""
    @AppStorage("notes.browser") private var showsBrowser = true
    @AppStorage("notes.railWidth") private var railWidth = 188.0
    /// 0 until the user drags it, so the list keeps its window-size default.
    @AppStorage("notes.listWidth") private var storedListWidth = 0.0

    @State private var query = ""
    @State private var searchesAll = false
    @State private var selection: Set<ID> = []
    /// A note created just now, so the editor focuses its title.
    @State private var freshID: ID?
    @State private var newCategoryName: String?
    @State private var renamingID: ID?
    @State private var dropTarget: String?
    @State private var pendingDelete: [ID] = []
    @State private var pendingCategoryDelete: NoteCategory?
    @State private var index = NoteSearchIndex()

    var body: some View {
        let scope = validScope
        let list = filtered(scope)
        // The list reads `noteSummaries`, not `notes`, so typing in the open note doesn't redraw it.
        let open = (store.noteSummaries.first { $0.id == openID } ?? list.first)?.id

        GeometryReader { geo in
            let railShown = showsBrowser && geo.size.width >= 940
            let defaultListWidth: CGFloat = geo.size.width >= 940 ? 300 : geo.size.width >= 700 ? 272 : 236
            // Keep at least 360pt for the editor, however wide the columns were dragged.
            let railW = railShown ? min(railWidth, 280) : 0
            let listMax = max(220, geo.size.width - railW - 360)
            let listWidth = min(storedListWidth > 0 ? storedListWidth : defaultListWidth, listMax)
            HStack(spacing: 0) {
                if railShown {
                    rail(scope)
                        .frame(width: railW)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    ColumnResizer(width: railW, range: 150...280) { railWidth = $0 } onReset: { railWidth = 188 }
                }
                if showsBrowser {
                    noteList(list, scope: scope)
                        .frame(width: listWidth)
                        .background(Palette.surface.opacity(0.5))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    ColumnResizer(width: listWidth, range: 220...listMax) { storedListWidth = $0 } onReset: { storedListWidth = 0 }
                }
                Group {
                    if let open {
                        OpenNoteEditor(id: open, isFresh: freshID == open, showsBrowser: $showsBrowser,
                                       onDuplicate: { duplicate(open) }, onDelete: { delete([open]) })
                            .id(open)
                    } else {
                        EmptyStateView(systemImage: "note.text", title: "No note selected", subtitle: "Pick a note from the list or create a new one.")
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface)
            }
            .background(Palette.background)
            .animation(.smooth(duration: 0.25), value: showsBrowser)
        }
        .overlay(alignment: .top) { Divider() }
        .onAppear {
            if let open { selection = [open] }
            handle(store.noteRequest)
        }
        .onChange(of: store.noteRequest) { handle(store.noteRequest) }
        .onChange(of: selection) {
            if selection.count == 1, let id = selection.first { openID = id }
        }
        .onChange(of: openID) { if openID != freshID { freshID = nil } }
        .onDisappear { store.saveUnsavedNotes() }
        .confirmationDialog("Delete \(pendingDelete.count) notes?", isPresented: Binding(get: { pendingDelete.count > 1 }, set: { if !$0 { pendingDelete = [] } })) {
            Button("Delete", role: .destructive) { delete(pendingDelete, confirmed: true) }
        } message: {
            Text("You can undo this with ⌘Z.")
        }
        .confirmationDialog("Delete \u{201C}\(pendingCategoryDelete?.name ?? "")\u{201D} and its notes?",
                            isPresented: Binding(get: { pendingCategoryDelete != nil }, set: { if !$0 { pendingCategoryDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let category = pendingCategoryDelete { deleteCategory(category, confirmed: true) }
            }
        } message: {
            let n = store.noteSummaries.filter { $0.categoryID == pendingCategoryDelete?.id }.count
            Text("\(n) \(n == 1 ? "note" : "notes") will be deleted. You can undo this with ⌘Z.")
        }
    }

    // MARK: Derived

    /// The stored scope, or "all" when its category no longer exists.
    private var validScope: String {
        scope == "all" || scope == "pinned" || store.noteCategory(scope) != nil ? scope : "all"
    }

    private func scopeName(_ scope: String) -> String {
        switch scope {
        case "all": "All Notes"
        case "pinned": "Pinned"
        default: store.noteCategory(scope)?.name ?? "All Notes"
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func filtered(_ scope: String) -> [NoteSummary] {
        let q = trimmedQuery
        let everywhere = (!q.isEmpty && searchesAll) || scope == "all"
        // Searching needs the notes' text; only then does the list follow every edit.
        let matches = q.isEmpty ? nil : Set(store.notes.filter { index.text(for: $0).contains(q) }.map(\.id))
        var list = store.noteSummaries.filter { note in
            guard everywhere || (scope == "pinned" ? note.pinned : note.categoryID == scope) else { return false }
            return matches?.contains(note.id) ?? true
        }
        switch sort {
        case .edited: list.sort { $0.editedAt > $1.editedAt }
        case .created: list.sort { $0.createdAt > $1.createdAt }
        case .title: list.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        return list
    }

    /// List sections: search results, or Pinned followed by date (or first-letter) groups.
    private func sections(_ list: [NoteSummary], scope: String) -> [(title: String, notes: [NoteSummary])] {
        if !trimmedQuery.isEmpty {
            let n = list.count
            return [("\(n) result\(n == 1 ? "" : "s")\(searchesAll ? " in all notes" : "")", list)]
        }
        var out: [(title: String, notes: [NoteSummary])] = []
        let pinned = scope == "pinned" ? [] : list.filter(\.pinned)
        if !pinned.isEmpty { out.append(("Pinned", pinned)) }
        for note in list where scope == "pinned" || !note.pinned {
            let title = switch sort {
            case .title: String(note.displayTitle.prefix(1)).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
            case .created: NoteDates.group(note.createdAt)
            case .edited: NoteDates.group(note.editedAt)
            }
            if let i = out.indices.last(where: { out[$0].title == title }), !(i == 0 && !pinned.isEmpty) {
                out[i].notes.append(note)
            } else {
                out.append((title, [note]))
            }
        }
        return out
    }

    private func count(_ scope: String) -> Int {
        switch scope {
        case "all": store.noteSummaries.count
        case "pinned": store.noteSummaries.filter(\.pinned).count
        default: store.noteSummaries.filter { $0.categoryID == scope }.count
        }
    }

    // MARK: Category panel

    private func rail(_ scope: String) -> some View {
        List(selection: Binding(get: { scope }, set: { if let s = $0 { pick(s) } })) {
            scopeRow("all", title: "All Notes", systemImage: "tray")
            scopeRow("pinned", title: "Pinned", systemImage: "pin")
            Section("Categories") {
                ForEach(store.noteCategories) { category in
                    categoryRow(category)
                }
                if newCategoryName != nil {
                    HStack(spacing: 8) {
                        ColorDot(color: Color(hex: NoteCategory.palette[store.noteCategories.count % NoteCategory.palette.count]), size: 8)
                        TextField("Category name", text: Binding(get: { newCategoryName ?? "" }, set: { newCategoryName = $0 }))
                            .textFieldStyle(.plain)
                            .onSubmit(createCategory)
                            .onEscape { newCategoryName = nil }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Notebook").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
                Spacer()
                Button("New Category", systemImage: "folder.badge.plus") { newCategoryName = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.ink2)
                    .help("New category")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.top, 10)
        }
    }

    private func scopeRow(_ id: String, title: String, systemImage: String) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(count(id).formatted()).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .tag(id)
        .modifier(NoteDropTarget(id: id, target: $dropTarget, onDrop: drop))
    }

    private func categoryRow(_ category: NoteCategory) -> some View {
        HStack(spacing: 8) {
            ColorDot(color: category.color, size: 8)
            if renamingID == category.id {
                RenameField(name: category.name) { name in
                    if let name { store.renameNoteCategory(category.id, to: name) }
                    renamingID = nil
                }
            } else {
                Text(category.name).lineLimit(1)
                    .onTapGesture(count: 2) { renamingID = category.id }
            }
            Spacer(minLength: 4)
            Text(count(category.id).formatted()).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
        .tag(category.id)
        .help("Double-click to rename")
        .contextMenu {
            Button("New Note in \(category.name)", systemImage: "square.and.pencil") { pick(category.id); addNote(in: category.id) }
            Button("Rename", systemImage: "pencil") { renamingID = category.id }
            Divider()
            Button("Delete Category", systemImage: "trash", role: .destructive) { deleteCategory(category) }
        }
        .modifier(NoteDropTarget(id: category.id, target: $dropTarget, onDrop: drop))
    }

    // MARK: Note list

    private func noteList(_ list: [NoteSummary], scope: String) -> some View {
        let q = trimmedQuery
        let found = q.isEmpty ? [:] : Dictionary(store.notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wide = scope == "all" || scope == "pinned" || (!q.isEmpty && searchesAll)
        return VStack(spacing: 0) {
            listHeader(list, scope: scope)
            NoteSearchField(placeholder: "Search \(searchesAll ? "all notes" : scopeName(scope))", text: $query)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            if !q.isEmpty, scope != "all" {
                Picker("Search in", selection: $searchesAll) {
                    Text(scopeName(scope)).tag(false)
                    Text("All notes").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            if list.isEmpty {
                VStack(spacing: 8) {
                    if q.isEmpty {
                        Text("No notes in \(scopeName(scope))")
                        Button("New note") { addNote() }.buttonStyle(.borderless)
                    } else {
                        Text("No notes match \u{201C}\(query)\u{201D}")
                        if !searchesAll, scope != "all" { Button("Search all notes") { searchesAll = true }.buttonStyle(.borderless) }
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink3)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List(selection: $selection) {
                    ForEach(sections(list, scope: scope), id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.notes) { note in
                                NoteRow(note: note, match: found[note.id], category: wide ? store.noteCategory(note.categoryID) : nil, query: q, sort: sort)
                                    .tag(note.id)
                                    .draggable(dragPayload(for: note.id))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                #if os(macOS)
                // Double-click (or Return) opens the note in its own window.
                .contextMenu(forSelectionType: ID.self) { ids in
                    if !ids.isEmpty { rowMenu(Array(ids)) }
                } primaryAction: { ids in
                    ids.forEach { openWindow(id: NoteWindow.id, value: $0) }
                }
                .onDeleteCommand { delete(Array(selection)) }
                #else
                .contextMenu(forSelectionType: ID.self) { ids in if !ids.isEmpty { rowMenu(Array(ids)) } }
                #endif
            }
            if selection.count > 1 { bulkBar }
        }
    }

    private func listHeader(_ list: [NoteSummary], scope: String) -> some View {
        HStack(spacing: 2) {
            Menu {
                Picker("Show", selection: Binding(get: { scope }, set: pick)) {
                    Label("All Notes", systemImage: "tray").tag("all")
                    Label("Pinned", systemImage: "pin").tag("pinned")
                    Divider()
                    ForEach(store.noteCategories) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        if let category = store.noteCategory(scope) { ColorDot(color: category.color, size: 8) }
                        Text(scopeName(scope)).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.ink3)
                    }
                    Text("\(list.count.formatted()) \(trimmedQuery.isEmpty ? "notes" : "matching")")
                        .font(.system(size: 11)).foregroundStyle(Palette.ink3).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Switch category")
            Spacer()
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(NoteSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort")
            Button("New Note", systemImage: "square.and.pencil") { addNote() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("New note (⌥⌘N)")
        }
        .foregroundStyle(Palette.ink2)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rowMenu(_ ids: [ID]) -> some View {
        let allPinned = ids.allSatisfy { id in store.noteSummaries.first { $0.id == id }?.pinned == true }
        Button(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin") { store.setPinned(ids, !allPinned) }
        Menu("Move to") {
            ForEach(store.noteCategories) { category in
                Button(category.name) { store.moveNotes(ids, to: category.id) }
            }
        }
        #if os(macOS)
        Button(ids.count == 1 ? "Open in New Window" : "Open in \(ids.count) Windows", systemImage: "macwindow") {
            ids.forEach { openWindow(id: NoteWindow.id, value: $0) }
        }
        #endif
        if ids.count == 1, let id = ids.first {
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(id) }
        }
        Divider()
        Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Notes", systemImage: "trash", role: .destructive) { delete(ids) }
    }

    private var bulkBar: some View {
        let ids = Array(selection)
        let allPinned = ids.allSatisfy { id in store.noteSummaries.first { $0.id == id }?.pinned == true }
        return HStack(spacing: 2) {
            Text("\(selection.count) selected").font(.system(size: 12.5, weight: .semibold))
            Spacer()
            Menu {
                ForEach(store.noteCategories) { category in
                    Button(category.name) { store.moveNotes(ids, to: category.id); selection = [] }
                }
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Move to category")
            Group {
                Button(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin") { store.setPinned(ids, !allPinned); selection = [] }
                Button("Delete", systemImage: "trash") { delete(ids) }
                Button("Clear Selection", systemImage: "xmark") { selection = openID.isEmpty ? [] : [openID] }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Palette.ink2)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 40)
        .background(Palette.surface)
        .overlay(alignment: .top) { Divider() }
    }

    /// Dragging a note that's part of a multi-selection drags the whole selection.
    private func dragPayload(for id: ID) -> String {
        selection.count > 1 && selection.contains(id) ? selection.joined(separator: "\n") : id
    }

    // MARK: Actions

    private func pick(_ newScope: String) {
        scope = newScope
        searchesAll = false
    }

    private func handle(_ request: NoteRequest?) {
        guard let request else { return }
        store.noteRequest = nil
        switch request {
        case .new:
            addNote()
        case .open(let id):
            guard let note = store.notes.first(where: { $0.id == id }) else { return }
            if validScope != "all", validScope != note.categoryID { scope = note.categoryID }
            query = ""
            showsBrowser = true
            selection = [id]
            openID = id
        }
    }

    private func addNote(in categoryID: ID? = nil) {
        let open = store.notes.first { $0.id == openID }
        guard let categoryID = categoryID ?? store.noteCategory(validScope)?.id ?? open?.categoryID ?? store.noteCategories.first?.id else { return }
        let note = store.addNote(in: categoryID)
        if validScope == "pinned" { scope = categoryID }
        query = ""
        freshID = note.id
        selection = [note.id]
        openID = note.id
    }

    private func duplicate(_ id: ID) {
        guard let copy = store.duplicateNote(id) else { return }
        selection = [copy.id]
        openID = copy.id
    }

    /// Deletes notes and opens the one that took the first deleted note's place. Several at once asks first.
    private func delete(_ ids: [ID], confirmed: Bool = false) {
        guard !ids.isEmpty else { return }
        if ids.count > 1, !confirmed { pendingDelete = ids; return }
        pendingDelete = []
        let order = sections(filtered(validScope), scope: validScope).flatMap(\.notes).map(\.id)
        let first = order.firstIndex { ids.contains($0) } ?? 0
        let remaining = order.filter { !ids.contains($0) }
        let next = remaining.isEmpty ? nil : remaining[min(first, remaining.count - 1)]
        store.deleteNotes(ids, undoManager: undoManager)
        selection = next.map { [$0] } ?? []
        openID = next ?? ""
    }

    private func createCategory() {
        if let category = store.addNoteCategory(name: newCategoryName ?? "") { pick(category.id) }
        newCategoryName = nil
    }

    private func deleteCategory(_ category: NoteCategory, confirmed: Bool = false) {
        if !confirmed, count(category.id) > 0 { pendingCategoryDelete = category; return }
        pendingCategoryDelete = nil
        store.deleteNoteCategory(category.id, undoManager: undoManager)
    }

    /// Drop on All Notes does nothing, on Pinned pins, on a category moves.
    private func drop(_ ids: [ID], on target: String) {
        switch target {
        case "all": return
        case "pinned": store.setPinned(ids, true)
        default: store.moveNotes(ids, to: target)
        }
        selection = openID.isEmpty ? [] : [openID]
    }
}

// MARK: - Pieces

/// The editor for the open note. It reads the note itself, so its edits redraw only the editor, not the list.
private struct OpenNoteEditor: View {
    var id: ID
    var isFresh: Bool
    var showsBrowser: Binding<Bool>
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        if let note = store.notes.first(where: { $0.id == id }) {
            NoteEditor(note: note, isFresh: isFresh, showsBrowser: showsBrowser, onDuplicate: onDuplicate, onDelete: onDelete)
        }
    }
}

private struct NoteRow: View {
    var note: NoteSummary
    /// The full note while searching, for the text around the match.
    var match: Note?
    /// Shown when the list mixes categories.
    var category: NoteCategory?
    var query: String
    var sort: NoteSort

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Palette.amber)
                }
                Text(highlighted(note.displayTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let category {
                    HStack(spacing: 4) {
                        ColorDot(color: category.color, size: 6)
                        Text(category.name).lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 96, alignment: .trailing)
                    .fixedSize()
                }
            }
            HStack(spacing: 6) {
                Text(NoteDates.short(sort == .created ? note.createdAt : note.editedAt))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(highlighted(query.isEmpty ? note.snippet : excerpt))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 5)
    }

    /// Text around the first match, for search results.
    private var excerpt: String {
        guard let match else { return note.snippet }
        let text = NoteText.plain(match.blocks.map(\.text).joined(separator: " · "))
        guard let range = text.range(of: query, options: .caseInsensitive) else { return note.snippet }
        let start = text.index(range.lowerBound, offsetBy: -28, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "\u{2026}") + text[start..<end]
    }

    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        if !query.isEmpty, let range = out.range(of: query, options: .caseInsensitive) {
            out[range].backgroundColor = Palette.amber.opacity(0.34)
        }
        return out
    }
}

/// Highlights a category row while notes are dragged over it, and hands over the dropped note IDs.
/// A column divider that resizes the column to its left: drag to resize, double-click to reset.
private struct ColumnResizer: View {
    let width: CGFloat
    let range: ClosedRange<CGFloat>
    let onChange: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Divider()
            .overlay {
                Rectangle()
                    .fill(hovering || startWidth != nil ? Color.accentColor.opacity(0.5) : .clear)
                    .frame(width: 2)
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
                    #if os(macOS)
                    .pointerStyle(.columnResize)
                    #endif
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                onChange(min(max(start + value.translation.width, range.lowerBound), range.upperBound))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
                    .onTapGesture(count: 2, perform: onReset)
            }
            .zIndex(1)
    }
}

private struct NoteDropTarget: ViewModifier {
    var id: String
    @Binding var target: String?
    var onDrop: ([ID], String) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { items, _ in
                let ids = items.flatMap { $0.split(separator: "\n").map(String.init) }
                onDrop(ids, id)
                return !ids.isEmpty
            } isTargeted: { on in
                if on { target = id } else if target == id { target = nil }
            }
            .listRowBackground(
                target == id
                    ? RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 1.5)).padding(.horizontal, 8)
                    : nil
            )
    }
}

/// Inline rename: Return commits, Escape or clicking away keeps the old name.
private struct RenameField: View {
    var name: String
    var onDone: (String?) -> Void
    @State private var text = ""
    @State private var done = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { text = name; focused = true }
            .onSubmit { finish(text) }
            .onEscape { finish(nil) }
            .onChange(of: focused) { if !focused { finish(text) } }
    }

    private func finish(_ result: String?) {
        guard !done else { return }
        done = true
        onDone(result)
    }
}

struct NoteSearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.ink3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onEscape { text = "" }
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5))
    }
}

/// Caches each note's lowercased search text until the note changes, so typing a query doesn't re-flatten every note.
final class NoteSearchIndex {
    private var cache: [ID: (updatedAt: Date, text: String)] = [:]

    func text(for note: Note) -> String {
        if let hit = cache[note.id], hit.updatedAt == note.updatedAt { return hit.text }
        let text = note.searchText
        cache[note.id] = (note.updatedAt, text)
        return text
    }
}

/// Date labels from the design's note list (`ntWhen`, `ntGroup`).
enum NoteDates {
    /// "4:35 AM", "Yesterday", "Tuesday", "3 Oct", "3 Oct 2024".
    static func short(_ date: Date) -> String {
        let days = -(Day.fromToday(date) ?? 0)
        if days <= 0 { return date.formatted(date: .omitted, time: .shortened) }
        if days == 1 { return "Yesterday" }
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        let sameYear = Day.calendar.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.day().month(.abbreviated)) : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// List section for a date: Today, Yesterday, Previous 7 days, Previous 30 days, then month, then year.
    static func group(_ date: Date) -> String {
        let days = -(Day.fromToday(date) ?? 0)
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "Previous 7 days" }
        if days < 30 { return "Previous 30 days" }
        if Day.calendar.isDate(date, equalTo: .now, toGranularity: .year) { return date.formatted(.dateTime.month(.wide)) }
        return date.formatted(.dateTime.year())
    }

    /// "just now", "5 min ago", "2 h ago", "3 d ago", then a date.
    static func ago(_ date: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(date)
        if s < 45 { return "just now" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min ago" }
        if s < 86400 { return "\(Int((s / 3600).rounded())) h ago" }
        if s < 86400 * 6 { return "\(Int((s / 86400).rounded())) d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    NotesView().environment(AppStore()).frame(width: 1200, height: 800)
}

extension View {
    /// Escape key: the exit command on macOS, a key press elsewhere.
    func onEscape(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        onKeyPress(.escape) { action(); return .handled }
        #endif
    }
}
