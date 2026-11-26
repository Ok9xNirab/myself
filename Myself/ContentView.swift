import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.sidebarStyle) private var sidebarStyle = SidebarStyle.floating
    /// Asked once on a fresh install: import from MySelf 1.3.1 and earlier, which used another bundle ID.
    @State private var showsLegacyImport = false
    @State private var legacyImportError: String?

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
            #if DIRECT_DISTRIBUTION
            UpdateChecker.shared.checkAutomatically()
            #endif
        }
        #endif
        .task {
            #if os(macOS)
            if store.shouldOfferLegacyImport { showsLegacyImport = true }
            #endif
        }
        #if os(macOS)
        .alert("Used MySelf before?", isPresented: $showsLegacyImport) {
            Button("Import\u{2026}") {
                store.declineLegacyImport()
                legacyImportError = store.runLegacyImport()
            }
            Button("Not Now", role: .cancel) { store.declineLegacyImport() }
        } message: {
            Text("If you used MySelf 1.3.1 or earlier on this Mac, you can bring over its todos, notes and settings. You can also do this later in Settings \u{203A} General.")
        }
        .alert("Couldn\u{2019}t import", isPresented: Binding(get: { legacyImportError != nil }, set: { if !$0 { legacyImportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(legacyImportError ?? "")
        }
        #endif
        // Pick up changes made on other Macs while the app was in the background.
        .onChange(of: scenePhase) {
            if scenePhase == .active { store.reloadSynced() } else { store.saveTypedText() }
        }
        .overlay { QuickOpenOverlay() }
        // Widget links (`myself://todos`, `myself://notes/new`, …) go to this window rather than a new one.
        .onOpenURL { url in
            if let link = DeepLink(url) { store.open(link) }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
            // The window keeps its title (Window menu, Mission Control); the toolbar shows the v2 breadcrumb instead.
            .toolbar(removing: .title)
            #endif
            .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            PageCrumb(page: store.page)
        }
        .sharedBackgroundVisibility(.hidden)
        // With the title removed nothing else fills the bar, so this keeps Search (and pages' buttons) on the right.
        ToolbarSpacer(.flexible)
        #endif
        // No Back / Forward buttons (the v2 design has none); Go › Back / Forward (⌘[ / ⌘]) still navigate.
        ToolbarItem(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { store.isQuickOpenPresented = true }
                .help("Search MySelf (⌘K)")
        }
    }
}

#if os(macOS)
/// The toolbar's breadcrumb: the page's outline icon and its name (the v2 `.crumb`).
private struct PageCrumb: View {
    var page: Page
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: page.systemImage).font(.system(size: 14, weight: .regular)).foregroundStyle(Palette.ink2)
            Text(page.title).font(.system(size: 14, weight: .semibold))
            if let crumb = store.crumb, crumb.page == page {
                Text("/ \(crumb.detail)").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink2)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
    }
}
#endif

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
        case .books: BooksView()
        }
    }
}

/// The v2 sidebar: Dashboard and TODOs, then every enabled feature under "Spaces" in its own colour, the next
/// class, and the iCloud status. Drawn by hand rather than as a `List` so a selected space gets its tint and edge
/// bar as in the design.
private struct Sidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rowDensity) private var density
    @AppStorage(PrefKey.sidebarStyle) private var style = SidebarStyle.floating

    var body: some View {
        let enabled = store.enabledPages
        let top = [Page.dashboard, .todos].filter { enabled.contains($0) }
        let spaces = Page.spaceOrder.filter { enabled.contains($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(top) { row($0, space: false) }
                if !spaces.isEmpty {
                    Text("Spaces")
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 8)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    ForEach(spaces) { row($0, space: true) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .modifier(SidebarBackground(style: style))
        // Up next stays at the bottom, just above the iCloud footer, however long the list is.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if store.isEnabled(.university), let next = store.nextClass() {
                    UpNextCard(session: next)
                        .onTapGesture { store.go(.university) }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                footer
            }
        }
    }

    private func row(_ page: Page, space: Bool) -> some View {
        SidebarRow(page: page, selected: store.page == page, badge: badge(for: page), colouredBadge: space,
                   height: 30 + density.paddingDelta * 2) { store.go(page) }
    }

    private func badge(for page: Page) -> String? {
        if page.isComingSoon { return "Soon" }
        let count = store.count(for: page)
        return count > 0 ? "\(count)" : nil
    }

    /// iCloud sync status; clicking it opens Settings › iCloud.
    private var footer: some View {
        let sync = store.sync
        return HStack(spacing: 9) {
            Button { store.openSettings(.iCloud) } label: {
                HStack(spacing: 9) {
                    Image(systemName: sync.status.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(LinearGradient(colors: [Color(hex: 0x5E8BFF), Color(hex: 0xA35BD8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Circle())
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sync.status.title).font(.system(size: 13, weight: .semibold))
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            HStack(spacing: 5) {
                                Circle().fill(sync.status.color).frame(width: 6, height: 6)
                                Text(detail(sync, now: context.date))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.ink2)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("iCloud settings")
            Button("Settings", systemImage: "gearshape") { store.openSettings(.appearance) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.ink2)
                .frame(width: 26, height: 26)
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.horizontal, 10) }
    }

    private func detail(_ sync: CloudStore, now: Date) -> String {
        switch sync.status {
        case .local: return "Turn on in Settings"
        case .noAccount: return "Sign in to sync"
        case .failed: return "Click for details"
        case .syncing, .upToDate:
            guard let date = sync.lastSynced else { return "Waiting for iCloud" }
            if now.timeIntervalSince(date) < 45 { return "Updated just now" }
            return "Updated " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
        }
    }
}

/// One sidebar row: the page's icon in its colour, its title and a count. The selected row takes a wash of the
/// page's colour and a bar on the sidebar's edge.
private struct SidebarRow: View {
    var page: Page
    var selected: Bool
    var badge: String?
    var colouredBadge: Bool
    var height: CGFloat
    var action: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // An outline over a faint fill of the same symbol: the design's stroke icons with `fill-opacity: .16`.
                TintedSymbol(name: page.systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(page.tint)
                .frame(width: 20)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: colouredBadge ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(colouredBadge ? page.tint : Palette.ink2)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(colouredBadge ? page.tint.opacity(0.13) : Color.primary.opacity(selected ? 0.0 : 0.055), in: Capsule())
                        .background(selected && !colouredBadge ? Palette.surface.opacity(0.7) : .clear, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? page.tint.opacity(0.14) : hover.isOn ? Color.primary.opacity(0.045) : .clear)
            }
            .overlay(alignment: .leading) {
                if selected {
                    UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 3, topTrailing: 3))
                        .fill(page.tint)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                        .offset(x: -12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Up next": the next class, under the spaces.
private struct UpNextCard: View {
    var session: AppStore.ClassSession

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Up next").textCase(.uppercase).kerning(0.5).fontWeight(.bold)
                Spacer()
                Text(session.dayLabel).fontWeight(.semibold)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.violet)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(session.uniClass.color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.uniClass.subject).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text([session.uniClass.time.formatted, session.uniClass.room].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11.5)).foregroundStyle(Palette.ink2).lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.violet.opacity(0.18), lineWidth: 0.5))
        .contentShape(Rectangle())
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
