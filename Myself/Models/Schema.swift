import Foundation
import SwiftData

// SwiftData models, mirrored to the user's private CloudKit database by `CloudStore`.
//
// CloudKit rules: every attribute has a default or is optional, every relationship is optional and has an inverse,
// there are no unique constraints and no `.deny` delete rules. Once the schema is deployed to production, fields can
// only be added: never rename, retype or remove one.
//
// The app still works with the structs in `Models.swift` / `Notes.swift`; each struct converts from its model
// (`init(_ model:)`) and writes itself into one (`apply(to:in:)`), so screens, undo and the editor are unchanged.
// `recordID` is the struct's `id`. It isn't unique in the store: `CloudStore` merges duplicates, keeping the newest.

/// A model that backs one of the app's synced structs.
protocol CloudRecord: PersistentModel {
    var recordID: String { get set }
    /// Random per stored copy, set on insert. Breaks `updatedAt` ties when duplicates are merged, so every device
    /// keeps the same copy.
    var copyID: String { get set }
    var updatedAt: Date { get set }
    init()
    /// Takes over another copy's relationships before that duplicate is deleted.
    func absorb(_ duplicate: Self)
}

extension CloudRecord {
    func absorb(_ duplicate: Self) {}
}

/// A model owned by a parent record (syllabus and Job Study topics), kept in step by `CloudStore.syncChildren`.
protocol ChildRecord: PersistentModel {
    var recordID: String { get set }
    init()
}

/// A synced struct and the model that stores it.
protocol CloudBacked: SyncRecord {
    associatedtype Model: CloudRecord
    init(_ model: Model)
    func apply(to model: Model, in store: CloudStore)
}

/// Every model in the store, for `ModelContainer`.
let cloudSchema = Schema([
    LabelModel.self, TodoModel.self, OfficeTaskModel.self,
    NoteCategoryModel.self, NoteModel.self, NoteImageModel.self,
    UniClassModel.self, SyllabusSubjectModel.self, SyllabusTopicModel.self, AssignmentModel.self, ExamModel.self,
    UniversityNotesModel.self,
    ProductModel.self, KanbanCardModel.self,
    StudySubjectModel.self, StudyTopicModel.self,
])

// MARK: Labels, todos, office

@Model final class LabelModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var name: String = ""
    var hex: Int = 0
    var sortOrder: Int = 0
    /// nil for TODO labels, "product" for Product Dev ones.
    var scope: String?
    var updatedAt: Date = Date.distantPast
    @Relationship(inverse: \TodoModel.labels) var todos: [TodoModel]? = []
    @Relationship(inverse: \KanbanCardModel.labels) var cards: [KanbanCardModel]? = []
    init() {}

    func absorb(_ duplicate: LabelModel) {
        for todo in duplicate.todos ?? [] where !(todo.labels ?? []).contains(self) { todo.labels?.append(self) }
        for card in duplicate.cards ?? [] where !(card.labels ?? []).contains(self) { card.labels?.append(self) }
    }
}

@Model final class TodoModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var title: String = ""
    var desc: String = ""
    var priority: String = Priority.medium.rawValue
    var due: Date?
    var done: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var labels: [LabelModel]? = []
    init() {}
}

@Model final class OfficeTaskModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var title: String = ""
    var desc: String = ""
    var refURL: String?
    var due: Date?
    var done: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    init() {}
}

// MARK: Notes

@Model final class NoteCategoryModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var name: String = ""
    var hex: Int = 0
    var sortOrder: Int = 0
    var updatedAt: Date = Date.distantPast
    @Relationship(inverse: \NoteModel.category) var notes: [NoteModel]? = []
    init() {}

    func absorb(_ duplicate: NoteCategoryModel) {
        for note in duplicate.notes ?? [] { note.category = self }
    }
}

