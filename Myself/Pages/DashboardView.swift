import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store

    /// Due today or overdue (assignments: due tomorrow too).
    private var focus: [FocusItem] {
        FocusItem.list(todos: store.todos, office: store.office, assignments: store.university.assignments,
                       officeOn: store.isEnabled(.office), universityOn: store.isEnabled(.university))
    }

    private var classesToday: [UniClass] {
        guard store.isEnabled(.university) else { return [] }
        return store.university.classes.filter { $0.days.contains(.today) }.sorted { $0.time < $1.time }
    }

    private var greeting: String {
        let h = Day.calendar.component(.hour, from: .now)
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        let focus = focus
        let university = store.isEnabled(.university)
        let office = store.isEnabled(.office)
        let jobStudy = store.isEnabled(.jobStudy)
        let products = store.isEnabled(.products)
        PageScroll(maxWidth: 1080) {
            hero(focusCount: focus.count)

            StatGrid(count: 1 + [office, university, jobStudy].filter { $0 }.count) {
                let openTodos = store.todos.filter { !$0.done }
                let overdueTodos = openTodos.filter { (Day.fromToday($0.due) ?? 0) < 0 }.count
                StatTile(systemImage: Page.todos.systemImage, label: "Open tasks", value: "\(openTodos.count)",
                         foot: overdueTodos > 0 ? "\(overdueTodos) overdue" : "none overdue", color: Page.todos.tint)
                if office {
                    StatTile(systemImage: Page.office.systemImage, label: "Office due", value: "\(store.office.filter { !$0.done && (Day.fromToday($0.due) ?? 1) <= 0 }.count)",
                             foot: "due today or overdue", color: Page.office.tint)
                }
                if university {
                    let open = store.university.assignments.filter { !$0.done }
                    StatTile(systemImage: "flag", label: "Assignments", value: "\(open.count)",
                             foot: assignmentsFoot(open), color: Page.university.tint)
                }
                if jobStudy {
                    let topics = store.jobStudy.flatMap(\.topics)
                    StatTile(systemImage: Page.jobStudy.systemImage, label: "Topics due", value: "\(store.count(for: .jobStudy))",
                             foot: "\(topics.filter(\.revisedToday).count) revised today", color: Page.jobStudy.tint)
                }
            }

            // The design's three columns (1.15 : 1 : 1): tasks and boards, classes and deadlines, Job Study.
            let deadlines = deadlineItems
            let columns: [AnyView] = [
                AnyView(VStack(spacing: 12) {
                    focusCard(focus)
                    if products { productCard }
                }),
                university || !deadlines.isEmpty ? AnyView(VStack(spacing: 12) {
                    if university { classesCard }
                    if university || office || products { deadlinesCard(deadlines) }
                }) : nil,
                jobStudy || university ? AnyView(VStack(spacing: 12) {
                    if jobStudy { jobStudyCard }
                    if university { syllabusCard }
                }) : nil,
            ].compactMap { $0 }
            DashboardColumns(columns: columns)
        }
    }

    /// "1 overdue · 1 Wed": how many are late and when the next one is due.
    private func assignmentsFoot(_ open: [Assignment]) -> String {
        guard !open.isEmpty else { return "nothing open" }
        let overdue = open.filter { (Day.fromToday($0.due) ?? 0) < 0 }
        let upcoming = open.filter { (Day.fromToday($0.due) ?? -1) >= 0 }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        var parts: [String] = []
        if !overdue.isEmpty { parts.append("\(overdue.count) overdue") }
        if let next = upcoming.first?.due {
            let sameDay = upcoming.filter { Day.calendar.isDate($0.due ?? .distantFuture, inSameDayAs: next) }.count
            let n = Day.fromToday(next) ?? 0
            let day = n == 0 ? "today" : n == 1 ? "tomorrow" : next.formatted(.dateTime.weekday(.abbreviated))
            parts.append("\(sameDay) \(day)")
        }
        return parts.isEmpty ? "\(open.count) open" : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Sections

    private func hero(focusCount: Int) -> some View {
        let week = Day.calendar.component(.weekOfYear, from: .now)
        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) · Week \(week)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.dynamic(light: 0x7A4A1F, dark: 0xFFB98A))
                Text("\(greeting).")
                    .font(.system(size: 38, weight: .heavy))
                    .kerning(-1.3)
                    .padding(.top, 6)
                summary(focusCount: focusCount)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dynamic(light: 0x45464F, dark: 0xA3A3AD))
                    .lineSpacing(3)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
            let rings = progressRings
            if !rings.isEmpty { ProgressRings(rings: rings) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Up to three rings for the hero: Job Study coverage, the University syllabus and today's todos.
    private var progressRings: [ProgressRings.Ring] {
        var rings: [ProgressRings.Ring] = []
        if store.isEnabled(.jobStudy) {
            let topics = store.jobStudy.flatMap(\.topics)
            if !topics.isEmpty {
                rings.append(.init(label: "Job Study", percent: topics.filter { $0.revisions > 0 }.count * 100 / topics.count, color: Page.jobStudy.tint))
            }
        }
        if store.isEnabled(.university), !store.university.syllabus.isEmpty {
            rings.append(.init(label: "University syllabus", percent: store.university.syllabusPercent, color: Page.university.tint))
        }
        let open = store.todos.filter { !$0.done }.count
        let doneToday = store.todos.filter { $0.done && Day.isToday($0.completedAt) }.count
        if open + doneToday > 0 {
            rings.append(.init(label: "Today\u{2019}s todos", percent: doneToday * 100 / (open + doneToday), color: Page.todos.tint))
        }
        return rings
    }

    private func summary(focusCount: Int) -> Text {
        guard store.isEnabled(.university) else {
            if focusCount > 0 {
                let count = Text("\(focusCount) \(focusCount == 1 ? "thing" : "things")").fontWeight(.semibold).foregroundStyle(.primary)
                return Text("You have \(count) due today.")
            }
            return Text("Nothing overdue — a clean slate.")
        }
        let n = classesToday.count
        let classes = "\(n) \(n == 1 ? "class" : "classes")"
        if focusCount > 0 {
            let count = Text("\(focusCount) \(focusCount == 1 ? "thing" : "things")").fontWeight(.semibold).foregroundStyle(.primary)
            let scheduled = Text(classes).fontWeight(.semibold).foregroundStyle(.primary)
            return Text("You have \(count) due today and \(scheduled) scheduled.")
        }
        return Text(n == 0 ? "Nothing overdue — a clean slate. No classes today." : "Nothing overdue — a clean slate. \(classes) today.")
    }

    private func focusCard(_ focus: [FocusItem]) -> some View {
        Card(title: "Today\u{2019}s focus", systemImage: "scope", tint: Palette.amber) {
            CountText(value: focus.count)
            Spacer()
            GhostButton(title: "All tasks", trailingChevron: true) { store.go(.todos) }
        } content: {
            if focus.isEmpty {
                EmptyStateView(systemImage: "checkmark", title: "All caught up", subtitle: "Nothing due today. Enjoy it.")
            } else {
                VStack(spacing: 0) {
                    ForEach(focus) { item in
                        DashboardRow(inset: 8, action: { store.go(item.page) }) {
                            HStack(alignment: .top, spacing: 11) {
                                SquareCheck { complete(item) }.padding(.top, 1)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                                    FlowLayout {
                                        DotChip(text: item.spaceName, color: item.page.tint)
                                        if let meta = DueMeta(item.due) { Badge(text: meta.text, color: meta.color) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func complete(_ item: FocusItem) {
        withAnimation {
            switch item.kind {
            case .todo: store.toggleTodo(item.id)
            case .office: store.toggleOffice(item.id)
            case .assignment: store.toggleAssignment(item.id)
            }
        }
    }

    /// The next few classes: the rest of today, then the coming days.
    private var upcomingClasses: [AppStore.ClassSession] {
        let calendar = Day.calendar
        let now = Date.now
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var sessions: [AppStore.ClassSession] = []
        for offset in 0..<8 where sessions.count < 3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = Weekday.of(day)
            let classes = store.university.classes
                .filter { $0.days.contains(weekday) && (offset > 0 || $0.time.hour * 60 + $0.time.minute > minute) }
                .sorted { $0.time < $1.time }
            sessions += classes.prefix(3 - sessions.count).map { AppStore.ClassSession(uniClass: $0, dayOffset: offset) }
        }
        return sessions
    }

    private var classesCard: some View {
        let sessions = upcomingClasses
        return Card(title: "Classes", systemImage: "calendar", tint: Palette.blue) {
            Spacer()
            GhostButton(title: "University", trailingChevron: true) { store.go(.university) }
        } content: {
            if classesToday.isEmpty {
                Text("No classes today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            if sessions.isEmpty {
                Text("No classes this week.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(20)
            }
            ForEach(sessions, id: \.id) { session in
                let c = session.uniClass
                DashboardRow(action: { store.go(.university) }) {
                    HStack(spacing: 11) {
                        TimeTile(time: c.time, color: c.color)
                        RowText(title: c.subject, detail: [session.dayLabel, c.code, c.room].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    }
                }
            }
        }
    }

    /// Upcoming exams, assignments, office tasks and cards in progress, soonest first.
    private var deadlineItems: [Deadline] {
        var items: [Deadline] = []
        if store.isEnabled(.university) {
            items += store.university.exams.map { Deadline(id: $0.id, title: "\($0.subject) \($0.kind.rawValue.lowercased())", detail: $0.kind.rawValue, date: $0.date, page: .university) }
            items += store.university.assignments.filter { !$0.done }.compactMap { a in
                a.due.map { Deadline(id: a.id, title: a.title, detail: "Assignment", date: $0, page: .university) }
            }
        }
        if store.isEnabled(.office) {
            items += store.office.filter { !$0.done }.compactMap { t in t.due.map { Deadline(id: t.id, title: t.title, detail: "Office", date: $0, page: .office) } }
        }
        if store.isEnabled(.products) {
            items += store.cards(in: .inProgress).compactMap { card in
                card.due.map { Deadline(id: card.id, title: card.title, detail: store.product(card.productID)?.name ?? "Product Dev", date: $0, page: .products, productID: card.productID) }
            }
        }
        return Array(items.filter { (Day.fromToday($0.date) ?? -1) >= 0 }.sorted { $0.date < $1.date }.prefix(4))
    }

    private func deadlinesCard(_ deadlines: [Deadline]) -> some View {
        Card(title: "Deadline countdown", systemImage: "clock", tint: Color.dynamic(light: 0xD98A00, dark: 0xFFC14D)) {
            if deadlines.isEmpty {
                Text("Nothing due soon.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(20)
            }
            ForEach(deadlines) { item in
                let n = Day.fromToday(item.date) ?? 0
                DashboardRow(action: {
                    if let id = item.productID { store.selectedProduct = id }
                    store.go(item.page)
                }) {
                    HStack(spacing: 11) {
                        Text("\(Text("\(n)").font(.system(size: 24, weight: .heavy)))\(Text("d").font(.system(size: 12, weight: .bold)))")
                            .kerning(-0.6)
                            .monospacedDigit()
                            .foregroundStyle(n <= 2 ? Palette.red : n <= 5 ? Palette.amber : .primary)
                            .frame(width: 40)
                        RowText(title: item.title, detail: "\(item.detail) \u{00B7} \(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    }
                }
            }
        }
    }

    private var productCard: some View {
        let inProgress = store.cards(in: .inProgress).compactMap { card in store.product(card.productID).map { (card: card, project: $0) } }
        return Card(title: "Product activity", systemImage: Page.products.systemImage, tint: Page.products.tint) {
            Spacer()
            GhostButton(title: "Open boards", trailingChevron: true) { store.go(.products) }
        } content: {
            if inProgress.isEmpty {
                EmptyStateView(systemImage: Page.products.systemImage, title: "Nothing in progress")
            } else {
                ForEach(inProgress, id: \.card.id) { item in
                    DashboardRow(action: {
                        store.selectedProduct = item.project.id
                        store.go(.products)
                    }) {
                        HStack(spacing: 11) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(item.project.color)
                                .frame(width: 26, height: 26)
                                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.card.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                                Text("\(Text(item.project.name).fontWeight(.semibold).foregroundStyle(item.project.color)) \u{00B7} in progress")
                                    .font(.system(size: 12)).foregroundStyle(Palette.ink2).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let due = item.card.due {
                                Badge(text: due.formatted(.dateTime.weekday(.abbreviated)), color: Palette.ink2)
                            }
                        }
                    }
                }
            }
        }
    }

    private var jobStudyCard: some View {
        let topics = store.jobStudy.flatMap(\.topics)
        let covered = topics.isEmpty ? 0 : topics.filter { $0.revisions > 0 }.count * 100 / topics.count
        let subjects = store.jobStudy.sorted { $0.percent > $1.percent }.prefix(5)
        return Card(title: "Job Study", systemImage: Page.jobStudy.systemImage, tint: Page.jobStudy.tint) {
            Spacer()
            GhostButton(title: "Revise", trailingChevron: true) { store.go(.jobStudy) }
        } content: {
            HStack(spacing: 10) {
                studyNumber("\(store.count(for: .jobStudy))", "topics due")
                studyNumber("\(covered)%", "covered")
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            if subjects.isEmpty {
                Text("No subjects yet.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(16)
            } else {
                VStack(spacing: 8) {
                    ForEach(subjects) { s in DashboardBar(label: s.subject, value: s.percent, color: s.color) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .onTapGesture { store.go(.jobStudy) }
    }

    private func studyNumber(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 20, weight: .heavy)).kerning(-0.4).foregroundStyle(Palette.amber).monospacedDigit()
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var syllabusCard: some View {
        Card(title: "Syllabus progress", systemImage: "book.closed", tint: Palette.green) {
            Spacer()
            GhostButton(title: "University", trailingChevron: true) { store.go(.university) }
        } content: {
            if store.university.syllabus.isEmpty {
                Text("No syllabus subjects yet.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.university.syllabus) { s in
                        DashboardBar(label: s.subject, value: s.percent, color: s.percent == 100 ? Palette.green : Page.university.tint)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

/// An item in Deadline countdown.
private struct Deadline: Identifiable {
    var id: ID
    var title: String
    var detail: String
    var date: Date
    var page: Page
    var productID: ID?
}

// MARK: Dashboard pieces

/// Lays the dashboard's card columns side by side (the first a little wider), two on a medium page, stacked on
/// a narrow one.
private struct DashboardColumns: View {
    var columns: [AnyView]
    @Environment(\.pageWidth) private var width

    var body: some View {
        let count = width >= 1000 ? columns.count : width >= 720 ? min(2, columns.count) : 1
        if count <= 1 {
            VStack(spacing: 12) { ForEach(columns.indices, id: \.self) { columns[$0] } }
        } else {
            // Columns that don't fit go under the last one.
            let shown = Array(columns.prefix(count - 1)) + [AnyView(VStack(spacing: 12) {
                ForEach((count - 1)..<columns.count, id: \.self) { columns[$0] }
            })]
            WeightedColumns(weights: [1.15] + Array(repeating: 1, count: count - 1), spacing: 12) {
                ForEach(shown.indices, id: \.self) { shown[$0] }
            }
        }
    }
}

/// Top-aligned columns whose widths follow `weights`.
private struct WeightedColumns: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat

    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let w = Array(weights.prefix(n))
        let sum = w.reduce(0, +)
        return w.map { (total - spacing * CGFloat(n - 1)) * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 1000
        let w = widths(total, subviews.count)
        let height = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, w) in zip(subviews, widths(bounds.width, subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: nil))
            x += w + spacing
        }
    }
}

/// A clickable card row that tints on hover (the design's `.d-row`).
private struct DashboardRow<Content: View>: View {
    /// Inner horizontal inset; rows inside a padded list (Today's focus) use a smaller one and round corners.
    var inset: CGFloat = 16
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = HoverState()

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, inset)
            .padding(.vertical, 8)
            .background { HoverFill(hover: hover, color: Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: inset < 16 ? 10 : 0, style: .continuous)) }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hover.isOn = $0 }
    }
}

/// Bold title over a grey detail line.
private struct RowText: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.ink2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "6:00 / PM" on a wash of the class colour.
private struct TimeTile: View {
    var time: ClockTime
    var color: Color

    var body: some View {
        let h = (time.hour + 11) % 12 + 1
        VStack(spacing: 0) {
            Text(String(format: "%d:%02d", h, time.minute)).font(.system(size: 14, weight: .bold)).monospacedDigit()
            Text(time.hour >= 12 ? "PM" : "AM").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(color)
        .frame(width: 52)
        .padding(.vertical, 5)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "Label ........ 30%" over a thin bar (the design's `.d-bar`).
private struct DashboardBar: View {
    var label: String
    var value: Int
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).foregroundStyle(Palette.ink2).lineLimit(1)
                Spacer()
                Text("\(value)%").fontWeight(.bold).monospacedDigit()
            }
            .font(.system(size: 12))
            ProgressBar(value: Double(value), color: color, height: 5)
        }
    }
}

/// Space name with a dot, in the space's colour (the focus list's chips).
private struct DotChip: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }
}

/// The focus list's square checkbox; ticking completes the item.
private struct SquareCheck: View {
    var action: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Palette.ink3, lineWidth: 1.6)
                .background { HoverFill(hover: hover, color: Color.accentColor.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .accessibilityLabel("Complete")
    }
}

/// Concentric activity rings with a legend, on frosted glass (the design's `.d-rings`).
struct ProgressRings: View {
    struct Ring: Identifiable {
        var label: String
        var percent: Int
        var color: Color
        var id: String { label }
    }

    var rings: [Ring]

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let inset = CGFloat(index) * 13
                    Circle().stroke(ring.color.opacity(0.16), lineWidth: 10).padding(inset)
                    Circle()
                        .trim(from: 0, to: max(0.005, min(1, Double(ring.percent) / 100)))
                        .stroke(ring.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                        .animation(.smooth(duration: 0.7), value: ring.percent)
                }
            }
            .padding(5)
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rings) { ring in
                    HStack(spacing: 8) {
                        Circle().fill(ring.color).frame(width: 8, height: 8)
                        Text(ring.label).foregroundStyle(Palette.ink2).frame(minWidth: 120, alignment: .leading)
                        Text("\(ring.percent)%").fontWeight(.bold).monospacedDigit()
                    }
                    .font(.system(size: 12.5))
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color.dynamic(light: 0xFFFFFF, dark: 0x2A2B33).opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

#Preview {
    DashboardView().environment(AppStore()).frame(width: 1000, height: 900)
}

private extension FocusItem {
    var page: Page { switch kind { case .todo: .todos; case .office: .office; case .assignment: .university } }
    var spaceName: String { switch kind { case .todo: "Todo"; case .office: "Office"; case .assignment: "University" } }
}
