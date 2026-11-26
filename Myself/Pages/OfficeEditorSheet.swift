import SwiftUI

/// Add / edit sheet for an office task, in the v2 quick-add style. A task that isn't in the store yet is added on save.
struct OfficeEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The page's undo manager, so ⌘Z in the main window undoes the save.
    var undoManager: UndoManager?
    @State private var draft: OfficeTask
    @State private var link: String
    @FocusState private var titleFocused: Bool

    init(task: OfficeTask, undoManager: UndoManager?) {
        self.undoManager = undoManager
        _draft = State(initialValue: task)
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
    private var canSave: Bool { !trimmedTitle.isEmpty && !linkIsInvalid }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add task", canSave: canSave, onSave: save) {
            SheetCheckbox(isOn: draft.done) { draft.done.toggle() }
                .padding(.top, 6)
                .disabled(isNew)
        } header: {
            SheetTitleField(title: "Title", prompt: "What needs doing at work?", text: $draft.title, onSubmit: submit)
                .focused($titleFocused)
            TextField("Notes", text: $draft.desc, prompt: Text("Add notes"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...5)
        } rows: {
            SheetRow(title: "Link", systemImage: "link") {
                HStack(spacing: 8) {
                    SheetTextField(title: "Link", prompt: "github.com/org/repo/issues/123", text: $link, maxWidth: 340)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    if let url = linkURL {
                        Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                            .help("Open \(url.host() ?? "link")")
                    }
                }
                if linkIsInvalid {
                    Text("That doesn\u{2019}t look like a web link.").font(.system(size: 12)).foregroundStyle(Palette.red)
                }
            }
            SheetRow(title: "Due", systemImage: "calendar") {
                DateChips(date: $draft.due, options: [("Today", 0), ("Tomorrow", 1), ("In a week", 7)])
            }
            SheetRow(title: "Priority", systemImage: "flag", last: true) {
                Badge(text: "High \u{00B7} locked", systemImage: "flag.fill", color: Palette.red)
            }
        }
        .onAppear { titleFocused = isNew }
    }

    private func submit() {
        guard canSave else { return }
        save()
        dismiss()
    }

    private func save() {
        guard canSave else { return }
        draft.title = trimmedTitle
        draft.desc = draft.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.refURL = linkURL
        draft.completedAt = draft.done ? (draft.completedAt ?? .now) : nil
        store.saveOfficeTask(draft, undoManager: undoManager)
    }
}

#Preview {
    OfficeEditorSheet(task: OfficeTask(title: ""), undoManager: nil).environment(AppStore())
}
