import SwiftUI

struct OfficeView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""

    var body: some View {
        let filtered = store.office.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
        let active = filtered.filter { !$0.done }.sorted { (Day.fromToday($0.due) ?? 999) < (Day.fromToday($1.due) ?? 999) }
        let done = filtered.filter(\.done)

        PageScroll {
            Callout(systemImage: "briefcase") {
                Text("Office tasks are always **high priority** and sorted by due date. Attach a reference link to each so it's one click to the ticket or doc.")
            }
            .padding(.bottom, 2)

            HStack(spacing: 8) {
                SearchField(placeholder: "Search office tasks…", text: $query)
                Spacer()
                Button("Add task", systemImage: "plus") {}
                    .buttonStyle(.borderedProminent)
            }

            Card(title: "Open tasks", systemImage: "briefcase") {
                CountText(value: active.count)
            } content: {
                if active.isEmpty {
                    EmptyStateView(systemImage: "briefcase", title: "Inbox zero", subtitle: "No open office tasks. Nice.")
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
    }
}

private struct OfficeRow: View {
    @Environment(AppStore.self) private var store
    var task: OfficeTask
    @State private var hovering = false

    var body: some View {
        ListRow {
            HStack(alignment: .top, spacing: 10) {
                CheckCircle(isOn: task.done) { withAnimation { store.toggleOffice(task.id) } }
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.done)
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
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowActions(isHovering: hovering, onDelete: {
                    store.office.removeAll { $0.id == task.id }
                })
            }
            .opacity(task.done ? 0.55 : 1)
        }
        .onHover { hovering = $0 }
    }
}

#Preview {
    OfficeView().environment(AppStore()).frame(width: 900, height: 700)
}
