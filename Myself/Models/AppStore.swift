import SwiftUI

enum Page: String, CaseIterable, Identifiable, Hashable {
    case dashboard, todos, university, office, jobStudy, products, workout, notes

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .todos: "TODOs"
        case .university: "University"
        case .office: "Office Tasks"
        case .jobStudy: "Job Study"
        case .products: "Product Dev"
        case .workout: "Workout"
        case .notes: "Notes"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Everything that matters, at a glance"
        case .todos: "Your personal task list"
        case .university: "Classes, syllabus, assignments & exams"
        case .office: "Work items — always high priority"
        case .jobStudy: "Interview prep with revision tracking"
        case .products: "Your solo company, on Kanban boards"
        case .workout: "Programs, streaks & progress"
        case .notes: "Pages by category — LaTeX, code & বাংলা"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .todos: "checklist"
        case .university: "graduationcap"
        case .office: "briefcase"
        case .jobStudy: "book.closed"
        case .products: "shippingbox"
        case .workout: "dumbbell"
        case .notes: "note.text"
        }
    }

    var group: String {
        switch self {
        case .dashboard: "Overview"
        case .todos, .university, .office, .jobStudy: "Plan & Track"
        case .products: "Build"
        case .notes: "Capture"
        case .workout: "Health"
        }
    }

    /// Pages that Settings › Features can turn off. Dashboard and TODOs are always on.
    var isOptional: Bool { self != .dashboard && self != .todos }

    /// One-line description shown in Settings › Features.
    var featureDescription: String {
        switch self {
        case .dashboard: "Everything that matters, at a glance"
        case .todos: "Your personal task list"
        case .university: "Classes, syllabus, assignments and exams"
        case .office: "Work items with reference links"
        case .jobStudy: "Interview prep with revision tracking"
        case .products: "Kanban boards for your products"
        case .workout: "Programs, streaks and progress"
        case .notes: "Pages by category with LaTeX, code and Bengali"
        }
    }

    /// Pages that render as a blurred, non-interactive preview behind a "Coming soon" card.
    var isComingSoon: Bool { self == .workout }

    /// Icon tile colour in Settings › Features.
    var featureColor: Color {
        switch self {
        case .dashboard, .office: Palette.blue
        case .todos: Palette.green
        case .university: Palette.violet
        case .jobStudy, .notes: Palette.amber
        case .products: Palette.cyan
        case .workout: Palette.red
        }
    }

    /// Sidebar section order. `allCases` order can't drive it: new pages go last to keep the ⌘1–⌘9 shortcuts stable.
    private static let groupOrder = ["Overview", "Plan & Track", "Build", "Capture", "Health"]

    /// Sidebar sections, in order, holding only the given pages.
    static func groups(_ pages: [Page]) -> [(name: String, pages: [Page])] {
        var out: [(String, [Page])] = []
        for page in pages {
            if let i = out.firstIndex(where: { $0.0 == page.group }) { out[i].1.append(page) } else { out.append((page.group, [page])) }
        }
        return out.sorted { (groupOrder.firstIndex(of: $0.0) ?? .max) < (groupOrder.firstIndex(of: $1.0) ?? .max) }
    }
}

enum SettingsTab: Hashable { case general, features, iCloud }

enum NoteRequest: Equatable { case open(ID), new }

/// App state. TODOs, labels and notes are persisted and synced through `SyncEngine`; the other features are still
/// in-memory sample content. Feature visibility is stored in UserDefaults.
@Observable
final class AppStore {
    private(set) var labels: [TaskLabel] = []
    private(set) var todos: [Todo] = []
    var office: [OfficeTask] = []
    var university = SampleData.university()
    var products: [Product] = []
    var jobStudy: [StudySubject] = []
    var workout = SampleData.workout()
    private(set) var noteCategories: [NoteCategory] = []
    private(set) var notes: [Note] = []