@Model final class NoteModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var title: String = ""
    var pinned: Bool = false
    var readerMode: Bool?
    /// The note's `[NoteBlock]` as JSON, so the block format can grow without schema changes. Large notes are kept
    /// outside the database (and sync as a CloudKit asset).
    @Attribute(.externalStorage) var blocksData: Data = Data()
    var createdAt: Date = Date.now
    var editedAt: Date = Date.now
    var updatedAt: Date = Date.now
    var category: NoteCategoryModel?
    var topics: [StudyTopicModel]? = []
    init() {}

    func absorb(_ duplicate: NoteModel) {
        for topic in duplicate.topics ?? [] where !(topic.notes ?? []).contains(self) { topic.notes?.append(self) }
    }
}

/// An image in a note. `recordID` is the file name note blocks refer to (`NoteBlock.image`).
@Model final class NoteImageModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    @Attribute(.externalStorage) var data: Data = Data()
    var updatedAt: Date = Date.now
    init() {}
}

// MARK: University

@Model final class UniClassModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var subject: String = ""
    var code: String = ""
    /// `Weekday` raw values.
    var days: [Int] = []
    var hour: Int = 9
    var minute: Int = 0
    var room: String = ""
    var hex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    init() {}
}

@Model final class SyllabusSubjectModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var subject: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \SyllabusTopicModel.parent) var topics: [SyllabusTopicModel]? = []
    init() {}
}

@Model final class SyllabusTopicModel: ChildRecord {
    var recordID: String = ""
    var name: String = ""
    var done: Bool = false
    /// Position in the subject; CloudKit relationships have no order.
    var order: Double = 0
    var parent: SyllabusSubjectModel?
    init() {}
}

@Model final class AssignmentModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var title: String = ""
    /// A class subject, by name.
    var subject: String = ""
    var due: Date?
    var done: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    init() {}
}

@Model final class ExamModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var subject: String = ""
    var kind: String = ExamKind.midterm.rawValue
    var date: Date = Date.now
    var prep: Int = 0
    var updatedAt: Date = Date.now
    init() {}
}

/// The University page's notes; there's one, with `recordID` "notes".
@Model final class UniversityNotesModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var text: String = ""
    var updatedAt: Date = Date.distantPast
    init() {}
}

// MARK: Product Dev

@Model final class ProductModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var name: String = ""
    var tagline: String = ""
    var hex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    @Relationship(inverse: \KanbanCardModel.product) var cards: [KanbanCardModel]? = []
    init() {}

    func absorb(_ duplicate: ProductModel) {
        for card in duplicate.cards ?? [] { card.product = self }
    }
}

@Model final class KanbanCardModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var status: String = KanbanStatus.backlog.rawValue
    var title: String = ""
    var desc: String = ""
    var priority: String = Priority.medium.rawValue
    var due: Date?
    var order: Double = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var product: ProductModel?
    var labels: [LabelModel]? = []
    init() {}
}

// MARK: Job Study

@Model final class StudySubjectModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var subject: String = ""
    var hex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \StudyTopicModel.parent) var topics: [StudyTopicModel]? = []
    init() {}
}

@Model final class StudyTopicModel: ChildRecord {
    var recordID: String = ""
    var name: String = ""
    var revisions: Int = 0
    var lastRevised: Date?
    var previousRevised: Date?
    var order: Double = 0
    var parent: StudySubjectModel?
    @Relationship(inverse: \NoteModel.topics) var notes: [NoteModel]? = []
    init() {}
}

// MARK: Struct ⇄ model

private extension UInt32 {
    init(stored: Int) { self.init(truncatingIfNeeded: stored) }
}

extension TaskLabel: CloudBacked {
    init(_ m: LabelModel) {
        self.init(id: m.recordID, name: m.name, hex: UInt32(stored: m.hex), sortOrder: m.sortOrder, updatedAt: m.updatedAt,
                  scope: m.scope.flatMap(Scope.init(rawValue:)))
    }

    func apply(to m: LabelModel, in store: CloudStore) {
        m.name = name
        m.hex = Int(hex)
        m.sortOrder = sortOrder
        m.scope = scope?.rawValue
    }
}

/// Label IDs in label order (relationships have none).
private func sortedLabelIDs(_ labels: [LabelModel]?) -> [ID] {
    (labels ?? []).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map(\.recordID)
}

