import Foundation
import SwiftData

// How the app writes its structs into the SwiftData models in `Shared/SchemaModels.swift`. Reading them back
// (`init(_ model:)`) is shared with the widget extension and lives there, except for notes, which widgets don't read.

/// A synced struct and the model that stores it.
protocol CloudBacked: SyncRecord {
    associatedtype Model: CloudRecord
    init(_ model: Model)
    func apply(to model: Model, in store: CloudStore)
}

extension TaskLabel: CloudBacked {
    func apply(to m: LabelModel, in store: CloudStore) {
        m.name = name
        m.hex = Int(hex)
        m.sortOrder = sortOrder
        m.scope = scope?.rawValue
    }
}

extension Todo: CloudBacked {
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
    func apply(to m: AssignmentModel, in store: CloudStore) {
        m.title = title
        m.subject = subject
        m.due = due
        m.done = done
        m.createdAt = createdAt
    }
}

extension Exam: CloudBacked {
    func apply(to m: ExamModel, in store: CloudStore) {
        m.subject = subject
        m.kind = kind.rawValue
        m.date = date
        m.prep = prep
    }
}

extension UniversityNotes: CloudBacked {
    func apply(to m: UniversityNotesModel, in store: CloudStore) {
        m.text = text
    }
}

extension Product: CloudBacked {
    func apply(to m: ProductModel, in store: CloudStore) {
        m.name = name
        m.tagline = tagline
        m.hex = Int(hex)
        m.createdAt = createdAt
    }
}

extension KanbanCard: CloudBacked {
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
