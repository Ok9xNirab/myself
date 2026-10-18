import SwiftUI

struct UniversityView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var openSyllabus: ID?

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

        @Bindable var store = store
        return PageScroll {
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
        .sheet(item: $store.editingUniversity) { UniversityEditorSheet(editor: $0, undoManager: undoManager) }
    }

    // MARK: Cards

    private var classesCard: some View {
        Card(title: "Upcoming classes", systemImage: "calendar") {
            Spacer()
            GhostButton(title: "Add class", systemImage: "plus", action: store.newClass)
        } content: {
            if store.university.classes.isEmpty {
                EmptyStateView(systemImage: "calendar", title: "No classes yet", subtitle: "Add a class with its weekdays and time to see upcoming sessions.")
            }
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
                        Text(c.days.sorted { $0.rawValue < $1.rawValue }.map(\.code).joined(separator: "·"))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink3)
                        Button { store.editingUniversity = .klass(c) } label: { Image(systemName: "pencil") }
                            .help("Edit class")
                        Button { withAnimation { store.deleteClass(c.id, undoManager: undoManager) } } label: { Image(systemName: "xmark") }
                            .help("Delete class")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.ink3)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(c.color.opacity(0.4), lineWidth: 0.5))
                    .contentShape(Capsule())
                    .onTapGesture(count: 2) { store.editingUniversity = .klass(c) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, store.university.classes.isEmpty ? 0 : 12)
        }
    }

    private func assignmentsCard(open: [Assignment]) -> some View {
        let done = store.university.assignments.filter(\.done)
        return Card(title: "Assignments", systemImage: "flag", tint: Palette.red) {
            CountText(value: open.count)
            Spacer()
            GhostButton(title: "Add", systemImage: "plus", action: store.newAssignment)
        } content: {
            if open.isEmpty && done.isEmpty {
                EmptyStateView(systemImage: "checkmark", title: "No assignments", subtitle: "Add one and it'll be flagged high priority.")
            }
            ForEach(open) { a in
                AssignmentRow(assignment: a)
            }
            ForEach(done) { a in
                AssignmentRow(assignment: a)
            }
        }
    }

    private var examsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "target").foregroundStyle(Palette.amber)
                Text("Exam countdown").font(.system(size: 15, weight: .semibold))
                Spacer()
                GhostButton(title: "Add exam", systemImage: "plus", action: store.newExam)
            }
            if store.university.exams.isEmpty {
                EmptyStateView(systemImage: "target", title: "No exams scheduled", subtitle: "Add a Class Test, Midterm or Final.")
            }
            ForEach(store.university.exams) { e in
                ExamRow(exam: e)
            }
        }
        .padding(16)
        .cardBackground()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(Palette.violet)
                Text("Notes").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("autosaved").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
            }
            TextEditor(text: Binding(get: { store.universityNotes.text }, set: store.editUniversityNotes))
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
            GhostButton(title: "Add subject", systemImage: "plus", action: store.newSyllabusSubject)
        } content: {
            if u.syllabus.isEmpty {
                EmptyStateView(systemImage: "book.closed", title: "No subjects yet", subtitle: "Add a subject and tick off its topics as you cover them.")
            }
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
    @Environment(\.undoManager) private var undoManager
    @State private var hovering = false
    var subject: SyllabusSubject
    var isOpen: Bool
    var onToggleOpen: () -> Void

    var body: some View {
        let pct = subject.percent
        let color = pct == 100 ? Palette.green : Color.accentColor
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(subject.subject).font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.ink3)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                        Spacer(minLength: 0)
                        RowActions(isHovering: hovering, onEdit: edit, onDelete: delete)
                            .frame(height: 16)
                    }
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
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func edit() { store.editingUniversity = .subject(subject) }

    private func delete() {
        withAnimation { store.deleteSyllabusSubject(subject.id, undoManager: undoManager) }
    }
}

private struct AssignmentRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var hovering = false
    var assignment: Assignment

    var body: some View {
        let a = assignment
        ListRow {
            HStack(alignment: a.done ? .center : .top, spacing: 10) {
                CheckCircle(isOn: a.done) { withAnimation { store.toggleAssignment(a.id, undoManager: undoManager) } }
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.title).font(.system(size: 13, weight: .medium)).strikethrough(a.done)
                    if !a.done {
                        FlowLayout {
                            PriorityBadge(priority: .high, locked: true)
                            if !a.subject.isEmpty { Badge(text: a.subject) }
                            DueBadge(date: a.due)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowActions(isHovering: hovering, onEdit: edit, onDelete: delete)
            }
            .opacity(a.done ? 0.55 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Button(a.done ? "Mark as Not Done" : "Mark as Done", systemImage: a.done ? "circle" : "checkmark.circle") {
                withAnimation { store.toggleAssignment(a.id, undoManager: undoManager) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func edit() { store.editingUniversity = .assignment(assignment) }

    private func delete() {
        withAnimation { store.deleteAssignment(assignment.id, undoManager: undoManager) }
    }
}

private struct ExamRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var hovering = false
    var exam: Exam

    var body: some View {
        let e = exam
        let d = Day.fromToday(e.date) ?? 0
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(d < 0 ? "✓" : "\(d)").font(.numeral(26))
                Text(d < 0 ? "done" : "days").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink3)
            }
            .foregroundStyle(d <= 5 ? Palette.red : d <= 10 ? Palette.amber : .primary)
            .frame(width: 54)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(e.subject).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    RowActions(isHovering: hovering, onEdit: edit, onDelete: delete)
                        .frame(height: 16)
                }
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
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Menu("Prep") {
                ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                    Button("\(value)%") { setPrep(value) }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func edit() { store.editingUniversity = .exam(exam) }

    private func setPrep(_ value: Int) {
        var e = exam
        e.prep = value
        withAnimation { store.saveExam(e, undoManager: undoManager) }
    }

    private func delete() {
        withAnimation { store.deleteExam(exam.id, undoManager: undoManager) }
    }
}

#Preview {
    UniversityView().environment(AppStore()).frame(width: 1000, height: 900)
}
