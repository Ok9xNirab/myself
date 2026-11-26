import SwiftUI

/// The TODOs page in the v2 design's "All tasks" layout: your todos together with everything else that has a due
/// date (office tasks, assignments, Product Dev cards), grouped Overdue / Today / Upcoming / No date, with the
/// completed ones folded away at the end. Todos are edited here; the other kinds open their own editor.
struct TodosView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var labelFilter: ID?
    @State private var priorityFilter: Priority?
    @State private var spaceFilter: TaskItem.Space?
    @State private var range = TaskRange.all
    @State private var showDone = false

    var body: some View {
        @Bindable var store = store
        let items = allItems
        let shown = items.filter(matches)
        let open = shown.filter { !$0.done }
        let groups: [(TaskGroup, [TaskItem])] = TaskGroup.allCases.compactMap { group in
            guard range.includes(group) else { return nil }
            let rows = open.filter { $0.group == group }.sorted(by: TaskItem.order)
            return rows.isEmpty ? nil : (group, rows)
        }
        let done = range == .all ? shown.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) } : []

        PageScroll {
            HStack(alignment: .center, spacing: 16) {
                SpaceHeader(page: .todos, detail: "Personal to-dos and everything due across your Spaces")
                Spacer(minLength: 0)
                TaskStats(items: items)
            }

            filterBar

            if groups.isEmpty && done.isEmpty {
                Group {
                    if items.isEmpty {
                        EmptyStateView(systemImage: Page.todos.systemImage, title: "No tasks yet", subtitle: "Press \u{2318}N or + Task to add your first one.")
                    } else {
                        EmptyStateView(systemImage: "checkmark", title: "All clear", subtitle: "Nothing matches these filters.")
                    }
                }
                .cardBackground(radius: 18)
            }

            ForEach(groups, id: \.0) { group, rows in
                VStack(alignment: .leading, spacing: 10) {
                    GroupHeading(title: group.title, count: rows.count, dot: group.color)
                    TaskList(items: rows)
                }
            }

            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .rotationEffect(.degrees(showDone ? 90 : 0))
                                .foregroundStyle(Palette.ink2)
                                .frame(width: 12)
                            GroupHeading(title: "Completed", count: done.count, dot: nil)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showDone { TaskList(items: done) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Task", systemImage: "plus", action: store.newTodo)
                    .labelStyle(.titleAndIcon)
                    .help("New todo (\u{2318}N)")
            }
        }
        .sheet(item: $store.editingTodo) { TodoEditorSheet(todo: $0, undoManager: undoManager) }
        .sheet(item: $store.editingOffice) { OfficeEditorSheet(task: $0, undoManager: undoManager) }
        .sheet(item: $store.editingUniversity) { UniversityEditorSheet(editor: $0, undoManager: undoManager) }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterMenu(systemImage: "tag", title: labelFilter.flatMap(store.label)?.name ?? "All labels", selection: $labelFilter) {
                Text("All labels").tag(ID?.none)
                ForEach(store.labels) { Text($0.name).tag(ID?.some($0.id)) }
                if store.isEnabled(.products), !store.productLabels.isEmpty {
                    Divider()
                    ForEach(store.productLabels) { Text($0.name).tag(ID?.some($0.id)) }
                }
            }
            FilterMenu(systemImage: "flag", title: priorityFilter?.title ?? "Any priority", selection: $priorityFilter) {
                Text("Any priority").tag(Priority?.none)
                ForEach(Priority.allCases) { Text($0.title).tag(Priority?.some($0)) }
            }
            FilterMenu(systemImage: "square.grid.2x2", title: spaceFilter?.title ?? "All spaces", selection: $spaceFilter) {
                Text("All spaces").tag(TaskItem.Space?.none)
                ForEach(TaskItem.Space.allCases.filter { $0.page.map(store.isEnabled) ?? true }) { Text($0.title).tag(TaskItem.Space?.some($0)) }
            }
            Spacer(minLength: 8)
            SegmentedTabs(options: TaskRange.allCases, title: \.rawValue, selection: $range)
        }
    }

    // MARK: Items

    private var allItems: [TaskItem] {
        var items = store.todos.map(TaskItem.init(todo:))
        if store.isEnabled(.office) { items += store.office.map(TaskItem.init(office:)) }
        if store.isEnabled(.university) { items += store.university.assignments.map(TaskItem.init(assignment:)) }
        if store.isEnabled(.products) {
            items += store.cards.filter { $0.due != nil && $0.status != .done }.map { TaskItem(card: $0, project: store.product($0.productID)) }
        }
        return items
    }

    private func matches(_ item: TaskItem) -> Bool {
        if let labelFilter, !item.labelIDs.contains(labelFilter) { return false }
        if let priorityFilter, item.priority != priorityFilter { return false }
        if let spaceFilter, item.space != spaceFilter { return false }
        return true
    }
}

