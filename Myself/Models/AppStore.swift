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
        case .notes: "Pages by category"
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
    private static let groupOrder = ["Overview", "Plan & Track", "Capture", "Build", "Health"]

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

/// A University record open in its editor sheet; one that isn't in the store yet is a new one.
enum UniversityEditor: Identifiable {
    case klass(UniClass), assignment(Assignment), exam(Exam), subject(SyllabusSubject)

    var id: ID {
        switch self {
        case .klass(let r): r.id
        case .assignment(let r): r.id
        case .exam(let r): r.id
        case .subject(let r): r.id
        }
    }
}

/// App state. TODOs, labels, office tasks, notes, University and Job Study are persisted and synced through `SyncEngine`; the other features are still
/// in-memory sample content. Feature visibility is stored in UserDefaults.
@Observable
final class AppStore {
    private(set) var labels: [TaskLabel] = []
    private(set) var todos: [Todo] = []
    private(set) var office: [OfficeTask] = []
    private(set) var university = University()
    private(set) var universityNotes = UniversityNotes()
    var products: [Product] = []
    private(set) var jobStudy: [StudySubject] = []
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
    var editingUniversity: UniversityEditor?
    /// The office task open in the editor sheet; one that isn't in `office` yet is a new one.
    var editingOffice: OfficeTask?


    let sync = SyncEngine()
    /// Last appearance/feature snapshot pushed to or pulled from `settings.json`.
    @ObservationIgnored private var syncedSettings: SyncedSettings?
    @ObservationIgnored private var applyingRemoteSettings = false
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// Notes edited in memory but not written yet; typing is saved in one write once it pauses.
    @ObservationIgnored private var unsavedNotes: Set<ID> = []
    @ObservationIgnored private var noteSaveTask: Task<Void, Never>?
    @ObservationIgnored private var universityNotesUnsaved = false
    @ObservationIgnored private var universityNotesSaveTask: Task<Void, Never>?

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

    /// Settings › Reset: replaces todos, labels, office tasks, notes, University and Job Study (in the sync folder too) and every other feature with the samples.
    func loadSampleData() {
        for todo in todos { sync.delete(Todo.self, id: todo.id) }
        labels = SampleData.labels
        todos = SampleData.todos()
        for label in labels { sync.save(label) }
        for todo in todos { sync.save(todo) }
        for task in office { sync.delete(OfficeTask.self, id: task.id) }
        office = SampleData.office()
        for task in office { sync.save(task) }
        unsavedNotes = []
        for note in notes { sync.delete(Note.self, id: note.id) }
        for category in noteCategories { sync.delete(NoteCategory.self, id: category.id) }
        noteCategories = SampleData.noteCategories
        notes = SampleData.notes()
        for category in noteCategories { sync.save(category) }
        for note in notes { sync.save(note) }
        loadSampleUniversity()
        for subject in jobStudy { sync.delete(StudySubject.self, id: subject.id) }
        jobStudy = SampleData.jobStudy()
        for subject in jobStudy { sync.save(subject) }
        loadSampleFeatures()
    }

    private func loadSampleFeatures() {
        products = SampleData.products()
        workout = SampleData.workout()
    }

