import SwiftUI
import WidgetKit

/// 10. Office (small): office tasks due or overdue, and how old the oldest is.
struct OfficeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.office, provider: SnapshotProvider()) { entry in
            OfficeWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.office.url)
        }
        .configurationDisplayName("Office")
        .description("Office tasks due today or overdue.")
        .supportedFamilies([.systemSmall])
    }
}

struct OfficeWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Office", dot: WidgetColor.blue)
            if entry.snapshot.officeOn {
                let due = entry.snapshot.officeDue(at: entry.date)
                let oldest = due.compactMap { Day.between(entry.date, $0.due) }.min() ?? 0
                Spacer(minLength: 0)
                Text("\(due.count)")
                    .font(WidgetFont.big)
                    .monospacedDigit()
                    .foregroundStyle(WidgetColor.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(due.isEmpty ? "nothing due or overdue" : "due or overdue")
                    .font(WidgetFont.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 4)
                Group {
                    if due.isEmpty {
                        Chip(text: "All clear", tint: WidgetColor.green)
                    } else if oldest < 0 {
                        Chip(text: "Oldest \(-oldest)d", tint: WidgetColor.red)
                    } else {
                        Chip(text: "Due today", tint: WidgetColor.blue)
                    }
                }
                .padding(.top, 12)
            } else {
                FeatureOffMessage(feature: "Office Tasks")
            }
        }
    }
}

#Preview("Office", as: .systemSmall) {
    OfficeWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("Office · dark") {
    WidgetPreviewCard(family: .systemSmall) { OfficeWidgetView(entry: .sample) }
}
