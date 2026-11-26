import SwiftUI

/// The app icon picked in Settings › Appearance › App icon, saved per device (`PrefKey.appIcon`).
///
/// The alternates are Icon Composer bundles next to `AppIcon.icon` (`AppIconOctopus.icon`, `AppIconSpaces.icon`),
/// listed in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (not for macOS).
///
/// iOS, iPadOS and visionOS only: the system switches the home screen icon and draws it in every style (dark,
/// clear, tinted). macOS has no alternate icon API, and a Dock image set while the app runs can't follow the Mac's
/// icon style, so the Mac always shows the default icon and has no picker.
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

    /// A picture of the icon for the picker (`Assets.xcassets/AppIconPreview…`, light and dark), since iOS can't
    /// load an app icon as an image. Re-export it with `ictool` when the icon changes.
    var previewName: String { "AppIconPreview" + title }

    static var saved: AppIconChoice {
        AppIconChoice(rawValue: UserDefaults.standard.string(forKey: PrefKey.appIcon) ?? "") ?? .standard
    }

    #if canImport(UIKit)
    static func applySaved() {
        let name = saved.assetName
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
    }
    #endif
}

#if canImport(UIKit)
/// Settings › Appearance › App icon: one tile per icon, the selected one ringed in the accent colour.
struct AppIconPicker: View {
    /// Plain state written through to UserDefaults on a click: `@AppStorage` here sometimes kept the earlier
    /// selection ringed after a few changes.
    @State private var selection = AppIconChoice.saved

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(AppIconChoice.allCases) { icon in
                let on = icon == selection
                Button { choose(icon) } label: {
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
    }

    private func choose(_ icon: AppIconChoice) {
        selection = icon
        UserDefaults.standard.set(icon.rawValue, forKey: PrefKey.appIcon)
        AppIconChoice.applySaved()
    }

    @ViewBuilder
    private func preview(_ icon: AppIconChoice) -> some View {
        Image(icon.previewName).resizable().interpolation(.high)
    }
}
#endif
