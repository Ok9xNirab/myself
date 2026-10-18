import SwiftUI

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
    @AppStorage(PrefKey.accent) private var accent = AccentChoice.blue
    @AppStorage(PrefKey.sidebarStyle) private var sidebarStyle = SidebarStyle.floating
    @AppStorage(PrefKey.rowDensity) private var density = RowDensity.regular
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Auto").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                LabeledContent("Accent color") { AccentPicker(selection: $accent) }
                Picker("Sidebar style", selection: $sidebarStyle) {
                    ForEach(SidebarStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Row density", selection: $density) {
                    ForEach(RowDensity.allCases) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.segmented)

            Section("Data") {
                LabeledContent {
                    Button("Reset…") { confirmingReset = true }
                } label: {
                    Text("Reset sample data")
                    Text("Replaces everything with the original sample content.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Reset sample data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive, action: store.loadSampleData)
        } message: {
            Text("Your changes to todos, classes, boards and workouts will be replaced with the original sample content.")
        }
    }
}

private struct AccentPicker: View {
    @Binding var selection: AccentChoice

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AccentChoice.allCases) { choice in
                Button { selection = choice } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 16, height: 16)
                        .overlay {
                            if choice == selection { Circle().fill(.white).frame(width: 6, height: 6) }
                        }
                        .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                        .padding(2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
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

/// iCloud sync is simulated for now: the toggles are stored locally and "Sync Now" only updates the timestamp.
private struct ICloudSettings: View {
    @AppStorage(PrefKey.iCloudSync) private var syncOn = true
    @AppStorage(PrefKey.syncFeatures) private var syncFeatures = true
    @AppStorage(PrefKey.syncAppearance) private var syncAppearance = true
    @AppStorage(PrefKey.lastSynced) private var lastSynced = Date.now.addingTimeInterval(-60).timeIntervalSince1970
    @State private var syncing = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $syncOn.animation()) {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Palette.blue.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sync with iCloud")
                            Text("Keeps MySelf up to date on your Mac, iPhone and iPad.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                LabeledContent {
                    Button("Sync Now", action: syncNow).disabled(!syncOn || syncing)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(syncOn ? (syncing ? Palette.amber : Palette.green) : Palette.ink3).frame(width: 7, height: 7)
                        Text(syncOn ? (syncing ? "Syncing…" : "Up to date") : "Sync is off")
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(syncOn ? "Last synced \(relative(context.date))" : "Data stays on this Mac.")
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
                    Text("Theme, accent color and sidebar style.")
                }
            } header: {
                Text("Also sync")
            } footer: {
                Text("Tasks, classes, boards and workouts always sync when iCloud is on.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(!syncOn)

            Section {
                LabeledContent {
                    Button("Manage…", action: manageAccount)
                } label: {
                    HStack(spacing: 10) {
                        Text("ME")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(LinearGradient(colors: [Color(hex: 0xA3A3AA), Color(hex: 0x7B7B83)], startPoint: .top, endPoint: .bottom), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Apple Account")
                            Text(verbatim: "me@icloud.com").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func relative(_ now: Date) -> String {
        let date = Date(timeIntervalSince1970: lastSynced)
        if now.timeIntervalSince(date) < 45 { return "just now" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
    }

    private func syncNow() {
        withAnimation { syncing = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            lastSynced = Date.now.timeIntervalSince1970
            withAnimation { syncing = false }
        }
    }

    private func manageAccount() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings") {
            NSWorkspace.shared.open(url)
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}

#Preview {
    SettingsView().environment(AppStore())
}
