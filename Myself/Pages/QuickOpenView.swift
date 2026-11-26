import SwiftUI

/// Where a Quick Open result leads.
enum QuickOpenTarget { case page(Page), note(ID), settings, newTodo, newOfficeTask, newNote }

/// ⌘K palette (the v2 design's Quick Open): jump to a page or to any open item, or run an action. In the main window it
/// floats over the page (`QuickOpenOverlay`); on macOS it's also the Spotlight-style panel opened by the system-wide
/// search shortcut, which passes `onClose` and lets `SearchShortcut` open the result. The presenter draws the glass
/// behind it (`quickOpenChrome`, or the panel's own visual effect view).
struct QuickOpenView: View {
    var onClose: (() -> Void)?
    @Environment(AppStore.self) private var store
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    static let width: CGFloat = 640
    static let cornerRadius: CGFloat = 20

    private struct Result {
        let group: String
        let title: String
        let subtitle: String
        let systemImage: String
        let tint: Color
        var shortcut = ""
        let target: QuickOpenTarget
    }

    private static let actionTint = Palette.ink2

    private var all: [Result] {
        let due = { (d: Date?) in DueMeta(d)?.text ?? "" }
        let on = store.isEnabled
        // ⌘1–⌘9 follow a page's position in `Page.allCases`, as in the Go menu.
        var results = store.enabledPages.map { page in
            Result(group: "Go to", title: page.title, subtitle: page.subtitle, systemImage: page.systemImage, tint: page.tint,
                   shortcut: (Page.allCases.firstIndex(of: page)).map { "⌘\($0 + 1)" } ?? "", target: .page(page))
        }
        func item(_ group: String, _ title: String, _ subtitle: String, _ page: Page, _ target: QuickOpenTarget? = nil, image: String? = nil) -> Result {
            Result(group: group, title: title, subtitle: subtitle, systemImage: image ?? page.systemImage, tint: page.tint, target: target ?? .page(page))
        }
        results += store.todos.filter { !$0.done }.map { item("TODOs", $0.title, due($0.due), .todos) }
        if on(.office) {
            results += store.office.filter { !$0.done }.map { item("Office Tasks", $0.title, due($0.due), .office) }
        }
        if on(.university) {
            results += store.university.assignments.filter { !$0.done }.map { item("Assignments", $0.title, due($0.due), .university, image: "flag") }
        }
        if on(.jobStudy) {
            results += store.jobStudy.flatMap { s in s.topics.map { item("Job Study", $0.name, s.subject, .jobStudy) } }
        }
        if on(.notes) {
            results += store.notes.filter { $0.bookID == nil }.map {
                item("Notes", $0.displayTitle, store.noteCategory($0.categoryID)?.name ?? "", .notes, .note($0.id))
            }
        }
        if on(.books) {
            results += store.notes.compactMap { note in
                note.bookID.map { item("Book Notes", note.displayTitle, store.book($0)?.displayTitle ?? "", .books, .note(note.id)) }
            }
        }
        results.append(Result(group: "Actions", title: "New todo", subtitle: "TODOs", systemImage: "plus", tint: Self.actionTint, shortcut: "⌘N", target: .newTodo))
        if on(.office) {
            results.append(Result(group: "Actions", title: "New office task", subtitle: "Office Tasks", systemImage: "plus", tint: Self.actionTint, shortcut: "⇧⌘N", target: .newOfficeTask))
        }
        if on(.notes) {
            results.append(Result(group: "Actions", title: "New note", subtitle: "Notes", systemImage: "plus", tint: Self.actionTint, shortcut: "⌥⌘N", target: .newNote))
        }
        results.append(Result(group: "Actions", title: "Settings", subtitle: "Appearance · Features · iCloud · Data", systemImage: "gearshape", tint: Self.actionTint, shortcut: "⌘,", target: .settings))
        return results
    }

