import SwiftUI

/// Add / edit sheet for an office task. A task that isn't in the store yet is added on save.
struct OfficeEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The page's undo manager, so ⌘Z in the main window undoes the save.
    var undoManager: UndoManager?
    @State private var draft: OfficeTask
    @State private var hasDue: Bool
    @State private var link: String
    @FocusState private var titleFocused: Bool

    init(task: OfficeTask, undoManager: UndoManager?) {
        self.undoManager = undoManager
        _draft = State(initialValue: task)
        _hasDue = State(initialValue: task.due != nil)
        _link = State(initialValue: task.refURL?.absoluteString ?? "")
    }

    private var isNew: Bool { !store.office.contains { $0.id == draft.id } }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The typed link as a URL; a bare "github.com/…" gets `https://`. `nil` when it isn't a usable web link.
    private var linkURL: URL? {
        guard !trimmedLink.isEmpty else { return nil }
        let text = trimmedLink.contains("://") ? trimmedLink : "https://" + trimmedLink
        guard let url = URL(string: text), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }

    private var linkIsInvalid: Bool { !trimmedLink.isEmpty && linkURL == nil }

    private var due: Binding<Date> {
        Binding(get: { draft.due ?? Day.offset(0) }, set: { draft.due = Day.calendar.startOfDay(for: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, prompt: Text("What needs doing at work?"))
                        .focused($titleFocused)
                    TextField("Notes", text: $draft.desc, prompt: Text("Notes (optional)"), axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    TextField("Link", text: $link, prompt: Text("https://github.com/org/repo/issues/123"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                } header: {
                    Text("Reference")
                } footer: {
                    if linkIsInvalid {
                        Text("That doesn\u{2019}t look like a web link.").foregroundStyle(Palette.red)
                    }
                }

                Section {
                    LabeledContent("Priority") { PriorityBadge(priority: .high, locked: true) }
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Date", selection: due, displayedComponents: .date)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Office Task" : "Edit Office Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save)
                        .disabled(trimmedTitle.isEmpty || linkIsInvalid)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460)
        #endif
        .onAppear { titleFocused = isNew }
    }

    private func save() {
        guard !trimmedTitle.isEmpty, !linkIsInvalid else { return }
        draft.title = trimmedTitle
        draft.desc = draft.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.refURL = linkURL
        draft.due = hasDue ? (draft.due ?? Day.offset(0)) : nil
        store.saveOfficeTask(draft, undoManager: undoManager)
        dismiss()
    }
}

#Preview {
    OfficeEditorSheet(task: OfficeTask(title: ""), undoManager: nil).environment(AppStore())
}
