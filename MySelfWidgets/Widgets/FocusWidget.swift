import AppIntents
import SwiftUI
import WidgetKit

/// 2. Today's focus (medium, interactive): the Dashboard's focus list with check circles that complete the task.
struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.focus, provider: SnapshotProvider()) { entry in
            FocusWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.dashboard.url)
        }
        .configurationDisplayName("Today's Focus")
        .description("Todos and office tasks due today or overdue, and assignments due by tomorrow. Tick them off here.")
        .supportedFamilies([.systemMedium])
    }
}

struct FocusWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let open = entry.snapshot.focus(at: entry.date)
        // Ticked-off items stay (struck through) so a mis-tap can be undone, after the open ones.
        let rows = Array((open + entry.snapshot.completedFocus(at: entry.date)).prefix(3))
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Today's focus", dot: WidgetColor.blue,
                    trailing: open.isEmpty ? (rows.isEmpty ? nil : "All done") : "\(open.count) left")
            if rows.isEmpty {
                EmptyMessage(text: "Nothing due today", systemImage: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline() }
                        FocusRow(item: item, now: entry.date)
                    }
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct FocusRow: View {
    let item: FocusItem
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ToggleTaskIntent(item)) {
                CheckCircle(isOn: item.done)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Reopen \(item.title)" : "Complete \(item.title)")

            Text(item.title)
                .font(WidgetFont.row)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            if !item.done {
                DueChip(due: item.due, now: now)
            }
        }
        .padding(.vertical, 7)
    }
}

/// The 18 pt check circle: an outline, or filled blue with a tick.
struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(WidgetColor.blue).widgetAccentable()
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(.tertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
    }
}

#Preview("Today's focus", as: .systemMedium) {
    FocusWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("Today's focus · dark") {
    WidgetPreviewCard(family: .systemMedium) { FocusWidgetView(entry: .sample) }
}
