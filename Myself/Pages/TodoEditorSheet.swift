import SwiftUI

/// Add / edit sheet for a todo. A todo that isn't in the store yet is added on save.
struct TodoEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The page's undo manager, so ⌘Z in the main window undoes the save.
    var undoManager: UndoManager?
    @State private var draft: Todo
    @State private var hasDue: Bool
    @FocusState private var titleFocused: Bool

    init(todo: Todo, undoManager: UndoManager?) {
        self.undoManager = undoManager
        _draft = State(initialValue: todo)
        _hasDue = State(initialValue: todo.due != nil)
    }

    private var isNew: Bool { !store.todos.contains { $0.id == draft.id } }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var due: Binding<Date> {
        Binding(get: { draft.due ?? Day.offset(0) }, set: { draft.due = Day.calendar.startOfDay(for: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, prompt: Text("What needs doing?"))
                        .focused($titleFocused)
                    TextField("Notes", text: $draft.desc, prompt: Text("Notes (optional)"), axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(Priority.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Date", selection: due, displayedComponents: .date)
                    }
                }

                Section("Labels") {
                    LabelPicker(scope: .todo, selection: $draft.labelIDs)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Todo" : "Edit Todo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460)
        .frame(minHeight: 420)
        #endif
        .onAppear { titleFocused = isNew }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        draft.title = trimmedTitle
        draft.desc = draft.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.due = hasDue ? (draft.due ?? Day.offset(0)) : nil
        let known = Set(store.labels.map(\.id))
        draft.labelIDs.removeAll { !known.contains($0) }
        store.saveTodo(draft, undoManager: undoManager)
        dismiss()
    }
}

/// One set of labels (TODO or Product Dev) as chips to switch on and off, with New Label and, in a chip's
/// context menu, Delete Label. Used by the todo and card sheets.
struct LabelPicker: View {
    var scope: TaskLabel.Scope
    @Binding var selection: [ID]

    @Environment(AppStore.self) private var store
    @State private var addingLabel = false
    @State private var labelName = ""
    @State private var labelHex = Palette.swatches[0]
    @FocusState private var labelFocused: Bool

    private var labels: [TaskLabel] { scope == .product ? store.productLabels : store.labels }

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(labels) { label in
                LabelToggle(label: label, isOn: selection.contains(label.id)) { toggle(label.id) }
                    .contextMenu {
                        Button("Delete Label", systemImage: "trash", role: .destructive) {
                            selection.removeAll { $0 == label.id }
                            store.deleteLabel(label.id)
                        }
                    }
            }
            if !addingLabel {
                Button("New Label", systemImage: "plus") { withAnimation { addingLabel = true } }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderless)
            }
        }
        if addingLabel { newLabelRow }
    }

    /// Name field with a live colour dot, then the colour swatches. Labels are hidden so the grouped Form
    /// doesn't split the field into a right-aligned label/value row.
    private var newLabelRow: some View {
        let color = Color(hex: labelHex)
        let isEmpty = labelName.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    TextField("Label name", text: $labelName, prompt: Text("New label name"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 13))
                        .focused($labelFocused)
                        .onSubmit(createLabel)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5))

                Button("Cancel") { withAnimation { addingLabel = false } }
                    .controlSize(.small)
                Button("Add Label", action: createLabel)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isEmpty)
            }

            HStack(spacing: 8) {
                ForEach(Palette.swatches, id: \.self) { hex in
                    let selected = hex == labelHex
                    Button { labelHex = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .padding(3)
                            .overlay { if selected { Circle().strokeBorder(Color(hex: hex), lineWidth: 2) } }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if !isEmpty {
                    LabelChip(label: TaskLabel(id: "preview", name: labelName.trimmingCharacters(in: .whitespaces), hex: labelHex))
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear { labelFocused = true }
    }

    private func toggle(_ id: ID) {
        if let i = selection.firstIndex(of: id) { selection.remove(at: i) } else { selection.append(id) }
    }

    private func createLabel() {
        guard let label = store.addLabel(name: labelName, hex: labelHex, scope: scope) else { return }
        selection.append(label.id)
        labelName = ""
        withAnimation { addingLabel = false }
    }
}

/// A label chip that can be switched on and off.
struct LabelToggle: View {
    var label: TaskLabel
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : "circle.fill")
                    .font(.system(size: isOn ? 8 : 6, weight: .bold))
                    .frame(width: 8)
                Text(label.name)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOn ? Color.white : label.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOn ? label.color : label.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    TodoEditorSheet(todo: Todo(title: ""), undoManager: nil).environment(AppStore())
}