/// Today / Upcoming / All: which groups show.
private enum TaskRange: String, CaseIterable, Identifiable {
    case today = "Today", upcoming = "Upcoming", all = "All"
    var id: Self { self }

    func includes(_ group: TaskGroup) -> Bool {
        switch self {
        case .today: group == .overdue || group == .today
        case .upcoming: group == .upcoming
        case .all: true
        }
    }
}

private enum TaskGroup: CaseIterable, Hashable {
    case overdue, today, upcoming, someday

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .someday: "No date"
        }
    }

    var color: Color? {
        switch self {
        case .overdue: Palette.red
        case .today: Palette.blue
        case .upcoming: Palette.amber
        case .someday: nil
        }
    }
}

/// One row of the page, whichever space it comes from.
struct TaskItem: Identifiable {
    enum Space: String, CaseIterable, Identifiable {
        case personal, office, university, products
        var id: Self { self }

        var title: String {
            switch self {
            case .personal: "Personal"
            case .office: "Office"
            case .university: "University"
            case .products: "Product Dev"
            }
        }

        var page: Page? {
            switch self {
            case .personal: nil
            case .office: .office
            case .university: .university
            case .products: .products
            }
        }

        var color: Color { page?.tint ?? Palette.ink3 }
    }

    var id: String
    var sourceID: ID
    var space: Space
    var title: String
    var detail: String
    var due: Date?
    var priority: Priority
    var labelIDs: [ID]
    var done: Bool
    var completedAt: Date?
    /// Product Dev: the card's project, shown instead of "Product Dev".
    var spaceName: String?
    var productID: ID?

    init(todo t: Todo) {
        (id, sourceID, space, title, detail, due, priority, labelIDs, done, completedAt) =
            ("t" + t.id, t.id, .personal, t.title, t.desc, t.due, t.priority, t.labelIDs, t.done, t.completedAt)
    }

    init(office t: OfficeTask) {
        (id, sourceID, space, title, detail, due, priority, labelIDs, done, completedAt) =
            ("o" + t.id, t.id, .office, t.title, t.desc, t.due, .high, [], t.done, t.completedAt)
    }

    init(assignment a: Assignment) {
        (id, sourceID, space, title, detail, due, priority, labelIDs, done, completedAt) =
            ("a" + a.id, a.id, .university, a.title, a.subject, a.due, .high, [], a.done, a.done ? a.updatedAt : nil)
    }

    init(card c: KanbanCard, project: Product?) {
        (id, sourceID, space, title, detail, due, priority, labelIDs, done, completedAt) =
            ("c" + c.id, c.id, .products, c.title, c.desc, c.due, c.priority, c.labelIDs, false, nil)
        spaceName = project?.name
        productID = c.productID
    }

    fileprivate var group: TaskGroup {
        guard let n = Day.fromToday(due) else { return .someday }
        return n < 0 ? .overdue : n == 0 ? .today : .upcoming
    }

    /// Soonest first, then by priority.
    static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let (da, db) = (a.due ?? .distantFuture, b.due ?? .distantFuture)
        return da != db ? da < db : a.priority.rank < b.priority.rank
    }
}

// MARK: Pieces

/// Active · High · This week · Done, in one strip (the design's header stats).
private struct TaskStats: View {
    var items: [TaskItem]

    var body: some View {
        let open = items.filter { !$0.done }
        let stats = [
            ("\(open.count)", "Active"),
            ("\(open.filter { $0.priority == .high }.count)", "High"),
            ("\(open.filter { (0...6).contains(Day.fromToday($0.due) ?? -1) }.count)", "This week"),
            ("\(items.filter(\.done).count)", "Done"),
        ]
        HStack(spacing: 0) {
            ForEach(stats.indices, id: \.self) { i in
                VStack(spacing: 1) {
                    Text(stats[i].0).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                    Text(stats[i].1).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.primary.opacity(0.75))
                }
                .frame(minWidth: 62)
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
                if i < stats.count - 1 { Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 0.5, height: 34) }
            }
        }
        .padding(.horizontal, 6)
        .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

private struct GroupHeading: View {
    var title: String
    var count: Int
    var dot: Color?

