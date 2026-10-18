import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
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
        }
    }
}

private struct Sidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rowDensity) private var density
    @AppStorage(PrefKey.sidebarStyle) private var style = SidebarStyle.floating
    @AppStorage(PrefKey.iCloudSync) private var syncOn = true

    var body: some View {
        List(selection: Binding(get: { store.page }, set: { if let page = $0 { store.go(page) } })) {
            ForEach(Page.groups(store.enabledPages), id: \.name) { group in
                Section(group.name) {
                    ForEach(group.pages) { page in
                        Label(page.title, systemImage: page.systemImage)
                            .badge(store.count(for: page))
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

    private var footer: some View {
        HStack(spacing: 9) {
            Text("ME")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(LinearGradient(colors: [Color(hex: 0xA3A3AA), Color(hex: 0x7B7B83)], startPoint: .top, endPoint: .bottom), in: Circle())
            Button { store.openSettings(.iCloud) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("My Workspace").font(.system(size: 12.5, weight: .semibold))
                    Label(syncOn ? "Synced with iCloud" : "On this Mac only", systemImage: syncOn ? "icloud" : "desktopcomputer")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink3)
                        .labelStyle(SyncStatusLabelStyle())
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
}

private struct SyncStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 9.5))
            configuration.title
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
