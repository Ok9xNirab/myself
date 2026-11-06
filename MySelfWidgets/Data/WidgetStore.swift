import Foundation
import os
import SwiftData

/// The widget extension's access to the app's SwiftData store in the App Group container. It opens the store without
/// CloudKit: only the app mirrors it to iCloud, and picks up what the extension writes (it's told through
/// `SharedStore.postDidChange`, and CloudKit exports the change from the store's history).
enum WidgetStore {
    enum Failure: Error { case noStore }

    private static let opened = OSAllocatedUnfairLock<ModelContainer?>(initialState: nil)

    /// The store, opened once per extension process. It's never created or migrated here: until the app has opened it
    /// with this schema (or in unsigned builds) there's nothing to show, so this stays nil and is tried again next time.
    private static var container: ModelContainer? {
        opened.withLock { opened in
            guard SharedStore.isStoreCurrent else { return nil }
            if let opened { return opened }
            guard SharedStore.hasGroupContainer, FileManager.default.fileExists(atPath: SharedStore.url.path) else { return nil }
            let configuration = ModelConfiguration("MySelf", schema: cloudSchema, url: SharedStore.url, cloudKitDatabase: .none)
            opened = try? ModelContainer(for: cloudSchema, configurations: configuration)
            return opened
        }
    }

    /// Everything the widgets show, or nil when there's no store to read.
    static func load() -> WidgetSnapshot? {
        guard let container else { return nil }
        let context = ModelContext(container)
        var snapshot = WidgetSnapshot()
        snapshot.todos = newest(TodoModel.self, in: context).map(Todo.init).sorted { $0.createdAt < $1.createdAt }
        snapshot.office = newest(OfficeTaskModel.self, in: context).map(OfficeTask.init).sorted { $0.createdAt < $1.createdAt }
        snapshot.university.classes = newest(UniClassModel.self, in: context).map(UniClass.init).sorted { $0.createdAt < $1.createdAt }
        snapshot.university.syllabus = newest(SyllabusSubjectModel.self, in: context).map(SyllabusSubject.init).sorted { $0.createdAt < $1.createdAt }
        snapshot.university.assignments = newest(AssignmentModel.self, in: context).map(Assignment.init).sorted { $0.createdAt < $1.createdAt }
        snapshot.university.exams = newest(ExamModel.self, in: context).map(Exam.init).sorted { $0.date < $1.date }
        snapshot.jobStudy = newest(StudySubjectModel.self, in: context).map(StudySubject.init).sorted { $0.createdAt < $1.createdAt }
        snapshot.disabled = SharedStore.disabledFeatures
        return snapshot
    }

    /// One model per record ID: the copy the app's merge would keep (newest `updatedAt`, then `copyID`).
    private static func newest<M: CloudRecord>(_ type: M.Type, in context: ModelContext) -> [M] {
        var byID: [String: M] = [:]
        for model in (try? context.fetch(FetchDescriptor<M>())) ?? [] {
            if let kept = byID[model.recordID], (kept.updatedAt, kept.copyID) >= (model.updatedAt, model.copyID) { continue }
            byID[model.recordID] = model
        }
        return Array(byID.values)
    }

    // MARK: Writing

    /// Runs `body` on a fresh context, saves, and tells the app.
    private static func write(_ body: (ModelContext) throws -> Void) throws {
        guard let container else { throw Failure.noStore }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try body(context)
        if context.hasChanges { try context.save() }
        SharedStore.postDidChange()
    }

    /// Every stored copy of a record, newest first. Edits go to all of them, so whichever the app's merge keeps has them.
    private static func copies<M: CloudRecord>(_ type: M.Type, id: String, in context: ModelContext) throws -> [M] {
        try context.fetch(FetchDescriptor<M>()).filter { $0.recordID == id }
            .sorted { ($0.updatedAt, $0.copyID) > ($1.updatedAt, $1.copyID) }
    }

    /// Ticks (or un-ticks) a todo, office task or assignment, as the Dashboard's check circles do.
    static func toggle(_ kind: FocusItem.Kind, id: String) throws {
        try write { context in
            let now = Date.now
            switch kind {
            case .todo:
                let models = try copies(TodoModel.self, id: id, in: context)
                guard let done = models.first.map({ !$0.done }) else { return }
                for m in models { m.done = done; m.completedAt = done ? now : nil; m.updatedAt = now }
            case .office:
                let models = try copies(OfficeTaskModel.self, id: id, in: context)
                guard let done = models.first.map({ !$0.done }) else { return }
                for m in models { m.done = done; m.completedAt = done ? now : nil; m.updatedAt = now }
            case .assignment:
                let models = try copies(AssignmentModel.self, id: id, in: context)
                guard let done = models.first.map({ !$0.done }) else { return }
                for m in models { m.done = done; m.updatedAt = now }
            }
        }
    }

    /// Logs one more revision of a Job Study topic, dated today: the app's + stepper (`AppStore.adjustRevisions`).
    static func addRevision(subject: String, topic: String) throws {
        try write { context in
            let now = Date.now
            let today = Day.calendar.startOfDay(for: now)
            for parent in try copies(StudySubjectModel.self, id: subject, in: context) {
                for t in parent.topics ?? [] where t.recordID == topic {
                    t.revisions += 1
                    if Day.between(now, t.lastRevised) != 0 { t.previousRevised = t.lastRevised }
                    t.lastRevised = today
                }
                parent.updatedAt = now
            }
        }
    }
}
