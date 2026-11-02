import AppIntents
import SwiftUI
import WidgetKit

/// 9. Revise next (medium, configurable, interactive): the three least-revised due topics of a Job Study subject,
/// each with a + that logs a revision today.
struct ReviseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.revise, intent: ReviseConfiguration.self, provider: ReviseProvider()) { entry in
            ReviseWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.jobStudy.url)
        }
        .configurationDisplayName("Revise Next")
        .description("The Job Study topics to revise next. Click + to log a revision.")
        .supportedFamilies([.systemMedium])
    }
}

struct ReviseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The chosen subject; nil means the one with the most topics due.
    var subjectID: String?

    static var sample: ReviseEntry { ReviseEntry(date: .now, snapshot: .sample) }
    static var empty: ReviseEntry { ReviseEntry(date: .now, snapshot: WidgetSnapshot()) }

    var subject: StudySubject? {
        if let subjectID, let chosen = snapshot.jobStudy.first(where: { $0.id == subjectID }) { return chosen }
        return snapshot.busiestSubject(at: date)
    }
}

struct ReviseProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ReviseEntry { .sample }

    func snapshot(for configuration: ReviseConfiguration, in context: Context) async -> ReviseEntry {
        ReviseEntry(date: .now, snapshot: .forSnapshot(context), subjectID: configuration.subject?.id)
    }

    func timeline(for configuration: ReviseConfiguration, in context: Context) async -> Timeline<ReviseEntry> {
        let (snapshot, readable) = WidgetSnapshot.current()
        let id = configuration.subject?.id
        return makeTimeline(snapshot, readable: readable) { ReviseEntry(date: $0, snapshot: snapshot, subjectID: id) }
    }
}

struct ReviseWidgetView: View {
    let entry: ReviseEntry

    var body: some View {
        let subject = entry.subject
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Revise next", dot: subject?.color ?? WidgetColor.orange,
                    trailing: entry.snapshot.jobStudyOn ? subject?.subject : nil)
            if !entry.snapshot.jobStudyOn {
                FeatureOffMessage(feature: "Job Study")
            } else if let subject {
                let queue = Array(entry.snapshot.reviseQueue(subject, at: entry.date).prefix(3))
                if queue.isEmpty {
                    EmptyMessage(text: subject.topics.isEmpty ? "No topics in \(subject.subject) yet" : "All revised this week",
                                 systemImage: subject.topics.isEmpty ? nil : "checkmark.circle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(queue.enumerated()), id: \.element.id) { index, topic in
                            if index > 0 { Hairline() }
                            TopicRow(subject: subject.id, topic: topic)
                        }
                    }
                    .padding(.top, 6)
                    Spacer(minLength: 0)
                }
            } else {
                EmptyMessage(text: "No subjects yet")
            }
        }
    }
}

private struct TopicRow: View {
    let subject: String
    let topic: StudyTopic

    var body: some View {
        HStack(spacing: 10) {
            Text(topic.name)
                .font(WidgetFont.row)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            Text("\(topic.revisions)\u{00D7}")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 22, alignment: .trailing)
            Button(intent: IncrementRevisionIntent(subject: subject, topic: topic.id)) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetColor.orange)
                    .frame(width: 24, height: 24)
                    .background(WidgetColor.soft, in: Circle())
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log a revision of \(topic.name)")
        }
        .padding(.vertical, 5)
    }
}

#Preview("Revise next", as: .systemMedium) {
    ReviseWidget()
} timeline: {
    ReviseEntry.sample
    ReviseEntry.empty
}

#Preview("Revise next · dark") {
    WidgetPreviewCard(family: .systemMedium) { ReviseWidgetView(entry: .sample) }
}
