import SwiftUI

@main struct MyApp: App {
    @State private var store = AppStore()
    @AppStorage(PrefKey.appearance) private var appearance = ""
    @AppStorage(PrefKey.rowDensity) private var density = RowDensity.regular
    @AppStorage(PrefKey.menuBarIcon) private var showsMenuBarIcon = true

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .appPreferences(appearance: appearance, density: density)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .appInfo) { AboutCommand() }
            #endif
            SidebarCommands()
            // MySelf is a single-window app with one shared store, so ⌘N makes a todo (⇧⌘N an office task, ⌥⌘N a note) instead of a window.
            CommandGroup(replacing: .newItem) {
                Button("New Todo", action: store.newTodo)
                    .keyboardShortcut("n")
                if store.isEnabled(.office) {
                    Button("New Office Task", action: store.newOfficeTask)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                if store.isEnabled(.notes) {
                    Button("New Note", action: store.newNote)
                        .keyboardShortcut("n", modifiers: [.command, .option])
                }
                Button("Quick Open…") { store.isQuickOpenPresented = true }
                    .keyboardShortcut("k")
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            CommandMenu("Go") {
                Button("Back", action: store.back)
                    .keyboardShortcut("[")
                    .disabled(!store.canGoBack)
                Button("Forward", action: store.forward)
                    .keyboardShortcut("]")
                    .disabled(!store.canGoForward)
                Divider()
                // Shortcuts stay tied to a page's position, so ⌘7 is always Workout (⌘8 Notes) even when others are hidden.
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    if store.isEnabled(page) {
                        Button(page.title) { store.go(page) }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    }
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(store)
                .appPreferences(appearance: appearance, density: density)
        }

        // A note opened on its own (double-click in the note list). Opening a note that already has a window brings that window forward.
        WindowGroup("Note", id: NoteWindow.id, for: ID.self) { $noteID in
            if let noteID {
                NoteWindow(noteID: noteID)
                    .environment(store)
                    .appPreferences(appearance: appearance, density: density)
            }
        }
        .defaultSize(width: 760, height: 680)

        Window("About \(AppInfo.name)", id: "about") {
            AboutView()
                .appPreferences(appearance: appearance, density: density)
                .windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)

        MenuBarExtra(AppInfo.name, image: "MenuBarIcon", isInserted: $showsMenuBarIcon) {
            MenuBarMenu()
                .environment(store)
        }
        #endif
    }
}
