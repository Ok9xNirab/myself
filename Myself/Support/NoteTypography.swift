import SwiftUI
import CoreText

/// Fonts for note pages. Latin text uses the system font (SF Pro) and Bengali the system's Bengali face (SF Bangla),
/// put first in the font's cascade list at its own weight.
enum NoteTypeface {
    /// Body text size; headings and code are sized from it.
    static let bodySize: CGFloat = 15.5
    static let bengaliFamily = "SF Bangla"

    private static var cache: [String: PlatformFont] = [:]

    static func platformFont(size: CGFloat, weight: PlatformFont.Weight = .regular,
                             italic: Bool = false, monospaced: Bool = false) -> PlatformFont {
        let key = "\(size)|\(weight.rawValue)|\(italic)|\(monospaced)"
        if let font = cache[key] { return font }

        var base = monospaced ? PlatformFont.monospacedSystemFont(ofSize: size, weight: weight) : PlatformFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        #if os(macOS)
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        descriptor = descriptor.addingAttributes([.cascadeList: [bengaliFont(size: size, weight: weight).fontDescriptor]])
        base = NSFont(descriptor: descriptor, size: size) ?? base
        #else
        if italic, let slanted = descriptor.withSymbolicTraits(.traitItalic) { descriptor = slanted }
        descriptor = descriptor.addingAttributes([.cascadeList: [bengaliFont(size: size, weight: weight).fontDescriptor]])
        base = UIFont(descriptor: descriptor, size: size)
        #endif
        cache[key] = base
        return base
    }

    static func font(size: CGFloat, weight: PlatformFont.Weight = .regular,
                     italic: Bool = false, monospaced: Bool = false) -> Font {
        Font(platformFont(size: size, weight: weight, italic: italic, monospaced: monospaced) as CTFont)
    }

    /// The system's Bengali font at `weight`, found the way text fallback would find it, so no hidden font name is
    /// spelled out. Regular text is set in Light (300).
    private static func bengaliFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        let bengaliWeight = weight.rawValue < 0.1 ? PlatformFont.Weight.light : weight
        let system = PlatformFont.systemFont(ofSize: size, weight: bengaliWeight)
        return CTFontCreateForString(system as CTFont, "অ" as CFString, CFRange(location: 0, length: 1)) as PlatformFont
    }

    /// Extra space between lines: the design's 1.65 line height, 1.85 for Bengali, which has taller glyphs.
    static func lineSpacing(size: CGFloat, bengali: Bool) -> CGFloat {
        size * (bengali ? 0.62 : 0.42)
    }
}
