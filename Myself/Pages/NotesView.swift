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

/// Notes in the v2 layout: a page of its own (header, category chips with a filter, pinned cards, then the other
/// notes grouped by date in cards) and, once a note is opened, its editor across the whole column with a Back
/// button. Fills the detail column instead of using `PageScroll` for the editor; the list uses `PageScroll`.
struct NotesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    /// "all" or a category ID. ("pinned", from before the v2 layout, reads as "all".)
    @AppStorage("notes.scope") private var scope = "all"
    @AppStorage("notes.sort") private var sort = NoteSort.edited
    @AppStorage("notes.open") private var openID = ""
    /// Whether the list page shows; false while a note is open in the editor.
    @AppStorage("notes.list") private var showsList = true

    @State private var query = ""
    @State private var searchesAll = false
    /// Notes picked with ⌘-click (or ⇧-click) for the bulk bar.
    @State private var selection: Set<ID> = []
    /// A note created just now, so the editor focuses its title.
    @State private var freshID: ID?
    @State private var showsNewCategory = false
    @State private var renamingID: ID?
    @State private var dropTarget: String?
    @State private var pendingDelete: [ID] = []
    @State private var pendingCategoryDelete: NoteCategory?
    @State private var index = NoteSearchIndex()

    var body: some View {
        let scope = validScope
        let open = store.noteSummaries.first { $0.id == openID && $0.bookID == nil }?.id

        Group {
            if !showsList, let open {
                OpenNoteEditor(id: open, isFresh: freshID == open, showsBrowser: $showsList, backToList: true,
                               onDuplicate: { duplicate(open) }, onDelete: { delete([open]) })
                    .id(open)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                browser(filtered(scope), scope: scope)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showsNewCategory) {
            NoteCategorySheet(hex: NoteCategory.palette[store.noteCategories.count % NoteCategory.palette.count]) { pick($0) }
        }
        .onAppear {
            handle(store.noteRequest)
            updateCrumb()
        }
        .onChange(of: store.noteRequest) { handle(store.noteRequest) }
        .onChange(of: showsList) { selection = []; updateCrumb() }
        .onChange(of: openID) { if openID != freshID { freshID = nil }; updateCrumb() }
        .onChange(of: scope) { updateCrumb() }
        .onChange(of: store.noteCategories) { updateCrumb() }
        .onDisappear {
            store.saveUnsavedNotes()
            if store.crumb?.page == .notes { store.crumb = nil }
        }
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
            let n = count(pendingCategoryDelete?.id ?? "")
            Text("\(n) \(n == 1 ? "note" : "notes") will be deleted. You can undo this with ⌘Z.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if showsList {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(NoteSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .menuIndicator(.hidden)
                .help("Sort notes")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { addNote() } label: {
                Label("New note", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.surface)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.primary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("New note (⌥⌘N)")
        }
    }

    // MARK: Derived

    /// The stored scope, or "all" when its category no longer exists.
    private var validScope: String {
        store.noteCategory(scope) != nil ? scope : "all"
    }

    private func scopeName(_ scope: String) -> String {
        store.noteCategory(scope)?.name ?? "All"
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func filtered(_ scope: String) -> [NoteSummary] {
        let q = trimmedQuery
        let everywhere = (!q.isEmpty && searchesAll) || scope == "all"
        // Searching needs the notes' text; only then does the list follow every edit.
        let matches = q.isEmpty ? nil : Set(store.notes.filter { index.text(for: $0).contains(q) }.map(\.id))
        var list = store.noteSummaries.filter { note in
            // Reading notes live on the Book Notes page.
            guard note.bookID == nil, everywhere || note.categoryID == scope else { return false }
            return matches?.contains(note.id) ?? true
        }
        switch sort {
        case .edited: list.sort { $0.editedAt > $1.editedAt }
        case .created: list.sort { $0.createdAt > $1.createdAt }
        case .title: list.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        return list
    }

    /// The unpinned notes in date (or first-letter) groups; search results are one group.
    private func groups(_ list: [NoteSummary]) -> [(title: String, notes: [NoteSummary])] {
        if !trimmedQuery.isEmpty {
            let n = list.count
            return n == 0 ? [] : [("\(n) result\(n == 1 ? "" : "s")\(searchesAll && validScope != "all" ? " in all notes" : "")", list)]
        }
        var out: [(title: String, notes: [NoteSummary])] = []
        for note in list where !note.pinned {
            let title = switch sort {
            case .title: String(note.displayTitle.prefix(1)).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
            case .created: NoteDates.group(note.createdAt)
            case .edited: NoteDates.group(note.editedAt)
            }
            if out.last?.title == title { out[out.count - 1].notes.append(note) } else { out.append((title, [note])) }
        }
        return out
    }

    /// Every note in the order the page shows them: pinned first, then the groups.
    private func order(_ list: [NoteSummary]) -> [ID] {
        trimmedQuery.isEmpty ? list.filter(\.pinned).map(\.id) + list.filter { !$0.pinned }.map(\.id) : list.map(\.id)
    }

    private func count(_ scope: String) -> Int {
        scope == "all" ? store.noteSummaries.count(where: { $0.bookID == nil })
            : store.noteSummaries.count(where: { $0.categoryID == scope && $0.bookID == nil })
    }

    private func updateCrumb() {
        let open = store.noteSummaries.first { $0.id == openID && $0.bookID == nil }
        let detail = !showsList ? open.flatMap { store.noteCategory($0.categoryID)?.name } : scopeName(validScope)
        store.crumb = detail.map { (page: Page.notes, detail: $0) }
    }

    // MARK: List page

    private func browser(_ list: [NoteSummary], scope: String) -> some View {
        let q = trimmedQuery
        let pins = q.isEmpty ? list.filter(\.pinned) : []
        let groups = groups(list)
        // Category names on rows only when the list mixes categories.
        let mixed = scope == "all" || (!q.isEmpty && searchesAll)
        let all = store.noteSummaries.filter { $0.bookID == nil }
        let editedToday = all.count(where: { Day.calendar.isDateInToday($0.editedAt) })

        return PageScroll(maxWidth: 980) {
            SpaceHeader(page: .notes, detail: "\(all.count) \(all.count == 1 ? "page" : "pages") · \(editedToday) edited today")

            chipBar(scope)

            if all.isEmpty {
                VStack(spacing: 14) {
                    EmptyStateView(systemImage: Page.notes.systemImage, title: "No notes yet", subtitle: "Pages with math, code, tables and images.")
                    Button("New Note", systemImage: "square.and.pencil") { addNote() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .cardBackground(radius: 18)
            } else if list.isEmpty {
                VStack(spacing: 10) {
                    if q.isEmpty {
                        Text("No notes in \(scopeName(scope)) yet.")
                        Button("New Note in \(scopeName(scope))") { addNote() }.buttonStyle(.borderless)
                    } else {
                        Text("No pages match \u{201C}\(query)\u{201D}.")
                        if !searchesAll, scope != "all" { Button("Search all notes") { searchesAll = true }.buttonStyle(.borderless) }
                    }
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink2)
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }

            if !pins.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    NoteSectionHeading(title: "Pinned", count: nil, systemImage: "pin")
                    PinnedGrid(notes: pins) { note in
                        PinnedNoteCard(note: note, category: store.noteCategory(note.categoryID), selected: selection.contains(note.id))
                            .modifier(NoteItemActions(id: note.id, select: { click(note.id, modifiers: $0, order: order(list)) },
                                                      payload: dragPayload(for: note.id)) { rowMenu(menuIDs(note.id)) })
                    }
                }
            }

            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    NoteSectionHeading(title: group.title, count: group.notes.count, systemImage: nil)
                    VStack(spacing: 0) {
                        ForEach(Array(group.notes.enumerated()), id: \.element.id) { i, note in
                            NoteListRow(note: note, category: store.noteCategory(note.categoryID), showsCategory: mixed,
                                        query: q, match: q.isEmpty ? nil : store.notes.first { $0.id == note.id },
                                        sort: sort, selected: selection.contains(note.id), first: i == 0)
                                .modifier(NoteItemActions(id: note.id, select: { click(note.id, modifiers: $0, order: order(list)) },
                                                          payload: dragPayload(for: note.id)) { rowMenu(menuIDs(note.id)) })
                        }
                    }
                    .padding(6)
                    .cardBackground(radius: 18)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selection.isEmpty {
                bulkBar.padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: selection.isEmpty)
        #if os(macOS)
        .onExitCommand { selection = [] }
        #endif
    }

    // MARK: Chips

    private func chipBar(_ scope: String) -> some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    NoteChip(name: "All", color: Color.primary.opacity(0.82), count: count("all"), on: scope == "all", targeted: dropTarget == "all") { pick("all") }
                        .modifier(ChipDropTarget(id: "all", target: $dropTarget, onDrop: drop))
                    ForEach(store.noteCategories) { category in
                        if renamingID == category.id {
                            chipField(color: category.color) {
                                RenameField(name: category.name) { name in
                                    if let name { store.renameNoteCategory(category.id, to: name) }
                                    renamingID = nil
                                }
                            }
                        } else {
                            NoteChip(name: category.name, color: category.color, count: count(category.id), on: scope == category.id,
                                     targeted: dropTarget == category.id) { pick(category.id) }
                                .contextMenu { categoryMenu(category) }
                                .modifier(ChipDropTarget(id: category.id, target: $dropTarget, onDrop: drop))
                        }
                    }
                    Button("New Category", systemImage: "plus") { showsNewCategory = true }
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink2)
                            .frame(width: 30, height: 30)
                            .background(.thinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                            .contentShape(Circle())
                            .buttonStyle(.plain)
                            .help("New category")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .padding(.vertical, -6)
        }
    }

    private func chipField(color: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            content()
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
    }

    @ViewBuilder
    private func categoryMenu(_ category: NoteCategory) -> some View {
        Button("New Note in \(category.name)", systemImage: "square.and.pencil") { pick(category.id); addNote(in: category.id) }
        Button("Rename", systemImage: "pencil") { renamingID = category.id }
        #if os(macOS)
        Button("Export as PDF…", systemImage: "arrow.down.document") { exportCategory(category) }
            .disabled(count(category.id) == 0)
        Button("Export as Separate PDFs…", systemImage: "doc.on.doc") { exportCategory(category, separately: true) }
            .disabled(count(category.id) == 0)
        #endif
        Divider()
        Button("Delete Category", systemImage: "trash", role: .destructive) { deleteCategory(category) }
    }

    // MARK: Rows

    /// A row's context menu acts on the selection when the row is part of it.
    private func menuIDs(_ id: ID) -> [ID] {
        selection.contains(id) ? Array(selection) : [id]
    }

    @ViewBuilder
    private func rowMenu(_ ids: [ID]) -> some View {
        let allPinned = ids.allSatisfy { id in store.noteSummaries.first { $0.id == id }?.pinned == true }
        if ids.count == 1, let id = ids.first {
            Button("Open", systemImage: "doc.text") { openNote(id) }
        }
        #if os(macOS)
        Button(ids.count == 1 ? "Open in New Window" : "Open in \(ids.count) Windows", systemImage: "macwindow") {
            ids.forEach { openWindow(id: NoteWindow.id, value: $0) }
        }
        #endif
        Divider()
        Button(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin") { store.setPinned(ids, !allPinned) }
        Menu("Move to") {
            ForEach(store.noteCategories) { category in
                Button(category.name) { store.moveNotes(ids, to: category.id) }
            }
        }
        if ids.count == 1, let id = ids.first {
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(id) }
        }
        #if os(macOS)
        Button(ids.count == 1 ? "Export as PDF…" : "Export \(ids.count) Notes as PDF…", systemImage: "arrow.down.document") { export(ids) }
        #endif
        Divider()
        Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Notes", systemImage: "trash", role: .destructive) { delete(ids) }
    }

    private var bulkBar: some View {
        let ids = Array(selection)
        let allPinned = ids.allSatisfy { id in store.noteSummaries.first { $0.id == id }?.pinned == true }
        return HStack(spacing: 4) {
            Text("\(selection.count) selected").font(.system(size: 13, weight: .semibold)).padding(.trailing, 8)
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
                #if os(macOS)
                Button("Export as PDF", systemImage: "arrow.down.document") { export(ids) }
                #endif
                Button("Delete", systemImage: "trash") { delete(ids) }
                Button("Clear Selection", systemImage: "xmark") { selection = [] }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Palette.ink2)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 40)
        .background {
            Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        }
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    /// A click opens the note; ⌘-click toggles it in the selection and ⇧-click extends the selection to it.
    private func click(_ id: ID, modifiers: EventModifiers, order: [ID]) {
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if modifiers.contains(.shift), let anchor = order.first(where: selection.contains),
                  let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
            selection.formUnion(order[min(a, b)...max(a, b)])
        } else if !selection.isEmpty {
            selection = []
        } else {
            openNote(id)
        }
    }

    #if os(macOS)
    /// Exports notes as one PDF, in the order the page shows them.
    private func export(_ ids: [ID]) {
        let order = order(filtered(validScope))
        let wanted = Set(ids)
        let byID = Dictionary(store.notes.filter { wanted.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let notes = (order.filter(wanted.contains) + ids.filter { !order.contains($0) }).compactMap { byID[$0] }
        let name = notes.count == 1 ? notes[0].displayTitle : validScope == "all" ? "Notes" : "\(scopeName(validScope)) Notes"
        NoteExport.savePDF(notes, name: name, store: store)
    }

    /// Exports every note in a category, pinned first, then in the page's sort order: as one PDF, or one per note.
    private func exportCategory(_ category: NoteCategory, separately: Bool = false) {
        var notes = store.notes.filter { $0.categoryID == category.id && $0.bookID == nil }
        switch sort {
        case .edited: notes.sort { $0.editedAt > $1.editedAt }
        case .created: notes.sort { $0.createdAt > $1.createdAt }
        case .title: notes.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        notes = notes.filter(\.pinned) + notes.filter { !$0.pinned }
        if separately {
            NoteExport.savePDFs(notes, name: category.name, store: store)
        } else {
            NoteExport.savePDF(notes, name: category.name, store: store)
        }
    }
    #endif

    /// Dragging a note that's part of a multi-selection drags the whole selection.
    private func dragPayload(for id: ID) -> String {
        selection.count > 1 && selection.contains(id) ? selection.joined(separator: "\n") : id
    }

    // MARK: Actions

    private func pick(_ newScope: String) {
        scope = newScope
        searchesAll = false
        selection = []
    }

    private func openNote(_ id: ID) {
        selection = []
        openID = id
        showsList = false
    }

    private func handle(_ request: NoteRequest?) {
        guard let request else { return }
        store.noteRequest = nil
        switch request {
        case .new:
            addNote()
        case .open(let id):
            guard store.notes.contains(where: { $0.id == id }) else { return }
            query = ""
            openNote(id)
        }
    }

    private func addNote(in categoryID: ID? = nil) {
        let open = showsList ? nil : store.notes.first { $0.id == openID }
        guard let categoryID = categoryID ?? store.noteCategory(validScope)?.id ?? open?.categoryID ?? store.noteCategories.first?.id else { return }
        let note = store.addNote(in: categoryID)
        query = ""
        freshID = note.id
        openNote(note.id)
    }

    private func duplicate(_ id: ID) {
        guard let copy = store.duplicateNote(id) else { return }
        if !showsList { openID = copy.id }
    }

    /// Deletes notes. Several at once asks first; deleting the open note goes back to the list.
    private func delete(_ ids: [ID], confirmed: Bool = false) {
        guard !ids.isEmpty else { return }
        if ids.count > 1, !confirmed { pendingDelete = ids; return }
        pendingDelete = []
        store.deleteNotes(ids, undoManager: undoManager)
        selection.subtract(ids)
        if ids.contains(openID) {
            showsList = true
            openID = ""
        }
    }

    private func deleteCategory(_ category: NoteCategory, confirmed: Bool = false) {
        if !confirmed, count(category.id) > 0 { pendingCategoryDelete = category; return }
        pendingCategoryDelete = nil
        store.deleteNoteCategory(category.id, undoManager: undoManager)
    }

    /// A drop on All does nothing; on a category it moves the notes there.
    private func drop(_ ids: [ID], on target: String) {
        guard target != "all" else { return }
        store.moveNotes(ids, to: target)
        selection = []
    }
}

// MARK: - Pieces

/// The editor for the open note. It reads the note itself, so its edits redraw only the editor, not the list.
struct OpenNoteEditor: View {
    var id: ID
    var isFresh: Bool
    var showsBrowser: Binding<Bool>
    var backToList = false
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        if let note = store.notes.first(where: { $0.id == id }) {
            NoteEditor(note: note, isFresh: isFresh, showsBrowser: showsBrowser, backToList: backToList, onDuplicate: onDuplicate, onDelete: onDelete)
        }
    }
}

/// New category: name and colour, in the v2 quick sheet. Calls `onAdd` with the new category's ID.
private struct NoteCategorySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State var hex: UInt32
    var onAdd: (ID) -> Void
    @FocusState private var focused: Bool

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        QuickSheet(isNew: true, addTitle: "Add category", canSave: canSave, onSave: save) {
            SheetIcon(systemImage: "folder", color: Color(hex: hex))
        } header: {
            SheetTitleField(title: "Category", prompt: "Algorithms", text: $name) {
                guard canSave else { return }
                save()
                dismiss()
            }
            .focused($focused)
            Text("Group notes by subject or project").font(.system(size: 14)).foregroundStyle(Palette.ink2)
        } rows: {
            SheetRow(title: "Colour", systemImage: "paintpalette", last: true) {
                SwatchPicker(hex: $hex, size: 20, swatches: NoteCategory.palette).padding(.top, 4)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        if let category = store.addNoteCategory(name: name, hex: hex) { onAdd(category.id) }
    }
}

/// Click (with its modifier keys), drag and context menu for a pinned card or list row.
private struct NoteItemActions<Menu: View>: ViewModifier {
    var id: ID
    var select: (EventModifiers) -> Void
    var payload: String
    @ViewBuilder var menu: () -> Menu

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(macOS)
                let flags = NSEvent.modifierFlags
                select(flags.contains(.command) ? .command : flags.contains(.shift) ? .shift : [])
                #else
                select([])
                #endif
            }
            .draggable(payload)
            .contextMenu { menu() }
    }
}

/// A section title: "Pinned", "Today 2".
private struct NoteSectionHeading: View {
    var title: String
    var count: Int?
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: 13, weight: .bold))
            if let count { Text(count.formatted()).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink3).monospacedDigit() }
        }
        .foregroundStyle(Palette.ink2)
        .padding(.leading, 4)
        .padding(.top, 4)
    }
}

