import SwiftUI
import WidgetKit

/// 8. Syllabus (medium, configurable): three subjects' progress, and the overall figure.
struct SyllabusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.syllabus, intent: SyllabusConfiguration.self, provider: SyllabusProvider()) { entry in
            SyllabusWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL(DeepLink.university.url)
        }
        .configurationDisplayName("Syllabus")
        .description("How far through the syllabus you are, per subject.")
        .supportedFamilies([.systemMedium])
    }
}

struct SyllabusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Chosen subject IDs; empty means the three furthest along.
    var subjectIDs: [String] = []

    static var sample: SyllabusEntry { SyllabusEntry(date: .now, snapshot: .sample) }
    static var empty: SyllabusEntry { SyllabusEntry(date: .now, snapshot: WidgetSnapshot()) }

    var subjects: [SyllabusSubject] {
        let all = snapshot.university.syllabus
        let chosen = subjectIDs.compactMap { id in all.first { $0.id == id } }
        if !chosen.isEmpty { return Array(chosen.prefix(3)) }
        return Array(all.sorted { ($0.percent, $1.subject) > ($1.percent, $0.subject) }.prefix(3))
    }
}

struct SyllabusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SyllabusEntry { .sample }

    func snapshot(for configuration: SyllabusConfiguration, in context: Context) async -> SyllabusEntry {
        SyllabusEntry(date: .now, snapshot: .forSnapshot(context), subjectIDs: ids(configuration))
    }

    func timeline(for configuration: SyllabusConfiguration, in context: Context) async -> Timeline<SyllabusEntry> {
        let (snapshot, readable) = WidgetSnapshot.current()
        let ids = ids(configuration)
        return makeTimeline(snapshot, readable: readable) { SyllabusEntry(date: $0, snapshot: snapshot, subjectIDs: ids) }
    }

    private func ids(_ configuration: SyllabusConfiguration) -> [String] {
        (configuration.subjects ?? []).map(\.id)
    }
}

struct SyllabusWidgetView: View {
    let entry: SyllabusEntry

    var body: some View {
        let university = entry.snapshot.university
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Syllabus", dot: WidgetColor.green,
                    trailing: university.syllabus.isEmpty || !entry.snapshot.universityOn ? nil : "\(university.syllabusPercent)% overall")
            if !entry.snapshot.universityOn {
                FeatureOffMessage(feature: "University")
            } else if entry.subjects.isEmpty {
                EmptyMessage(text: "No syllabus yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.subjects) { subject in
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                Text(subject.subject).lineLimit(1).privacySensitive()
                                Spacer(minLength: 0)
                                Text("\(subject.percent)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 34, alignment: .trailing)
                            }
                            .font(WidgetFont.subtitle)
                            ProgressBar(value: Double(subject.percent) / 100, tint: WidgetColor.blue)
                        }
                    }
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("Syllabus", as: .systemMedium) {
    SyllabusWidget()
} timeline: {
    SyllabusEntry.sample
    SyllabusEntry.empty
}

#Preview("Syllabus · dark") {
    WidgetPreviewCard(family: .systemMedium) { SyllabusWidgetView(entry: .sample) }
}