    private func loadSampleUniversity() {
        let u = university
        for r in u.classes { sync.delete(UniClass.self, id: r.id) }
        for r in u.syllabus { sync.delete(SyllabusSubject.self, id: r.id) }
        for r in u.assignments { sync.delete(Assignment.self, id: r.id) }
        for r in u.exams { sync.delete(Exam.self, id: r.id) }
        university = SampleData.university()
        for r in university.classes { sync.save(r) }
        for r in university.syllabus { sync.save(r) }
        for r in university.assignments { sync.save(r) }
        for r in university.exams { sync.save(r) }
        universityNotesUnsaved = false
        universityNotes = UniversityNotes(text: SampleData.universityNotes, updatedAt: .now)
        sync.save(universityNotes)
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
        case .jobStudy: jobStudy.reduce(0) { $0 + $1.dueCount }
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

    // MARK: Office

    func newOfficeTask() {
        go(.office)
        editingOffice = OfficeTask(title: "", due: Day.offset(0))
    }

    func saveOfficeTask(_ task: OfficeTask, undoManager: UndoManager? = nil) {
        let isNew = !office.contains { $0.id == task.id }
        put(task, in: \.office, undoManager: undoManager, action: isNew ? "Add Office Task" : "Edit Office Task")
    }

    func toggleOffice(_ id: ID, undoManager: UndoManager? = nil) {
        guard var task = office.first(where: { $0.id == id }) else { return }
        task.done.toggle()
        task.completedAt = task.done ? .now : nil
        put(task, in: \.office, undoManager: undoManager, action: task.done ? "Complete Office Task" : "Reopen Office Task")
    }

    func deleteOfficeTask(_ id: ID, undoManager: UndoManager? = nil) {
        remove(id, from: \.office, undoManager: undoManager, action: "Delete Office Task")
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

    // MARK: University

    func newClass() {
        let hex = Palette.swatches[university.classes.count % Palette.swatches.count]
        editingUniversity = .klass(UniClass(subject: "", code: "", days: [], time: ClockTime(hour: 9, minute: 0), room: "", hex: hex))
    }

    func newAssignment() {
        editingUniversity = .assignment(Assignment(title: "", subject: university.subjects.first ?? "", due: Day.offset(7)))
    }

    func newExam() {
        editingUniversity = .exam(Exam(subject: university.subjects.first ?? "", kind: .midterm, date: Day.offset(14), prep: 0))
    }

    func newSyllabusSubject() {
        let taken = Set(university.syllabus.map(\.subject))
        editingUniversity = .subject(SyllabusSubject(subject: university.classes.map(\.subject).first { !taken.contains($0) } ?? "", topics: []))
    }

    /// Adds or updates a class. Renaming its subject renames it on assignments, exams and the syllabus too.
    func saveClass(_ klass: UniClass, undoManager: UndoManager? = nil) {
        let old = university.classes.first { $0.id == klass.id }
        put(klass, in: \.university.classes, undoManager: undoManager, action: old == nil ? "Add Class" : "Edit Class")
        if let old, old.subject != klass.subject { renameSubject(old.subject, to: klass.subject, undoManager: undoManager) }
    }

    func deleteClass(_ id: ID, undoManager: UndoManager? = nil) {
        remove(id, from: \.university.classes, undoManager: undoManager, action: "Delete Class")
    }

    func saveAssignment(_ assignment: Assignment, undoManager: UndoManager? = nil) {
        let isNew = !university.assignments.contains { $0.id == assignment.id }
        put(assignment, in: \.university.assignments, undoManager: undoManager, action: isNew ? "Add Assignment" : "Edit Assignment")
    }

    func toggleAssignment(_ id: ID, undoManager: UndoManager? = nil) {
        guard var assignment = university.assignments.first(where: { $0.id == id }) else { return }
        assignment.done.toggle()
        put(assignment, in: \.university.assignments, undoManager: undoManager, action: assignment.done ? "Complete Assignment" : "Reopen Assignment")
    }

    func deleteAssignment(_ id: ID, undoManager: UndoManager? = nil) {
        remove(id, from: \.university.assignments, undoManager: undoManager, action: "Delete Assignment")
    }

    func saveExam(_ exam: Exam, undoManager: UndoManager? = nil) {
        let isNew = !university.exams.contains { $0.id == exam.id }
        put(exam, in: \.university.exams, undoManager: undoManager, action: isNew ? "Add Exam" : "Edit Exam")
    }

    func deleteExam(_ id: ID, undoManager: UndoManager? = nil) {
        remove(id, from: \.university.exams, undoManager: undoManager, action: "Delete Exam")
    }

    func saveSyllabusSubject(_ subject: SyllabusSubject, undoManager: UndoManager? = nil) {
        let isNew = !university.syllabus.contains { $0.id == subject.id }
        put(subject, in: \.university.syllabus, undoManager: undoManager, action: isNew ? "Add Subject" : "Edit Subject")
    }

    func deleteSyllabusSubject(_ id: ID, undoManager: UndoManager? = nil) {
        remove(id, from: \.university.syllabus, undoManager: undoManager, action: "Delete Subject")
    }

    func toggleSyllabusTopic(subject: ID, topic: ID) {
        editSyllabus(subject) { s in
            if let t = s.topics.firstIndex(where: { $0.id == topic }) { s.topics[t].done.toggle() }
        }
    }

    func addSyllabusTopic(subject: ID, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        editSyllabus(subject) { $0.topics.append(SyllabusTopic(name: name)) }
    }

    func deleteSyllabusTopic(subject: ID, topic: ID) {
        editSyllabus(subject) { $0.topics.removeAll { $0.id == topic } }
    }

    private func editSyllabus(_ id: ID, _ change: (inout SyllabusSubject) -> Void) {
        guard var subject = university.syllabus.first(where: { $0.id == id }) else { return }
        change(&subject)
        put(subject, in: \.university.syllabus, undoManager: nil, action: "")
    }

    private func renameSubject(_ old: String, to new: String, undoManager: UndoManager?) {
        for var a in university.assignments where a.subject == old {
            a.subject = new
            put(a, in: \.university.assignments, undoManager: undoManager, action: "Edit Class")
        }
        for var e in university.exams where e.subject == old {
            e.subject = new
            put(e, in: \.university.exams, undoManager: undoManager, action: "Edit Class")
        }
        for var s in university.syllabus where s.subject == old {
            s.subject = new
            put(s, in: \.university.syllabus, undoManager: undoManager, action: "Edit Class")
        }
    }

    /// Adds or replaces a record in one of the synced lists (office tasks, University) and writes its file.
    private func put<T: SyncRecord & Equatable>(_ record: T, in list: ReferenceWritableKeyPath<AppStore, [T]>, undoManager: UndoManager?, action: String) {
        var record = record
        record.updatedAt = .now
        let old = self[keyPath: list].first { $0.id == record.id }
        if let i = self[keyPath: list].firstIndex(where: { $0.id == record.id }) { self[keyPath: list][i] = record } else { self[keyPath: list].append(record) }
        sync.save(record)
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            if let old { store.put(old, in: list, undoManager: undoManager, action: action) } else { store.remove(record.id, from: list, undoManager: undoManager, action: action) }
        }
        undoManager.setActionName(action)
    }

    private func remove<T: SyncRecord & Equatable>(_ id: ID, from list: ReferenceWritableKeyPath<AppStore, [T]>, undoManager: UndoManager?, action: String) {
        guard let record = self[keyPath: list].first(where: { $0.id == id }) else { return }
        self[keyPath: list].removeAll { $0.id == id }
        sync.delete(T.self, id: id)
        undoManager?.registerUndo(withTarget: self) { $0.put(record, in: list, undoManager: undoManager, action: action) }
        undoManager?.setActionName(action)
    }

    /// Edits the University notes. Memory updates straight away; the file is written once typing pauses.
    func editUniversityNotes(_ text: String) {
        guard text != universityNotes.text else { return }
        universityNotes.text = text
        universityNotes.updatedAt = .now
        universityNotesUnsaved = true
        universityNotesSaveTask?.cancel()
        universityNotesSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveUniversityNotes()
        }
    }

