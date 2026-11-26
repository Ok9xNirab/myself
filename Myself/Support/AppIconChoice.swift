import SwiftUI

/// The app icon picked in Settings › Appearance › App icon, saved per device (`PrefKey.appIcon`).
///
/// The alternates are Icon Composer bundles next to `AppIcon.icon` (`AppIconOctopus.icon`, `AppIconSpaces.icon`),
/// listed in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`. The default tile draws `AppIcon` from the asset
/// catalog, so it follows `AppIcon.icon` whenever that changes.
///
/// iOS and visionOS switch the home screen icon. macOS has no alternate icon API: the Dock shows the choice while
/// MySelf runs (`NSApp.applicationIconImage`), and Finder and the Dock show the default icon once it quits.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = ""
    case octopus = "AppIconOctopus"
    case spaces = "AppIconSpaces"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Mirror"
        case .octopus: "Octopus"
        case .spaces: "Spaces"
        }
    }

    var caption: String { self == .standard ? "Default" : "Alternate" }

    /// The asset catalog's name for this icon, or nil for the primary one.
    var assetName: String? { self == .standard ? nil : rawValue }

    static var saved: AppIconChoice {
        AppIconChoice(rawValue: UserDefaults.standard.string(forKey: PrefKey.appIcon) ?? "") ?? .standard
    }

    #if os(macOS)
    /// The icon from the app's asset catalog. Not `NSWorkspace.icon(forFile:)`: Icon Services caches that per
    /// bundle, so it can show an older build's icon.
    var image: NSImage {
        NSImage(named: assetName ?? "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    /// Shows the saved icon in the Dock; called at launch and when the setting changes. The default is set too,
    /// so a Dock tile cached from an older build is replaced.
    static func applySaved() {
        NSApp.applicationIconImage = NSImage(named: saved.assetName ?? "AppIcon")
    }
    #elseif canImport(UIKit)
    static func applySaved() {
        let name = saved.assetName
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
    }
    #endif
}

/// Settings › Appearance › App icon: one tile per icon, the selected one ringed in the accent colour.
struct AppIconPicker: View {
    @AppStorage(PrefKey.appIcon) private var selection = AppIconChoice.standard

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(AppIconChoice.allCases) { icon in
                let on = icon == selection
                Button { selection = icon } label: {
                    VStack(spacing: 4) {
                        preview(icon)
                            .frame(width: 64, height: 64)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                        Text(icon.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Color.accentColor : .primary)
                        Text(icon.caption)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(icon.title) app icon")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .onChange(of: selection) { AppIconChoice.applySaved() }
    }

    @ViewBuilder
    private func preview(_ icon: AppIconChoice) -> some View {
        #if os(macOS)
        Image(nsImage: icon.image).resizable().interpolation(.high)
        #else
        if let image = UIImage(named: icon.assetName ?? "AppIcon") {
            Image(uiImage: image).resizable().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary)
        }
        #endif
    }
}
