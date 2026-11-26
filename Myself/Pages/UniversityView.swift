import SwiftUI

/// The v2 "University space": header, four tiles, the next-exam alert, classes and assignments beside the exam
/// countdown and notes, then the syllabus grid.
struct UniversityView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var openSyllabus: ID?

    var body: some View {
        let u = store.university
        let openAssignments = u.assignments.filter { !$0.done }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let upcomingExams = u.exams.filter { (Day.fromToday($0.date) ?? -1) >= 0 }.sorted { $0.date < $1.date }

        @Bindable var store = store
        return PageScroll(maxWidth: 1080) {
            SpaceHeader(page: .university,
                        detail: u.classes.isEmpty ? nil : "\(Page.university.subtitle) \u{00B7} \(courses(u.classes.count))")
            StatGrid {
                StatTile(systemImage: "calendar", label: "Classes / week", value: "\(u.classes.reduce(0) { $0 + $1.days.count })",
                         foot: courses(u.classes.count), color: Palette.blue)
                StatTile(systemImage: "book.closed", label: "Syllabus done", value: "\(u.syllabusPercent)%",
                         foot: "across all courses", color: Palette.green)
                StatTile(systemImage: "flag", label: "Assignments due", value: "\(openAssignments.count)",
                         foot: "all high priority", color: Palette.red)
                StatTile(systemImage: "target", label: "Next exam",
                         value: upcomingExams.first.flatMap { Day.fromToday($0.date) }.map { "\($0)d" } ?? "—",
                         foot: upcomingExams.first.map { "\($0.subject) \u{00B7} \($0.kind.rawValue)" } ?? "none scheduled",
                         color: Color.dynamic(light: 0xD98A00, dark: 0xFFC14D))
            }

            if let exam = upcomingExams.first, let days = Day.fromToday(exam.date), days <= 7 {
                ExamAlert(exam: exam, days: days)
            }

            AdaptiveColumns(ratio: 1.2) {
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

    private func courses(_ n: Int) -> String { "\(n) \(n == 1 ? "course" : "courses")" }

    // MARK: Classes

    /// The next six classes: the rest of today, then the coming days.
    private var sessions: [AppStore.ClassSession] {
        let calendar = Day.calendar
        let now = Date.now
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var sessions: [AppStore.ClassSession] = []
        for offset in 0..<14 where sessions.count < 6 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = Weekday.of(day)
            let classes = store.university.classes
                .filter { $0.days.contains(weekday) && (offset > 0 || $0.time.hour * 60 + $0.time.minute > minute) }
                .sorted { $0.time < $1.time }
            sessions += classes.prefix(6 - sessions.count).map { AppStore.ClassSession(uniClass: $0, dayOffset: offset) }
        }
        return sessions
    }

    private var classesCard: some View {
        let classes = store.university.classes
        return Card(title: "Upcoming classes", systemImage: "calendar", tint: Palette.blue) {
            Spacer()
            GhostButton(title: "Add class", systemImage: "plus", action: store.newClass)
        } content: {
            if classes.isEmpty {
                EmptyStateView(systemImage: "calendar", title: "No classes yet", subtitle: "Add a class with its weekdays and time to see upcoming sessions.")
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions, id: \.id) { SessionRow(session: $0) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(classes) { ClassPill(klass: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .overlay(alignment: .top) { Hairline() }
                .padding(.bottom, -6)
            }
        }
    }

    // MARK: Assignments

    private func assignmentsCard(open: [Assignment]) -> some View {
        let done = store.university.assignments.filter(\.done)
        return Card(title: "Assignments", systemImage: "flag", tint: Palette.red) {
            CountText(value: open.count)
            Spacer()
            GhostButton(title: "Add", systemImage: "plus", action: store.newAssignment)
        } content: {
            if open.isEmpty && done.isEmpty {
                EmptyStateView(systemImage: "checkmark", title: "No assignments", subtitle: "Add one and it'll be flagged high priority.")
            } else {
                VStack(spacing: 0) {
                    ForEach(open + done) { AssignmentRow(assignment: $0) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            }
        }
    }

    // MARK: Exams

    private var examsCard: some View {
        let exams = store.university.exams.sorted { a, b in
            let pa = (Day.fromToday(a.date) ?? 0) < 0, pb = (Day.fromToday(b.date) ?? 0) < 0
            return pa == pb ? (pa ? a.date > b.date : a.date < b.date) : !pa
        }
        return Card(title: "Exam countdown", systemImage: "target", tint: Color.dynamic(light: 0xD98A00, dark: 0xFFC14D)) {
            Spacer()
            GhostButton(title: "Add exam", systemImage: "plus", action: store.newExam)
        } content: {
            if exams.isEmpty {
                EmptyStateView(systemImage: "target", title: "No exams scheduled", subtitle: "Add a Class Test, Midterm or Final.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(exams.enumerated()), id: \.element.id) { i, e in
                        ExamRow(exam: e)
                            .overlay(alignment: .top) { if i > 0 { Hairline() } }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
            }
        }
    }

    // MARK: Notes

    private var notesCard: some View {
        Card(title: "Notes", systemImage: "doc.text", tint: Palette.violet) {
            Spacer()
            Text("autosaved").font(.system(size: 11.5)).foregroundStyle(Palette.ink2)
        } content: {
            SemesterNotes()
        }
    }

    // MARK: Syllabus

    private var syllabusCard: some View {
        let u = store.university
        let colors = Dictionary(u.classes.map { ($0.subject, $0.color) }, uniquingKeysWith: { a, _ in a })
        return Card(title: "Syllabus completion", systemImage: "book.closed", tint: Palette.green) {
            Spacer()
            if !u.syllabus.isEmpty {
                Text("\(u.syllabusPercent)% overall").font(.system(size: 11.5)).foregroundStyle(Palette.ink2)
                Spacer()
            }
            GhostButton(title: "Add course", systemImage: "plus", action: store.newSyllabusSubject)
        } content: {
            if u.syllabus.isEmpty {
                EmptyStateView(systemImage: "book.closed", title: "No courses yet", subtitle: "Add a course and tick off its topics as you cover them.")
            } else {
                SyllabusGrid(subjects: u.syllabus, colors: colors, open: $openSyllabus)
            }
        }
    }
}

// MARK: Pieces

private enum UniTone {
    static let soft = Color.primary.opacity(0.045)
    static let blueText = Color.dynamic(light: 0x1D5AD6, dark: 0x7AA6FF)
    static let redText = Color.dynamic(light: 0xC62828, dark: 0xFF7B7B)
    static let orangeText = Color.dynamic(light: 0xB25D00, dark: 0xFFAE5C)
    static let orange = Color.dynamic(light: 0xF5871F, dark: 0xFFAE5C)
}

private struct Hairline: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5) }
}

/// A design `.chip`: small semibold text on a wash of its colour.
private struct Chip: View {
    var text: String
    var systemImage: String?
    var color: Color
    var fill: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(fill ?? color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }
}

/// The design's square checkbox (`.cb`), filled with `color` when on.
private struct SquareCheckbox: View {
    var isOn: Bool
    var color: Color = .accentColor
    var size: CGFloat = 18
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(isOn ? color : .clear)
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(isOn ? color : Palette.ink3, lineWidth: 1.6)
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A row that highlights with a rounded soft fill on hover.
private struct HoverRow<Content: View>: View {
    var radius: CGFloat = 12
    var padding: CGFloat = 8
    @ViewBuilder var content: Content
    @State private var hover = HoverState()

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background { HoverFill(hover: hover, color: UniTone.soft).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
            .contentShape(Rectangle())
            .onHover { hover.isOn = $0 }
    }
}

/// "⚠ Electronic Devices Lab — final exam · Wed 4 Nov, 6:00 PM · lab report due the same day   in 2 days ›"
private struct ExamAlert: View {
    @Environment(AppStore.self) private var store
    var exam: Exam
    var days: Int
    @State private var hover = HoverState()

    var body: some View {
        Button { store.editingUniversity = .exam(exam) } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(UniTone.redText)
                (Text("\(exam.subject) \u{2014} \(exam.kind.rawValue.lowercased()) exam").fontWeight(.bold)
                    + Text(" \u{00B7} \(detail)").foregroundStyle(Palette.ink2))
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Chip(text: relative, color: UniTone.redText, fill: Palette.red.opacity(0.12))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(alertFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.red.opacity(0.25), lineWidth: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .help("Edit exam")
    }

    private var alertFill: some ShapeStyle { Palette.red.opacity(hover.isOn ? 0.14 : 0.1) }

    private var relative: String { days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days" }

    /// "Wed 4 Nov, 6:00 PM · lab report due the same day": the class's time when the exam's course has one.
    private var detail: String {
        var date = exam.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let weekday = Weekday.of(exam.date)
        if let klass = store.university.classes.first(where: { $0.subject == exam.subject && $0.days.contains(weekday) }) {
            date += ", \(klass.time.formatted)"
        }
        let sameDay = store.university.assignments.filter { a in
            !a.done && a.due.map { Day.calendar.isDate($0, inSameDayAs: exam.date) } == true
        }
        switch sameDay.count {
        case 0: return date
        case 1: return "\(date) \u{00B7} \(sameDay[0].title.lowercased()) due the same day"
        default: return "\(date) \u{00B7} \(sameDay.count) assignments due the same day"
        }
    }
}

private struct SessionRow: View {
    @Environment(AppStore.self) private var store
    var session: AppStore.ClassSession

    var body: some View {
        let c = session.uniClass
        let date = Day.offset(session.dayOffset)
        HoverRow {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(Weekday.of(date).code).font(.system(size: 9.5, weight: .heavy)).kerning(0.6).foregroundStyle(c.color)
                    Text("\(Day.calendar.component(.day, from: date))").font(.system(size: 18, weight: .heavy)).monospacedDigit()
                }
                .frame(width: 44, height: 46)
                .background(c.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .top) {
                    // The design's `inset 0 3px 0`: a bar along the top edge, inside the rounded tile.
                    c.color.frame(height: 3).frame(maxHeight: .infinity, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.subject).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        if !c.code.isEmpty {
                            Text(c.code)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(c.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(c.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        Label(c.time.formatted, systemImage: "clock").labelStyle(MetaLabelStyle())
                        if !c.room.isEmpty {
                            Circle().fill(Palette.ink3).frame(width: 3, height: 3)
                            Label(c.room, systemImage: "mappin.and.ellipse").labelStyle(MetaLabelStyle())
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(relative)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(session.dayOffset <= 1 ? UniTone.blueText : Palette.ink2)
                    .fixedSize()
            }
        }
        .onTapGesture(count: 2) { store.editingUniversity = .klass(c) }
        .contextMenu {
            Button("Edit Class…", systemImage: "pencil") { store.editingUniversity = .klass(c) }
        }
    }

    private var relative: String {
        switch session.dayOffset {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "in \(session.dayOffset) days"
        }
    }
}

private struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10.5))
            configuration.title
        }
    }
}

/// A course pill under the sessions: dot, name and weekdays; click to edit.
private struct ClassPill: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var klass: UniClass

    var body: some View {
        let c = klass
        Button { store.editingUniversity = .klass(c) } label: {
            HStack(spacing: 6) {
                Circle().fill(c.color).frame(width: 7, height: 7)
                Text(c.subject).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Text(c.days.sorted { $0.rawValue < $1.rawValue }.map(\.code).joined(separator: " \u{00B7} "))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(c.color.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(c.color.opacity(0.3), lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Edit class")
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { store.editingUniversity = .klass(c) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteClass(c.id, undoManager: undoManager) }
            }
        }
    }
}

private struct AssignmentRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var assignment: Assignment

    var body: some View {
        let a = assignment
        HoverRow(radius: 10) {
            HStack(alignment: .top, spacing: 11) {
                SquareCheckbox(isOn: a.done, action: toggle).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(a.title)
                        .font(.system(size: 14))
                        .strikethrough(a.done)
                        .foregroundStyle(a.done ? Palette.ink3 : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout {
                        Chip(text: "High", systemImage: "flag", color: UniTone.redText, fill: Palette.red.opacity(0.12))
                        if !a.subject.isEmpty { Chip(text: a.subject, color: Palette.ink2, fill: UniTone.soft) }
                        if let due = a.due { dueChip(due, done: a.done) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Button(a.done ? "Mark as Not Done" : "Mark as Done", systemImage: a.done ? "circle" : "checkmark.circle", action: toggle)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteAssignment(a.id, undoManager: undoManager) }
            }
        }
    }

    /// "Sun 1 Nov · overdue" in red, the next three days in orange, later dates in grey.
    private func dueChip(_ due: Date, done: Bool) -> Chip {
        let n = Day.fromToday(due) ?? 0
        let text = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if done { return Chip(text: text, color: Palette.ink2, fill: UniTone.soft) }
        if n < 0 { return Chip(text: "\(text) \u{00B7} overdue", color: UniTone.redText, fill: Palette.red.opacity(0.12)) }
        if n <= 3 { return Chip(text: n == 0 ? "\(text) \u{00B7} today" : text, color: UniTone.orangeText, fill: UniTone.orange.opacity(0.14)) }
        return Chip(text: text, color: Palette.ink2, fill: UniTone.soft)
    }

    private func edit() { store.editingUniversity = .assignment(assignment) }

    private func toggle() {
        withAnimation { store.toggleAssignment(assignment.id, undoManager: undoManager) }
    }
}

private struct ExamRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var exam: Exam

    var body: some View {
        let e = exam
        let d = Day.fromToday(e.date) ?? 0
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(d < 0 ? "✓" : "\(d)").font(.system(size: 24, weight: .heavy)).kerning(-0.7).monospacedDigit()
                Text(d < 0 ? "done" : d == 1 ? "day" : "days").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.ink2)
            }
            .foregroundStyle(d < 0 ? Palette.ink2 : d <= 5 ? UniTone.redText : d <= 10 ? UniTone.orangeText : .primary)
            .frame(width: 56)
            .padding(.vertical, 6)
            .background(UniTone.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(e.subject).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Chip(text: e.kind.rawValue, color: e.kind.color)
                    Text(e.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 12)).foregroundStyle(Palette.ink2)
                }
                .padding(.top, 4)
                HStack(spacing: 8) {
                    Text("Prep").font(.system(size: 11.5)).foregroundStyle(Palette.ink2)
                    ProgressBar(value: Double(e.prep), color: prepColor, height: 5)
                    Text("\(e.prep)%").font(.system(size: 11.5, weight: .bold)).monospacedDigit().frame(minWidth: 30, alignment: .trailing)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .opacity(d < 0 ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Menu("Prep") {
                ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                    Button("\(value)%") { setPrep(value) }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteExam(exam.id, undoManager: undoManager) }
            }
        }
    }

    private var prepColor: Color { exam.prep >= 70 ? Palette.green : exam.prep >= 40 ? UniTone.orange : Palette.red }

    private func edit() { store.editingUniversity = .exam(exam) }

    private func setPrep(_ value: Int) {
        var e = exam
        e.prep = value
        withAnimation { store.saveExam(e, undoManager: undoManager) }
    }
}

/// The semester notes field (`.u-notes`): a soft rounded well with a violet ring while editing.
private struct SemesterNotes: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: Binding(get: { store.universityNotes.text }, set: store.editUniversityNotes))
            .font(.system(size: 13.5))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(minHeight: 150)
            .background(UniTone.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.violet.opacity(focused ? 0.35 : 0), lineWidth: 2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }
}

