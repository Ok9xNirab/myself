import SwiftUI

/// Add / edit sheet for a class, assignment, exam or syllabus subject. A record that isn't in the store yet is added on save.
struct UniversityEditorSheet: View {
    var editor: UniversityEditor
    /// The page's undo manager, so ⌘Z in the main window undoes the save.
    var undoManager: UndoManager?

    var body: some View {
        switch editor {
        case .klass(let r): ClassEditor(draft: r, undoManager: undoManager)
        case .assignment(let r): AssignmentEditor(draft: r, undoManager: undoManager)
        case .exam(let r): ExamEditor(draft: r, undoManager: undoManager)
        case .subject(let r): SubjectEditor(draft: r, undoManager: undoManager)
        }
    }
}

func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

struct SwatchPicker: View {
    @Binding var hex: UInt32
    var size: CGFloat = 16
    var swatches = Palette.swatches

    var body: some View {
        HStack(spacing: 8) {
            ForEach(swatches, id: \.self) { swatch in
                let selected = swatch == hex
                Button { hex = swatch } label: {
                    Circle()
                        .fill(Color(hex: swatch))
                        .frame(width: size, height: size)
                        .padding(3)
                        .overlay { if selected { Circle().strokeBorder(Color(hex: swatch), lineWidth: 2) } }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Chips for the courses already in use (dotted in their class colour) plus an "Other…" chip that reveals a field
/// for a new name. A name that isn't one of the chips shows in the field.
private struct CourseChips: View {
    @Environment(AppStore.self) private var store
    @Binding var text: String
    @State private var typing = false
    @FocusState private var focused: Bool

    var body: some View {
        let subjects = store.university.subjects
        let colors = Dictionary(store.university.classes.map { ($0.subject, $0.color) }, uniquingKeysWith: { a, _ in a })
        let custom = !trimmed(text).isEmpty && !subjects.contains(trimmed(text))
        if !subjects.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(subjects, id: \.self) { s in
                    let color = colors[s] ?? Page.university.tint
                    ChoiceChip(isOn: trimmed(text) == s, tint: color) {
                        text = s
                        typing = false
                    } label: {
                        Circle().fill(color).frame(width: 7, height: 7)
                        Text(s)
                    }
                }
                if !(typing || custom) {
                    ChoiceChip(isOn: false, tint: Palette.ink2, dashed: true) {
                        text = ""
                        typing = true
                        focused = true
                    } label: {
                        Image(systemName: "plus").font(.system(size: 11))
                        Text("Other")
                    }
                }
            }
        }
        if subjects.isEmpty || typing || custom {
            SheetTextField(title: "Course", prompt: "Course name", text: $text)
                .focused($focused)
        }
    }
}

// MARK: Class

private struct ClassEditor: View {
    @Environment(AppStore.self) private var store
    @State var draft: UniClass
    var undoManager: UndoManager?
    @FocusState private var focused: Bool

    private var isNew: Bool { !store.university.classes.contains { $0.id == draft.id } }
    private var canSave: Bool { !trimmed(draft.subject).isEmpty && !draft.days.isEmpty }

    private var time: Binding<Date> {
        Binding(
            get: { Day.calendar.date(bySettingHour: draft.time.hour, minute: draft.time.minute, second: 0, of: .now) ?? .now },
            set: {
                let c = Day.calendar.dateComponents([.hour, .minute], from: $0)
                draft.time = ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
            }
        )
    }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add class", canSave: canSave, onSave: save) {
            SheetIcon(systemImage: "calendar", color: draft.color)
        } header: {
            SheetTitleField(title: "Course", prompt: "Course name", text: $draft.subject, onSubmit: submit)
                .focused($focused)
            Text(summary).font(.system(size: 14)).foregroundStyle(Palette.ink2)
        } rows: {
            SheetRow(title: "Code", systemImage: "number") {
                SheetTextField(title: "Code", prompt: "CSE 2101", text: $draft.code, maxWidth: 180)
            }
            SheetRow(title: "Room", systemImage: "mappin.and.ellipse") {
                SheetTextField(title: "Room", prompt: "Room 401, Online…", text: $draft.room)
            }
            SheetRow(title: "Days", systemImage: "calendar") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        let on = draft.days.contains(day)
                        ChoiceChip(isOn: on, tint: draft.color) {
                            if on { draft.days.removeAll { $0 == day } } else { draft.days.append(day) }
                            draft.days.sort { $0.rawValue < $1.rawValue }
                        } label: {
                            Text(day.code.capitalized)
                        }
                        .accessibilityLabel(day.code.capitalized)
                    }
                }
            }
            SheetRow(title: "Time", systemImage: "clock") {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
            }
            SheetRow(title: "Colour", systemImage: "paintpalette", last: true) {
                SwatchPicker(hex: $draft.hex, size: 20)
                    .padding(.top, 4)
            }
        }
        .onAppear { focused = isNew }
    }

    /// "Tue · Thu at 9:00 AM", or a hint while no day is picked.
    private var summary: String {
        draft.days.isEmpty ? "Pick the days it meets" : "\(draft.days.map { $0.code.capitalized }.joined(separator: " \u{00B7} ")) at \(draft.time.formatted)"
    }

    private func submit() {
        guard canSave else { return }
        save()
        store.editingUniversity = nil
    }

    private func save() {
        draft.subject = trimmed(draft.subject)
        draft.code = trimmed(draft.code)
        draft.room = trimmed(draft.room)
        store.saveClass(draft, undoManager: undoManager)
    }
}