    var body: some View {
        HStack(spacing: 9) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(dot == Palette.red ? Palette.red : dot == nil && title == "Completed" ? Palette.ink2 : .primary)
            CountText(value: count)
        }
        .padding(.leading, 6)
    }
}

/// A card holding a group's rows.
private struct TaskList: View {
    var items: [TaskItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { TaskRow(item: $0) }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .cardBackground(radius: 18)
    }
}

private struct TaskRow: View {
    var item: TaskItem
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.rowDensity) private var density
    @State private var hover = HoverState()

    var body: some View {
        HStack(spacing: 14) {
            CheckCircle(isOn: item.done, action: toggle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Palette.ink3 : .primary)
                    .lineLimit(2)
                if !item.detail.isEmpty, !item.done {
                    Text(item.detail).font(.system(size: 12)).foregroundStyle(Palette.ink2).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.space == .personal { RowActions(hover: hover, onEdit: edit, onDelete: delete) }
            HStack(spacing: 6) {
                ForEach(item.labelIDs.compactMap(store.label).prefix(3)) { label in
                    Text(label.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(label.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(label.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .fixedSize()
                }
            }
            HStack(spacing: 6) {
                Circle().fill(item.space.color).frame(width: 6, height: 6)
                Text(item.spaceName ?? item.space.title).lineLimit(1)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.ink2)
            .frame(width: 104, alignment: .leading)
            Image(systemName: "flag")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.priority.color)
                .frame(width: 24, height: 24)
                .background(item.priority.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help("\(item.priority.title) priority")
            dueText
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 9 + density.paddingDelta)
        .background { HoverFill(hover: hover, color: Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .onHover { hover.isOn = $0 }
        .contextMenu {
            Button(item.space == .personal ? "Edit\u{2026}" : "Open in \(item.space.title)", systemImage: "pencil", action: edit)
            Button(item.done ? "Mark as Not Done" : "Mark as Done", systemImage: item.done ? "circle" : "checkmark.circle", action: toggle)
            if item.space == .personal {
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        }
    }

    @ViewBuilder private var dueText: some View {
        if item.done {
            Text(item.completedAt.map { "Done " + $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "Done").foregroundStyle(Palette.green)
        } else if let n = Day.fromToday(item.due), let due = item.due {
            let hasTime = Day.calendar.component(.hour, from: due) != 0 || Day.calendar.component(.minute, from: due) != 0
            switch n {
            case ..<(-1): Text("\(-n)d overdue").foregroundStyle(Palette.red)
            case -1: Text("Yesterday").foregroundStyle(Palette.red)
            case 0: Text(hasTime ? "Today " + due.formatted(.dateTime.hour()) : "Today").foregroundStyle(Palette.blue)
            case 1: Text("Tomorrow").foregroundStyle(Palette.ink2)
            case 2...6: Text(due.formatted(.dateTime.weekday(.abbreviated))).foregroundStyle(Palette.ink2)
            default: Text(due.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(Palette.ink2)
            }
        } else {
            Text("No date").foregroundStyle(Palette.ink3)
        }
    }

    private func toggle() {
        withAnimation {
            switch item.space {
            case .personal: store.toggleTodo(item.sourceID, undoManager: undoManager)
            case .office: store.toggleOffice(item.sourceID, undoManager: undoManager)
            case .university: store.toggleAssignment(item.sourceID, undoManager: undoManager)
            case .products: store.moveCard(item.sourceID, to: .done, undoManager: undoManager)
            }
        }
    }

    private func edit() {
        switch item.space {
        case .personal:
            store.editingTodo = store.todos.first { $0.id == item.sourceID }
        case .office:
            store.editingOffice = store.office.first { $0.id == item.sourceID }
        case .university:
            if let a = store.university.assignments.first(where: { $0.id == item.sourceID }) { store.editingUniversity = .assignment(a) }
        case .products:
            store.selectedProduct = item.productID
            store.go(.products)
        }
    }

    private func delete() {
        withAnimation { store.deleteTodo(item.sourceID, undoManager: undoManager) }
    }
}

/// A filter pill ("All labels ⌄") that opens a menu of choices.
private struct FilterMenu<Value: Hashable, Options: View>: View {
    var systemImage: String
    var title: String
    @Binding var selection: Value
    @ViewBuilder var options: Options

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage).font(.system(size: 12)).foregroundStyle(Palette.ink2)
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink2)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: 280)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

#Preview {
    TodosView().environment(AppStore()).frame(width: 900, height: 800)
}