extension Todo: CloudBacked {
    init(_ m: TodoModel) {
        self.init(id: m.recordID, title: m.title, desc: m.desc, labelIDs: sortedLabelIDs(m.labels),
                  priority: Priority(rawValue: m.priority) ?? .medium, due: m.due, done: m.done, completedAt: m.completedAt,
                  createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: TodoModel, in store: CloudStore) {
        m.title = title
        m.desc = desc
        m.labels = labelIDs.compactMap { store.model(LabelModel.self, id: $0) }
        m.priority = priority.rawValue
        m.due = due
        m.done = done
        m.completedAt = completedAt
        m.createdAt = createdAt
    }
}

extension OfficeTask: CloudBacked {
    init(_ m: OfficeTaskModel) {
        self.init(id: m.recordID, title: m.title, desc: m.desc, refURL: m.refURL.flatMap(URL.init(string:)), due: m.due,
                  done: m.done, completedAt: m.completedAt, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: OfficeTaskModel, in store: CloudStore) {
        m.title = title
        m.desc = desc
        m.refURL = refURL?.absoluteString
        m.due = due
        m.done = done
        m.completedAt = completedAt
        m.createdAt = createdAt
    }
}

extension NoteCategory: CloudBacked {
    init(_ m: NoteCategoryModel) {
        self.init(id: m.recordID, name: m.name, hex: UInt32(stored: m.hex), sortOrder: m.sortOrder, updatedAt: m.updatedAt)
    }

    func apply(to m: NoteCategoryModel, in store: CloudStore) {
        m.name = name
        m.hex = Int(hex)
        m.sortOrder = sortOrder
    }
}

extension Note: CloudBacked {
    /// Decoded blocks by note, reused while the note's `updatedAt` hasn't changed (every reload maps every note).
    private static var blockCache: [ID: (updatedAt: Date, blocks: [NoteBlock])] = [:]

    init(_ m: NoteModel) {
        let blocks: [NoteBlock]
        if let hit = Self.blockCache[m.recordID], hit.updatedAt == m.updatedAt {
            blocks = hit.blocks
        } else {
            let decoded = (try? JSONDecoder().decode([NoteBlock].self, from: m.blocksData)) ?? []
            blocks = decoded.isEmpty ? [NoteBlock()] : decoded
            Self.blockCache[m.recordID] = (m.updatedAt, blocks)
        }
        self.init(id: m.recordID, categoryID: m.category?.recordID ?? "", title: m.title, pinned: m.pinned, readerMode: m.readerMode,
                  blocks: blocks, createdAt: m.createdAt, editedAt: m.editedAt, updatedAt: m.updatedAt)
    }

    func apply(to m: NoteModel, in store: CloudStore) {
        m.title = title
        m.pinned = pinned
        m.readerMode = readerMode
        m.blocksData = (try? JSONEncoder().encode(blocks)) ?? Data()
        m.createdAt = createdAt
        m.editedAt = editedAt
        if m.category?.recordID != categoryID { m.category = store.model(NoteCategoryModel.self, id: categoryID) }
        Self.blockCache[id] = (updatedAt, blocks)
    }
}

extension UniClass: CloudBacked {
    init(_ m: UniClassModel) {
        self.init(id: m.recordID, subject: m.subject, code: m.code, days: m.days.compactMap(Weekday.init(rawValue:)),
                  time: ClockTime(hour: m.hour, minute: m.minute), room: m.room, hex: UInt32(stored: m.hex),
                  createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: UniClassModel, in store: CloudStore) {
        m.subject = subject
        m.code = code
        m.days = days.map(\.rawValue)
        m.hour = time.hour
        m.minute = time.minute
        m.room = room
        m.hex = Int(hex)
        m.createdAt = createdAt
    }
}

extension SyllabusSubject: CloudBacked {
    init(_ m: SyllabusSubjectModel) {
        let topics = (m.topics ?? []).sorted { $0.order < $1.order }.map { SyllabusTopic(id: $0.recordID, name: $0.name, done: $0.done) }
        self.init(id: m.recordID, subject: m.subject, topics: topics, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: SyllabusSubjectModel, in store: CloudStore) {
        m.subject = subject
        m.createdAt = createdAt
        store.syncChildren(of: m, \.topics, to: topics, id: \.id, make: { SyllabusTopicModel() }) { child, topic, order in
            child.name = topic.name
            child.done = topic.done
            child.order = order
            child.parent = m
        }
    }
}

extension Assignment: CloudBacked {
    init(_ m: AssignmentModel) {
        self.init(id: m.recordID, title: m.title, subject: m.subject, due: m.due, done: m.done, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: AssignmentModel, in store: CloudStore) {
        m.title = title
        m.subject = subject
        m.due = due
        m.done = done
        m.createdAt = createdAt
    }
}

extension Exam: CloudBacked {
    init(_ m: ExamModel) {
        self.init(id: m.recordID, subject: m.subject, kind: ExamKind(rawValue: m.kind) ?? .midterm, date: m.date, prep: m.prep, updatedAt: m.updatedAt)
    }

