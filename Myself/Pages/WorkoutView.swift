import SwiftUI

struct WorkoutView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: ID?

    var body: some View {
        let w = store.workout
        let selected = w.programs.first { $0.id == selection } ?? w.programs.first

        content(w, selected: selected)
            .blur(radius: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay { ComingSoonCard(page: .workout) }
    }

    private func content(_ w: WorkoutData, selected: WorkoutProgram?) -> some View {
        PageScroll {
            hero(w)

            HStack(alignment: .firstTextBaseline) {
                Text("Programs").font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(w.programs.count) active").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
            }
            .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 13)], spacing: 13) {
                ForEach(w.programs) { p in
                    ProgramCard(program: p, isActive: p.id == selected?.id) { selection = p.id }
                }
            }

            if let selected {
                HStack(spacing: 10) {
                    ColorDot(color: selected.color, size: 11)
                    Text(selected.name).font(.system(size: 17, weight: .bold))
                    Badge(text: selected.kind, color: selected.color)
                }
                .padding(.top, 12)

                if selected.weeks.isEmpty {
                    SimpleProgramView(program: selected)
                } else {
                    WeekPlanView(program: selected).id(selected.id)
                }
            }
        }
    }

    private func hero(_ w: WorkoutData) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill").font(.system(size: 24)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Text("\(w.streak)").font(.numeral(32, weight: .bold))) \(Text("days").font(.system(size: 13)).foregroundStyle(Palette.ink3))")
                    Text("current streak").font(.system(size: 11.5)).foregroundStyle(Palette.ink3)
                }
            }
            VStack(spacing: 8) {
                HStack {
                    Text("Last 14 days")
                    Spacer()
                    Text("\(w.sessionsThisWeek) sessions this week")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
                HStack(spacing: 5) {
                    ForEach(Array(w.history.enumerated()), id: \.offset) { i, trained in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(trained ? Color.accentColor.opacity(0.55 + 0.45 * Double(i) / Double(w.history.count)) : Palette.surface3)
                            .frame(height: 30)
                            .help(Day.offset(i - (w.history.count - 1)).monthDay)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            if w.trainedToday {
                Button("Trained today", systemImage: "checkmark") { withAnimation { store.toggleTrainedToday() } }
                    .buttonStyle(.bordered)
            } else {
                Button("Log today", systemImage: "plus") { withAnimation { store.toggleTrainedToday() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .cardBackground()
    }
}

private struct ProgramCard: View {
    var program: WorkoutProgram
    var isActive: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(program.kind.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(program.color)
                    Spacer()
                    Donut(percent: program.percent, size: 46, lineWidth: 5, color: program.color)
                }
                Text(program.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                Text(program.desc).font(.system(size: 12)).foregroundStyle(Palette.ink2).lineLimit(2, reservesSpace: true)
                HStack(spacing: 14) {
                    Label("\(program.daysPerWeek)× / wk", systemImage: "calendar")
                    Label("\(program.sessionMin) min", systemImage: "clock")
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .padding(.top, 4)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(program.color, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Week-by-week accordion. Completed weeks form a prefix; later weeks are locked.
private struct WeekPlanView: View {
    @Environment(AppStore.self) private var store
    var program: WorkoutProgram
    @State private var open: Int?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(program.weeks.indices, id: \.self) { wi in
                weekCard(wi)
            }
        }
        .onAppear { open = min(program.completedWeeks, program.weeks.count - 1) }
    }

    private func weekCard(_ wi: Int) -> some View {
        let week = program.weeks[wi]
        let isDone = wi < program.completedWeeks
        let isCurrent = wi == program.completedWeeks
        let locked = wi > program.completedWeeks
        let expanded = open == wi && !locked
        let tone: Color = isDone ? Palette.green : isCurrent ? .accentColor : Palette.ink3

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !locked else { return }
                withAnimation(.snappy) { open = expanded ? nil : wi }
            } label: {
                HStack(spacing: 14) {
                    Text("W\(wi + 1)").font(.numeral(22)).foregroundStyle(tone).frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(week.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.primary)
                        Text(week.sub).font(.system(size: 12)).foregroundStyle(Palette.ink2)
                    }
                    Spacer()
                    Badge(text: isDone ? "done" : isCurrent ? "current" : "locked", systemImage: isDone ? "checkmark" : nil, color: tone)
                    if !locked {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(Palette.ink3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().overlay(Palette.border)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(week.days.indices, id: \.self) { di in
                        dayRow(week: wi, day: di, week.days[di])
                    }
                    if let milestone = week.milestone {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill").font(.system(size: 20)).foregroundStyle(Palette.amber)
                            Text(milestone).font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button { markWeek(wi) } label: {
                        Label(isDone ? "Week completed — tap to undo" : "Mark week complete", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(isDone ? Palette.green : nil)
                }
                .padding(16)
            }
        }
        .cardBackground()
        .opacity(locked ? 0.6 : 1)
    }

    private func dayRow(week wi: Int, day di: Int, _ day: ProgramDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(day.label.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.ink3).frame(width: 46, alignment: .leading)
            if let name = day.name {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.system(size: 13, weight: .medium))
                    FlowLayout(spacing: 6) {
                        ForEach(day.sets.indices, id: \.self) { si in
                            setChip(day.sets[si], on: program.chips["\(wi)_\(di)"]?.contains(si) == true) {
                                toggleChip(week: wi, day: di, set: si)
                            }
                        }
                    }
                    if let tip = day.tip {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                Text("Rest — walk, stretch, or do nothing.").font(.system(size: 12.5)).italic().foregroundStyle(Palette.ink3)
            }
        }
    }

    private func setChip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
                Text(text)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(on ? Palette.green : Palette.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(on ? Palette.green.opacity(0.15) : Palette.surface2, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Palette.green : Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func toggleChip(week: Int, day: Int, set: Int) {
        var p = program
        let key = "\(week)_\(day)"
        var done = p.chips[key] ?? []
        if done.contains(set) { done.remove(set) } else { done.insert(set) }
        p.chips[key] = done
        store.updateProgram(p)
    }

    private func markWeek(_ wi: Int) {
        var p = program
        p.completedWeeks = wi < p.completedWeeks ? wi : wi + 1
        withAnimation(.snappy) {
            store.updateProgram(p)
            if p.completedWeeks > wi { open = min(wi + 1, p.weeks.count - 1) }
        }
    }
}

private struct SimpleProgramView: View {
    @Environment(AppStore.self) private var store
    var program: WorkoutProgram

    var body: some View {
        HStack(spacing: 16) {
            Donut(value: Double(program.percent), size: 88, lineWidth: 9, color: program.color) {
                VStack(spacing: 0) {
                    Text("\(program.completedWeeks)").font(.numeral(22))
                    Text("/ \(program.totalWeeks) wks").font(.system(size: 10)).foregroundStyle(Palette.ink3)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(program.name).font(.system(size: 16, weight: .semibold))
                Text(program.desc).font(.system(size: 13)).foregroundStyle(Palette.ink2)
                HStack(spacing: 8) {
                    Button("Log a week", systemImage: "checkmark") { bump(1) }
                        .buttonStyle(.borderedProminent)
                    Button("Undo") { bump(-1) }
                        .buttonStyle(.borderless)
                }
                .controlSize(.small)
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardBackground()
    }

    private func bump(_ delta: Int) {
        var p = program
        p.completedWeeks = max(0, min(p.totalWeeks, p.completedWeeks + delta))
        withAnimation { store.updateProgram(p) }
    }
}

#Preview {
    WorkoutView().environment(AppStore()).frame(width: 1000, height: 900)
}
