import SwiftUI

/// Subjects → a revision checklist. Ticking a topic logs one revision for today, ± corrects the count,
/// and topics can link notes, which open in their own window.
struct JobStudyView: View {
    var body: some View {
        PageScroll { JobStudyContent() }
    }
}

private enum TopicFilter: String, CaseIterable {
    case all = "All", due = "Due", today = "Revised today"

    func includes(_ t: StudyTopic) -> Bool {
        switch self {
        case .all: true
        case .due: t.isDue
        case .today: t.revisedToday
        }
    }
}

private struct JobStudyContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.pageWidth) private var width
    @State private var selection: ID?
    @State private var editing: StudySubject?
    @State private var deleting: StudySubject?

    var body: some View {
        let active = store.jobStudy.first { $0.id == selection } ?? store.jobStudy.first

        Group {
            if width >= 820 {
                HStack(alignment: .top, spacing: 16) {
                    sidebar(active: active).frame(width: 240)
                    main(active)
                }
            } else {
                VStack(spacing: 16) {
                    sidebar(active: active)
                    main(active)
                }
            }
        }
        .sheet(item: $editing) { subject in
            StudySubjectSheet(draft: subject, undoManager: undoManager) { selection = $0 }
        }
        .confirmationDialog("Delete \u{201C}\(deleting?.subject ?? "")\u{201D}?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Subject", role: .destructive) {
                if let deleting { withAnimation { store.deleteStudySubject(deleting.id, undoManager: undoManager) } }
            }
        } message: {
            Text("Its \(deleting?.topics.count ?? 0) topics are deleted too.")
        }
    }

    // MARK: Subjects

    private func sidebar(active: StudySubject?) -> some View {
        let all = store.jobStudy.flatMap(\.topics)
        let covered = Int((100 * Double(all.filter { $0.revisions > 0 }.count) / Double(max(1, all.count))).rounded())

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Subjects").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink3)
                Spacer()
                IconButton(systemImage: "plus", help: "Add subject", action: newSubject)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Group {
                if width >= 820 {
                    VStack(spacing: 2) { subjectButtons(active: active) }
                } else {
                    FlowLayout(spacing: 2, lineSpacing: 2) { subjectButtons(active: active) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)

            if store.jobStudy.isEmpty {
                Text("No subjects yet.").font(.system(size: 12)).foregroundStyle(Palette.ink3).padding(.horizontal, 16).padding(.bottom, 10)
            }

            Divider().overlay(Palette.border)
            HStack(spacing: 0) {
                footerStat(all.reduce(0) { $0 + $1.revisions }.formatted(), "revisions")
                footerStat("\(all.filter(\.isDue).count)", "due")
                footerStat("\(covered)%", "covered")
            }
            .padding(.vertical, 10)
        }
        .cardBackground()
    }

    @ViewBuilder
    private func subjectButtons(active: StudySubject?) -> some View {
        ForEach(store.jobStudy) { s in
            SubjectButton(subject: s, isSelected: s.id == active?.id, fixedWidth: width < 820) { selection = s.id }
        }
    }

    private func footerStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private func newSubject() {
        editing = StudySubject(subject: "", hex: Palette.swatches[store.jobStudy.count % Palette.swatches.count])
    }

    // MARK: Topics

    @ViewBuilder
    private func main(_ active: StudySubject?) -> some View {
        if let active {
            SubjectChecklist(subject: active, onEdit: { editing = active }, onDelete: {
                if active.topics.isEmpty {
                    withAnimation { store.deleteStudySubject(active.id, undoManager: undoManager) }
                } else {
                    deleting = active
                }
            })
            .id(active.id)
        } else {
            EmptyStateView(systemImage: "book", title: "No subjects yet", subtitle: "Add a subject and list topics to track revisions.")
                .frame(maxWidth: .infinity)
                .cardBackground()
        }
    }
}