/// A category filter chip: a dot, the name and its count; filled in its colour when on.
private struct NoteChip: View {
    var name: String
    var color: Color
    var count: Int
    var on: Bool
    var targeted: Bool
    var action: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(on ? .white : color).frame(width: 8, height: 8)
                Text(name).lineLimit(1)
                Text(count.formatted())
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(on ? .white.opacity(0.8) : Palette.ink2)
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? .white : .primary)
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(height: 30)
            .background { ChipBackground(color: color, on: on, hover: hover) }
            .overlay {
                if targeted { Capsule().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .fixedSize()
    }
}

private struct ChipBackground: View {
    var color: Color
    var on: Bool
    var hover: HoverState

    var body: some View {
        if on {
            Capsule().fill(color).shadow(color: color.opacity(0.3), radius: 6, y: 3)
        } else {
            Capsule().fill(Palette.surface.opacity(hover.isOn ? 0.92 : 0.62))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}

/// Hands over the note IDs dropped on a chip and outlines it while notes are over it.
private struct ChipDropTarget: ViewModifier {
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
    }
}

/// Pinned notes as cards, three to a row (two, then one, on narrower pages).
private struct PinnedGrid<Card: View>: View {
    var notes: [NoteSummary]
    @ViewBuilder var card: (NoteSummary) -> Card
    @Environment(\.pageWidth) private var width

