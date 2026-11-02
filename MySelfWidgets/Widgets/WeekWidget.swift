import SwiftUI
import WidgetKit

/// 1. This week (large): a Monday–Sunday strip with a dot per class or deadline, the next four events, and counts.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.week, provider: SnapshotProvider()) { entry in
            WeekWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.university.url)
        }
        .configurationDisplayName("This Week")
        .description("Your classes, exams and deadlines from Monday to Sunday.")
        .supportedFamilies([.systemLarge])
    }
}

struct WeekWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if entry.snapshot.universityOn {
            WeekContent(week: WeekPlan(entry.snapshot, now: entry.date), now: entry.date)
        } else {
            VStack(alignment: .leading) {
                Caption(title: "This week", dot: WidgetColor.blue)
                FeatureOffMessage(feature: "University")
            }
        }
    }
}

/// One thing on the week's calendar.
struct WeekEvent: Identifiable {
    enum Kind { case session, exam, assignment }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let start: Date
    /// Whether `start` carries a time (classes, exams set for a time) or only a day.
    let timed: Bool
    let color: Color

    var isDeadline: Bool { kind != .session }
}

/// The week containing `now`, worked out from a snapshot.
struct WeekPlan {
    struct DayCell: Identifiable {
        let date: Date
        let isToday: Bool
        let dots: [Color]
        var id: Date { date }
    }

    let days: [DayCell]
    let range: Range<Date>
    let upcoming: [WeekEvent]
    let classes: Int
    let deadlines: Int
    let overdue: Int

    init(_ snapshot: WidgetSnapshot, now: Date) {
        let calendar = Day.calendar
        let today = calendar.startOfDay(for: now)
        // Monday first, whatever the locale's first weekday.
        let fromMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -fromMonday, to: today)!
        let end = calendar.date(byAdding: .day, value: 7, to: monday)!
        range = monday..<end

        var events = snapshot.sessions(in: monday..<end).map { session in
            WeekEvent(id: session.id, kind: .session, title: session.klass.subject,
                      subtitle: session.klass.room.isEmpty ? "Class" : "Class \u{00B7} \(session.klass.room)",
                      start: session.start, timed: true, color: session.klass.color)
        }
        for exam in snapshot.university.exams where (monday..<end).contains(exam.date) {
            let timed = calendar.component(.hour, from: exam.date) != 0 || calendar.component(.minute, from: exam.date) != 0
            let kind = exam.kind == .classTest ? "Class test" : "\(exam.kind.rawValue) exam"
            events.append(WeekEvent(id: exam.id, kind: .exam, title: exam.subject, subtitle: kind, start: exam.date, timed: timed,
                                    color: snapshot.color(ofSubject: exam.subject) ?? WidgetColor.red))
        }
        for assignment in snapshot.university.assignments where !assignment.done {
            guard let due = assignment.due, (monday..<end).contains(due) else { continue }
            let subtitle = assignment.subject.isEmpty ? "Assignment" : "Assignment \u{00B7} \(assignment.subject)"
            events.append(WeekEvent(id: assignment.id, kind: .assignment, title: assignment.title, subtitle: subtitle,
                                    start: calendar.startOfDay(for: due), timed: false,
                                    color: snapshot.color(ofSubject: assignment.subject) ?? WidgetColor.red))
        }
        // Day-only deadlines come first on their day.
        events.sort { ($0.start, $0.timed ? 1 : 0) < ($1.start, $1.timed ? 1 : 0) }

        days = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday)!
            let dots = events.filter { calendar.isDate($0.start, inSameDayAs: date) }.prefix(3).map(\.color)
            return DayCell(date: date, isToday: date == today, dots: Array(dots))
        }
        // Still to come: classes that haven't started, and today's or later deadlines.
        upcoming = Array(events.filter { $0.timed ? $0.start >= now : $0.start >= today }.prefix(4))
        classes = events.filter { $0.kind == .session }.count
        deadlines = events.filter(\.isDeadline).count
        overdue = snapshot.overdueAssignments(at: now)
    }
}

private struct WeekContent: View {
    let week: WeekPlan
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "This week", dot: WidgetColor.blue,
                    trailing: (week.range.lowerBound..<week.days[6].date).formatted(.interval.day().month(.abbreviated)))
            HStack(spacing: 4) {
                ForEach(week.days) { DayColumn(day: $0) }
            }
            .padding(.top, 12)

            if week.upcoming.isEmpty {
                EmptyMessage(text: week.classes + week.deadlines == 0 ? "No classes this week" : "Nothing else this week")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(week.upcoming.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Hairline() }
                        EventRow(event: event, now: now)
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }

            HStack {
                Text(summary).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if week.overdue > 0 {
                    Text("\(week.overdue) overdue").fontWeight(.semibold).foregroundStyle(WidgetColor.red)
                }
            }
            .font(WidgetFont.subtitle)
            .lineLimit(1)
        }
    }

    private var summary: String {
        "\(week.classes) \(week.classes == 1 ? "class" : "classes") \u{00B7} \(week.deadlines) \(week.deadlines == 1 ? "deadline" : "deadlines")"
    }
}

private struct DayColumn: View {
    let day: WeekPlan.DayCell

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(day.isToday ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            HStack(spacing: 3) {
                ForEach(Array(day.dots.enumerated()), id: \.offset) { _, color in
                    Circle().fill(day.isToday ? .white : color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WidgetColor.blue).widgetAccentable()
            }
        }
    }
}

private struct EventRow: View {
    let event: WeekEvent
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3).widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(WidgetFont.title).lineLimit(1).privacySensitive()
                Text(event.subtitle).font(WidgetFont.subtitle).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(dayText)
                    .font(WidgetFont.title)
                    .foregroundStyle(event.isDeadline ? AnyShapeStyle(WidgetColor.red) : AnyShapeStyle(.primary))
                Text(timeText).font(WidgetFont.subtitle).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            .fixedSize()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 7)
    }

    private var dayText: String {
        Day.between(now, event.start) == 0 ? "Today" : event.start.formatted(.dateTime.weekday(.abbreviated))
    }

    private var timeText: String {
        if event.timed { return event.start.formatted(date: .omitted, time: .shortened) }
        return event.kind == .exam ? "Exam" : "Due"
    }
}

#Preview("This week", as: .systemLarge) {
    WeekWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("This week · dark") {
    WidgetPreviewCard(family: .systemLarge) { WeekWidgetView(entry: .sample) }
}
