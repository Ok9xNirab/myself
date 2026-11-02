import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage
#endif

/// Colour tokens ported from the design's `native.css` (light / dark pairs).
enum Palette {
    static let background = Color.dynamic(light: 0xF5F5F7, dark: 0x1E1E20)
    static let surface    = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2A2C)
    static let surface2   = Color.dynamic(light: 0xF0F0F2, dark: 0x323234)
    static let surface3   = Color.dynamic(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let border     = Color.dynamic(light: 0xE2E2E6, dark: 0x38383A)
    static let ink2       = Color.dynamic(light: 0x6E6E73, dark: 0xA1A1A6)
    static let ink3       = Color.dynamic(light: 0x86868B, dark: 0x7F7F85)

    static let blue   = Color.dynamic(light: 0x007AFF, dark: 0x0A84FF)
    static let green  = Color.dynamic(light: 0x28A745, dark: 0x30D158)
    static let cyan   = Color.dynamic(light: 0x0A9FBD, dark: 0x40C8E0)
    static let violet = Color.dynamic(light: 0x9B4FD0, dark: 0xBF5AF2)
    static let amber  = Color.dynamic(light: 0xE08600, dark: 0xFF9F0A)
    static let red    = Color.dynamic(light: 0xFF3B30, dark: 0xFF453A)

    /// User-pickable colours for labels, classes, projects and subjects.
    static let swatches: [UInt32] = [0xC15F3C, 0x2B7BBF, 0x6F8F24, 0x1F9D8F, 0x6A63C4, 0xBC8A1C, 0xCB4733, 0xB34A82, 0x6C6557]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(macOS)
        Color(nsColor: .dynamic(light: light, dark: dark))
        #else
        Color(uiColor: .dynamic(light: light, dark: dark))
        #endif
    }
}

extension PlatformColor {
    /// AppKit/UIKit version of `Color.dynamic`, for text views.
    static func dynamic(light: UInt32, dark: UInt32) -> PlatformColor {
        #if os(macOS)
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return platformColor(isDark ? dark : light)
        }
        #else
        UIColor { traits in
            platformColor(traits.userInterfaceStyle == .dark ? dark : light)
        }
        #endif
    }
}

#if os(macOS)
nonisolated private func platformColor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
#else
nonisolated private func platformColor(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
#endif

extension Font {
    /// Big numerals (stat tiles, countdowns) use SF Pro Rounded in the design.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        // The shadow is on the background shape, not the content: a shadow on the content renders the whole card
        // (every row of a long list) offscreen again whenever anything in it changes.
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }
}

extension View {
    func cardBackground(radius: CGFloat = 12) -> some View { modifier(CardBackground(radius: radius)) }
}