private struct SubjectButton: View {
    var subject: StudySubject
    var isSelected: Bool
    /// In the narrow layout the subjects wrap, so each one gets a fixed width instead of the column's.
    var fixedWidth: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let due = subject.dueCount
        Button(action: action) {
            HStack(spacing: 10) {
                ColorDot(color: subject.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(subject.subject).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text("\(subject.topics.count) topics" + (due > 0 ? " · \(due) due" : ""))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(subject.percent)%").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Palette.ink2)
            }
            .padding(8)
            .frame(width: fixedWidth ? 200 : nil)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : hovering ? Palette.surface2 : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SubjectChecklist: View {
    @Environment(AppStore.self) private var store
    @Environment(\.pageWidth) private var width
    var subject: StudySubject
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var filter = TopicFilter.all

    var body: some View {
        let pct = subject.percent
        let shown = subject.topics.filter(filter.includes)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 9) {
                        ColorDot(color: subject.color)
                        Text(subject.subject).font(.system(size: 17, weight: .bold))
                    }
                    HStack(spacing: 10) {
                        ProgressBar(value: Double(pct), color: pct == 100 ? Palette.green : .accentColor, height: 5)
                            .frame(maxWidth: 280)
                        Text("\(pct)% revised at least once").font(.system(size: 11.5)).foregroundStyle(Palette.ink3).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(systemImage: "pencil", help: "Edit subject", action: onEdit)
                IconButton(systemImage: "trash", help: "Delete subject", action: onDelete)
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 4) {
                ForEach(TopicFilter.allCases, id: \.self) { f in
                    FilterPill(title: f.rawValue, count: subject.topics.filter(f.includes).count, isOn: filter == f) { filter = f }
                }
                Spacer(minLength: 8)
                if width >= 640 {
                    Text("Tick = +1 revision today · ± to correct · double-click to rename")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            Divider().overlay(Palette.border)

            // Lazy, so opening a subject with many topics builds only the rows on screen, not all of them at once.
            LazyVStack(spacing: 0) {
                ForEach(shown) { t in
                    TopicRow(subject: subject.id, topic: t)
                }
            }
            if shown.isEmpty {
                Text(emptyMessage).font(.system(size: 12)).foregroundStyle(Palette.ink3).padding(18)
            }
            if filter == .all {
                InlineAdder(placeholder: "Add topic…") { store.addStudyTopic(subject: subject.id, name: $0) }
                    .padding(.leading, 18)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
                    .modifier(TopicDrop(subject: subject.id, before: nil))
            }
        }
        .cardBackground()
    }

    private var emptyMessage: String {
        if subject.topics.isEmpty { return "No topics yet." }
        switch filter {
        case .due: return "Nothing due \u{2014} every topic was revised in the last \(StudyTopic.dueDays) days."
        case .today: return "Nothing revised today yet."
        case .all: return ""
        }
    }
}

private struct FilterPill: View {
    var title: String
    var count: Int
    var isOn: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(isOn ? Color.primary : Palette.ink2)
                Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isOn || hovering ? Palette.surface2 : .clear, in: Capsule())
            .overlay { Capsule().strokeBorder(isOn ? Palette.border : .clear) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct TopicRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.pageWidth) private var width
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    var subject: ID
    var topic: StudyTopic
    @State private var hover = HoverState()
    @State private var renaming = false
    @State private var name = ""
    @State private var picking = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let compact = width < 640
        HStack(alignment: compact ? .top : .center, spacing: 12) {
            CheckCircle(isOn: topic.revisedToday) { withAnimation { store.reviseTopic(subject: subject, topic: topic.id) } }
                .help(topic.revisedToday ? "Undo today\u{2019}s revision" : "Revised today")
            if compact {
                VStack(alignment: .leading, spacing: 6) {
                    topicBody
                    HStack {
                        lastRevised
                        Spacer()
                        stepper
                    }
                }
                actions.opacity(1)
            } else {
                topicBody.frame(maxWidth: .infinity, alignment: .leading)
                lastRevised.frame(minWidth: 64, alignment: .trailing)
                stepper
                actions
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .background { HoverFill(hover: hover, color: Palette.surface2.opacity(0.6)) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }
        .onHover { hover.isOn = $0 }
        .modifier(TopicDrag(topic: topic.id, enabled: !renaming))
        .modifier(TopicDrop(subject: subject, before: topic.id))
    }

    // MARK: Parts

    private var topicBody: some View {
        // Summaries, not notes: they only change when a title does, so typing in a note doesn't redraw every topic.
        let linked = topic.noteIDs.compactMap { id in store.noteSummaries.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 6) {
            if renaming {
                TextField("Topic", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5)) }
                    .padding(.horizontal, -7)
                    .padding(.vertical, -4)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                    #if os(macOS)
                    .onExitCommand { renaming = false }
                    #endif
            } else {
                Text(topic.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(topic.revisedToday ? Palette.ink2 : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: startRename)
            }
            if !linked.isEmpty, store.isEnabled(.notes) {
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(linked) { note in
                        NoteChip(title: note.displayTitle, open: { open(note.id) }) {
                            store.toggleTopicNote(subject: subject, topic: topic.id, note: note.id)
                        }
                    }
                }
            }
        }
    }

    private var lastRevised: some View {
        Text(topic.lastRevisedText)
            .font(.system(size: 11.5))
            .foregroundStyle(topic.isDue ? Palette.amber : Palette.ink3)
            .help(topic.isDue ? "Due \u{2014} not revised in the last \(StudyTopic.dueDays) days" : "Last revised")
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", "Remove a revision", delta: -1).disabled(topic.revisions == 0)
            Text("\(topic.revisions)\u{00D7}")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 26)
            stepButton("plus", "Add a revision", delta: 1)
        }
        .background(Palette.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.border) }
    }

    private func stepButton(_ systemImage: String, _ help: String, delta: Int) -> some View {
        Button { withAnimation { store.adjustRevisions(subject: subject, topic: topic.id, by: delta) } } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.ink2)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if store.isEnabled(.notes) {
                IconButton(systemImage: "link", help: "Link notes") { picking.toggle() }
                    .popover(isPresented: $picking, arrowEdge: .bottom) {
                        NotePicker(topicName: topic.name, linked: topic.noteIDs,
                                   onToggle: { store.toggleTopicNote(subject: subject, topic: topic.id, note: $0) },
                                   onCreate: createNote)
                    }
            }
            IconButton(systemImage: "trash", help: "Delete topic") {
                withAnimation { store.deleteStudyTopic(subject: subject, topic: topic.id, undoManager: undoManager) }
            }
        }
        .modifier(HoverOpacity(hover: hover, off: 0.35, forced: picking))
    }

    // MARK: Actions

    private func startRename() {
        name = topic.name
        renaming = true
        nameFocused = true
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        store.renameStudyTopic(subject: subject, topic: topic.id, to: name)
    }

    private func createNote(_ title: String) {
        picking = false
        let note = store.addTopicNote(subject: subject, topic: topic.id, title: title.isEmpty ? topic.name : title)
        open(note.id)
    }

    /// Opens a linked note in its own window on macOS, or on the Notes page elsewhere.
    private func open(_ id: ID) {
        #if os(macOS)
        openWindow(id: NoteWindow.id, value: id)
        #else
        store.openNote(id)
        #endif
    }
}