// MARK: Syllabus

private struct SyllabusGrid: View {
    var subjects: [SyllabusSubject]
    var colors: [String: Color]
    @Binding var open: ID?
    @Environment(\.pageWidth) private var width

    var body: some View {
        let count = width >= 900 ? 3 : width >= 600 ? 2 : 1
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count), alignment: .leading, spacing: 10) {
            ForEach(subjects) { s in
                SyllabusCell(subject: s, color: colors[s.subject] ?? Page.university.tint, isOpen: open == s.id) {
                    withAnimation(.snappy) { open = open == s.id ? nil : s.id }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

private struct SyllabusCell: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var subject: SyllabusSubject
    var color: Color
    var isOpen: Bool
    var onToggleOpen: () -> Void

    var body: some View {
        let done = subject.topics.filter(\.done).count
        let pct = subject.percent
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleOpen) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(subject.subject).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                        Text("\(done) of \(subject.topics.count) topics").font(.system(size: 11.5)).foregroundStyle(Palette.ink2)
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule().fill(color).frame(width: geo.size.width * Double(pct) / 100)
                                }
                            }
                            .frame(height: 5)
                            .padding(.top, 7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SyllabusRing(percent: pct, color: color)
                }
                .padding(.leading, 14)
                .padding([.trailing, .vertical], 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(subject.topics) { t in
                        TopicRow(subject: subject.id, topic: t, color: color)
                    }
                    InlineAdder(placeholder: "Add topic…") { store.addSyllabusTopic(subject: subject.id, name: $0) }
                        .padding(.horizontal, 2)
                        .foregroundStyle(Palette.ink2)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isOpen ? AnyShapeStyle(color.opacity(0.07)) : AnyShapeStyle(UniTone.soft))
        }
        .overlay {
            if isOpen {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            }
        }
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { store.editingUniversity = .subject(subject) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteSyllabusSubject(subject.id, undoManager: undoManager) }
            }
        }
    }
}

