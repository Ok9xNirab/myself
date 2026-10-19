import SwiftUI

/// Where a Quick Open result leads.
enum QuickOpenTarget { case page(Page), note(ID), settings }

/// ⌘K palette: jump to a page or to any open item. On macOS it's also the floating Spotlight-style panel
/// opened by the system-wide search shortcut, which passes `onClose` and lets `SearchShortcut` open the result.
struct QuickOpenView: View {
    var onClose: (() -> Void)?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private struct Result: Identifiable {
        typealias Target = QuickOpenTarget
        let id = UUID()
        let group: String
        let title: String
        let subtitle: String
        let systemImage: String
        let target: Target

        init(group: String, title: String, subtitle: String, systemImage: String, page: Page) {
            self.init(group: group, title: title, subtitle: subtitle, systemImage: systemImage, target: .page(page))
        }

        init(group: String, title: String, subtitle: String, systemImage: String, target: Target) {
            (self.group, self.title, self.subtitle, self.systemImage, self.target) = (group, title, subtitle, systemImage, target)
        }
    }

    private var all: [Result] {
        let due = { (d: Date?) in DueMeta(d)?.text ?? "" }
        let on = store.isEnabled
        var results = store.enabledPages.map { Result(group: "Go to", title: $0.title, subtitle: $0.subtitle, systemImage: $0.systemImage, page: $0) }
        results.append(Result(group: "Go to", title: "Settings", subtitle: "Features, appearance and iCloud", systemImage: "gearshape", target: .settings))
        results += store.todos.filter { !$0.done }.map { Result(group: "TODOs", title: $0.title, subtitle: due($0.due), systemImage: Page.todos.systemImage, page: .todos) }
        if on(.office) {
            results += store.office.filter { !$0.done }.map { Result(group: "Office Tasks", title: $0.title, subtitle: due($0.due), systemImage: Page.office.systemImage, page: .office) }
        }
        if on(.university) {
            results += store.university.assignments.filter { !$0.done }.map { Result(group: "Assignments", title: $0.title, subtitle: due($0.due), systemImage: "flag", page: .university) }
        }
        if on(.jobStudy) {
            results += store.jobStudy.flatMap { s in s.topics.map { Result(group: "Job Study", title: $0.name, subtitle: s.subject, systemImage: Page.jobStudy.systemImage, page: .jobStudy) } }
        }
        if on(.notes) {
            results += store.notes.map { Result(group: "Notes", title: $0.displayTitle, subtitle: store.noteCategory($0.categoryID)?.name ?? "", systemImage: Page.notes.systemImage, target: .note($0.id)) }
        }
        return results
    }

    private func open(_ r: Result) {
        #if os(macOS)
        if let onClose {
            onClose()
            SearchShortcut.shared.open(r.target)
            return
        }
        #endif
        switch r.target {
        case .page(let page): store.go(page)
        case .note(let id):
            // On macOS a note opens in its own window, like double-clicking it in the note list.
            #if os(macOS)
            store.isQuickOpenPresented = false
            openWindow(id: NoteWindow.id, value: id)
            #else
            store.openNote(id)
            #endif
        case .settings: store.openSettings(.general)
        }
    }

    private var results: [Result] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return all.filter { $0.group == "Go to" } }
        return Array(all.filter { "\($0.title) \($0.group)".localizedCaseInsensitiveContains(q) }.prefix(14))
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Palette.ink3)
                TextField("Search MySelf", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit { if results.indices.contains(selected) { open(results[selected]) } }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if results.isEmpty {
                        Text("No results for \u{201C}\(query)\u{201D}").foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(26)
                    }
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, r in
                        if i == 0 || results[i - 1].group != r.group {
                            Text(r.group).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 3)
                        }
                        row(r, isSelected: i == selected)
                            .onHover { if $0 { selected = i } }
                            .onTapGesture { open(r) }
                    }
                }
                .padding(6)
            }
            .frame(height: 360)

            Divider()
            HStack(spacing: 14) {
                Text("↑↓ Navigate"); Text("↵ Open"); Text("esc Close")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 580)
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
        .onKeyPress(.downArrow) { selected = min(results.count - 1, selected + 1); return .handled }
        .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
        .onKeyPress(.escape) { if let onClose { onClose() } else { dismiss() }; return .handled }
    }

    private func row(_ r: Result, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .frame(width: 22, height: 22)
                .background(isSelected ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            Text(r.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if !r.subtitle.isEmpty {
                Text(r.subtitle).font(.system(size: 12)).foregroundStyle(isSelected ? .white.opacity(0.8) : Palette.ink3).lineLimit(1)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}
