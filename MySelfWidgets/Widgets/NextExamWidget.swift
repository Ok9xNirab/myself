import SwiftUI
import WidgetKit

/// 4. Next exam (small): days until the nearest exam, on a red gradient.
struct NextExamWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextExam, provider: SnapshotProvider()) { entry in
            NextExamWidgetView(entry: entry)
                .containerBackground(for: .widget) { NextExamWidgetView.gradient }
                .widgetURL(DeepLink.university.url)
        }
        .configurationDisplayName("Next Exam")
        .description("A countdown to your next exam.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextExamWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    static let gradient = LinearGradient(colors: [Color(hex: 0xFF5A4F), Color(hex: 0xE2352B)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    /// White on the red background; in accented and vibrant modes the system draws the background, so use its styles.
    private var onRed: Bool { renderingMode == .fullColor }
    private var primary: AnyShapeStyle { onRed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary) }
    private var secondary: Color? { onRed ? .white.opacity(0.85) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Next exam", tint: secondary)
            if !entry.snapshot.universityOn {
                FeatureOffMessage(feature: "University").foregroundStyle(primary)
            } else if let exam = entry.snapshot.nextExam(at: entry.date) {
                Spacer(minLength: 0)
                countdown(Day.between(entry.date, exam.date) ?? 0)
                Text(exam.subject)
                    .font(WidgetFont.title)
                    .lineLimit(2)
                    .padding(.top, 8)
                    .privacySensitive()
                Text("\(exam.kind.rawValue) \u{00B7} \(exam.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(WidgetFont.subtitle)
                    .foregroundStyle(secondary.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                    .lineLimit(1)
            } else {
                Text("No exams scheduled")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(secondary.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(primary)
    }

    @ViewBuilder
    private func countdown(_ days: Int) -> some View {
        if days == 0 {
            Text("Today").font(.system(size: 40, weight: .bold)).widgetAccentable()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(days)").font(.system(size: 56, weight: .bold)).monospacedDigit()
                Text(days == 1 ? "day" : "days").font(.system(size: 22, weight: .semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()
        }
    }
}

#Preview("Next exam", as: .systemSmall) {
    NextExamWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.empty
}

#Preview("Next exam · dark") {
    WidgetPreviewCard(family: .systemSmall, background: AnyShapeStyle(NextExamWidgetView.gradient)) {
        NextExamWidgetView(entry: .sample)
    }
}
