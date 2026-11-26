import SwiftUI

/// `@AppStorage` keys for Settings, kept in one place so every scene reads the same values.
enum PrefKey {
    static let appearance = "appearance"          // "", "light", "dark"
    static let sidebarStyle = "sidebarStyle"      // SidebarStyle raw value
    static let rowDensity = "rowDensity"          // RowDensity raw value
    static let spaceTheme = "spaceTheme"          // SpaceTheme raw value
    static let themeAppearance = "themeAppearance" // ThemeAppearance raw value: match the system, or let the theme decide
    static let paperWidth = "paperWidth"          // PaperWidth raw value
    static let iCloudSync = "iCloudSync"
    static let syncFeatures = "syncFeatureVisibility"
    static let syncAppearance = "syncAppearance"
    static let menuBarIcon = "showMenuBarIcon"
    static let lastSynced = "lastSynced"          // TimeInterval since 1970
    static let checkForUpdates = "checkForUpdates"
    static let lastUpdateCheck = "lastUpdateCheck" // TimeInterval since 1970
    static let skippedVersion = "skippedVersion"  // a release version the automatic check won't offer again
    static let legacyImportOffered = "legacyImportOffered" // asked once whether to import from com.ok9xnirab.myself
    static let importedLocalFolder = "importedLocalFolder" // the pre-CloudKit local folder was read into the store
}

enum SidebarStyle: String, CaseIterable, Identifiable {
    case floating, classic

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum RowDensity: String, CaseIterable, Identifiable {
    case compact, regular, comfy

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// Added to a list row's vertical padding.
    var paddingDelta: CGFloat {
        switch self {
        case .compact: -3
        case .regular: 0
        case .comfy: 3
        }
    }
}

extension EnvironmentValues {
    @Entry var rowDensity: RowDensity = .regular
}

extension View {
    /// Applies the appearance, theme and row density chosen in Settings.
    func appPreferences() -> some View { modifier(AppPreferences()) }
}

private struct AppPreferences: ViewModifier {
    @AppStorage(PrefKey.appearance) private var appearance = ""
    @AppStorage(PrefKey.rowDensity) private var density = RowDensity.regular
    @AppStorage(PrefKey.spaceTheme) private var theme = SpaceTheme.default
    @AppStorage(PrefKey.themeAppearance) private var mode = ThemeAppearance.system

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(themedColorScheme(appearance: appearance, theme: theme, mode: mode))
            .environment(\.rowDensity, density)
    }
}
