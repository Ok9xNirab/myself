import SwiftUI

@main struct MyApp: App {
    @State private var store = AppStore()
    @AppStorage(PrefKey.appearance) private var appearance = ""
    @AppStorage(PrefKey.accent) private var accent = AccentChoice.blue
    @AppStorage(PrefKey.rowDensity) private var density = RowDensity.regular

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .appPreferences(appearance: appearance, accent: accent, density: density)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
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
                // Shortcuts stay tied to a page's position, so ⌘7 is always Workout even when others are hidden.
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
                .appPreferences(appearance: appearance, accent: accent, density: density)
        }
        #endif
    }
}
