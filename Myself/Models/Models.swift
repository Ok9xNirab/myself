import SwiftUI

typealias ID = String

func newID() -> ID { UUID().uuidString }

enum Priority: String, CaseIterable, Identifiable, Codable {
    case high, medium, low

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var rank: Int { Self.allCases.firstIndex(of: self)! }

    var color: Color {
        switch self {
        case .high: Palette.red
        case .medium: Palette.amber
        case .low: Palette.blue
        }
    }
}

/// Synced as `labels/<id>.json`.
struct TaskLabel: Identifiable, Hashable, Codable, SyncRecord {
    static let folder = "labels"

    let id: ID
    var name: String
    var hex: UInt32
    var sortOrder = 0
    var updatedAt = Date.distantPast
    var color: Color { Color(hex: hex) }
}

/// Synced as `todos/<id>.json`.
struct Todo: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "todos"

    var id = newID()
    var title: String
    var desc = ""
    var labelIDs: [ID] = []
    var priority: Priority = .medium
    var due: Date?
    var done = false
    var completedAt: Date?
    var createdAt = Date.now
    var updatedAt = Date.now
}

/// Synced as `office/<id>.json`. Office tasks are always high priority and carry a reference link.
struct OfficeTask: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "office"

    var id = newID()
    var title: String
    var desc = ""
    var refURL: URL?
    var due: Date?
    var done = false
    var completedAt: Date?
    var createdAt = Date.now
    var updatedAt = Date.now
}

// MARK: University

/// Synced as `classes/<id>.json`.
struct UniClass: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "classes"

    var id = newID()
    var subject: String
    var code: String
    var days: [Weekday]
    var time: ClockTime
    var room: String
    var hex: UInt32
    var createdAt = Date.now
    var updatedAt = Date.now
    var color: Color { Color(hex: hex) }
}

struct SyllabusTopic: Identifiable, Equatable, Codable {
    var id = newID()
    var name: String
    var done = false
}

/// Synced as `syllabus/<id>.json`, topics included.
struct SyllabusSubject: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "syllabus"

    var id = newID()
    var subject: String
    var topics: [SyllabusTopic]
    var createdAt = Date.now
    var updatedAt = Date.now

    var percent: Int {
        topics.isEmpty ? 0 : Int((100 * Double(topics.filter(\.done).count) / Double(topics.count)).rounded())
    }
}

/// Synced as `assignments/<id>.json`. Always high priority.
struct Assignment: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "assignments"

    var id = newID()
    var title: String
    var subject: String
    var due: Date?
    var done = false
    var createdAt = Date.now
    var updatedAt = Date.now
}

enum ExamKind: String, CaseIterable, Codable {
    case classTest = "Class Test", midterm = "Midterm", final = "Final"

    var color: Color {
        switch self {
        case .classTest: Palette.blue
        case .midterm: Palette.amber
        case .final: Palette.red
        }
    }
}

/// Synced as `exams/<id>.json`.
struct Exam: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "exams"

    var id = newID()
    var subject: String
    var kind: ExamKind
    var date: Date
    /// Preparation, 0–100.
    var prep: Int
    var updatedAt = Date.now
}

/// The University page's free-text notes, synced as the single file `university/notes.json`.
struct UniversityNotes: Equatable, Codable, SyncRecord {
    static let folder = "university"

    var id = "notes"
    var text = ""
    var updatedAt = Date.distantPast
}

struct University: Equatable {
    var classes: [UniClass] = []
    var syllabus: [SyllabusSubject] = []
    var assignments: [Assignment] = []
    var exams: [Exam] = []

    var syllabusPercent: Int {
        let all = syllabus.flatMap(\.topics)
        return Int((100 * Double(all.filter(\.done).count) / Double(max(1, all.count))).rounded())
    }

    /// Subject names from classes and syllabus, for the subject pickers.
    var subjects: [String] {
        var seen = Set<String>()
        return (classes.map(\.subject) + syllabus.map(\.subject)).filter { seen.insert($0).inserted }
    }
}

// MARK: Product dev (kanban)

struct KanbanCard: Identifiable {
    var id = newID()
    var title: String
    var desc = ""
    var labelIDs: [ID] = []
    var priority: Priority = .medium
    var due: Date?
}

struct KanbanColumn: Identifiable {
    var id = newID()
    var title: String
    var cards: [KanbanCard]
}

struct Product: Identifiable {
    var id = newID()
    var name: String
    var tagline: String
    var hex: UInt32
    var columns: [KanbanColumn]
    var color: Color { Color(hex: hex) }

    func column(titled title: String) -> KanbanColumn? {
        columns.first { $0.title.lowercased() == title.lowercased() }
    }
}

// MARK: Job study

struct StudyTopic: Identifiable {
    var id = newID()
    var name: String
    var revisions: Int
    var lastRevised: Date?
    /// Remembered so un-ticking today's revision can restore the previous date.
    var previousRevised: Date?
}

struct StudySubject: Identifiable {
    var id = newID()
    var subject: String
    var hex: UInt32
    var topics: [StudyTopic]
    var color: Color { Color(hex: hex) }

    var percent: Int {
        topics.isEmpty ? 0 : Int((100 * Double(topics.filter { $0.revisions > 0 }.count) / Double(topics.count)).rounded())
    }
}

// MARK: Workout

struct ProgramDay {
    var label: String
    /// `nil` means a rest day.
    var name: String?
    var sets: [String] = []
    var tip: String?

    static func rest(_ label: String) -> ProgramDay { ProgramDay(label: label) }
}

struct ProgramWeek {
    var title: String
    var sub: String
    var milestone: String?
    var days: [ProgramDay]
}

struct WorkoutProgram: Identifiable {
    var id = newID()
    var name: String
    var kind: String
    var desc: String
    var hex: UInt32
    var daysPerWeek: Int
    var sessionMin: Int
    var completedWeeks: Int
    var weeks: [ProgramWeek] = []
    /// Completed set indices keyed by "week_day".
    var chips: [String: Set<Int>] = [:]
    var color: Color { Color(hex: hex) }

    var totalWeeks: Int { weeks.isEmpty ? 8 : weeks.count }
    var percent: Int { Int((100 * Double(completedWeeks) / Double(totalWeeks)).rounded()) }
}

struct WorkoutData {
    var streak: Int
    /// Last 14 days, oldest first; `true` = trained.
    var history: [Bool]
    var programs: [WorkoutProgram]

    var sessionsThisWeek: Int { history.suffix(7).filter { $0 }.count }
    var trainedToday: Bool { history.last == true }
}