    var body: some View {
        let columns = width >= 820 ? 3 : width >= 520 ? 2 : 1
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns), spacing: 14) {
            ForEach(notes) { card($0) }
        }
    }
}

/// A pinned note: its cover (or its category's colours), the icon on the cover's edge, title, category and time,
/// and the content badges.
private struct PinnedNoteCard: View {
    var note: NoteSummary
    var category: NoteCategory?
    var selected: Bool
    @State private var hover = HoverState()

    private var color: Color { category?.color ?? Palette.ink3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    icon
                        .padding(3)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.leading, 9)
                        .offset(y: 17)
                }
                .zIndex(1)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text("\(category?.name ?? "Notes") · \(NoteDates.stamp(note.editedAt))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                NoteBadges(note: note, tint: nil).padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.surface)
                .shadow(color: .black.opacity(0.07), radius: 9, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Palette.border, lineWidth: selected ? 2 : 0.5)
        }
        .modifier(HoverLift(hover: hover))
        .onHover { hover.isOn = $0 }
    }

    @ViewBuilder
    private var cover: some View {
        if let name = note.coverImage {
            StoredNoteImage(name: name, contentMode: .fill) { Palette.surface2 }
        } else if let cover = note.cover.flatMap(CoverGradient.init(rawValue:)) {
            MeshGradientView(colors: cover.colors)
        } else {
            MeshGradientView(colors: NoteTint.cover(category?.hex ?? 0x8E8E93))
        }
    }

    @ViewBuilder
    private var icon: some View {
        if note.icon != nil || note.iconImage != nil {
            NoteIconView(summary: note, size: 28)
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Raises a card a little while the pointer is over it.
private struct HoverLift: ViewModifier {
    var hover: HoverState

    func body(content: Content) -> some View {
        content
            .offset(y: hover.isOn ? -2 : 0)
            .animation(.easeOut(duration: 0.15), value: hover.isOn)
    }
}

/// A note in a group's card: a glyph tile in its category's colour, title and time, then category, snippet and
/// badges.
private struct NoteListRow: View {
    var note: NoteSummary
    var category: NoteCategory?
    var showsCategory: Bool
    var query: String
    /// The full note while searching, for the text around the match.
    var match: Note?
    var sort: NoteSort
    var selected: Bool
    var first: Bool
    @State private var hover = HoverState()

    private var color: Color { category?.color ?? Palette.ink3 }

    var body: some View {
        HStack(spacing: 14) {
            glyph
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(highlighted(note.displayTitle))
                        .font(.system(size: 14.5, weight: .semibold))
                        .kerning(-0.1)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(NoteDates.stamp(sort == .created ? note.createdAt : note.editedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink2)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    if showsCategory, let category {
                        Text(category.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(color).lineLimit(1).fixedSize()
                        Text("·").font(.system(size: 12)).foregroundStyle(Palette.ink3)
                    }
                    Text(highlighted(query.isEmpty ? note.snippet : excerpt))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .frame(maxWidth: 460, alignment: .leading)
                    NoteBadges(note: note, tint: color)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.13) : .clear)
            HoverFill(hover: hover, color: color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Palette.border).frame(height: 0.5).padding(.leading, 60).padding(.trailing, 14) }
        }
        .onHover { hover.isOn = $0 }
    }

    @ViewBuilder
    private var glyph: some View {
        if note.icon != nil || note.iconImage != nil {
            NoteIconView(summary: note, size: 36)
        } else {
            Text(glyphText)
                .font(.system(size: glyphText.count > 1 ? 13 : 15, weight: .bold, design: glyphText == "</>" ? .monospaced : .default))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 0.5))
        }
    }

    /// What the design's `glyph` picks: Bengali, then code, math, checklist, or plain text.
    private var glyphText: String {
        if NoteText.hasBengali(note.title) { return "অ" }
        if note.hasCode { return "</>" }
        if note.hasMath { return "∑" }
        if note.todos > 0 { return "✓" }
        return "Aa"
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

/// ∑ for math, </> for code and ☑ done/total for checklists: grey on cards, in the category's colour in rows.
private struct NoteBadges: View {
    var note: NoteSummary
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if note.hasMath { badge(Text("∑")).help("Math") }
            if note.hasCode { badge(Text("</>").font(.system(size: 10.5, weight: .bold, design: .monospaced))).help("Code") }
            if note.todos > 0 {
                badge(Text("\(Image(systemName: "checkmark.square")) \(note.todosDone)/\(note.todos)")).help("To-dos")
            }
        }
        .fixedSize()
    }

    private func badge(_ text: Text) -> some View {
        text
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint ?? Palette.ink2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background((tint?.opacity(0.12) ?? Palette.surface2), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Colours for a pinned note without a cover: its category's colour, lightened three ways for the mesh.
enum NoteTint {
    static func cover(_ hex: UInt32) -> [UInt32] {
        [mix(hex, 0xFFFFFF, 0.6), mix(hex, 0xFFE3F3, 0.72), mix(hex, 0xDCE6FF, 0.66)]
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) * (1 - t) + ch(b, s) * t).rounded()) << s }
        return m(16) | m(8) | m(0)
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

    /// The list page's time: "2m ago" / "5h ago" today, the time yesterday, the weekday this week, then "Oct 18".
    static func stamp(_ date: Date, now: Date = .now) -> String {
        let days = -(Day.fromToday(date) ?? 0)
        if days <= 0 {
            let s = now.timeIntervalSince(date)
            if s < 45 { return "just now" }
            if s < 3600 { return "\(max(1, Int((s / 60).rounded())))m ago" }
            return "\(Int((s / 3600).rounded(.down)))h ago"
        }
        if days == 1 { return date.formatted(date: .omitted, time: .shortened) }
        if days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        let sameYear = Day.calendar.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
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