    // Navigation history (⌘[ / ⌘])
    private(set) var history: [Page] = [.dashboard]
    private(set) var historyIndex = 0
    var isQuickOpenPresented = false
    var isSettingsPresented = false
    var settingsTab: SettingsTab = .general
    /// The todo open in the editor sheet; a todo that isn't in `todos` yet is a new one.
    var editingTodo: Todo?
    /// Asks the Notes page to open or create a note (Quick Open, File › New Note); the page clears it.
    var noteRequest: NoteRequest?


    let sync = SyncEngine()
    /// Last appearance/feature snapshot pushed to or pulled from `settings.json`.
    @ObservationIgnored private var syncedSettings: SyncedSettings?
    @ObservationIgnored private var applyingRemoteSettings = false
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// Notes edited in memory but not written yet; typing is saved in one write once it pauses.
    @ObservationIgnored private var unsavedNotes: Set<ID> = []
    @ObservationIgnored private var noteSaveTask: Task<Void, Never>?

    /// Features turned off in Settings. Their data is kept; they're only hidden.
    private(set) var disabledPages: Set<Page> = Set(
        (UserDefaults.standard.stringArray(forKey: "disabledFeatures") ?? []).compactMap(Page.init(rawValue:))
    )

    init() {
        loadSampleFeatures()
        sync.onChange = { [weak self] in self?.reloadSynced() }
        reloadSynced()
        // Fresh folder: create the default labels. Their fixed IDs stop two Macs from seeding duplicates.
        if labels.isEmpty, !sync.hasFiles(TaskLabel.self) {
            for label in SampleData.labels { sync.save(label, onlyIfNewer: true) }
            reloadSynced()
        }
        if noteCategories.isEmpty, !sync.hasFiles(NoteCategory.self) {
            for category in SampleData.noteCategories { sync.save(category, onlyIfNewer: true) }
            reloadSynced()
        }
        syncedSettings = localSettings()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushSettings() }
        }
    }

    /// Settings › Reset: replaces todos, labels and notes (in the sync folder too) and every other feature with the samples.
    func loadSampleData() {
        for todo in todos { sync.delete(Todo.self, id: todo.id) }
        labels = SampleData.labels
        todos = SampleData.todos()
        for label in labels { sync.save(label) }
        for todo in todos { sync.save(todo) }
        unsavedNotes = []
        for note in notes { sync.delete(Note.self, id: note.id) }
        for category in noteCategories { sync.delete(NoteCategory.self, id: category.id) }
        noteCategories = SampleData.noteCategories
        notes = SampleData.notes()
        for category in noteCategories { sync.save(category) }
        for note in notes { sync.save(note) }
        loadSampleFeatures()
    }

    private func loadSampleFeatures() {
        office = SampleData.office()
        university = SampleData.university()
        products = SampleData.products()
        jobStudy = SampleData.jobStudy()
        workout = SampleData.workout()
    }

    // MARK: Navigation

    var page: Page { history[historyIndex] }
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    func go(_ page: Page) {
        isQuickOpenPresented = false
        guard page != self.page, isEnabled(page) else { return }
        history = Array(history.prefix(historyIndex + 1)) + [page]
        historyIndex += 1
    }

    func back() { if canGoBack { historyIndex -= 1 } }
    func forward() { if canGoForward { historyIndex += 1 } }

    func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        isQuickOpenPresented = false
        isSettingsPresented = true
    }

    // MARK: Features

    func isEnabled(_ page: Page) -> Bool { !disabledPages.contains(page) }

    var enabledPages: [Page] { Page.allCases.filter(isEnabled) }

    func setEnabled(_ page: Page, _ enabled: Bool) {
        guard page.isOptional else { return }
        if enabled { disabledPages.remove(page) } else { disabledPages.insert(page) }
        UserDefaults.standard.set(disabledPages.map(\.rawValue).sorted(), forKey: "disabledFeatures")
        if !enabled { removeFromHistory(page) }
    }

    /// Drops a hidden page from back/forward history; if it was showing, you land on the page before it (or the Dashboard).
    private func removeFromHistory(_ hidden: Page) {
        var kept: [Page] = []
        var index = 0
        for (i, page) in history.enumerated() {
            if page != hidden, page != kept.last { kept.append(page) }
            if i == historyIndex { index = max(0, kept.count - 1) }
        }
        if kept.isEmpty { kept = [.dashboard] }
        history = kept
        historyIndex = min(index, kept.count - 1)
    }

    // MARK: Derived

    func label(_ id: ID) -> TaskLabel? { labels.first { $0.id == id } }

    /// Sidebar badge counts.
    func count(for page: Page) -> Int {
        switch page {
        case .dashboard, .notes: 0
        case .todos: todos.filter { !$0.done }.count
        case .office: office.filter { !$0.done }.count
        case .university: university.assignments.filter { !$0.done }.count
        case .products: products.reduce(0) { $0 + ($1.column(titled: "In Progress")?.cards.count ?? 0) }
        case .workout: workout.streak
        case .jobStudy: jobStudy.reduce(0) { $0 + $1.topics.filter { $0.revisions == 0 }.count }
        }
    }

    // MARK: Mutations

    func newTodo() {
        go(.todos)
        editingTodo = Todo(title: "")
    }

    /// Adds or updates a todo and writes it to the sync folder.
    func saveTodo(_ todo: Todo, undoManager: UndoManager? = nil) {
        var todo = todo
        todo.updatedAt = .now
        let old = todos.first { $0.id == todo.id }
        if let i = todos.firstIndex(where: { $0.id == todo.id }) { todos[i] = todo } else { todos.append(todo) }
        sync.save(todo)
        undoManager?.registerUndo(withTarget: self) { store in
            if let old { store.saveTodo(old, undoManager: undoManager) } else { store.deleteTodo(todo.id, undoManager: undoManager) }
        }
        undoManager?.setActionName(old == nil ? "Add Todo" : "Edit Todo")
    }

    func toggleTodo(_ id: ID, undoManager: UndoManager? = nil) {
        guard var todo = todos.first(where: { $0.id == id }) else { return }
        todo.done.toggle()
        todo.completedAt = todo.done ? .now : nil
        saveTodo(todo, undoManager: undoManager)
        undoManager?.setActionName(todo.done ? "Complete Todo" : "Reopen Todo")
    }

    func deleteTodo(_ id: ID, undoManager: UndoManager? = nil) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        todos.removeAll { $0.id == id }
        sync.delete(Todo.self, id: id)
        undoManager?.registerUndo(withTarget: self) { $0.saveTodo(todo, undoManager: undoManager) }
        undoManager?.setActionName("Delete Todo")
    }

    @discardableResult
    func addLabel(name: String, hex: UInt32) -> TaskLabel? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let label = TaskLabel(id: newID(), name: name, hex: hex, sortOrder: (labels.map(\.sortOrder).max() ?? -1) + 1, updatedAt: .now)
        labels.append(label)
        sync.save(label)
        return label
    }

    /// Deletes a label and takes it off every todo.
    func deleteLabel(_ id: ID) {
        labels.removeAll { $0.id == id }
        sync.delete(TaskLabel.self, id: id)
        for var todo in todos where todo.labelIDs.contains(id) {
            todo.labelIDs.removeAll { $0 == id }
            saveTodo(todo)
        }
    }

    // MARK: Notes

    func noteCategory(_ id: ID) -> NoteCategory? { noteCategories.first { $0.id == id } }

    /// File › New Note: opens the Notes page and asks it for a new note in the category it shows.
    func newNote() {
        go(.notes)
        noteRequest = .new
    }

    /// Opens a note from outside the Notes page.
    func openNote(_ id: ID) {
        go(.notes)
        noteRequest = .open(id)
    }

    @discardableResult
    func addNote(in categoryID: ID) -> Note {
        let note = Note(categoryID: categoryID)
        notes.append(note)
        sync.save(note)
        return note
    }

    /// Edits a note's content. Memory updates straight away; the file is written once typing pauses.
    func editNote(_ id: ID, _ edit: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[i]
        edit(&note)
        guard note != notes[i] else { return }
        note.editedAt = .now
        note.updatedAt = .now
        notes[i] = note
        unsavedNotes.insert(id)
        noteSaveTask?.cancel()
        noteSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveUnsavedNotes()
        }
    }

    /// Writes notes edited with `editNote` that haven't been saved yet.
    func saveUnsavedNotes() {
        noteSaveTask?.cancel()
        for id in unsavedNotes {
            if let note = notes.first(where: { $0.id == id }) { sync.save(note) }
        }
        unsavedNotes = []
    }

    /// Changes that aren't edits (pin, move): saved at once and they keep the "Date edited".
    private func updateNotes(_ ids: [ID], _ change: (inout Note) -> Void) {
        for i in notes.indices where ids.contains(notes[i].id) {
            change(&notes[i])
            notes[i].updatedAt = .now
            unsavedNotes.remove(notes[i].id)
            sync.save(notes[i])
        }
    }

    func setPinned(_ ids: [ID], _ pinned: Bool) { updateNotes(ids) { $0.pinned = pinned } }

    func moveNotes(_ ids: [ID], to categoryID: ID) { updateNotes(ids) { $0.categoryID = categoryID } }

    @discardableResult
    func duplicateNote(_ id: ID) -> Note? {
        guard var copy = notes.first(where: { $0.id == id }) else { return nil }
        copy.id = newID()
        copy.title += " copy"
        copy.pinned = false
        copy.blocks = copy.blocks.map { var b = $0; b.id = newID(); return b }
        (copy.createdAt, copy.editedAt, copy.updatedAt) = (.now, .now, .now)
        notes.append(copy)
        sync.save(copy)
        return copy
    }

    func deleteNotes(_ ids: [ID], undoManager: UndoManager? = nil) {
        let removed = notes.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        notes.removeAll { ids.contains($0.id) }
        for note in removed {
            unsavedNotes.remove(note.id)
            sync.delete(Note.self, id: note.id)
        }
        undoManager?.registerUndo(withTarget: self) { $0.restore(notes: removed, categories: [], undoManager: undoManager) }
        undoManager?.setActionName(removed.count == 1 ? "Delete Note" : "Delete Notes")
    }

    @discardableResult
    func addNoteCategory(name: String) -> NoteCategory? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let category = NoteCategory(id: newID(), name: name, hex: NoteCategory.palette[noteCategories.count % NoteCategory.palette.count],
                                    sortOrder: (noteCategories.map(\.sortOrder).max() ?? -1) + 1, updatedAt: .now)
        noteCategories.append(category)
        sync.save(category)
        return category
    }

    func renameNoteCategory(_ id: ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = noteCategories.firstIndex(where: { $0.id == id }), noteCategories[i].name != name else { return }
        noteCategories[i].name = name
        noteCategories[i].updatedAt = .now
        sync.save(noteCategories[i])
    }

    /// Deletes a category together with its notes.
    func deleteNoteCategory(_ id: ID, undoManager: UndoManager? = nil) {
        guard let category = noteCategory(id) else { return }
        let removed = notes.filter { $0.categoryID == id }
        noteCategories.removeAll { $0.id == id }
        sync.delete(NoteCategory.self, id: id)
        deleteNotes(removed.map(\.id))
        undoManager?.registerUndo(withTarget: self) { $0.restore(notes: removed, categories: [category], undoManager: undoManager) }
        undoManager?.setActionName("Delete Category")
    }

    private func restore(notes restored: [Note], categories: [NoteCategory], undoManager: UndoManager?) {
        for var category in categories {
            category.updatedAt = .now
            noteCategories.append(category)
            sync.save(category)
        }
        noteCategories.sort { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        for var note in restored {
            note.updatedAt = .now
            notes.append(note)
            sync.save(note)
        }
        undoManager?.registerUndo(withTarget: self) { store in
            if let category = categories.first {
                store.deleteNoteCategory(category.id, undoManager: undoManager)
            } else {
                store.deleteNotes(restored.map(\.id), undoManager: undoManager)
            }
        }
    }

    // MARK: Sync

    /// Re-reads todos, labels and notes from the sync folder and pulls shared settings.
    func reloadSynced() {
        // Write pending note edits first so the reload can't bring back older text.
        saveUnsavedNotes()
        sync.scan {
            let todos = sync.load(Todo.self, keeping: todos).sorted { $0.createdAt < $1.createdAt }
            if todos != self.todos { self.todos = todos }
            let labels = sync.load(TaskLabel.self, keeping: labels).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            if labels != self.labels { self.labels = labels }
            let categories = sync.load(NoteCategory.self, keeping: noteCategories).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            if categories != self.noteCategories { self.noteCategories = categories }
            let notes = sync.load(Note.self, keeping: notes).sorted { $0.createdAt < $1.createdAt }
            if notes != self.notes { self.notes = notes }
        }
        pullSettings()
    }

    func setICloudSync(_ on: Bool) {
        carryData { sync.setCloudEnabled(on) }
    }

    func useICloudFolder(_ url: URL) throws {
        try carryData { try sync.useCloudFolder(url) }
    }

    /// Switches the sync folder and copies over what's in memory, without overwriting newer files already there.
    private func carryData(_ change: () throws -> Void) rethrows {
        saveUnsavedNotes()
        let (todos, labels, categories, notes) = (todos, labels, noteCategories, notes)
        try change()
        for label in labels { sync.save(label, onlyIfNewer: true) }
        for todo in todos { sync.save(todo, onlyIfNewer: true) }
        for category in categories { sync.save(category, onlyIfNewer: true) }
        for note in notes { sync.save(note, onlyIfNewer: true) }
        syncedSettings = nil
        reloadSynced()
    }

    private static let appearanceKeys = [PrefKey.appearance, PrefKey.accent, PrefKey.sidebarStyle, PrefKey.rowDensity]
    private static let settingsSyncedAtKey = "settingsSyncedAt"

    /// This Mac's share of `settings.json`: only the groups turned on under Settings › iCloud › Also sync.
    private func localSettings() -> SyncedSettings {
        let defaults = UserDefaults.standard
        var settings = SyncedSettings()
        if defaults.object(forKey: PrefKey.syncAppearance) as? Bool ?? true {
            settings.appearance = Dictionary(uniqueKeysWithValues: Self.appearanceKeys.compactMap { key in defaults.string(forKey: key).map { (key, $0) } })
        }
        if defaults.object(forKey: PrefKey.syncFeatures) as? Bool ?? true {
            settings.disabledFeatures = disabledPages.map(\.rawValue).sorted()
        }
        return settings
    }

    /// Writes local appearance/feature changes to `settings.json`.
    private func pushSettings() {
        guard sync.usesCloud, !applyingRemoteSettings else { return }
        let local = localSettings()
        guard local != syncedSettings else { return }
        syncedSettings = local
        var out = local
        out.updatedAt = .now
        // Keep the groups this Mac doesn't sync as other Macs left them.
        if let remote = sync.readSettings() {
            out.appearance = out.appearance ?? remote.appearance
            out.disabledFeatures = out.disabledFeatures ?? remote.disabledFeatures
        }
        sync.writeSettings(out)
        UserDefaults.standard.set(out.updatedAt.timeIntervalSince1970, forKey: Self.settingsSyncedAtKey)
    }

    /// Applies `settings.json` when another Mac changed it since this one last synced.
    private func pullSettings() {
        guard sync.usesCloud else { return }
        guard let remote = sync.readSettings() else {
            if syncedSettings == nil { syncedSettings = SyncedSettings() }
            pushSettings()
            return
        }
        let defaults = UserDefaults.standard
        guard remote.updatedAt.timeIntervalSince1970 > defaults.double(forKey: Self.settingsSyncedAtKey) else {
            if syncedSettings == nil { syncedSettings = localSettings() }
            return
        }
        applyingRemoteSettings = true
        defer {
            applyingRemoteSettings = false
            syncedSettings = localSettings()
        }
        if defaults.object(forKey: PrefKey.syncAppearance) as? Bool ?? true, let appearance = remote.appearance {
            for (key, value) in appearance where Self.appearanceKeys.contains(key) && defaults.string(forKey: key) != value {
                defaults.set(value, forKey: key)
            }
        }
        if defaults.object(forKey: PrefKey.syncFeatures) as? Bool ?? true, let disabled = remote.disabledFeatures {
            for page in Page.allCases where page.isOptional && isEnabled(page) == disabled.contains(page.rawValue) {
                setEnabled(page, !disabled.contains(page.rawValue))
            }
        }
        defaults.set(remote.updatedAt.timeIntervalSince1970, forKey: Self.settingsSyncedAtKey)
    }

    // MARK: Other features

    func toggleOffice(_ id: ID) {
        if let i = office.firstIndex(where: { $0.id == id }) { office[i].done.toggle() }
    }

    func toggleAssignment(_ id: ID) {
        if let i = university.assignments.firstIndex(where: { $0.id == id }) { university.assignments[i].done.toggle() }
    }

    func toggleSyllabusTopic(subject: ID, topic: ID) {
        guard let s = university.syllabus.firstIndex(where: { $0.id == subject }),
              let t = university.syllabus[s].topics.firstIndex(where: { $0.id == topic }) else { return }
        university.syllabus[s].topics[t].done.toggle()
    }

    func addSyllabusTopic(subject: ID, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let s = university.syllabus.firstIndex(where: { $0.id == subject }) else { return }
        university.syllabus[s].topics.append(SyllabusTopic(name: name))
    }

    func deleteSyllabusTopic(subject: ID, topic: ID) {
        guard let s = university.syllabus.firstIndex(where: { $0.id == subject }) else { return }
        university.syllabus[s].topics.removeAll { $0.id == topic }
    }

    /// Ticking a topic logs one revision for today; un-ticking the same day undoes it.
    func reviseTopic(subject: ID, topic: ID) {
        guard let s = jobStudy.firstIndex(where: { $0.id == subject }),
              let t = jobStudy[s].topics.firstIndex(where: { $0.id == topic }) else { return }
        var item = jobStudy[s].topics[t]
        if Day.isToday(item.lastRevised) {
            item.revisions = max(0, item.revisions - 1)
            item.lastRevised = item.previousRevised
            item.previousRevised = nil
        } else {
            item.revisions += 1
            item.previousRevised = item.lastRevised
            item.lastRevised = Day.offset(0)
        }
        jobStudy[s].topics[t] = item
    }

    func addStudyTopic(subject: ID, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let s = jobStudy.firstIndex(where: { $0.id == subject }) else { return }
        jobStudy[s].topics.append(StudyTopic(name: name, revisions: 0))
    }

    func deleteStudyTopic(subject: ID, topic: ID) {
        guard let s = jobStudy.firstIndex(where: { $0.id == subject }) else { return }
        jobStudy[s].topics.removeAll { $0.id == topic }
    }

    func moveCard(_ cardID: ID, to columnID: ID, in productID: ID) {
        guard let p = products.firstIndex(where: { $0.id == productID }) else { return }
        var columns = products[p].columns
        guard let from = columns.firstIndex(where: { $0.cards.contains { $0.id == cardID } }),
              let to = columns.firstIndex(where: { $0.id == columnID }), from != to,
              let c = columns[from].cards.firstIndex(where: { $0.id == cardID }) else { return }
        let card = columns[from].cards.remove(at: c)
        columns[to].cards.append(card)
        products[p].columns = columns
    }

    func toggleTrainedToday() {
        let already = workout.trainedToday
        workout.history[workout.history.count - 1] = !already
        workout.streak = already ? max(0, workout.streak - 1) : workout.streak + 1
    }

    func updateProgram(_ program: WorkoutProgram) {
        if let i = workout.programs.firstIndex(where: { $0.id == program.id }) { workout.programs[i] = program }
    }
}