/// The percentage in a thick ring (`.u-ring`).
private struct SyllabusRing: View {
    var percent: Int
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5.5)
            Circle()
                .trim(from: 0, to: Double(percent) / 100)
                .stroke(color, lineWidth: 5.5)
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: percent)
            Text("\(percent)%").font(.system(size: 11, weight: .heavy)).monospacedDigit()
        }
        .padding(2.75)
        .frame(width: 44, height: 44)
        .background(Palette.surface, in: Circle())
    }
}

private struct TopicRow: View {
    @Environment(AppStore.self) private var store
    var subject: ID
    var topic: SyllabusTopic
    var color: Color

    var body: some View {
        HoverRow(radius: 8, padding: 6) {
            HStack(spacing: 9) {
                SquareCheckbox(isOn: topic.done, color: color, size: 16, action: toggle)
                Text(topic.name)
                    .font(.system(size: 13))
                    .strikethrough(topic.done)
                    .foregroundStyle(topic.done ? Palette.ink2 : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button(topic.done ? "Mark as Not Done" : "Mark as Done", systemImage: topic.done ? "square" : "checkmark.square", action: toggle)
            Divider()
            Button("Delete Topic", systemImage: "trash", role: .destructive) {
                store.deleteSyllabusTopic(subject: subject, topic: topic.id)
            }
        }
    }

    private func toggle() { store.toggleSyllabusTopic(subject: subject, topic: topic.id) }
}

#Preview {
    UniversityView().environment(AppStore()).frame(width: 1100, height: 1000)
}
