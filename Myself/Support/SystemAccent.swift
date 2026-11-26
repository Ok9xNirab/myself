import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Whether the Mac's accent colour is Multicolor (System Settings › Appearance), when `Color.accentColor` is just the
/// default blue. Prominent fills use the accent, except under Multicolor, where they stay the design's black.
@Observable
final class SystemAccent {
    static let shared = SystemAccent()

    private(set) var isMulticolor = SystemAccent.readMulticolor()

    private init() {
        #if os(macOS)
        // Posted when the accent (or highlight) colour changes.
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemAccent.shared.isMulticolor = SystemAccent.readMulticolor() }
        }
        #endif
    }

    /// The global `AppleAccentColor` default is absent under Multicolor and a number for every fixed colour.
    private static func readMulticolor() -> Bool {
        #if os(macOS)
        UserDefaults.standard.object(forKey: "AppleAccentColor") == nil
        #else
        true
        #endif
    }

    /// Fill for a prominent pill button and the colour of its label.
    var fill: Color { isMulticolor ? .primary : .accentColor }
    var onFill: Color { isMulticolor ? Palette.surface : .white }
}
