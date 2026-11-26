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
        let workout = store.isEnabled(.workout)
        let office = store.isEnabled(.office)
        let jobStudy = store.isEnabled(.jobStudy)
        PageScroll {
            hero(focusCount: focus.count)

            StatGrid(count: 1 + [office, university, jobStudy].filter { $0 }.count) {
                StatTile(systemImage: "checklist", label: "Open todos", value: "\(store.todos.filter { !$0.done }.count)",
                         foot: "\(store.todos.filter { !$0.done && $0.priority == .high }.count) high priority", color: Page.todos.tint)
                if office {
                    StatTile(systemImage: "briefcase", label: "Office due", value: "\(store.office.filter { !$0.done && (Day.fromToday($0.due) ?? 1) <= 0 }.count)",
                             foot: "due today or overdue", color: Page.office.tint)
                }
                if university {
                    let open = store.university.assignments.filter { !$0.done }
                    let thisWeek = open.filter { (Day.fromToday($0.due) ?? 7) < 7 }.count
                    StatTile(systemImage: "flag", label: "Assignments", value: "\(open.count)",
                             foot: open.isEmpty ? "nothing open" : "\(thisWeek) due this week", color: Page.university.tint)
                }
                if jobStudy {
                    let topics = store.jobStudy.flatMap(\.topics)
                    StatTile(systemImage: Page.jobStudy.systemImage, label: "Topics due", value: "\(store.count(for: .jobStudy))",
                             foot: "\(topics.filter(\.revisedToday).count) revised today", color: Page.jobStudy.tint)
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
        return Card(title: "Product activity", systemImage: "square.stack.3d.up", tint: Page.products.tint) {
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
        Card(title: "Training", systemImage: "flame", tint: Page.workout.tint) {
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

#Preview {
    DashboardView().environment(AppStore()).frame(width: 1000, height: 900)
}

private extension FocusItem {
    var page: Page { switch kind { case .todo: .todos; case .office: .office; case .assignment: .university } }
}
