import SwiftUI

/// Add / edit sheet for a todo, in the v2 design's quick-add style. A todo that isn't in the store yet is added
/// on save. A new one can go to Office instead (Space › Office), which saves it as an office task.
struct TodoEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The page's undo manager, so ⌘Z in the main window undoes the save.
    var undoManager: UndoManager?
    @State private var draft: Todo
    @State private var space = TaskItem.Space.personal
    @State private var pickingDate = false
    @FocusState private var titleFocused: Bool

    init(todo: Todo, undoManager: UndoManager?) {
        self.undoManager = undoManager
        _draft = State(initialValue: todo)
    }

    private var isNew: Bool { !store.todos.contains { $0.id == draft.id } }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var toOffice: Bool { space == .office }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            VStack(spacing: 0) {
                if isNew && store.isEnabled(.office) {
                    row("Space", "square.grid.2x2") { spaceChips }
                }
                row("Due", "calendar") { dueChips }
                row("Priority", "flag") {
                    if toOffice {
                        Badge(text: "High \u{00B7} locked", systemImage: "flag.fill", color: Palette.red)
                    } else {
                        PriorityTabs(selection: $draft.priority)
                    }
                }
                if !toOffice {
                    row("Labels", "tag", last: true) { LabelPicker(scope: .todo, selection: $draft.labelIDs) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            footer
        }
        #if os(macOS)
        .frame(width: 580)
        #endif
        .background(Palette.surface)
        .onAppear { titleFocused = isNew }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { draft.done.toggle() } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(draft.done ? Color.accentColor : Palette.ink3, lineWidth: 1.6)
                    .background(draft.done ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay { if draft.done { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) } }
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .disabled(isNew)
            .help(draft.done ? "Mark as not done" : "Mark as done")
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $draft.title, prompt: Text("What needs doing?"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                    .focused($titleFocused)
                    .onSubmit(save)
                TextField("Notes", text: $draft.desc, prompt: Text("Add notes"), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink2).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 26)
    }

    private func row<Content: View>(_ title: String, _ icon: String, last: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink2)
                .frame(width: 104, alignment: .leading)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5) } }
    }

    private var spaceChips: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach([TaskItem.Space.personal, .office]) { option in
                ChoiceChip(isOn: space == option, tint: option == .personal ? Palette.ink2 : option.color) {
                    space = option
                } label: {
                    Circle().fill(option.color).frame(width: 7, height: 7)
                    Text(option.title)
                }
            }
        }
    }

    private var dueChips: some View {
        let today = Day.offset(0)
        let options: [(String, Date)] = [
            ("Today", today),
            ("Tomorrow", Day.offset(1)),
            ("This weekend", Self.nextWeekday(7, from: today, allowToday: true)),
            ("Next week", Self.nextWeekday(2, from: Day.offset(1), allowToday: true)),
        ]
        let quick = options.contains { draft.due.map(Day.calendar.startOfDay(for:)) == $0.1 }
        return FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(options, id: \.0) { name, date in
                let on = draft.due.map(Day.calendar.startOfDay(for:)) == date
                ChoiceChip(isOn: on, tint: Palette.blue) {
                    draft.due = on ? nil : date
                } label: {
                    Text(name)
                    Text(date.formatted(name == "Next week" ? .dateTime.weekday(.abbreviated).day() : .dateTime.weekday(.abbreviated)))
                        .foregroundStyle(Palette.ink2).fontWeight(.medium)
                }
            }
            ChoiceChip(isOn: draft.due != nil && !quick, tint: Palette.blue, dashed: draft.due == nil || quick) {
                pickingDate = true
            } label: {
                Image(systemName: "calendar").font(.system(size: 11))
                Text(draft.due != nil && !quick ? draft.due!.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) : "Pick date")
            }
            .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                DatePicker("Due", selection: Binding(get: { draft.due ?? today }, set: { draft.due = Day.calendar.startOfDay(for: $0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            HStack(spacing: 4) {
                KeyCap("\u{2318}"); KeyCap("\u{21A9}")
                Text("to \(isNew ? "add" : "save") \u{00B7}")
                KeyCap("esc")
                Text("to cancel")
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink2)
            #endif
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.primary.opacity(0.06), in: Capsule())
            Button(action: save) {
                Label(isNew ? "Add task" : "Save", systemImage: isNew ? "plus" : "checkmark")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.surface)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Color.primary.opacity(trimmedTitle.isEmpty ? 0.3 : 1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(trimmedTitle.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.surface2.opacity(0.6))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    /// The first day on or after `from` that falls on `weekday` (1 = Sunday … 7 = Saturday).
    private static func nextWeekday(_ weekday: Int, from: Date, allowToday: Bool) -> Date {
        let calendar = Day.calendar
        var day = calendar.startOfDay(for: from)
        if !allowToday { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        while calendar.component(.weekday, from: day) != weekday {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let desc = draft.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if toOffice {
            store.saveOfficeTask(OfficeTask(title: trimmedTitle, desc: desc, due: draft.due), undoManager: undoManager)
            dismiss()
            return
        }
        draft.title = trimmedTitle
        draft.desc = desc
        draft.completedAt = draft.done ? (draft.completedAt ?? .now) : nil
        let known = Set(store.labels.map(\.id))
        draft.labelIDs.removeAll { !known.contains($0) }
        store.saveTodo(draft, undoManager: undoManager)
        dismiss()
    }
}

/// A rounded chip that's on or off (the sheet's Space and Due choices).
private struct ChoiceChip<Label: View>: View {
    var isOn: Bool
    var tint: Color
    var dashed = false
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isOn ? tint : .primary)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(isOn ? tint.opacity(0.12) : Palette.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isOn ? tint : Color.primary.opacity(dashed ? 0.2 : 0.08),
                                           style: StrokeStyle(lineWidth: isOn ? 1.5 : 1, dash: dashed && !isOn ? [3, 3] : []))
                }
                .shadow(color: .black.opacity(isOn ? 0 : 0.04), radius: 1, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Low / Medium / High as segmented tabs with coloured flags.
private struct PriorityTabs: View {
    @Binding var selection: Priority

    var body: some View {
        HStack(spacing: 0) {
            ForEach([Priority.low, .medium, .high]) { p in
                let on = p == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = p } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.color)
                        Text(p.title)
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(on ? Color.primary : Palette.ink2)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.surface)
                                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .fixedSize()
    }
}

#if os(macOS)
private struct KeyCap: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
#endif

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
                Button { withAnimation { addingLabel = true } } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("New label")
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

/// A label chip that can be switched on and off: a white pill with the label's dot, tinted and outlined when on.
struct LabelToggle: View {
    var label: TaskLabel
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(label.color).frame(width: 7, height: 7)
                Text(label.name)
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(isOn ? label.color : .primary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(isOn ? label.color.opacity(0.13) : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? label.color : Color.primary.opacity(0.08), lineWidth: isOn ? 1.5 : 1))
            .shadow(color: .black.opacity(isOn ? 0 : 0.04), radius: 1, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    TodoEditorSheet(todo: Todo(title: ""), undoManager: nil).environment(AppStore())
}
