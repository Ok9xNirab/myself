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

/// Colour tokens from the v2 design (`MySelf macOS v2.html`): a warm paper background, white cards and
/// saturated "space" colours (light / dark pairs).
enum Palette {
    static let background = Color.dynamic(light: 0xF5F4F1, dark: 0x121318)
    static let surface    = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1D23)
    static let surface2   = Color.dynamic(light: 0xF0EFEB, dark: 0x24252C)
    static let surface3   = Color.dynamic(light: 0xE7E6E1, dark: 0x2E2F37)
    static let border     = Color.dynamic(light: 0xE6E5E1, dark: 0x2B2C33)
    static let ink2       = Color.dynamic(light: 0x6B6B70, dark: 0xA3A3AD)
    static let ink3       = Color.dynamic(light: 0x8E8E93, dark: 0x74747E)

    static let blue   = Color.dynamic(light: 0x2F6FEC, dark: 0x7AA6FF)
    static let green  = Color.dynamic(light: 0x2FA866, dark: 0x5FD393)
    static let cyan   = Color.dynamic(light: 0x1AA6B7, dark: 0x4CC9D8)
    static let violet = Color.dynamic(light: 0x8A5CF0, dark: 0xB9A0FF)
    static let amber  = Color.dynamic(light: 0xF5871F, dark: 0xFFAE5C)
    static let red    = Color.dynamic(light: 0xEF4B4B, dark: 0xFF7B7B)
    static let brown  = Color.dynamic(light: 0xB0773E, dark: 0xD49A60)

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
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        // The shadow is on the background shape, not the content: a shadow on the content renders the whole card
        // (every row of a long list) offscreen again whenever anything in it changes.
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: Color(red: 30 / 255, green: 30 / 255, blue: 70 / 255).opacity(0.07), radius: 12, y: 6)
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

extension View {
    func cardBackground(radius: CGFloat = 16) -> some View { modifier(CardBackground(radius: radius)) }
}
