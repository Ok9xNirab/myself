import SwiftUI
import WidgetKit

/// 6. Job Study (small): topics due for revision, and how much has been covered.
struct JobStudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.jobStudy, provider: SnapshotProvider()) { entry in
            JobStudyWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.jobStudy.url)
        }
        .configurationDisplayName("Job Study")
        .description("Topics due for revision and how much you've covered.")
        .supportedFamilies([.systemSmall])
    }
}

struct JobStudyWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Job Study", dot: WidgetColor.orange)
            if !snapshot.jobStudyOn {
                FeatureOffMessage(feature: "Job Study")
            } else if snapshot.allTopics.isEmpty {
                EmptyMessage(text: "No topics yet")
            } else {
                let due = snapshot.dueTopicCount(at: entry.date)
                Spacer(minLength: 0)
                Text("\(due)")
                    .font(WidgetFont.big)
                    .monospacedDigit()
                    .foregroundStyle(WidgetColor.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(due == 1 ? "topic due for revision" : "topics due for revision")
                    .font(WidgetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 4)
                ProgressBar(value: Double(snapshot.coveredPercent) / 100, tint: WidgetColor.orange)
                    .padding(.top, 12)
                HStack {
                    Text("\(snapshot.coveredPercent)% covered")
                    Spacer(minLength: 4)
                    Text("\(snapshot.revisedToday(at: entry.date)) today")
                }
                .font(WidgetFont.subtitle)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.top, 6)
            }
        }
    }
}

#Preview("Job Study", as: .systemSmall) {
    JobStudyWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("Job Study · dark") {
    WidgetPreviewCard(family: .systemSmall) { JobStudyWidgetView(entry: .sample) }
}
