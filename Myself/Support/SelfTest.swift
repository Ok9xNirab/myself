#if DEBUG
import Foundation

/// Debug-only check of the SwiftData layer, run with `Myself -selfTest` (it prints a report and quits). Uses a
/// temporary local store, never the real one: every sample record is saved, read back and compared, then edits,
/// deletes, duplicate merging, folder import and images are exercised.
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-selfTest") else { return }
        let failures = run()
        print(failures.isEmpty ? "SELFTEST PASSED" : "SELFTEST FAILED\n" + failures.map { "- " + $0 }.joined(separator: "\n"))
        exit(failures.isEmpty ? 0 : 1)
    }

    static func run() -> [String] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "myself-selftest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        var failures: [String] = []
        func check(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { failures.append(what()) } }

        let storeURL = dir.appending(path: "Test.store")
        let store = CloudStore(testStoreAt: storeURL)

        let labels = SampleData.labels + SampleData.productLabels
        let categories = SampleData.noteCategories + [SampleData.philosophyCategory]
        let bookCategories = SampleData.bookCategories
        let books = SampleData.books()
        let notes = SampleData.notes()
        var todos = SampleData.todos()
        let office = SampleData.office()
        var university = SampleData.university()
        let (products, cards) = SampleData.products()
        var study = SampleData.jobStudy()
        if !study.isEmpty, !study[0].topics.isEmpty, notes.count > 1 { study[0].topics[0].noteIDs = [notes[0].id, notes[1].id] }
        let uniNotes = UniversityNotes(text: "Midterm on chapter 4", updatedAt: .now)

        store.batch {
            labels.forEach { store.save($0) }
            categories.forEach { store.save($0) }
            bookCategories.forEach { store.save($0) }
            books.forEach { store.save($0) }
            products.forEach { store.save($0) }
            notes.forEach { store.save($0) }
            todos.forEach { store.save($0) }
            office.forEach { store.save($0) }
            university.classes.forEach { store.save($0) }
            university.syllabus.forEach { store.save($0) }
            university.assignments.forEach { store.save($0) }
            university.exams.forEach { store.save($0) }
            store.save(uniNotes)
            cards.forEach { store.save($0) }
            study.forEach { store.save($0) }
        }

        func roundTrip<T: CloudBacked & Equatable>(_ saved: [T], _ name: String, _ normalize: @escaping (T) -> T = { $0 }) {
            var loaded: [T] = []
            store.scan { loaded = store.load(T.self, keeping: []) }
            let a = Dictionary(saved.map { ($0.id, normalize($0)) }, uniquingKeysWith: { x, _ in x })
            let b = Dictionary(loaded.map { ($0.id, normalize($0)) }, uniquingKeysWith: { x, _ in x })
            check(loaded.count == b.count, "\(name): duplicate IDs after load")
            check(a.count == b.count, "\(name): \(a.count) saved, \(b.count) loaded")
            for (id, record) in a where b[id] != record {
                failures.append("\(name) \(id) differs\n    saved:  \(record)\n    loaded: \(b[id].map { "\($0)" } ?? "missing")")
            }
        }
        let sortLabels: (Todo) -> Todo = { var t = $0; t.labelIDs.sort(); return t }
        let sortCardLabels: (KanbanCard) -> KanbanCard = { var c = $0; c.labelIDs.sort(); return c }
        let sortTopicNotes: (StudySubject) -> StudySubject = { var s = $0; for i in s.topics.indices { s.topics[i].noteIDs.sort() }; return s }

        roundTrip(labels, "labels")
        roundTrip(categories, "note categories")
        roundTrip(products, "products")
        roundTrip(notes, "notes")
        roundTrip(bookCategories, "book categories")
        roundTrip(books, "books")
        roundTrip(todos, "todos", sortLabels)
        roundTrip(office, "office tasks")
        roundTrip(university.classes, "classes")
        roundTrip(university.syllabus, "syllabus")
        roundTrip(university.assignments, "assignments")
        roundTrip(university.exams, "exams")
        roundTrip([uniNotes], "university notes")
        roundTrip(cards, "cards", sortCardLabels)
        roundTrip(study, "job study", sortTopicNotes)

        // Note links and reading notes.
        check(NoteMarkdown.parse("a [[Plato|np_pl]] b") == [.text("a ", [], link: nil, note: nil), .text("Plato", [], link: nil, note: "np_pl"), .text(" b", [], link: nil, note: nil)],
              "links: parse gave \(NoteMarkdown.parse("a [[Plato|np_pl]] b"))")
        check(NoteMarkdown.parse("[[**Bold**|x1]]") == [.text("Bold", [.bold], link: nil, note: "x1")], "links: markdown in a label")
        for text in ["[[", "[[no id]]", "[[|x]]", "[[a|]]", "[[a|b]", "[x](https://a.b)"] {
            check(NoteMarkdown.linkIDs(text).isEmpty, "links: \(text) isn't a link")
        }
        check(NoteMarkdown.linkIDs("`[[a|b]]` [[c|d]]") == ["d"], "links: one in inline code counted")
        check(NoteText.plain("see [[Plato|np_pl]]") == "see Plato", "links: plain text kept the ID")
        check(NoteTable.cells("| [[a|b]] | c |") == ["[[a|b]]", "c"], "links: the pipe split a table cell")
        check(notes.first { $0.id == "bn2" }?.linkIDs == ["np_ar", "np_pl"], "links: wrong IDs for bn2")
        let withLinks = Note(categoryID: "nc1", blocks: [NoteBlock(.p, "[[A|one]] [[A again|one]]"), NoteBlock(.code, "[[B|two]]")])
        check(withLinks.linkIDs == ["one"], "links: got \(withLinks.linkIDs)")
        check(!withLinks.searchText.contains("one") && withLinks.searchText.contains("a again"), "links: search text is \(withLinks.searchText)")
        check(notes.first { $0.id == "bn1" }.map { $0.bookID == "bk1" && $0.categoryID.isEmpty && $0.location == "pp. 1–6" } == true, "books: reading note fields")
        if var book = books.first {
            book.title = "Renamed"
            book.status = .done
            book.categoryID = nil
            book.cover = "cover.jpg"
            book.updatedAt = .now
            store.save(book)
            roundTrip([book] + books.dropFirst(), "books after edit")
            store.save(books[0])
        }
        let cover = NoteImages.bookCover(from: Self.tinyPNG)
        check(cover?.starts(with: [0xFF, 0xD8]) == true, "books: cover isn't a JPEG")
        check(NoteImages.bookCover(from: Data([1, 2, 3])) == nil, "books: a non-image made a cover")

        // Edits and deletes.
        if todos.count > 1 {
            todos[0].title = "Edited title"
            todos[0].labelIDs = [labels[0].id]
            todos[0].updatedAt = .now
            store.save(todos[0])
            store.delete(Todo.self, id: todos[1].id)
            todos.remove(at: 1)
            roundTrip(todos, "todos after edit/delete", sortLabels)
        }
        if var subject = university.syllabus.first, subject.topics.count > 2 {
            subject.topics.removeFirst()
            subject.topics.reverse()
            subject.topics.append(SyllabusTopic(name: "New topic"))
            subject.updatedAt = .now
            store.save(subject)
            university.syllabus[0] = subject
            roundTrip(university.syllabus, "syllabus after reorder")
        }

        // Two copies of one record (two devices seeding the same default label): the newest wins, and records
        // pointing at the other copy move to it.
        let other = CloudStore(testStoreAt: storeURL)
        var twin = TaskLabel(id: "dup-label", name: "Old copy", hex: 0xFF0000, updatedAt: Date(timeIntervalSinceNow: -60))
        other.scan { _ = other.load(TaskLabel.self, keeping: []) }  // index built before the first copy exists
        store.save(twin)
        let linked = Todo(title: "Linked to the old copy", labelIDs: ["dup-label"])
        store.save(linked)
        twin.name = "New copy"
        twin.updatedAt = .now
        other.save(twin)
        var merged: [TaskLabel] = []
        var linkedAfter: Todo?
        store.scan {
            merged = store.load(TaskLabel.self, keeping: []).filter { $0.id == "dup-label" }
            linkedAfter = store.load(Todo.self, keeping: []).first { $0.id == linked.id }
        }
        check(merged.count == 1 && merged.first?.name == "New copy", "duplicate merge: got \(merged.map(\.name))")
        check(linkedAfter?.labelIDs == ["dup-label"], "duplicate merge: todo lost its label (\(linkedAfter?.labelIDs ?? []))")

        // Folder import: a newer file replaces the record, an older one doesn't, a new one is added.
        let folder = dir.appending(path: "folder", directoryHint: .isDirectory)
        try? fm.createDirectory(at: folder.appending(path: "office"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: folder.appending(path: "noteimages"), withIntermediateDirectories: true)
        var newer = office[0]
        newer.title = "From the folder"
        newer.updatedAt = .now.addingTimeInterval(60)
        var older = office[1]
        older.title = "Stale"
        older.updatedAt = .distantPast
        let added = OfficeTask(title: "Only in the folder")
        for task in [newer, older, added] {
            try? JSONEncoder().encode(task).write(to: folder.appending(path: "office/\(task.id).json"))
        }
        try? Data([1, 2, 3]).write(to: folder.appending(path: "noteimages/pic.png"))
        let result = FolderImport.run(from: folder, into: store)
        var imported: [OfficeTask] = []
        store.scan { imported = store.load(OfficeTask.self, keeping: []) }
        check(result.imported == 4, "folder import: counted \(result.imported), expected 4")
        check(imported.first { $0.id == newer.id }?.title == "From the folder", "folder import: newer file didn't replace the record")
        check(imported.first { $0.id == older.id }?.title == office[1].title, "folder import: older file replaced the record")
        check(imported.contains { $0.id == added.id }, "folder import: new record missing")
        check(imported.count == office.count + 1, "folder import: \(imported.count) office tasks, expected \(office.count + 1)")
        FolderImport.run(from: folder, into: store)
        store.scan { imported = store.load(OfficeTask.self, keeping: []) }
        check(imported.count == office.count + 1, "folder import twice: \(imported.count) office tasks")

        // Images.
        check(store.imageData("pic.png") == Data([1, 2, 3]), "image: imported data differs")
        if let name = store.saveImage(Data([9, 8, 7]), ext: "jpg") {
            store.scan {}
            if case .ready(let url) = store.imageState(name) {
                check((try? Data(contentsOf: url)) == Data([9, 8, 7]), "image: cached file differs")
            } else {
                failures.append("image: not ready after saving")
            }
            store.deleteImage(name)
            store.scan {}
            if case .missing = store.imageState(name) {} else { failures.append("image: still there after delete") }
        } else {
            failures.append("image: save failed")
        }

        return failures
    }

    /// A 1×1 PNG.
    private static let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAEBgIApD5fRAAAAABJRU5ErkJggg==")!
}
#endif