/// Topics drag as `topic:<id>`, so a card or note dragged in from elsewhere isn't taken for one.
private let topicDragPrefix = "topic:"

private struct TopicDrag: ViewModifier {
    var topic: ID
    var enabled: Bool

    func body(content: Content) -> some View {
        // Off while renaming, so dragging in the text field selects text.
        if enabled { content.draggable(topicDragPrefix + topic) } else { content }
    }
}

/// Dropping a topic on a row moves it above that row; on the adder (`before` nil), to the end.
private struct TopicDrop: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var subject: ID
    var before: ID?
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isTargeted {
                    Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -1.5).padding(.horizontal, 12)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first, item.hasPrefix(topicDragPrefix) else { return false }
                let topic = String(item.dropFirst(topicDragPrefix.count))
                withAnimation(.snappy) { store.moveStudyTopic(subject: subject, topic: topic, before: before, undoManager: undoManager) }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

/// A linked note under a topic: click to open it, × to unlink.
private struct NoteChip: View {
    var title: String
    var open: () -> Void
    var unlink: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "note.text").font(.system(size: 10))
            Text(title).lineLimit(1).truncationMode(.tail)
            Button(action: unlink) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.ink3)
            }
            .buttonStyle(.plain)
            .help("Unlink note")
            #if os(macOS)
            .opacity(hovering ? 1 : 0)
            #endif
        }
        .font(.system(size: 11.5))
        .foregroundStyle(hovering ? Color.accentColor : Palette.ink2)
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: 260, alignment: .leading)
        .background(hovering ? Color.accentColor.opacity(0.12) : Palette.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(hovering ? Color.accentColor.opacity(0.4) : Palette.border) }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help("Open in new window")
    }
}

