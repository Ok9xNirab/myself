import AppIntents
import WidgetKit

/// Today's focus check circles: completes (or reopens) a todo, office task or assignment in the shared store.
struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false

    @Parameter(title: "Kind") var kind: String
    @Parameter(title: "Task") var id: String

    init() {}

    init(_ item: FocusItem) {
        kind = item.kind.rawValue
        id = item.id
    }

    func perform() async throws -> some IntentResult {
        guard let kind = FocusItem.Kind(rawValue: kind) else { return .result() }
        try WidgetStore.toggle(kind, id: id)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.office)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.week)
        return .result()
    }
}

/// Revise next's + buttons: one more revision of a Job Study topic, dated today.
struct IncrementRevisionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Revision"
    static let isDiscoverable = false

    @Parameter(title: "Subject") var subject: String
    @Parameter(title: "Topic") var topic: String

    init() {}

    init(subject: String, topic: String) {
        self.subject = subject
        self.topic = topic
    }

    func perform() async throws -> some IntentResult {
        try WidgetStore.addRevision(subject: subject, topic: topic)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.jobStudy)
        return .result()
    }
}

// MARK: Configuration

/// A Job Study subject, for picking Revise next's subject.
struct StudySubjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Job Study Subject"
    static let defaultQuery = StudySubjectQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct StudySubjectQuery: EntityQuery {
    func entities(for identifiers: [StudySubjectEntity.ID]) async throws -> [StudySubjectEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StudySubjectEntity] {
        (WidgetStore.load()?.jobStudy ?? []).map { StudySubjectEntity(id: $0.id, name: $0.subject) }
    }
}

struct ReviseConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Revise Next"
    static let description = IntentDescription("Choose the Job Study subject to revise. Leave it empty for the one with the most topics due.")

    @Parameter(title: "Subject") var subject: StudySubjectEntity?
}

/// A University syllabus subject, for picking the Syllabus widget's rows.
struct SyllabusSubjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Syllabus Subject"
    static let defaultQuery = SyllabusSubjectQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct SyllabusSubjectQuery: EntityQuery {
    func entities(for identifiers: [SyllabusSubjectEntity.ID]) async throws -> [SyllabusSubjectEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SyllabusSubjectEntity] {
        (WidgetStore.load()?.university.syllabus ?? []).map { SyllabusSubjectEntity(id: $0.id, name: $0.subject) }
    }
}

struct SyllabusConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Syllabus"
    static let description = IntentDescription("Choose up to three subjects. Leave it empty for the three furthest along.")

    @Parameter(title: "Subjects") var subjects: [SyllabusSubjectEntity]?
}
