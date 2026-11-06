import Foundation
import SwiftData

// SwiftData models, mirrored to the user's private CloudKit database by `CloudStore`.
//
// CloudKit rules: every attribute has a default or is optional, every relationship is optional and has an inverse,
// there are no unique constraints and no `.deny` delete rules. Once the schema is deployed to production, fields can
// only be added: never rename, retype or remove one.
//
// Shared by the app and the widget extension, so both open the same schema. The app works with the structs in
// `Models.swift` / `Notes.swift`; each struct converts from its model (`init(_ model:)`, here) and writes itself into
// one (`apply(to:in:)`, in the app's `Models/Schema.swift`), so screens, undo and the editor are unchanged.
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

/// Every model in the store, for `ModelContainer`.
let cloudSchema = Schema([
    LabelModel.self, TodoModel.self, OfficeTaskModel.self,
    NoteCategoryModel.self, NoteModel.self, NoteImageModel.self,
    UniClassModel.self, SyllabusSubjectModel.self, SyllabusTopicModel.self, AssignmentModel.self, ExamModel.self,
    UniversityNotesModel.self,
    ProductModel.self, KanbanCardModel.self,
    StudySubjectModel.self, StudyTopicModel.self,
    BookCategoryModel.self, BookModel.self,
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
    /// The book a reading note belongs to, by record ID. A plain field rather than a relationship: CloudKit can deliver
    /// a note before its book, and without this it would briefly show up among the ordinary notes.
    var bookID: String?
    /// Where in the book a reading note is ("pp. 35–43").
    var location: String?
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

// MARK: Book Notes

@Model final class BookCategoryModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var name: String = ""
    var hex: Int = 0
    var sortOrder: Int = 0
    var updatedAt: Date = Date.now
    init() {}
}

@Model final class BookModel: CloudRecord {
    var recordID: String = ""
    var copyID: String = ""
    var title: String = ""
    var author: String = ""
    var hex: Int = 0
    /// A `BookStatus` raw value.
    var status: String = "reading"
    /// A book category's record ID; nil for uncategorized.
    var categoryID: String?
    var totalPages: Int = 0
    var currentPage: Int = 0
    /// File name of the uploaded cover in `NoteImageModel`.
    var cover: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    init() {}
}

// MARK: Model → struct

extension UInt32 {
    init(stored: Int) { self.init(truncatingIfNeeded: stored) }
}

/// Label IDs in label order (relationships have none).
func sortedLabelIDs(_ labels: [LabelModel]?) -> [ID] {
    (labels ?? []).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map(\.recordID)
}

extension TaskLabel {
    init(_ m: LabelModel) {
        self.init(id: m.recordID, name: m.name, hex: UInt32(stored: m.hex), sortOrder: m.sortOrder, updatedAt: m.updatedAt,
                  scope: m.scope.flatMap(Scope.init(rawValue:)))
    }
}

extension Todo {
    init(_ m: TodoModel) {
        self.init(id: m.recordID, title: m.title, desc: m.desc, labelIDs: sortedLabelIDs(m.labels),
                  priority: Priority(rawValue: m.priority) ?? .medium, due: m.due, done: m.done, completedAt: m.completedAt,
                  createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension OfficeTask {
    init(_ m: OfficeTaskModel) {
        self.init(id: m.recordID, title: m.title, desc: m.desc, refURL: m.refURL.flatMap(URL.init(string:)), due: m.due,
                  done: m.done, completedAt: m.completedAt, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension UniClass {
    init(_ m: UniClassModel) {
        self.init(id: m.recordID, subject: m.subject, code: m.code, days: m.days.compactMap(Weekday.init(rawValue:)),
                  time: ClockTime(hour: m.hour, minute: m.minute), room: m.room, hex: UInt32(stored: m.hex),
                  createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension SyllabusSubject {
    init(_ m: SyllabusSubjectModel) {
        let topics = (m.topics ?? []).sorted { $0.order < $1.order }.map { SyllabusTopic(id: $0.recordID, name: $0.name, done: $0.done) }
        self.init(id: m.recordID, subject: m.subject, topics: topics, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension Assignment {
    init(_ m: AssignmentModel) {
        self.init(id: m.recordID, title: m.title, subject: m.subject, due: m.due, done: m.done, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension Exam {
    init(_ m: ExamModel) {
        self.init(id: m.recordID, subject: m.subject, kind: ExamKind(rawValue: m.kind) ?? .midterm, date: m.date, prep: m.prep, updatedAt: m.updatedAt)
    }
}

extension UniversityNotes {
    init(_ m: UniversityNotesModel) {
        self.init(id: m.recordID, text: m.text, updatedAt: m.updatedAt)
    }
}

extension Product {
    init(_ m: ProductModel) {
        self.init(id: m.recordID, name: m.name, tagline: m.tagline, hex: UInt32(stored: m.hex), createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension KanbanCard {
    init(_ m: KanbanCardModel) {
        self.init(id: m.recordID, productID: m.product?.recordID ?? "", status: KanbanStatus(rawValue: m.status) ?? .backlog,
                  title: m.title, desc: m.desc, labelIDs: sortedLabelIDs(m.labels), priority: Priority(rawValue: m.priority) ?? .medium,
                  due: m.due, order: m.order, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}

extension StudySubject {
    init(_ m: StudySubjectModel) {
        let topics = (m.topics ?? []).sorted { $0.order < $1.order }.map { t in
            StudyTopic(id: t.recordID, name: t.name, revisions: t.revisions, lastRevised: t.lastRevised, previousRevised: t.previousRevised,
                       noteIDs: (t.notes ?? []).sorted { $0.createdAt < $1.createdAt }.map(\.recordID))
        }
        self.init(id: m.recordID, subject: m.subject, hex: UInt32(stored: m.hex), topics: topics, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }
}
