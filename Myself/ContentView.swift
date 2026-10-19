import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.sidebarStyle) private var sidebarStyle = SidebarStyle.floating

    var body: some View {
        @Bindable var store = store
        Group {
            #if os(macOS)
            if sidebarStyle == .classic {
                ClassicSplitView { Sidebar() } detail: { detail }
            } else {
                splitView
            }
            #else
            splitView
            #endif
        }
        #if os(macOS)
        .onAppear {
            SearchShortcut.shared.openMainWindow = { openWindow(id: "main") }
            SearchShortcut.shared.openNoteWindow = { openWindow(id: NoteWindow.id, value: $0) }
            SearchShortcut.shared.start(store: store)
        }
        #endif
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

    /// The system split view. On macOS 26 its sidebar is the floating glass panel.
    private var splitView: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        } detail: {
            detail
        }
    }

    private var detail: some View {
        PageView(page: store.page)
            .id(store.page)
            .navigationTitle(store.page.title)
            #if os(macOS)
            .navigationSubtitle(store.page.subtitle)
            #endif
            .toolbar { toolbar }
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

#if os(macOS)
/// The "Classic" sidebar: a flat, full-height column with a hairline edge. `NavigationSplitView` always draws its
/// sidebar as a floating panel on macOS 26 and has no way to turn that off, so this lays the two columns out itself.
/// The sidebar can be dragged between 200 and 300 points wide and hidden with the toolbar button or ⌃⌘S.
private struct ClassicSplitView<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var detail: Detail
    @AppStorage("classicSidebarWidth") private var width = 232.0
    @AppStorage("classicSidebarHidden") private var isHidden = false
    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 0) {
            if !isHidden {
                sidebar
                    .frame(width: width)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Palette.border).frame(width: 0.5).ignoresSafeArea()
                    }
                    .overlay(alignment: .trailing) { resizeHandle }
                    .transition(.move(edge: .leading))
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(isHidden ? "Show Sidebar" : "Hide Sidebar", systemImage: "sidebar.left") {
                            withAnimation(.smooth(duration: 0.25)) { isHidden.toggle() }
                        }
                        .keyboardShortcut("s", modifiers: [.control, .command])
                        .help(isHidden ? "Show Sidebar (⌃⌘S)" : "Hide Sidebar (⌃⌘S)")
                    }
                }
        }
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .offset(x: 3)
            .ignoresSafeArea()
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? width
                        dragStart = start
                        width = min(300, max(200, start + value.translation.width))
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
#endif

#Preview {
    ContentView()
        .environment(AppStore())
        .frame(width: 1200, height: 800)
}
