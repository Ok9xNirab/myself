import SwiftUI

/// The v2 Office page: header with Open / Overdue / Done counts, the high-priority note, then open tasks grouped
/// Overdue / Today / Upcoming / No date, and a foldable Done group.
struct OfficeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var showDone = true

    private enum Group: CaseIterable {
        case overdue, today, upcoming, noDate

        var title: String {
            switch self {
            case .overdue: "Overdue"
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .noDate: "No date"
            }
        }

        var color: Color {
            switch self {
            case .overdue: Palette.red
            case .today: Palette.blue
            case .upcoming: Palette.amber
            case .noDate: Palette.ink3
            }
        }

        static func of(_ task: OfficeTask) -> Group {
            guard let n = Day.fromToday(task.due) else { return .noDate }
            return n < 0 ? .overdue : n == 0 ? .today : .upcoming
        }
    }

    var body: some View {
        @Bindable var store = store
        let open = store.office.filter { !$0.done }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let done = store.office.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let overdue = open.filter { Group.of($0) == .overdue }.count

        PageScroll {
            HStack(alignment: .bottom, spacing: 16) {
                SpaceHeader(page: .office, detail: "Work items \u{2014} always high priority, sorted by due date")
                Spacer(minLength: 0)
                CountStrip(items: [(open.count, "Open"), (overdue, "Overdue"), (done.count, "Done")])
                    .padding(.bottom, 4)
            }

            HStack(spacing: 10) {
                Image(systemName: "lock").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.blue)
                Text("Every office task is \(Text("high priority").fontWeight(.bold).foregroundStyle(.primary)). Attach a reference link so the ticket, doc or PR is one click away.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Palette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.blue.opacity(0.15), lineWidth: 0.5))

            if store.office.isEmpty {
                EmptyStateView(systemImage: "briefcase", title: "No office tasks yet", subtitle: "Add a work item with a link to its ticket or doc.")
                    .cardBackground(radius: 18)
            } else if open.isEmpty {
                EmptyStateView(systemImage: "checkmark", title: "Inbox zero", subtitle: "No open office tasks. Nice.")
                    .cardBackground(radius: 18)
            }

            ForEach(Group.allCases, id: \.self) { group in
                let tasks = open.filter { Group.of($0) == group }
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().fill(group.color).frame(width: 8, height: 8)
                            Text(group.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(group == .overdue ? Color.dynamic(light: 0xC62828, dark: 0xFF7B7B) : .primary)
                            CountText(value: tasks.count)
                        }
                        .padding(.leading, 8)
                        TaskGroupCard(tasks: tasks)
                    }
                }
            }

            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .rotationEffect(.degrees(showDone ? 0 : -90))
                            Text("Done").font(.system(size: 16, weight: .bold))
                            CountText(value: done.count)
                        }
                        .foregroundStyle(Palette.ink2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                    if showDone { TaskGroupCard(tasks: done) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Task", systemImage: "plus", action: store.newOfficeTask)
                    .labelStyle(.titleAndIcon)
                    .help("New office task (\u{21E7}\u{2318}N)")
            }
        }
        .sheet(item: $store.editingOffice) { OfficeEditorSheet(task: $0, undoManager: undoManager) }
    }
}

/// "7 Open | 3 Overdue | 2 Done" in a frosted strip beside the header.
private struct CountStrip: View {
    var items: [(Int, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(spacing: 1) {
                    Text("\(item.0)").font(.system(size: 13.5, weight: .bold)).monospacedDigit()
                    Text(item.1).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink2)
                }
                .frame(minWidth: 62)
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
                .overlay(alignment: .leading) {
                    if i > 0 { Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 0.5).padding(.vertical, 8) }
                }
            }
        }
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .fixedSize()
    }
}

private struct TaskGroupCard: View {
    var tasks: [OfficeTask]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                OfficeRow(task: task)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 12) }
                    }
            }
        }
        .padding(.vertical, 4)
        .cardBackground(radius: 18)
    }
}

private struct OfficeRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var task: OfficeTask
    @State private var hover = HoverState()

    var body: some View {
        HStack(spacing: 14) {
            CheckCircle(isOn: task.done, action: toggle)
                .scaleEffect(1.2)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 15))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Palette.ink3 : .primary)
                if !task.desc.isEmpty && !task.done {
                    Text(task.desc).font(.system(size: 13)).foregroundStyle(Palette.ink2).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let url = task.refURL {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                            Text(url.host()?.replacingOccurrences(of: "www.", with: "") ?? "link")
                            Image(systemName: "arrow.up.right").font(.system(size: 9.5, weight: .bold))
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.dynamic(light: 0x1D5AD6, dark: 0x7AA6FF))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Palette.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(url.absoluteString)
                }
                Image(systemName: "flag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.red)
                    .frame(width: 24, height: 24)
                    .background(Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .help("High priority \u{00B7} locked")
            }
            .opacity(task.done ? 0.5 : 1)
            Text(dueText)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(dueColor)
                .lineLimit(1)
                .frame(width: 118, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, task.desc.isEmpty || task.done ? 14 : 11)
        .background { HoverFill(hover: hover, color: Color.primary.opacity(0.03)) }
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

    /// "13d overdue", "Today", "Tomorrow", "Fri", "Mon 7 Dec", or "Done Mon" once ticked.
    private var dueText: String {
        if task.done {
            guard let at = task.completedAt else { return "Done" }
            let n = -(Day.fromToday(at) ?? 0)
            return n == 0 ? "Done today" : n == 1 ? "Done yesterday" : n < 7
                ? "Done \(at.formatted(.dateTime.weekday(.abbreviated)))" : "Done \(at.formatted(.dateTime.day().month(.abbreviated)))"
        }
        guard let due = task.due, let n = Day.fromToday(due) else { return "No date" }
        switch n {
        case ..<0: return "\(-n)d overdue"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return due.formatted(.dateTime.weekday(.abbreviated))
        default: return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    private var dueColor: Color {
        if task.done { return Palette.green }
        guard let n = Day.fromToday(task.due) else { return Palette.ink3 }
        return n < 0 ? Color.dynamic(light: 0xC62828, dark: 0xFF7B7B) : n == 0 ? Color.dynamic(light: 0x1D5AD6, dark: 0x7AA6FF) : Palette.ink2
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
    OfficeView().environment(AppStore()).frame(width: 1000, height: 800)
}