/// Popover for linking notes to a topic: search, tick to link or unlink, or create a new note.
private struct NotePicker: View {
    @Environment(AppStore.self) private var store
    var topicName: String
    var linked: [ID]
    var onToggle: (ID) -> Void
    var onCreate: (String) -> Void
    @State private var query = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let results = store.notes
            .filter { q.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(q) }
            .sorted { a, b in
                let (la, lb) = (linked.contains(a.id), linked.contains(b.id))
                return la != lb ? la : a.editedAt > b.editedAt
            }
            .prefix(40)

        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.ink3)
                TextField("Search notes to link", text: $query).textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            Divider().overlay(Palette.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if results.isEmpty {
                        Text(q.isEmpty ? "No notes yet." : "No notes match \u{201C}\(q)\u{201D}")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    ForEach(results) { note in
                        PickerRow(note: note, category: store.noteCategory(note.categoryID), isOn: linked.contains(note.id)) { onToggle(note.id) }
                    }
                }
                .padding(4)
            }
            .frame(height: 260)
            Divider().overlay(Palette.border)

            Button { onCreate(q) } label: {
                Label("New note \u{201C}\(q.isEmpty ? topicName : q)\u{201D}", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
    }
}

private struct PickerRow: View {
    var note: Note
    var category: NoteCategory?
    var isOn: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Color.accentColor : .clear)
                    .strokeBorder(isOn ? Color.accentColor : Palette.border)
                    .frame(width: 16, height: 16)
                    .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) } }
                Text(note.displayTitle).font(.system(size: 13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let category {
                    HStack(spacing: 5) {
                        ColorDot(color: category.color, size: 7)
                        Text(category.name)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? Palette.surface2 : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Borderless icon button used in the Job Study headers and rows.
private struct IconButton: View {
    var systemImage: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12)).foregroundStyle(Palette.ink2).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Add / edit sheet for a subject's name and colour.
private struct StudySubjectSheet: View {
    @Environment(AppStore.self) private var store
    @State var draft: StudySubject
    var undoManager: UndoManager?
    /// Called with the subject's ID after saving, so the page can select a new subject.
    var onSave: (ID) -> Void
    @FocusState private var focused: Bool

    private var isNew: Bool { !store.jobStudy.contains { $0.id == draft.id } }

    var body: some View {
        EditorForm(title: isNew ? "New Subject" : "Edit Subject", isNew: isNew, canSave: !trimmed(draft.subject).isEmpty, onSave: save) {
            Section {
                TextField("Subject", text: $draft.subject, prompt: Text("System Design"))
                    .focused($focused)
            }
            Section("Colour") {
                SwatchPicker(hex: $draft.hex)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        draft.subject = trimmed(draft.subject)
        // Topics may have changed while the sheet was open; only the name and colour come from it.
        if let current = store.jobStudy.first(where: { $0.id == draft.id }) { draft.topics = current.topics }
        store.saveStudySubject(draft, undoManager: undoManager)
        onSave(draft.id)
    }
}

#Preview {
    JobStudyView().environment(AppStore()).frame(width: 900, height: 700)
}
