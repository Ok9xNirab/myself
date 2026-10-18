import SwiftUI

/// `@AppStorage` keys for Settings, kept in one place so every scene reads the same values.
enum PrefKey {
    static let appearance = "appearance"          // "", "light", "dark"
    static let accent = "accent"                  // AccentChoice raw value
    static let sidebarStyle = "sidebarStyle"      // SidebarStyle raw value
    static let rowDensity = "rowDensity"          // RowDensity raw value
    static let iCloudSync = "iCloudSync"
    static let syncFeatures = "syncFeatureVisibility"
    static let syncAppearance = "syncAppearance"
    static let lastSynced = "lastSynced"          // TimeInterval since 1970
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, orange, green, graphite

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: Palette.blue
        case .purple: Palette.violet
        case .orange: Palette.amber
        case .green: Palette.green
        case .graphite: Color.dynamic(light: 0x8E8E93, dark: 0x98989D)
        }
    }
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
    /// Applies the appearance, accent colour and row density chosen in Settings.
    func appPreferences(appearance: String, accent: AccentChoice, density: RowDensity) -> some View {
        self
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .tint(accent.color)
            // `.tint` drives controls; `Color.accentColor` only follows this (deprecated) modifier.
            .accentColor(accent.color)
            .environment(\.rowDensity, density)
    }
}
