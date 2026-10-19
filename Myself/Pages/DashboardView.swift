import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store

    private struct FocusItem: Identifiable {
        enum Kind { case todo, office, assignment }
        let id: ID
        let kind: Kind
        let title: String
        let due: Date?

        var label: String { switch kind { case .todo: "Todo"; case .office: "Office"; case .assignment: "Assignment" } }
        var color: Color { switch kind { case .todo: Palette.blue; case .office: .accentColor; case .assignment: Palette.red } }
        var page: Page { switch kind { case .todo: .todos; case .office: .office; case .assignment: .university } }
    }

    /// Due today or overdue (assignments: due tomorrow too).
    private var focus: [FocusItem] {
        var items: [FocusItem] = []
        items += store.todos.filter { !$0.done && (Day.fromToday($0.due) ?? 1) <= 0 }
            .map { FocusItem(id: $0.id, kind: .todo, title: $0.title, due: $0.due) }
        if store.isEnabled(.office) {
            items += store.office.filter { !$0.done && (Day.fromToday($0.due) ?? 1) <= 0 }
                .map { FocusItem(id: $0.id, kind: .office, title: $0.title, due: $0.due) }
        }
        if store.isEnabled(.university) {
            items += store.university.assignments.filter { !$0.done && (Day.fromToday($0.due) ?? 2) <= 1 }
                .map { FocusItem(id: $0.id, kind: .assignment, title: $0.title, due: $0.due) }
        }
        return items.sorted { (Day.fromToday($0.due) ?? 0) < (Day.fromToday($1.due) ?? 0) }
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
        let workout = store.isEnabled(.workout)
        let office = store.isEnabled(.office)
        let jobStudy = store.isEnabled(.jobStudy)
        PageScroll {
            hero(focusCount: focus.count)

            StatGrid(count: 1 + [office, university, jobStudy].filter { $0 }.count) {
                StatTile(systemImage: "checklist", label: "Open todos", value: "\(store.todos.filter { !$0.done }.count)",
                         foot: "\(store.todos.filter { !$0.done && $0.priority == .high }.count) high priority", color: Palette.blue)
                if office {
                    StatTile(systemImage: "briefcase", label: "Office due", value: "\(store.office.filter { !$0.done && (Day.fromToday($0.due) ?? 1) <= 0 }.count)",
                             foot: "due today or overdue", color: .accentColor)
                }
                if university {
                    let open = store.university.assignments.filter { !$0.done }
                    let thisWeek = open.filter { (Day.fromToday($0.due) ?? 7) < 7 }.count
                    StatTile(systemImage: "flag", label: "Assignments", value: "\(open.count)",
                             foot: open.isEmpty ? "nothing open" : "\(thisWeek) due this week", color: Palette.violet)
                }
                if jobStudy {
                    let topics = store.jobStudy.flatMap(\.topics)
                    StatTile(systemImage: "book.closed", label: "Topics due", value: "\(store.count(for: .jobStudy))",
                             foot: "\(topics.filter(\.revisedToday).count) revised today", color: Palette.amber)
                }
            }

            if university || workout {
                AdaptiveColumns {
                    focusCard(focus)
                    if store.isEnabled(.products) { productCard }
                } trailing: {
                    if university {
                        classesCard
                        deadlinesCard
                        syllabusCard
                    }
                    if workout { trainingCard }
                }
            } else {
                // Nothing for the right column: let the remaining cards use the full width.
                focusCard(focus)
                if store.isEnabled(.products) { productCard }
            }
        }
    }

    // MARK: Sections

    private func hero(focusCount: Int) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.weekdayMonthDay).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
                Text("\(greeting).").font(.system(size: 26, weight: .bold)).padding(.top, 4)
                summary(focusCount: focusCount).font(.system(size: 13.5)).foregroundStyle(Palette.ink2).padding(.top, 6)
            }
            Spacer(minLength: 0)
            if store.isEnabled(.university) {
                let pct = store.university.syllabusPercent
                Donut(value: Double(pct), size: 92, lineWidth: 9, color: Palette.green) {
                    VStack(spacing: 0) {
                        Text("\(pct)%").font(.numeral(22))
                        Text("syllabus").font(.system(size: 9.5)).foregroundStyle(Palette.ink3)
                    }
                }
            }
        }
        .padding(.bottom, 2)
    }

    private func summary(focusCount: Int) -> Text {
        guard store.isEnabled(.university) else {
            if focusCount > 0 {
                let count = Text("\(focusCount)").fontWeight(.semibold).foregroundStyle(Color.accentColor)
                return Text("You have \(count) \(focusCount == 1 ? "thing" : "things") due today.")
            }
            return Text("Nothing overdue — a clean slate.")
        }
        let n = classesToday.count
        let classes = "\(n) \(n == 1 ? "class" : "classes")"
        if focusCount > 0 {
            let count = Text("\(focusCount)").fontWeight(.semibold).foregroundStyle(Color.accentColor)
            return Text("You have \(count) \(focusCount == 1 ? "thing" : "things") due today and \(classes) scheduled.")
        }
        return Text(n == 0 ? "Nothing overdue — a clean slate. No classes today." : "Nothing overdue — a clean slate. \(classes) today.")
    }

    private func focusCard(_ focus: [FocusItem]) -> some View {
        Card(title: "Today's focus", systemImage: "target", tint: .accentColor) {
            Spacer()
            CountText(value: focus.count)
        } content: {
            if focus.isEmpty {
                EmptyStateView(systemImage: "checkmark", title: "All caught up", subtitle: "Nothing due today. Enjoy it.")
            } else {
                ForEach(focus) { item in
                    ListRow(verticalPadding: 9) {
                        HStack(alignment: .top, spacing: 10) {
                            CheckCircle(isOn: false) { complete(item) }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.system(size: 13, weight: .medium))
                                FlowLayout {
                                    Badge(text: item.label, color: item.color)
                                    DueBadge(date: item.due)
                                }
                            }
                        }
                    }
                    .onTapGesture { store.go(item.page) }
                }
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

    private var classesCard: some View {
        Card(title: "Classes today", systemImage: "calendar", tint: Palette.blue) {
            if classesToday.isEmpty {
                Text("No classes today.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(24)
            } else {
                ForEach(classesToday) { c in
                    ListRow(verticalPadding: 9) {
                        HStack(spacing: 10) {
                            Text(c.time.formatted)
                                .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(c.color)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(c.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.subject).font(.system(size: 13, weight: .medium))
                                Text("\(c.code) · \(c.room)").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                            }
                        }
                    }
                    .onTapGesture { store.go(.university) }
                }
            }
        }
    }

    private var deadlinesCard: some View {
        let deadlines = store.university.exams
            .filter { (Day.fromToday($0.date) ?? -1) >= 0 }
            .sorted { $0.date < $1.date }
            .prefix(4)
        return Card(title: "Deadline countdown", systemImage: "clock", tint: Palette.amber) {
            if deadlines.isEmpty {
                Text("No upcoming exams.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(24)
            }
            ForEach(deadlines) { exam in
                let n = Day.fromToday(exam.date) ?? 0
                ListRow(verticalPadding: 9) {
                    HStack(spacing: 10) {
                        Text("\(Text("\(n)").font(.numeral(22)))\(Text("d").font(.numeral(13)))")
                            .foregroundStyle(n <= 5 ? Palette.red : n <= 10 ? Palette.amber : .primary)
                            .frame(minWidth: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exam.subject).font(.system(size: 13, weight: .medium))
                            Text("\(exam.kind.rawValue) · \(exam.date.monthDay)").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                        }
                    }
                }
                .onTapGesture { store.go(.university) }
            }
        }
    }

    private var productCard: some View {
        let inProgress = store.cards(in: .inProgress).compactMap { card in store.product(card.productID).map { (card: card, project: $0) } }
        return Card(title: "Product activity", systemImage: "shippingbox", tint: Palette.cyan) {
            Spacer()
            GhostButton(title: "Open boards", trailingChevron: true) { store.go(.products) }
        } content: {
            if inProgress.isEmpty {
                EmptyStateView(systemImage: "shippingbox", title: "Nothing in progress")
            } else {
                ForEach(inProgress, id: \.card.id) { item in
                    ListRow(verticalPadding: 9) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(item.project.color)
                                .frame(width: 26, height: 26)
                                .background(item.project.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.card.title).font(.system(size: 13, weight: .medium))
                                FlowLayout {
                                    Badge(text: item.project.name, color: item.project.color)
                                    DueBadge(date: item.card.due)
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        store.selectedProduct = item.project.id
                        store.go(.products)
                    }
                }
            }
        }
    }

    /// Workout is still sample data (`Page.isComingSoon`), so the card only announces it.
    private var trainingCard: some View {
        Card(title: "Training", systemImage: "dumbbell", tint: Palette.red) {
            Spacer()
            Badge(text: "Coming soon", systemImage: "sparkles", color: .accentColor)
        } content: {
            Text("\(Page.workout.featureDescription) are on the way.")
                .font(.system(size: 13)).foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity).padding(24)
        }
    }

    private var syllabusCard: some View {
        Card(title: "Syllabus progress", systemImage: "book.closed", tint: Palette.green) {
            if store.university.syllabus.isEmpty {
                Text("No syllabus subjects yet.").font(.system(size: 13)).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).padding(24)
            } else {
                VStack(spacing: 11) {
                    ForEach(store.university.syllabus) { s in
                        LabeledProgress(label: s.subject, value: s.percent, color: s.percent == 100 ? Palette.green : .accentColor)
                    }
                }
                .padding(16)
            }
        }
    }
}

#Preview {
    DashboardView().environment(AppStore()).frame(width: 1000, height: 900)
}
