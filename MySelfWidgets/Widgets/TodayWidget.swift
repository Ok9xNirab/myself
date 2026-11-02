import SwiftUI
import WidgetKit

/// 3. Today (small): a ring of what's due today (the focus list), split by area.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.dashboard.url)
        }
        .configurationDisplayName("Today")
        .description("How much is due today, by Office, University and TODOs.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry

    private struct Area: Identifiable {
        let id: String
        let count: Int
        let color: Color
    }

    var body: some View {
        let focus = entry.snapshot.focus(at: entry.date)
        let areas = [
            Area(id: "Office", count: focus.filter { $0.kind == .office }.count, color: WidgetColor.blue),
            Area(id: "Uni", count: focus.filter { $0.kind == .assignment }.count, color: WidgetColor.red),
            Area(id: "Todos", count: focus.filter { $0.kind == .todo }.count, color: WidgetColor.green),
        ]
        VStack(spacing: 0) {
            Caption(title: "Today")
            ZStack {
                Ring(segments: areas.map { Ring.Segment(id: $0.id, value: Double($0.count), color: $0.color) })
                VStack(spacing: 1) {
                    Text("\(focus.count)")
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                    Text("due").font(WidgetFont.subtitle).foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            .padding(.top, 6)
            Spacer(minLength: 4)
            if focus.isEmpty {
                Text("Nothing due today").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(spacing: 10) {
                    ForEach(areas.filter { $0.count > 0 }) { area in
                        HStack(spacing: 4) {
                            Circle().fill(area.color).frame(width: 6, height: 6).widgetAccentable()
                            Text("\(area.id) \(area.count)")
                        }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }
}

#Preview("Today", as: .systemSmall) {
    TodayWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("Today · dark") {
    WidgetPreviewCard(family: .systemSmall) { TodayWidgetView(entry: .sample) }
}
