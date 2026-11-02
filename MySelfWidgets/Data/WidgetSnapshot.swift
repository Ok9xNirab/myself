import SwiftUI

/// Everything the widgets show, read from the shared store in one go (`WidgetStore.load`) or made up for the gallery
/// (`WidgetSnapshot.sample`). Every derived value takes `now`, the timeline entry's date, so entries for later in the
/// day (the next class, midnight) work out "today" and "overdue" for that moment.
struct WidgetSnapshot {
    var todos: [Todo] = []
    var office: [OfficeTask] = []
    var university = University()
    var jobStudy: [StudySubject] = []
    /// `Page` raw values turned off in Settings › Features.
    var disabled: Set<String> = []

    var officeOn: Bool { !disabled.contains("office") }
    var universityOn: Bool { !disabled.contains("university") }
    var jobStudyOn: Bool { !disabled.contains("jobStudy") }
    var notesOn: Bool { !disabled.contains("notes") }

    // MARK: Focus

    func focus(at now: Date) -> [FocusItem] {
        FocusItem.list(todos: todos, office: office, assignments: university.assignments,
                       officeOn: officeOn, universityOn: universityOn, now: now)
    }

    func completedFocus(at now: Date) -> [FocusItem] {
        FocusItem.completedToday(todos: todos, office: office, assignments: university.assignments,
                                 officeOn: officeOn, universityOn: universityOn, now: now)
    }

    // MARK: Office

    func officeDue(at now: Date) -> [OfficeTask] {
        office.filter { !$0.done && (Day.between(now, $0.due) ?? 1) <= 0 }
    }

    // MARK: University

    /// A class's colour for an exam or assignment that names it.
    func color(ofSubject subject: String) -> Color? {
        university.classes.first { $0.subject == subject }?.color
    }

    struct ClassSession: Identifiable {
        let klass: UniClass
        let start: Date
        var id: String { "\(klass.id)-\(start.timeIntervalSince1970)" }
    }

    /// Every class meeting that starts in `range`, in order.
    func sessions(in range: Range<Date>) -> [ClassSession] {
        let calendar = Day.calendar
        var out: [ClassSession] = []
        var day = calendar.startOfDay(for: range.lowerBound)
        while day < range.upperBound {
            let weekday = Weekday.of(day)
            for klass in university.classes where klass.days.contains(weekday) {
                if let start = calendar.date(bySettingHour: klass.time.hour, minute: klass.time.minute, second: 0, of: day),
                   range.contains(start) {
                    out.append(ClassSession(klass: klass, start: start))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out.sorted { $0.start < $1.start }
    }

    /// The next classes that haven't started yet, looking two weeks ahead.
    func nextClasses(after now: Date, count: Int) -> [ClassSession] {
        let end = Day.calendar.date(byAdding: .day, value: 14, to: now) ?? now
        return Array(sessions(in: now..<end).prefix(count))
    }

    /// The nearest exam today or later.
    func nextExam(at now: Date) -> Exam? {
        university.exams.filter { (Day.between(now, $0.date) ?? -1) >= 0 }.min { $0.date < $1.date }
    }

    func overdueAssignments(at now: Date) -> Int {
        university.assignments.filter { !$0.done && (Day.between(now, $0.due) ?? 0) < 0 }.count
    }

    // MARK: Job Study

    var allTopics: [StudyTopic] { jobStudy.flatMap(\.topics) }

    /// Topics due for revision, as of `now` (a topic is due once `StudyTopic.dueDays` have passed since it was revised).
    func dueTopics(in subject: StudySubject, at now: Date) -> [StudyTopic] {
        subject.topics.filter { topic in
            guard let days = Day.between(now, topic.lastRevised) else { return true }
            return days <= -StudyTopic.dueDays
        }
    }

    func dueTopicCount(at now: Date) -> Int {
        jobStudy.reduce(0) { $0 + dueTopics(in: $1, at: now).count }
    }

    /// Share of all topics revised at least once, 0–100.
    var coveredPercent: Int {
        let all = allTopics
        guard !all.isEmpty else { return 0 }
        return Int((100 * Double(all.filter { $0.revisions > 0 }.count) / Double(all.count)).rounded())
    }

    func revisedToday(at now: Date) -> Int {
        allTopics.filter { Day.between(now, $0.lastRevised) == 0 }.count
    }

    /// The subject with the most topics due; the default for Revise next.
    func busiestSubject(at now: Date) -> StudySubject? {
        jobStudy.max { dueTopics(in: $0, at: now).count < dueTopics(in: $1, at: now).count }
    }

    /// Due topics with the fewest revisions first, then the longest unrevised, then in subject order.
    func reviseQueue(_ subject: StudySubject, at now: Date) -> [StudyTopic] {
        let order = Dictionary(subject.topics.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return dueTopics(in: subject, at: now).sorted { a, b in
            if a.revisions != b.revisions { return a.revisions < b.revisions }
            let ad = a.lastRevised ?? .distantPast, bd = b.lastRevised ?? .distantPast
            if ad != bd { return ad < bd }
            return (order[a.id] ?? 0) < (order[b.id] ?? 0)
        }
    }

    // MARK: Timeline

    /// When the widgets should redraw on their own: each class start in the next day (Next classes and This week
    /// move on) and midnight (due dates and "today" change).
    func refreshDates(after now: Date) -> [Date] {
        let calendar = Day.calendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let starts = sessions(in: now.addingTimeInterval(1)..<midnight).map { $0.start.addingTimeInterval(1) }
        return Array(Set(starts)).sorted().prefix(12) + [midnight]
    }
}