    private var results: [Result] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return all.filter { $0.group == "Go to" || $0.group == "Actions" } }
        let hits = all.filter { "\($0.title) \($0.subtitle) \($0.group)".localizedCaseInsensitiveContains(q) }
        // Pages first, then items (at most 14), then actions.
        let items = hits.filter { $0.group != "Go to" && $0.group != "Actions" }.prefix(14)
        return hits.filter { $0.group == "Go to" } + items + hits.filter { $0.group == "Actions" }
    }

    private func close() {
        if let onClose { onClose() } else { store.isQuickOpenPresented = false }
    }

    private func open(_ r: Result) {
        #if os(macOS)
        if let onClose {
            onClose()
            SearchShortcut.shared.open(r.target)
            return
        }
        #endif
        store.isQuickOpenPresented = false
        switch r.target {
        case .page(let page): store.go(page)
        case .note(let id):
            // On macOS a note opens in its own window, like double-clicking it in the note list.
            #if os(macOS)
            openWindow(id: NoteWindow.id, value: id)
            #else
            store.openNote(id)
            #endif
        case .settings: store.openSettings(.appearance)
        case .newTodo: store.newTodo()
        case .newOfficeTask: store.newOfficeTask()
        case .newNote: store.newNote()
        }
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink2)
                TextField("Search MySelf\u{2026}", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit { if results.indices.contains(selected) { open(results[selected]) } }
                Button(action: close) { PaletteKey("esc", size: 11.5, padding: 7) }
                    .buttonStyle(.plain)
                    .help("Close")
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            Divider().opacity(0.6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if results.isEmpty {
                            Text("No results for \u{201C}\(query)\u{201D}")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        }
                        ForEach(results.indices, id: \.self) { i in
                            let r = results[i]
                            if i == 0 || results[i - 1].group != r.group {
                                Text(r.group)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.ink2)
                                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                            }
                            row(r, isSelected: i == selected)
                                .id(i)
                                .onHover { if $0 { selected = i } }
                                .onTapGesture { open(r) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                .onChange(of: selected) { proxy.scrollTo(selected) }
            }
            .frame(height: 400)

            Divider().opacity(0.6)
            HStack(spacing: 16) {
                hint(["↑", "↓"], "to move")
                hint(["↵"], "to open")
                hint(["esc"], "to close")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: Self.width)
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
        .onKeyPress(.downArrow) { selected = min(results.count - 1, selected + 1); return .handled }
        .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        #if os(macOS)
        .onExitCommand(perform: close)
        #endif
    }

    private func row(_ r: Result, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: r.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(r.tint)
                .frame(width: 26, height: 26)
                .background(r.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(r.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).layoutPriority(1)
            Text(r.subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.ink2).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !r.shortcut.isEmpty { PaletteKey(r.shortcut) }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(isSelected ? Palette.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { PaletteKey($0) }
            Text(label).padding(.leading, 1)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Palette.ink2)
    }
}

/// The design's `kbd`: a key name on a faint rounded chip.
private struct PaletteKey: View {
    let key: String
    var size: CGFloat = 11
    var padding: CGFloat = 6

    init(_ key: String, size: CGFloat = 11, padding: CGFloat = 6) {
        (self.key, self.size, self.padding) = (key, size, padding)
    }

    var body: some View {
        Text(key)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, padding)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Quick Open inside the main window: a light dim over the page and the palette floating near the top, as in the
/// design. A click on the dim closes it.
struct QuickOpenOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            if store.isQuickOpenPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { store.isQuickOpenPresented = false }
                    .transition(.opacity)
                QuickOpenView()
                    .quickOpenChrome()
                    .padding(.top, 70)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: store.isQuickOpenPresented)
    }
}

extension View {
    /// The palette's glass card: a translucent material with a hairline edge and a deep, soft shadow (on the
    /// background shape, so the content isn't re-rendered for it).
    func quickOpenChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: QuickOpenView.cornerRadius, style: .continuous)
        return clipShape(shape)
            .background {
                shape.fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.28), radius: 40, y: 24)
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
    }
}
