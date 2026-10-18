import SwiftUI

struct TodosView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""
    @State private var labelFilter: ID?
    @State private var priorityFilter: Priority?
    @State private var showDone = false

    private var filtered: [Todo] {
        store.todos.filter { t in
            if !query.isEmpty, !(t.title + " " + t.desc).localizedCaseInsensitiveContains(query) { return false }
            if let labelFilter, !t.labelIDs.contains(labelFilter) { return false }
            if let priorityFilter, t.priority != priorityFilter { return false }
            return true
        }
    }

    var body: some View {
        @Bindable var store = store
        let todos = store.todos
        let active = filtered.filter { !$0.done }.sorted { $0.priority.rank < $1.priority.rank }
        let done = filtered.filter(\.done)

        PageScroll {
            HStack(spacing: 8) {
                SearchField(placeholder: "Search tasks…", text: $query)
                Picker("Label", selection: $labelFilter) {
                    Text("All labels").tag(ID?.none)
                    ForEach(store.labels) { Text($0.name).tag(ID?.some($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Priority", selection: $priorityFilter) {
                    Text("Any priority").tag(Priority?.none)
                    ForEach(Priority.allCases) { Text($0.title).tag(Priority?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Add todo", systemImage: "plus", action: store.newTodo)
                    .buttonStyle(.borderedProminent)
                    .help("Add todo (⌘N)")
            }

            StatGrid(minimum: 140) {
                StatTile(systemImage: "checklist", label: "Active", value: "\(todos.filter { !$0.done }.count)", color: Palette.blue)
                StatTile(systemImage: "flag", label: "High priority", value: "\(todos.filter { !$0.done && $0.priority == .high }.count)", color: Palette.red)
                StatTile(systemImage: "clock", label: "Due this week",
                         value: "\(todos.filter { !$0.done && (0...6).contains(Day.fromToday($0.due) ?? -1) }.count)", color: Palette.amber)
                StatTile(systemImage: "checkmark", label: "Completed", value: "\(todos.filter(\.done).count)", color: Palette.green)
            }
            .padding(.bottom, 4)

            Card(title: "To do", systemImage: "checklist") {
                CountText(value: active.count)
            } content: {
                if active.isEmpty {
                    if todos.isEmpty {
                        EmptyStateView(systemImage: "checklist", title: "No todos yet", subtitle: "Press ⌘N or Add todo to create your first one.")
                    } else {
                        EmptyStateView(systemImage: "checkmark", title: "All clear", subtitle: "Nothing on your plate matching these filters.")
                    }
                } else {
                    ForEach(active) { TodoRow(todo: $0) }
                }
            }

            if !done.isEmpty {
                VStack(spacing: 0) {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark").foregroundStyle(Palette.ink3).frame(width: 18)
                            Text("Completed").font(.system(size: 13, weight: .semibold))
                            CountText(value: done.count)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showDone ? 90 : 0))
                                .foregroundStyle(Palette.ink3)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showDone {
                        Divider().overlay(Palette.border)
                        ForEach(done) { TodoRow(todo: $0) }
                    }
                }
                .cardBackground()
            }
        }
        .sheet(item: $store.editingTodo) { TodoEditorSheet(todo: $0, undoManager: undoManager) }
    }
}

struct TodoRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var todo: Todo
    @State private var hovering = false

    var body: some View {
        ListRow {
            HStack(alignment: .top, spacing: 10) {
                CheckCircle(isOn: todo.done) { withAnimation { store.toggleTodo(todo.id, undoManager: undoManager) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(todo.done)
                    if !todo.desc.isEmpty {
                        Text(todo.desc).font(.system(size: 12)).foregroundStyle(Palette.ink2)
                    }
                    FlowLayout {
                        if !todo.done { PriorityBadge(priority: todo.priority) }
                        DueBadge(date: todo.due)
                        ForEach(todo.labelIDs.compactMap(store.label)) { LabelChip(label: $0) }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowActions(isHovering: hovering, onEdit: edit, onDelete: delete)
            }
            .opacity(todo.done ? 0.55 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            Button(todo.done ? "Mark as Not Done" : "Mark as Done", systemImage: todo.done ? "circle" : "checkmark.circle") {
                withAnimation { store.toggleTodo(todo.id, undoManager: undoManager) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func edit() { store.editingTodo = todo }

    private func delete() {
        withAnimation { store.deleteTodo(todo.id, undoManager: undoManager) }
    }
}

struct SearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.ink3)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 13))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: 280)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5))
    }
}

#Preview {
    TodosView().environment(AppStore()).frame(width: 900, height: 800)
}
