import SwiftUI

typealias ID = String

func newID() -> ID { UUID().uuidString }

enum Priority: String, CaseIterable, Identifiable {
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

struct TaskLabel: Identifiable, Hashable {
    let id: ID
    var name: String
    var hex: UInt32
    var color: Color { Color(hex: hex) }
}

struct Todo: Identifiable {
    var id = newID()
    var title: String
    var desc = ""
    var labelIDs: [ID] = []
    var priority: Priority = .medium
    var due: Date?
    var done = false
}

/// Office tasks are always high priority and carry a reference link.
struct OfficeTask: Identifiable {
    var id = newID()
    var title: String
    var refURL: URL?
    var due: Date?
    var done = false
}

// MARK: University

struct UniClass: Identifiable {
    var id = newID()
    var subject: String
    var code: String
    var days: [Weekday]
    var time: ClockTime
    var room: String
    var hex: UInt32
    var color: Color { Color(hex: hex) }
}

struct SyllabusTopic: Identifiable {
    var id = newID()
    var name: String
    var done = false
}

struct SyllabusSubject: Identifiable {
    var id = newID()
    var subject: String
    var topics: [SyllabusTopic]

    var percent: Int {
        topics.isEmpty ? 0 : Int((100 * Double(topics.filter(\.done).count) / Double(topics.count)).rounded())
    }
}

struct Assignment: Identifiable {
    var id = newID()
    var title: String
    var subject: String
    var due: Date?
    var done = false
}

enum ExamKind: String, CaseIterable {
    case classTest = "Class Test", midterm = "Midterm", final = "Final"

    var color: Color {
        switch self {
        case .classTest: Palette.blue
        case .midterm: Palette.amber
        case .final: Palette.red
        }
    }
}

struct Exam: Identifiable {
    var id = newID()
    var subject: String
    var kind: ExamKind
    var date: Date
    var prep: Int
}

struct University {
    var notes: String
    var classes: [UniClass]
    var syllabus: [SyllabusSubject]
    var assignments: [Assignment]
    var exams: [Exam]

    var syllabusPercent: Int {
        let all = syllabus.flatMap(\.topics)
        return Int((100 * Double(all.filter(\.done).count) / Double(max(1, all.count))).rounded())
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
