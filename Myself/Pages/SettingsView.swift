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
    #if DIRECT_DISTRIBUTION
    @AppStorage(PrefKey.checkForUpdates) private var checksForUpdates = true
    @State private var updates = UpdateChecker.shared
    #endif
    #endif
    @State private var confirmingReset = false
    @State private var importError: String?

    #if os(macOS)
    private var shortcutNote: String {
        let shortcut = SearchShortcut.shared
        if shortcut.hotKey == nil { return "Off. Click to set a shortcut that opens search from any app." }
        if !shortcut.isRegistered { return "Another app is using this shortcut. Choose a different one." }
        return "Opens search from any app. ⌘K still works inside MySelf."
    }

    #if DIRECT_DISTRIBUTION
    private var updateNote: String {
        guard let date = updates.lastChecked else { return "Not checked yet." }
        return "Last checked " + date.formatted(.relative(presentation: .named)) + "."
    }
    #endif
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

            #if DIRECT_DISTRIBUTION
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
            #endif

            Section("Data") {
                #if os(macOS)
                LabeledContent {
                    Button("Import\u{2026}") { importError = store.runLegacyImport() }
                } label: {
                    Text("Import from an earlier MySelf")
                    Text("Brings over todos, notes and settings from MySelf 1.3.1 or earlier on this Mac, keeping what\u{2019}s already here.")
                }
                #endif
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
            Text("Your todos, labels, office tasks, notes, classes, boards and workouts will be replaced with the original sample content. Synced data is replaced on all your devices.")
        }
        .alert("Couldn\u{2019}t import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }
}

// MARK: Features

private struct FeatureSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let optional = Page.allCases.filter { $0.isOptional && $0.isAvailable }
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

/// Sync goes through the user's private CloudKit database (see `CloudStore`); settings through iCloud key-value storage.
private struct ICloudSettings: View {
    @Environment(AppStore.self) private var store
    @AppStorage(PrefKey.syncFeatures) private var syncFeatures = true
    @AppStorage(PrefKey.syncAppearance) private var syncAppearance = true
    @State private var choosingFolder = false
    @State private var importMessage: (title: String, text: String)?

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
                            Text("Keeps your devices in step through your iCloud account.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                LabeledContent {
                    EmptyView()
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
                Toggle(isOn: $syncFeatures) {
                    Text("Feature visibility")
                    Text("Use the same features on all your devices.")
                }
                Toggle(isOn: $syncAppearance) {
                    Text("Appearance")
                    Text("Theme, sidebar style and row density.")
                }
            } header: {
                Text("Also sync")
            } footer: {
                Text("Todos, office tasks, notes, University, Job Study and Product Dev sync when iCloud is on. Workouts stay on this device for now.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(!sync.usesCloud)

            Section {
                LabeledContent {
                    Button("Import\u{2026}") { choosingFolder = true }
                } label: {
                    Text("Import a sync folder")
                    Text("Earlier versions synced through a folder in iCloud Drive, such as iCloud Drive \u{203A} MySelf. Choose it to bring its data in; newer changes here are kept.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            do {
                let imported = try store.importFolder(result.get())
                var text = imported.imported == 1 ? "1 item was imported." : "\(imported.imported) items were imported."
                if imported.pending > 0 {
                    text += " \(imported.pending) files are still downloading from iCloud Drive; import the folder again in a minute to add them."
                }
                importMessage = ("Import finished", text)
            } catch {
                importMessage = ("Couldn\u{2019}t import that folder", error.localizedDescription)
            }
        }
        #if os(macOS)
        .fileDialogDefaultDirectory(ICloudSettings.iCloudDriveURL)
        .fileDialogMessage("Choose the folder earlier versions of MySelf synced through.")
        .fileDialogConfirmationLabel("Import")
        #endif
        .alert(importMessage?.title ?? "", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage?.text ?? "")
        }
    }

    #if os(macOS)
    /// The user's iCloud Drive folder, the import panel's starting point.
    private static var iCloudDriveURL: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let url = URL(filePath: String(cString: home)).appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    #endif

    private func statusTitle(_ status: CloudStore.Status) -> String {
        switch status {
        case .local: "Sync is off"
        case .noAccount: "Not signed in to iCloud"
        case .syncing: "Syncing\u{2026}"
        case .upToDate: "Up to date"
        case .failed: "Sync problem"
        }
    }

    private func statusDetail(_ sync: CloudStore, now: Date) -> String {
        switch sync.status {
        case .local: return "Data stays on this device."
        case .noAccount: return "Sign in to iCloud in System Settings to sync. Until then, changes are saved on this device."
        case .failed(let message): return message
        case .syncing, .upToDate:
            guard let date = sync.lastSynced else { return "Waiting for iCloud" }
            if now.timeIntervalSince(date) < 45 { return "Last synced just now" }
            return "Last synced " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
        }
    }
}

#Preview {
    SettingsView().environment(AppStore())
}
