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

/// Shared sheet chrome: grouped form, title, Cancel and Add/Save.
private struct EditorForm<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var isNew: Bool
    var canSave: Bool
    var onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            Form { content }
                .formStyle(.grouped)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isNew ? "Add" : "Save") {
                            onSave()
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
                }
        }
        #if os(macOS)
        .frame(width: 460)
        #endif
    }
}

private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

/// Text field for a subject name with a menu of the subjects already in use.
private struct SubjectField: View {
    @Environment(AppStore.self) private var store
    @Binding var text: String

    var body: some View {
        let subjects = store.university.subjects
        HStack {
            TextField("Subject", text: $text, prompt: Text("Subject"))
            if !subjects.isEmpty {
                Menu {
                    ForEach(subjects, id: \.self) { s in Button(s) { text = s } }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a subject")
            }
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
        EditorForm(title: isNew ? "New Class" : "Edit Class", isNew: isNew,
                   canSave: !trimmed(draft.subject).isEmpty && !draft.days.isEmpty, onSave: save) {
            Section {
                TextField("Subject", text: $draft.subject, prompt: Text("Data Structures & Algorithms"))
                    .focused($focused)
                TextField("Code", text: $draft.code, prompt: Text("CSE 2101"))
                TextField("Room", text: $draft.room, prompt: Text("Room 401"))
            }
            Section {
                LabeledContent("Days") {
                    HStack(spacing: 4) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            let on = draft.days.contains(day)
                            Button {
                                if on { draft.days.removeAll { $0 == day } } else { draft.days.append(day) }
                                draft.days.sort { $0.rawValue < $1.rawValue }
                            } label: {
                                Text(day.initial)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(on ? Color.white : Palette.ink2)
                                    .background(on ? draft.color : Palette.surface2, in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(day.code.capitalized)
                            .accessibilityLabel(day.code.capitalized)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            Section("Colour") {
                SwatchPicker(hex: $draft.hex)
            }
        }
        .onAppear { focused = isNew }
    }

    private func save() {
        draft.subject = trimmed(draft.subject)
        draft.code = trimmed(draft.code)
        draft.room = trimmed(draft.room)
        store.saveClass(draft, undoManager: undoManager)
    }
}

private struct SwatchPicker: View {
    @Binding var hex: UInt32

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Palette.swatches, id: \.self) { swatch in
                let selected = swatch == hex
                Button { hex = swatch } label: {
                    Circle()
                        .fill(Color(hex: swatch))
                        .frame(width: 16, height: 16)
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

// MARK: Assignment

private struct AssignmentEditor: View {
    @Environment(AppStore.self) private var store
    @State var draft: Assignment
    var undoManager: UndoManager?
    @FocusState private var focused: Bool

    private var isNew: Bool { !store.university.assignments.contains { $0.id == draft.id } }

    private var hasDue: Binding<Bool> {
        Binding(get: { draft.due != nil }, set: { draft.due = $0 ? Day.offset(7) : nil })
    }

    private var due: Binding<Date> {
        Binding(get: { draft.due ?? Day.offset(0) }, set: { draft.due = Day.calendar.startOfDay(for: $0) })
    }

    var body: some View {
        EditorForm(title: isNew ? "New Assignment" : "Edit Assignment", isNew: isNew,
                   canSave: !trimmed(draft.title).isEmpty, onSave: save) {
            Section {
                TextField("Title", text: $draft.title, prompt: Text("What's due?"))
                    .focused($focused)
                SubjectField(text: $draft.subject)
            }
            Section {
                LabeledContent("Priority") { PriorityBadge(priority: .high, locked: true) }
                Toggle("Due date", isOn: hasDue.animation())
                if draft.due != nil {
                    DatePicker("Date", selection: due, displayedComponents: .date)
                }
            }
        }
        .onAppear { focused = isNew }
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

    private var date: Binding<Date> {
        Binding(get: { draft.date }, set: { draft.date = Day.calendar.startOfDay(for: $0) })
    }

    private var prep: Binding<Double> {
        Binding(get: { Double(draft.prep) }, set: { draft.prep = Int($0.rounded()) })
    }

    var body: some View {
        EditorForm(title: isNew ? "New Exam" : "Edit Exam", isNew: isNew,
                   canSave: !trimmed(draft.subject).isEmpty, onSave: save) {
            Section {
                SubjectField(text: $draft.subject)
                Picker("Type", selection: $draft.kind) {
                    ForEach(ExamKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Date", selection: date, displayedComponents: .date)
            }
            Section {
                LabeledContent("Prep") {
                    HStack {
                        Slider(value: prep, in: 0...100, step: 5)
                        Text("\(draft.prep)%").monospacedDigit().foregroundStyle(Palette.ink2).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func save() {
        draft.subject = trimmed(draft.subject)
        store.saveExam(draft, undoManager: undoManager)
    }
}

// MARK: Syllabus subject

private struct SubjectEditor: View {
    @Environment(AppStore.self) private var store
    @State var draft: SyllabusSubject
    var undoManager: UndoManager?

    private var isNew: Bool { !store.university.syllabus.contains { $0.id == draft.id } }

    var body: some View {
        EditorForm(title: isNew ? "New Subject" : "Edit Subject", isNew: isNew,
                   canSave: !trimmed(draft.subject).isEmpty, onSave: save) {
            Section {
                SubjectField(text: $draft.subject)
            }
            Section("Topics") {
                ForEach($draft.topics) { $topic in
                    HStack(spacing: 10) {
                        CheckCircle(isOn: topic.done) { topic.done.toggle() }
                        TextField("Topic", text: $topic.name, prompt: Text("Topic"))
                            .labelsHidden()
                        Button { draft.topics.removeAll { $0.id == topic.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Palette.ink3)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove topic")
                    }
                }
                .onMove { draft.topics.move(fromOffsets: $0, toOffset: $1) }
                InlineAdder(placeholder: "Add topic…") { name in
                    let name = trimmed(name)
                    if !name.isEmpty { draft.topics.append(SyllabusTopic(name: name)) }
                }
            }
        }
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
