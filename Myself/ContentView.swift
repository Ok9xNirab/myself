import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.appearance) private var appearance = ""

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        } detail: {
            PageView(page: store.page)
                .id(store.page)
                .navigationTitle(store.page.title)
                #if os(macOS)
                .navigationSubtitle(store.page.subtitle)
                #endif
                .toolbar { toolbar }
        }
        // Pick up changes made on other Macs while the app was in the background.
        .onChange(of: scenePhase) { if scenePhase == .active { store.reloadSynced() } }
        .sheet(isPresented: $store.isQuickOpenPresented) {
            QuickOpenView()
        }
        #if os(macOS)
        // The Settings window is its own scene; the store only signals that it should open.
        .onChange(of: store.isSettingsPresented) {
            guard store.isSettingsPresented else { return }
            store.isSettingsPresented = false
            openSettings()
        }
        #else
        .sheet(isPresented: $store.isSettingsPresented) {
            NavigationStack {
                SettingsView()
                    .toolbar { Button("Done") { store.isSettingsPresented = false } }
            }
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.left", action: store.back)
                .disabled(!store.canGoBack)
            Button("Forward", systemImage: "chevron.right", action: store.forward)
                .disabled(!store.canGoForward)
        }
        ToolbarItem(placement: .primaryAction) {
            let dark = colorScheme == .dark
            Button(dark ? "Light Appearance" : "Dark Appearance", systemImage: dark ? "sun.max" : "moon") {
                appearance = dark ? "light" : "dark"
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { store.isQuickOpenPresented = true }
                .help("Search MySelf (⌘K)")
        }
    }
}

private struct PageView: View {
    var page: Page

    var body: some View {
        switch page {
        case .dashboard: DashboardView()
        case .todos: TodosView()
        case .university: UniversityView()
        case .office: OfficeView()
        case .jobStudy: JobStudyView()
        case .products: ProductsView()
        case .workout: WorkoutView()
        case .notes: NotesView()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rowDensity) private var density
    @AppStorage(PrefKey.sidebarStyle) private var style = SidebarStyle.floating

    var body: some View {
        List(selection: Binding(get: { store.page }, set: { if let page = $0 { store.go(page) } })) {
            ForEach(Page.groups(store.enabledPages), id: \.name) { group in
                Section(group.name) {
                    ForEach(group.pages) { page in
                        Label(page.title, systemImage: page.systemImage)
                            .badge(badge(for: page))
                            .tag(page)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28 + density.paddingDelta * 2)
        .modifier(SidebarBackground(style: style))
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private func badge(for page: Page) -> Text? {
        if page.isComingSoon { return Text("Soon") }
        let count = store.count(for: page)
        return count > 0 ? Text("\(count)") : nil
    }

    /// iCloud sync status; clicking it opens Settings › iCloud.
    private var footer: some View {
        let sync = store.sync
        return HStack(spacing: 9) {
            Button { store.openSettings(.iCloud) } label: {
                HStack(spacing: 9) {
                    Image(systemName: sync.status.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(sync.status.color)
                        .frame(width: 26, height: 26)
                        .background(sync.status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(sync.status.title).font(.system(size: 12.5, weight: .semibold))
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(detail(sync, now: context.date))
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.ink3)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("iCloud settings")
            Button("Settings", systemImage: "gearshape") { store.openSettings(.general) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.ink2)
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
    }

    private func detail(_ sync: SyncEngine, now: Date) -> String {
        switch sync.status {
        case .local: return "Turn on in Settings"
        case .needsFolder: return "Click to set up sync"
        case .failed: return "Click for details"
        case .syncing, .upToDate:
            guard let date = sync.lastSynced else { return "Waiting for iCloud Drive" }
            if now.timeIntervalSince(date) < 45 { return "Updated just now" }
            return "Updated " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
        }
    }
}

/// "Classic" swaps the translucent floating sidebar for a flat, opaque one.
private struct SidebarBackground: ViewModifier {
    var style: SidebarStyle

    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content
        case .classic:
            content
                .scrollContentBackground(.hidden)
                .background(Palette.surface2.ignoresSafeArea())
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .frame(width: 1200, height: 800)
}
