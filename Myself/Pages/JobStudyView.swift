import SwiftUI

/// Subjects → topics. Ticking a topic logs one revision for today.
struct JobStudyView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: ID?

    var body: some View {
        let active = store.jobStudy.first { $0.id == selection } ?? store.jobStudy.first

        PageScroll {
            ColorTabs(items: store.jobStudy, selection: active?.id, title: \.subject, color: \.color) { selection = $0 }

            if let active {
                subjectCard(active)
            } else {
                EmptyStateView(systemImage: "book.closed", title: "No subjects yet", subtitle: "Add a subject and list topics to track revisions.")
            }
        }
    }

    private func subjectCard(_ s: StudySubject) -> some View {
        let pct = s.percent
        let color = pct == 100 ? Palette.green : Color.accentColor
        let revisions = s.topics.reduce(0) { $0 + $1.revisions }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(s.subject).font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text("\(revisions) revisions · \(s.topics.count) topics").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                        RowActions(isHovering: true)
                    }
                    ProgressBar(value: Double(pct), color: color)
                }
                Donut(percent: pct, size: 52, lineWidth: 6, color: color)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(s.topics) { t in
                    TopicRow(subject: s.id, topic: t)
                }
                if s.topics.isEmpty {
                    Text("No topics yet.").font(.system(size: 11.5)).foregroundStyle(Palette.ink3).padding(.vertical, 4)
                }
                InlineAdder(placeholder: "Add topic…") { store.addStudyTopic(subject: s.id, name: $0) }
            }
        }
        .padding(16)
        .cardBackground()
    }
}

private struct TopicRow: View {
    @Environment(AppStore.self) private var store
    var subject: ID
    var topic: StudyTopic
    @State private var hovering = false

    var body: some View {
        let revisedToday = Day.isToday(topic.lastRevised)
        HStack(spacing: 10) {
            CheckCircle(isOn: revisedToday) { store.reviseTopic(subject: subject, topic: topic.id) }
            Text(topic.name)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { store.reviseTopic(subject: subject, topic: topic.id) }
            Text("\(topic.revisions)×")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(topic.revisions > 0 ? Color.accentColor : Palette.ink3)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(topic.revisions > 0 ? Color.accentColor.opacity(0.14) : Palette.surface2, in: Capsule())
                .help(topic.lastRevised.map { "Last revised " + (revisedToday ? "today" : $0.monthDay) } ?? "Not revised yet")
            Button { store.deleteStudyTopic(subject: subject, topic: topic.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Palette.ink3)
            }
            .buttonStyle(.borderless)
            #if os(macOS)
            .opacity(hovering ? 1 : 0)
            #endif
        }
        .padding(.vertical, 5)
        .onHover { hovering = $0 }
    }
}

#Preview {
    JobStudyView().environment(AppStore()).frame(width: 900, height: 700)
}
