import SwiftUI
import WidgetKit

/// 5. Next classes (medium): the next two classes as a timeline.
struct NextClassesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextClasses, provider: SnapshotProvider()) { entry in
            NextClassesWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.university.url)
        }
        .configurationDisplayName("Next Classes")
        .description("Your next two classes, with their time and room.")
        .supportedFamilies([.systemMedium])
    }
}

struct NextClassesWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let sessions = entry.snapshot.universityOn ? entry.snapshot.nextClasses(after: entry.date, count: 2) : []
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Next classes", dot: sessions.first?.klass.color ?? WidgetColor.purple,
                    trailing: sessions.first.map { dayLabel($0.start) })
            if !entry.snapshot.universityOn {
                FeatureOffMessage(feature: "University")
            } else if sessions.isEmpty {
                EmptyMessage(text: entry.snapshot.university.classes.isEmpty ? "No classes yet" : "No classes this week")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sessions) { session in
                        ClassRow(session: session,
                                 day: Day.calendar.isDate(session.start, inSameDayAs: sessions[0].start) ? nil : dayLabel(session.start))
                    }
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        switch Day.between(entry.date, date) {
        case 0: "Today"
        case 1: "Tomorrow"
        default: date.formatted(.dateTime.weekday(.wide))
        }
    }
}

private struct ClassRow: View {
    let session: WidgetSnapshot.ClassSession
    /// Shown under the time when this class is on another day than the first.
    let day: String?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(session.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                if let day {
                    Text(day).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 58, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1.5).fill(session.klass.color).frame(width: 3, height: 34).widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(session.klass.subject).font(WidgetFont.title).lineLimit(1).privacySensitive()
                Text([session.klass.code, session.klass.room].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(WidgetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Next classes", as: .systemMedium) {
    NextClassesWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("Next classes · dark") {
    WidgetPreviewCard(family: .systemMedium) { NextClassesWidgetView(entry: .sample) }
}