    func apply(to m: ExamModel, in store: CloudStore) {
        m.subject = subject
        m.kind = kind.rawValue
        m.date = date
        m.prep = prep
    }
}

extension UniversityNotes: CloudBacked {
    init(_ m: UniversityNotesModel) {
        self.init(id: m.recordID, text: m.text, updatedAt: m.updatedAt)
    }

    func apply(to m: UniversityNotesModel, in store: CloudStore) {
        m.text = text
    }
}

extension Product: CloudBacked {
    init(_ m: ProductModel) {
        self.init(id: m.recordID, name: m.name, tagline: m.tagline, hex: UInt32(stored: m.hex), createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: ProductModel, in store: CloudStore) {
        m.name = name
        m.tagline = tagline
        m.hex = Int(hex)
        m.createdAt = createdAt
    }
}

extension KanbanCard: CloudBacked {
    init(_ m: KanbanCardModel) {
        self.init(id: m.recordID, productID: m.product?.recordID ?? "", status: KanbanStatus(rawValue: m.status) ?? .backlog,
                  title: m.title, desc: m.desc, labelIDs: sortedLabelIDs(m.labels), priority: Priority(rawValue: m.priority) ?? .medium,
                  due: m.due, order: m.order, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: KanbanCardModel, in store: CloudStore) {
        if m.product?.recordID != productID { m.product = store.model(ProductModel.self, id: productID) }
        m.status = status.rawValue
        m.title = title
        m.desc = desc
        m.labels = labelIDs.compactMap { store.model(LabelModel.self, id: $0) }
        m.priority = priority.rawValue
        m.due = due
        m.order = order
        m.createdAt = createdAt
    }
}

extension StudySubject: CloudBacked {
    init(_ m: StudySubjectModel) {
        let topics = (m.topics ?? []).sorted { $0.order < $1.order }.map { t in
            StudyTopic(id: t.recordID, name: t.name, revisions: t.revisions, lastRevised: t.lastRevised, previousRevised: t.previousRevised,
                       noteIDs: (t.notes ?? []).sorted { $0.createdAt < $1.createdAt }.map(\.recordID))
        }
        self.init(id: m.recordID, subject: m.subject, hex: UInt32(stored: m.hex), topics: topics, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func apply(to m: StudySubjectModel, in store: CloudStore) {
        m.subject = subject
        m.hex = Int(hex)
        m.createdAt = createdAt
        store.syncChildren(of: m, \.topics, to: topics, id: \.id, make: { StudyTopicModel() }) { child, topic, order in
            child.name = topic.name
            child.revisions = topic.revisions
            child.lastRevised = topic.lastRevised
            child.previousRevised = topic.previousRevised
            child.order = order
            child.parent = m
            let linked = Set((child.notes ?? []).map(\.recordID))
            if linked != Set(topic.noteIDs) {
                child.notes = topic.noteIDs.compactMap { store.model(NoteModel.self, id: $0) }
            }
        }
    }
}