// MARK: Assignment

private struct AssignmentEditor: View {
    @Environment(AppStore.self) private var store
    @State var draft: Assignment
    var undoManager: UndoManager?
    @FocusState private var focused: Bool

    private var isNew: Bool { !store.university.assignments.contains { $0.id == draft.id } }
    private var canSave: Bool { !trimmed(draft.title).isEmpty }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add assignment", canSave: canSave, onSave: save) {
            SheetCheckbox(isOn: draft.done) { draft.done.toggle() }
                .padding(.top, 6)
                .disabled(isNew)
        } header: {
            SheetTitleField(title: "Title", prompt: "What's due?", text: $draft.title, onSubmit: submit)
                .focused($focused)
        } rows: {
            SheetRow(title: "Course", systemImage: "graduationcap") {
                CourseChips(text: $draft.subject)
            }
            SheetRow(title: "Due", systemImage: "calendar") {
                DateChips(date: $draft.due, options: [("Today", 0), ("Tomorrow", 1), ("In a week", 7)])
            }
            SheetRow(title: "Priority", systemImage: "flag", last: true) {
                Badge(text: "High \u{00B7} locked", systemImage: "flag.fill", color: Palette.red)
            }
        }
        .onAppear { focused = isNew }
    }

    private func submit() {
        guard canSave else { return }
        save()
        store.editingUniversity = nil
    }

    private func save() {
        draft.title = trimmed(draft.title)
        draft.subject = trimmed(draft.subject)
        store.saveAssignment(draft, undoManager: undoManager)
    }
}

// MARK: Exam

private struct ExamEditor: View {
    @Environment(AppStore.self) private var store
    @State var draft: Exam
    var undoManager: UndoManager?

    private var isNew: Bool { !store.university.exams.contains { $0.id == draft.id } }
    private var canSave: Bool { !trimmed(draft.subject).isEmpty }

