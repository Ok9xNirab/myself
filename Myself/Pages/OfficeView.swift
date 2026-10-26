import SwiftUI

struct OfficeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""

    var body: some View {
        @Bindable var store = store
        let filtered = store.office.filter { query.isEmpty || ($0.title + " " + $0.desc).localizedCaseInsensitiveContains(query) }
        let active = filtered.filter { !$0.done }.sorted { (Day.fromToday($0.due) ?? 999) < (Day.fromToday($1.due) ?? 999) }
        let done = filtered.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        PageScroll {
            Callout(systemImage: "briefcase") {
                Text("Office tasks are always **high priority** and sorted by due date. Attach a reference link to each so it's one click to the ticket or doc.")
            }
            .padding(.bottom, 2)

            HStack(spacing: 8) {
                SearchField(placeholder: "Search office tasks…", text: $query)
                Spacer()
                Button("Add task", systemImage: "plus", action: store.newOfficeTask)
                    .buttonStyle(.borderedProminent)
            }

            Card(title: "Open tasks", systemImage: "briefcase") {
                CountText(value: active.count)
            } content: {
                if active.isEmpty {
                    if store.office.isEmpty {
                        EmptyStateView(systemImage: "briefcase", title: "No office tasks yet", subtitle: "Add a work item with a link to its ticket or doc.")
                    } else if query.isEmpty {
                        EmptyStateView(systemImage: "briefcase", title: "Inbox zero", subtitle: "No open office tasks. Nice.")
                    } else {
                        EmptyStateView(systemImage: "magnifyingglass", title: "No matches", subtitle: "No open office tasks match \u{201C}\(query)\u{201D}.")
                    }
                } else {
                    ForEach(active) { OfficeRow(task: $0) }
                }
            }

            if !done.isEmpty {
                Card(title: "Done", systemImage: "checkmark") {
                    CountText(value: done.count)
                } content: {
                    ForEach(done) { OfficeRow(task: $0) }
                }
            }
        }
        .sheet(item: $store.editingOffice) { OfficeEditorSheet(task: $0, undoManager: undoManager) }
    }
}

private struct OfficeRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var task: OfficeTask
    @State private var hover = HoverState()

    var body: some View {
        ListRow {
            HStack(alignment: .top, spacing: 10) {
                CheckCircle(isOn: task.done) { toggle() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.done)
                    if !task.desc.isEmpty {
                        Text(task.desc).font(.system(size: 12)).foregroundStyle(Palette.ink2)
                    }
                    FlowLayout(spacing: 8) {
                        if !task.done { PriorityBadge(priority: .high, locked: true) }
                        DueBadge(date: task.due)
                        if let url = task.refURL {
                            Link(destination: url) {
                                HStack(spacing: 3) {
                                    Image(systemName: "link")
                                    Text(url.host()?.replacingOccurrences(of: "www.", with: "") ?? "reference")
                                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                                }
                                .font(.system(size: 12))
                            }
                            .help(url.absoluteString)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowActions(hover: hover, onEdit: edit, onDelete: delete)
            }
            .opacity(task.done ? 0.55 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .onHover { hover.isOn = $0 }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Button(task.done ? "Mark as Not Done" : "Mark as Done", systemImage: task.done ? "circle" : "checkmark.circle", action: toggle)
            if let url = task.refURL {
                Link(destination: url) { Label("Open Link", systemImage: "arrow.up.right.square") }
                Button("Copy Link", systemImage: "doc.on.doc") { copy(url) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func edit() { store.editingOffice = task }

    private func toggle() {
        withAnimation { store.toggleOffice(task.id, undoManager: undoManager) }
    }

    private func delete() {
        withAnimation { store.deleteOfficeTask(task.id, undoManager: undoManager) }
    }

    private func copy(_ url: URL) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
        UIPasteboard.general.url = url
        #endif
    }
}

#Preview {
    OfficeView().environment(AppStore()).frame(width: 900, height: 700)
}