    func saveUniversityNotes() {
        universityNotesSaveTask?.cancel()
        guard universityNotesUnsaved else { return }
        universityNotesUnsaved = false
        sync.save(universityNotes)
    }

    // MARK: Job Study

    /// Adds or updates a subject (name and colour; topics are changed with the methods below).
    func saveStudySubject(_ subject: StudySubject, undoManager: UndoManager? = nil) {
        let isNew = !jobStudy.contains { $0.id == subject.id }
        put(subject, in: \.jobStudy, undoManager: undoManager, action: isNew ? "Add Subject" : "Edit Subject")
    }

    func deleteStudySubject(_ id: ID, undoManager: UndoManager? = nil) {
        remove(id, from: \.jobStudy, undoManager: undoManager, action: "Delete Subject")
    }

    /// Ticking a topic logs one revision for today; un-ticking the same day undoes it.
    func reviseTopic(subject: ID, topic: ID) {
        editStudyTopic(subject, topic) { t in
            if t.revisedToday {
                t.revisions = max(0, t.revisions - 1)
                t.lastRevised = t.previousRevised
                t.previousRevised = nil
            } else {
                t.revisions += 1
                t.previousRevised = t.lastRevised
                t.lastRevised = Day.offset(0)
            }
        }
    }

    /// The ± stepper: corrects the revision count. Adding dates the revision today; removing the last one clears the date.
    func adjustRevisions(subject: ID, topic: ID, by delta: Int) {
        editStudyTopic(subject, topic) { t in
            t.revisions = max(0, t.revisions + delta)
            if delta > 0 {
                if !t.revisedToday { t.previousRevised = t.lastRevised }
                t.lastRevised = Day.offset(0)
            } else if t.revisions == 0 {
                t.lastRevised = nil
                t.previousRevised = nil
            }
        }
    }

    func addStudyTopic(subject: ID, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        editStudySubject(subject) { $0.topics.append(StudyTopic(name: name)) }
    }

    func renameStudyTopic(subject: ID, topic: ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        editStudyTopic(subject, topic) { $0.name = name }
    }

    func deleteStudyTopic(subject: ID, topic: ID, undoManager: UndoManager? = nil) {
        editStudySubject(subject, undoManager: undoManager, action: "Delete Topic") { $0.topics.removeAll { $0.id == topic } }
    }

    /// Links a note to a topic, or unlinks it if it's linked already.
    func toggleTopicNote(subject: ID, topic: ID, note: ID) {
        editStudyTopic(subject, topic) { t in
            if t.noteIDs.contains(note) { t.noteIDs.removeAll { $0 == note } } else { t.noteIDs.append(note) }
        }
    }

