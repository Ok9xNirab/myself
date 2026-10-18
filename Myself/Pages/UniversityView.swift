import SwiftUI

struct UniversityView: View {
    @Environment(AppStore.self) private var store
    @State private var openSyllabus: ID? = "s1"

    private struct Session: Identifiable {
        let date: Date
        let klass: UniClass
        var id: String { klass.id + date.description }
    }

    /// Next dated sessions generated from each class's weekdays.
    private var sessions: [Session] {
        let all: [Session] = store.university.classes.flatMap { c in
            Day.sessions(on: c.days, count: 4).map { Session(date: $0, klass: c) }
        }
        let sorted = all.sorted { a, b in
            a.date == b.date ? a.klass.time < b.klass.time : a.date < b.date
        }
        return Array(sorted.prefix(7))
    }

    var body: some View {
        let u = store.university
        let openAssignments = u.assignments.filter { !$0.done }.sorted { (Day.fromToday($0.due) ?? 999) < (Day.fromToday($1.due) ?? 999) }
        let nextExam = u.exams.sorted { $0.date < $1.date }.first { (Day.fromToday($0.date) ?? -1) >= 0 }

        PageScroll {
            StatGrid {
                StatTile(systemImage: "calendar", label: "Classes / week", value: "\(u.classes.reduce(0) { $0 + $1.days.count })",
                         foot: "\(u.classes.count) subjects", color: Palette.blue)
                StatTile(systemImage: "book.closed", label: "Syllabus done", value: "\(u.syllabusPercent)%", foot: "across all subjects", color: Palette.green)
                StatTile(systemImage: "flag", label: "Assignments due", value: "\(openAssignments.count)", foot: "all high priority", color: Palette.red)
                StatTile(systemImage: "target", label: "Next exam", value: nextExam.flatMap { Day.fromToday($0.date) }.map { "\($0)d" } ?? "—",
                         foot: nextExam?.subject ?? "none scheduled", color: Palette.amber)
            }
            .padding(.bottom, 4)

            AdaptiveColumns(ratio: 1.25) {
                classesCard
                assignmentsCard(open: openAssignments)
            } trailing: {
                examsCard
                notesCard
            }

            syllabusCard
        }
    }

    // MARK: Cards

