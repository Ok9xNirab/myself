import SwiftUI

/// One row of "Today's focus": a todo or office task due today or overdue, or an assignment due by tomorrow. Shared
/// by the Dashboard and the widgets (Today's focus, Today).
struct FocusItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case todo, office, assignment }

    let id: ID
    let kind: Kind
    let title: String
    let due: Date?
    var done = false

    var label: String { switch kind { case .todo: "Todo"; case .office: "Office"; case .assignment: "Assignment" } }
    var color: Color { switch kind { case .todo: Palette.blue; case .office: .accentColor; case .assignment: Palette.red } }

    /// Open items, most overdue first. `now` is the moment to judge "today" by (a widget's entry date).
    static func list(todos: [Todo], office: [OfficeTask], assignments: [Assignment],
                     officeOn: Bool = true, universityOn: Bool = true, now: Date = .now) -> [FocusItem] {
        var items: [FocusItem] = []
        items += todos.filter { !$0.done && (Day.between(now, $0.due) ?? 1) <= 0 }
            .map { FocusItem(id: $0.id, kind: .todo, title: $0.title, due: $0.due) }
        if officeOn {
            items += office.filter { !$0.done && (Day.between(now, $0.due) ?? 1) <= 0 }
                .map { FocusItem(id: $0.id, kind: .office, title: $0.title, due: $0.due) }
        }
        if universityOn {
            items += assignments.filter { !$0.done && (Day.between(now, $0.due) ?? 2) <= 1 }
                .map { FocusItem(id: $0.id, kind: .assignment, title: $0.title, due: $0.due) }
        }
        return items.sorted { (Day.between(now, $0.due) ?? 0) < (Day.between(now, $1.due) ?? 0) }
    }

    /// Items that were in focus and were completed on the day of `now`, so a widget can still show them ticked.
    /// Assignments have no completion date; their `updatedAt` stands in for it.
    static func completedToday(todos: [Todo], office: [OfficeTask], assignments: [Assignment],
                               officeOn: Bool = true, universityOn: Bool = true, now: Date = .now) -> [FocusItem] {
        let today = { (date: Date?) in Day.between(now, date) == 0 }
        var items: [FocusItem] = []
        items += todos.filter { $0.done && today($0.completedAt) && (Day.between(now, $0.due) ?? 1) <= 0 }
            .map { FocusItem(id: $0.id, kind: .todo, title: $0.title, due: $0.due, done: true) }
        if officeOn {
            items += office.filter { $0.done && today($0.completedAt) && (Day.between(now, $0.due) ?? 1) <= 0 }
                .map { FocusItem(id: $0.id, kind: .office, title: $0.title, due: $0.due, done: true) }
        }
        if universityOn {
            items += assignments.filter { $0.done && today($0.updatedAt) && (Day.between(now, $0.due) ?? 2) <= 1 }
                .map { FocusItem(id: $0.id, kind: .assignment, title: $0.title, due: $0.due, done: true) }
        }
        return items
    }
}