    private var date: Binding<Date?> {
        Binding(get: { draft.date }, set: { if let d = $0 { draft.date = Day.calendar.startOfDay(for: d) } })
    }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add exam", canSave: canSave, onSave: save) {
            SheetIcon(systemImage: "target", color: draft.kind.color)
        } header: {
            Text(isNew ? "New exam" : "\(draft.kind.rawValue) exam")
                .font(.system(size: 22, weight: .bold))
            Text(countdown).font(.system(size: 14)).foregroundStyle(Palette.ink2)
        } rows: {
            SheetRow(title: "Course", systemImage: "graduationcap") {
                CourseChips(text: $draft.subject)
            }
            SheetRow(title: "Type", systemImage: "list.bullet") {
                TintedTabs(options: ExamKind.allCases, selection: $draft.kind, title: \.rawValue,
                           systemImage: { _ in "circle.fill" }, color: \.color)
            }
            SheetRow(title: "Date", systemImage: "calendar") {
                DateChips(date: date, options: [("Tomorrow", 1), ("In a week", 7), ("In 2 weeks", 14)], optional: false)
            }
            SheetRow(title: "Prep", systemImage: "gauge.with.needle", last: true) {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { Double(draft.prep) }, set: { draft.prep = Int($0.rounded()) }), in: 0...100, step: 5)
                        .tint(prepColor)
                        .frame(maxWidth: 260)
                    Text("\(draft.prep)%").font(.system(size: 13.5, weight: .bold)).monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }

    private var prepColor: Color { draft.prep >= 70 ? Palette.green : draft.prep >= 40 ? Palette.amber : Palette.red }

    /// "Sun 29 Nov · in 3 days"
    private var countdown: String {
        let n = Day.fromToday(draft.date) ?? 0
        let when = n < 0 ? "\(-n)d ago" : n == 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days"
        return "\(draft.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \u{00B7} \(when)"
    }

    private func save() {
        draft.subject = trimmed(draft.subject)
        store.saveExam(draft, undoManager: undoManager)
    }
}

// MARK: Syllabus course

private struct SubjectEditor: View {
    @Environment(AppStore.self) private var store
    @State var draft: SyllabusSubject
    var undoManager: UndoManager?
    @FocusState private var focused: Bool

    private var isNew: Bool { !store.university.syllabus.contains { $0.id == draft.id } }
    private var color: Color {
        store.university.classes.first { $0.subject == trimmed(draft.subject) }?.color ?? Page.university.tint
    }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add course", canSave: !trimmed(draft.subject).isEmpty, onSave: save) {
            SheetIcon(systemImage: "book.closed", color: color)
        } header: {
            SheetTitleField(title: "Course", prompt: "Course name", text: $draft.subject)
                .focused($focused)
            let done = draft.topics.filter(\.done).count
            Text(draft.topics.isEmpty ? "Add the topics it covers" : "\(done) of \(draft.topics.count) topics done")
                .font(.system(size: 14)).foregroundStyle(Palette.ink2)
        } rows: {
            SheetRow(title: "Topics", systemImage: "checklist", last: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach($draft.topics) { $topic in
                        HStack(spacing: 10) {
                            SheetCheckbox(isOn: topic.done) { topic.done.toggle() }
                            TextField("Topic", text: $topic.name, prompt: Text("Topic"))
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .font(.system(size: 13.5))
                                .strikethrough(topic.done)
                                .foregroundStyle(topic.done ? Palette.ink2 : .primary)
                            Button { draft.topics.removeAll { $0.id == topic.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink3)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove topic")
                        }
                        .padding(.vertical, 3)
                    }
                    InlineAdder(placeholder: "Add topic…") { name in
                        let name = trimmed(name)
                        if !name.isEmpty { draft.topics.append(SyllabusTopic(name: name)) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear { focused = isNew }
    }

    private func save() {
        draft.subject = trimmed(draft.subject)
        draft.topics = draft.topics.compactMap { var t = $0; t.name = trimmed(t.name); return t.name.isEmpty ? nil : t }
        store.saveSyllabusSubject(draft, undoManager: undoManager)
    }
}

#Preview {
    UniversityEditorSheet(editor: .klass(UniClass(subject: "", code: "", days: [], time: ClockTime(hour: 9, minute: 0), room: "", hex: 0x2B7BBF)),
                          undoManager: nil)
        .environment(AppStore())
}
