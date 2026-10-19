#if os(macOS)
import SwiftUI

/// The menu bar icon's menu (Settings › General › Show in menu bar): quick ways to add things, search, or jump to a page
/// without switching to MySelf first. Every action brings the main window forward, reopening it if it was closed.
struct MenuBarMenu: View {
    @Environment(AppStore.self) private var store
    @State private var shortcut = SearchShortcut.shared

    var body: some View {
        Button("New Todo", systemImage: "checkmark.circle") { inMainWindow(store.newTodo) }
        if store.isEnabled(.office) {
            Button("New Office Task", systemImage: "briefcase") { inMainWindow(store.newOfficeTask) }
        }
        if store.isEnabled(.notes) {
            Button("New Note", systemImage: "note.text") { inMainWindow(store.newNote) }
        }
        Divider()
        Button(searchTitle, systemImage: "magnifyingglass") {
            // Let the menu close first, or the panel loses focus to it and hides straight away.
            DispatchQueue.main.async { shortcut.showPanel() }
        }
        Menu("Go To", systemImage: "arrow.right.circle") {
            ForEach(store.enabledPages) { page in
                Button(page.title, systemImage: page.systemImage) { inMainWindow { store.go(page) } }
            }
        }
        Divider()
        Button("Open \(AppInfo.name)") { shortcut.showMainWindow() }
        Button("Settings…") { shortcut.open(.settings) }
        Divider()
        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
    }

    /// "Search MySelf  ⌥⌘K" — the system-wide shortcut, as a reminder; a menu bar menu can't show it as a real key equivalent.
    private var searchTitle: String {
        guard let hotKey = shortcut.hotKey else { return "Search \(AppInfo.name)…" }
        return "Search \(AppInfo.name)…  \(hotKey.display)"
    }

    private func inMainWindow(_ action: () -> Void) {
        action()
        shortcut.showMainWindow()
    }
}
#endif