    private var classesCard: some View {
        Card(title: "Upcoming classes", systemImage: "calendar") {
            Spacer()
            GhostButton(title: "Add class", systemImage: "plus")
        } content: {
            ForEach(sessions) { s in
                ListRow {
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(Weekday.of(s.date).code).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Palette.ink3)
                            Text("\(Day.calendar.component(.day, from: s.date))").font(.numeral(17))
                        }
                        .frame(width: 42, height: 42)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .leading) {
                            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(s.klass.color).frame(width: 3)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(s.klass.subject).font(.system(size: 13, weight: .medium))
                            FlowLayout(spacing: 8) {
                                Badge(text: s.klass.code, color: s.klass.color)
                                Label(s.klass.time.formatted, systemImage: "clock").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                                if !s.klass.room.isEmpty {
                                    Text(s.klass.room).font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let meta = DueMeta(s.date) {
                            Badge(text: meta.text, color: meta.tone == .today ? .accentColor : Palette.ink2)
                        }
                    }
                }
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(store.university.classes) { c in
                    HStack(spacing: 6) {
                        ColorDot(color: c.color, size: 7)
                        Text(c.subject)
                        Text(c.days.map(\.code).joined(separator: "·")).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink3)
                        Image(systemName: "pencil").foregroundStyle(Palette.ink3)
                        Image(systemName: "xmark").foregroundStyle(Palette.ink3)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(c.color.opacity(0.4), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func assignmentsCard(open: [Assignment]) -> some View {
        let done = store.university.assignments.filter(\.done)
        return Card(title: "Assignments", systemImage: "flag", tint: Palette.red) {
            CountText(value: open.count)
            Spacer()
            GhostButton(title: "Add", systemImage: "plus")
        } content: {
            if open.isEmpty && done.isEmpty {
                EmptyStateView(systemImage: "checkmark", title: "No assignments", subtitle: "Add one and it'll be flagged high priority.")
            }
            ForEach(open) { a in
                ListRow {
                    HStack(alignment: .top, spacing: 10) {
                        CheckCircle(isOn: false) { withAnimation { store.toggleAssignment(a.id) } }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(a.title).font(.system(size: 13, weight: .medium))
                            FlowLayout {
                                PriorityBadge(priority: .high, locked: true)
                                Badge(text: a.subject)
                                DueBadge(date: a.due)
                            }
                        }
                    }
                }
            }
            ForEach(done) { a in
                ListRow {
                    HStack(spacing: 10) {
                        CheckCircle(isOn: true) { withAnimation { store.toggleAssignment(a.id) } }
                        Text(a.title).font(.system(size: 13, weight: .medium)).strikethrough()
                    }
                    .opacity(0.55)
                }
            }
        }
    }

    private var examsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "target").foregroundStyle(Palette.amber)
                Text("Exam countdown").font(.system(size: 15, weight: .semibold))
                Spacer()
                GhostButton(title: "Add exam", systemImage: "plus")
            }
            if store.university.exams.isEmpty {
                EmptyStateView(systemImage: "target", title: "No exams scheduled", subtitle: "Add a Class Test, Midterm or Final.")
            }
            ForEach(store.university.exams.sorted { $0.date < $1.date }) { e in
                let d = Day.fromToday(e.date) ?? 0
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Text(d < 0 ? "✓" : "\(d)").font(.numeral(26))
                        Text(d < 0 ? "done" : "days").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink3)
                    }
                    .foregroundStyle(d <= 5 ? Palette.red : d <= 10 ? Palette.amber : .primary)
                    .frame(width: 54)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.subject).font(.system(size: 13, weight: .medium))
                        HStack(spacing: 8) {
                            Badge(text: e.kind.rawValue, color: e.kind.color)
                            Text(e.date.monthDay).font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                        }
                        .padding(.top, 5)
                        LabeledProgress(label: "Prep", value: e.prep,
                                        color: e.prep >= 70 ? Palette.green : e.prep >= 40 ? Palette.amber : Palette.red)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    private var notesCard: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(Palette.violet)
                Text("Notes").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("autosaved").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
            }
            TextEditor(text: $store.university.notes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 180)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .cardBackground()
    }

    private var syllabusCard: some View {
        let u = store.university
        return Card(title: "Syllabus completion", systemImage: "book.closed") {
            Spacer()
            Text("\(u.syllabusPercent)% overall").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
            GhostButton(title: "Add subject", systemImage: "plus")
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 0, alignment: .top)], spacing: 0) {
                ForEach(u.syllabus) { s in
                    SyllabusCell(subject: s, isOpen: openSyllabus == s.id) {
                        withAnimation(.snappy) { openSyllabus = openSyllabus == s.id ? nil : s.id }
                    }
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.border).frame(width: 0.5) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }
                }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
    }
}

private struct SyllabusCell: View {
    @Environment(AppStore.self) private var store
    var subject: SyllabusSubject
    var isOpen: Bool
    var onToggleOpen: () -> Void

    var body: some View {
        let pct = subject.percent
        let color = pct == 100 ? Palette.green : Color.accentColor
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subject.subject).font(.system(size: 13, weight: .medium))
                    ProgressBar(value: Double(pct), color: color)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleOpen)
                Donut(percent: pct, size: 52, lineWidth: 6, color: color)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(subject.topics) { t in
                        HStack(spacing: 10) {
                            CheckCircle(isOn: t.done) { store.toggleSyllabusTopic(subject: subject.id, topic: t.id) }
                            Text(t.name)
                                .font(.system(size: 13))
                                .strikethrough(t.done)
                                .foregroundStyle(t.done ? Palette.ink3 : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { store.toggleSyllabusTopic(subject: subject.id, topic: t.id) }
                            Button { store.deleteSyllabusTopic(subject: subject.id, topic: t.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Palette.ink3)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                    }
                    if subject.topics.isEmpty {
                        Text("No topics yet.").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                    }
                    InlineAdder(placeholder: "Add topic…") { store.addSyllabusTopic(subject: subject.id, name: $0) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
    }
}

#Preview {
    UniversityView().environment(AppStore()).frame(width: 1000, height: 900)
}
