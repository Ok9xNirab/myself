import SwiftUI
import UniformTypeIdentifiers

/// Settings window (⌘,): General, Features and iCloud tabs.
struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.settingsTab) {
            Tab("General", systemImage: "gearshape", value: .general) { GeneralSettings() }
            Tab("Features", systemImage: "square.grid.2x2", value: .features) { FeatureSettings() }
            Tab("iCloud", systemImage: "icloud", value: .iCloud) { ICloudSettings() }
        }
        #if os(macOS)
        .frame(width: 480)
        .scenePadding(.vertical)
        #endif
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Environment(AppStore.self) private var store
    @AppStorage(PrefKey.appearance) private var appearance = ""
    @AppStorage(PrefKey.sidebarStyle) private var sidebarStyle = SidebarStyle.floating
    @AppStorage(PrefKey.rowDensity) private var density = RowDensity.regular
    #if os(macOS)
    @AppStorage(PrefKey.menuBarIcon) private var showsMenuBarIcon = true
    @AppStorage(PrefKey.checkForUpdates) private var checksForUpdates = true
    @State private var updates = UpdateChecker.shared
    #endif
    @State private var confirmingReset = false

    #if os(macOS)
    private var shortcutNote: String {
        let shortcut = SearchShortcut.shared
        if shortcut.hotKey == nil { return "Off. Click to set a shortcut that opens search from any app." }
        if !shortcut.isRegistered { return "Another app is using this shortcut. Choose a different one." }
        return "Opens search from any app. ⌘K still works inside MySelf."
    }

    private var updateNote: String {
        guard let date = updates.lastChecked else { return "Not checked yet." }
        return "Last checked " + date.formatted(.relative(presentation: .named)) + "."
    }
    #endif

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Auto").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Sidebar style", selection: $sidebarStyle) {
                    ForEach(SidebarStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Row density", selection: $density) {
                    ForEach(RowDensity.allCases) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.segmented)

            #if os(macOS)
            Section {
                LabeledContent {
                    ShortcutRecorder()
                } label: {
                    Text("Search MySelf")
                    Text(shortcutNote)
                }
                Toggle(isOn: $showsMenuBarIcon) {
                    Text("Show in menu bar")
                    Text("Add todos, office tasks and notes, search, or jump to a page from the menu bar.")
                }
            }

            Section("Updates") {
                Toggle(isOn: $checksForUpdates) {
                    Text("Check for updates automatically")
                    Text("Looks for a new release on GitHub once a day.")
                }
                LabeledContent {
                    Button(updates.isChecking ? "Checking\u{2026}" : "Check Now", action: updates.checkNow)
                        .disabled(updates.isChecking)
                } label: {
                    Text("Version \(UpdateChecker.currentVersion)")
                    Text(updateNote)
                }
            }
            #endif

            Section("Data") {
                LabeledContent {
                    Button("Reset…") { confirmingReset = true }
                } label: {
                    Text("Reset sample data")
                    Text("Replaces everything with the original sample content, including synced todos, labels, office tasks, notes and University.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Reset sample data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive, action: store.loadSampleData)
        } message: {
            Text("Your todos, labels, office tasks, notes, classes, boards and workouts will be replaced with the original sample content. Todos, labels, office tasks, notes and University are replaced on every Mac that syncs this folder.")
        }
    }
}

// MARK: Features

private struct FeatureSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let optional = Page.allCases.filter(\.isOptional)
        Form {
            Section {
                ForEach(optional) { page in
                    Toggle(isOn: Binding(get: { store.isEnabled(page) }, set: { on in withAnimation { store.setEnabled(page, on) } })) {
                        HStack(spacing: 10) {
                            Image(systemName: page.systemImage)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(page.featureColor.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(page.title)
                                Text(page.featureDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
            } header: {
                HStack {
                    Text("Show in MySelf")
                    Spacer()
                    Text("\(optional.filter(store.isEnabled).count) of \(optional.count) on")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            } footer: {
                Text("Turning a feature off hides it from the sidebar, Dashboard, search and shortcuts. Its data is kept, so turning it back on restores everything. Dashboard and TODOs are always on.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: iCloud

/// Sync goes through a folder the user picks in iCloud Drive (see `SyncEngine`), so it needs no iCloud entitlement.
private struct ICloudSettings: View {
    @Environment(AppStore.self) private var store
    @AppStorage(PrefKey.syncFeatures) private var syncFeatures = true
    @AppStorage(PrefKey.syncAppearance) private var syncAppearance = true
    @State private var choosingFolder = false
    @State private var folderError: String?

    var body: some View {
        let sync = store.sync
        Form {
            Section {
                Toggle(isOn: Binding(get: { sync.isCloudEnabled }, set: { on in withAnimation { store.setICloudSync(on) } })) {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Palette.blue.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sync with iCloud")
                            Text("Keeps your Macs in step through a folder in iCloud Drive.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                LabeledContent {
                    Button("Sync Now", action: store.reloadSynced).disabled(!sync.usesCloud)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(sync.status.color).frame(width: 7, height: 7)
                        Text(statusTitle(sync.status))
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(statusDetail(sync, now: context.date))
                    }
                }
            }

            Section {
                LabeledContent {
                    Button(sync.cloudFolder == nil ? "Choose…" : "Change…") { choosingFolder = true }
                } label: {
                    Text("Sync folder")
                    if let name = sync.cloudFolderDisplayName {
                        Text(name)
                    } else if let lost = sync.lostFolder {
                        Text("Can\u{2019}t open \(lost). Choose it again to resume syncing.").foregroundStyle(Palette.red)
                    } else {
                        Text("Pick or create a folder in iCloud Drive, such as iCloud Drive › MySelf.")
                    }
                }
                if sync.cloudFolder != nil, !sync.cloudFolderIsInICloud {
                    Label("This folder isn\u{2019}t in iCloud Drive, so it won\u{2019}t sync between Macs.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.amber)
                }
            } footer: {
                Text("Choose the same folder on each Mac. Your todos and notes are copied into it, and changes made on any Mac appear on the others within a minute.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!sync.isCloudEnabled)

            Section {
                Toggle(isOn: $syncFeatures) {
                    Text("Feature visibility")
                    Text("Use the same features on all your Macs.")
                }
                Toggle(isOn: $syncAppearance) {
                    Text("Appearance")
                    Text("Theme, sidebar style and row density.")
                }
            } header: {
                Text("Also sync")
            } footer: {
                Text("Todos, office tasks, notes, University, Job Study and Product Dev sync when iCloud is on. Workouts stay on this Mac for now.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(!sync.usesCloud)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            do {
                try store.useICloudFolder(result.get())
            } catch {
                folderError = error.localizedDescription
            }
        }
        #if os(macOS)
        .fileDialogDefaultDirectory(sync.cloudFolder ?? SyncEngine.iCloudDriveURL)
        .fileDialogMessage("Choose a folder in iCloud Drive for MySelf to sync through. Pick the same folder on each Mac.")
        .fileDialogConfirmationLabel("Use Folder")
        #endif
        .alert("Couldn\u{2019}t use that folder", isPresented: Binding(get: { folderError != nil }, set: { if !$0 { folderError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(folderError ?? "")
        }
    }

    private func statusTitle(_ status: SyncEngine.Status) -> String {
        switch status {
        case .local: "Sync is off"
        case .needsFolder: "No sync folder chosen"
        case .syncing: "Syncing\u{2026}"
        case .upToDate: "Up to date"
        case .failed: "Sync problem"
        }
    }

    private func statusDetail(_ sync: SyncEngine, now: Date) -> String {
        switch sync.status {
        case .local: return "Data stays on this Mac."
        case .needsFolder: return "Todos and notes are saved on this Mac until you choose a folder."
        case .failed(let message): return message
        case .syncing, .upToDate:
            guard let date = sync.lastSynced else { return "Waiting for iCloud Drive" }
            if now.timeIntervalSince(date) < 45 { return "Last synced just now" }
            return "Last synced " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
        }
    }
}

#Preview {
    SettingsView().environment(AppStore())
}