    /// Creates a note in the "Job Study" category (added if missing) and links it to the topic.
    @discardableResult
    func addTopicNote(subject: ID, topic: ID, title: String) -> Note {
        let category = noteCategories.first { $0.name == "Job Study" } ?? {
            let category = NoteCategory(id: newID(), name: "Job Study", hex: 0xFF9500,
                                        sortOrder: (noteCategories.map(\.sortOrder).max() ?? -1) + 1, updatedAt: .now)
            noteCategories.append(category)
            sync.save(category)
            return category
        }()
        let note = Note(categoryID: category.id, title: title)
        notes.append(note)
        sync.save(note)
        toggleTopicNote(subject: subject, topic: topic, note: note.id)
        return note
    }

    private func editStudyTopic(_ subject: ID, _ topic: ID, _ change: (inout StudyTopic) -> Void) {
        editStudySubject(subject) { s in
            if let t = s.topics.firstIndex(where: { $0.id == topic }) { change(&s.topics[t]) }
        }
    }

    private func editStudySubject(_ id: ID, undoManager: UndoManager? = nil, action: String = "", _ change: (inout StudySubject) -> Void) {
        guard var subject = jobStudy.first(where: { $0.id == id }) else { return }
        change(&subject)
        put(subject, in: \.jobStudy, undoManager: undoManager, action: action)
    }

    // MARK: Sync

    /// Re-reads todos, labels, office tasks, notes, University and Job Study from the sync folder and pulls shared settings.
    func reloadSynced() {
        // Write pending note edits first so the reload can't bring back older text.
        saveUnsavedNotes()
        saveUniversityNotes()
        sync.scan {
            let todos = sync.load(Todo.self, keeping: todos).sorted { $0.createdAt < $1.createdAt }
            if todos != self.todos { self.todos = todos }
            let labels = sync.load(TaskLabel.self, keeping: labels).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            if labels != self.labels { self.labels = labels }
            let office = sync.load(OfficeTask.self, keeping: office).sorted { $0.createdAt < $1.createdAt }
            if office != self.office { self.office = office }
            let categories = sync.load(NoteCategory.self, keeping: noteCategories).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            if categories != self.noteCategories { self.noteCategories = categories }
            let notes = sync.load(Note.self, keeping: notes).sorted { $0.createdAt < $1.createdAt }
            if notes != self.notes { self.notes = notes }

            var u = University()
            u.classes = sync.load(UniClass.self, keeping: university.classes).sorted { $0.createdAt < $1.createdAt }
            u.syllabus = sync.load(SyllabusSubject.self, keeping: university.syllabus).sorted { $0.createdAt < $1.createdAt }
            u.assignments = sync.load(Assignment.self, keeping: university.assignments).sorted { $0.createdAt < $1.createdAt }
            u.exams = sync.load(Exam.self, keeping: university.exams).sorted { $0.date < $1.date }
            if u != university { university = u }
            let uniNotes = sync.load(UniversityNotes.self, keeping: [universityNotes]).first ?? UniversityNotes()
            if uniNotes != universityNotes { universityNotes = uniNotes }
            let jobStudy = sync.load(StudySubject.self, keeping: jobStudy).sorted { $0.createdAt < $1.createdAt }
            if jobStudy != self.jobStudy { self.jobStudy = jobStudy }
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
        saveUniversityNotes()
        let (todos, labels, office, categories, notes) = (todos, labels, office, noteCategories, notes)
        let (u, uniNotes, jobStudy) = (university, universityNotes, jobStudy)
        try change()
        for r in jobStudy { sync.save(r, onlyIfNewer: true) }
        for r in u.classes { sync.save(r, onlyIfNewer: true) }
        for r in u.syllabus { sync.save(r, onlyIfNewer: true) }
        for r in u.assignments { sync.save(r, onlyIfNewer: true) }
        for r in u.exams { sync.save(r, onlyIfNewer: true) }
        if uniNotes.updatedAt > .distantPast { sync.save(uniNotes, onlyIfNewer: true) }
        for label in labels { sync.save(label, onlyIfNewer: true) }
        for todo in todos { sync.save(todo, onlyIfNewer: true) }
        for task in office { sync.save(task, onlyIfNewer: true) }
        for category in categories { sync.save(category, onlyIfNewer: true) }
        for note in notes { sync.save(note, onlyIfNewer: true) }
        syncedSettings = nil
        reloadSynced()
    }

    private static let appearanceKeys = [PrefKey.appearance, PrefKey.sidebarStyle, PrefKey.rowDensity]
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
