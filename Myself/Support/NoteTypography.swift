import SwiftUI
import CoreText

/// Fonts for note pages. Latin text uses the system font (SF Pro) and Bengali falls back, through the font's
/// cascade list, to the bundled Hind Siliguri.
enum NoteTypeface {
    /// Body text size; headings and code are sized from it.
    static let bodySize: CGFloat = 15.5
    static let bengaliFamily = "Hind Siliguri"

    /// Registers the bundled `Fonts/*.ttf` for this process. Runs once, the first time a note font is made.
    private static let registered: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    private static var cache: [String: PlatformFont] = [:]

    static func platformFont(size: CGFloat, weight: PlatformFont.Weight = .regular,
                             italic: Bool = false, monospaced: Bool = false) -> PlatformFont {
        _ = registered
        let key = "\(size)|\(weight.rawValue)|\(italic)|\(monospaced)"
        if let font = cache[key] { return font }

        var base = monospaced ? PlatformFont.monospacedSystemFont(ofSize: size, weight: weight) : PlatformFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        #if os(macOS)
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        let bengali = NSFontDescriptor(fontAttributes: [.name: bengaliName(weight)])
        descriptor = descriptor.addingAttributes([.cascadeList: [bengali]])
        base = NSFont(descriptor: descriptor, size: size) ?? base
        #else
        if italic, let slanted = descriptor.withSymbolicTraits(.traitItalic) { descriptor = slanted }
        let bengali = UIFontDescriptor(fontAttributes: [.name: bengaliName(weight)])
        descriptor = descriptor.addingAttributes([.cascadeList: [bengali]])
        base = UIFont(descriptor: descriptor, size: size)
        #endif
        cache[key] = base
        return base
    }

    static func font(size: CGFloat, weight: PlatformFont.Weight = .regular,
                     italic: Bool = false, monospaced: Bool = false) -> Font {
        Font(platformFont(size: size, weight: weight, italic: italic, monospaced: monospaced) as CTFont)
    }

    /// The bundled Hind Siliguri file closest to `weight` (Regular, Medium, SemiBold, Bold), named outright so the
    /// cascade can't settle on another weight.
    private static func bengaliName(_ weight: PlatformFont.Weight) -> String {
        switch weight.rawValue {
        case ..<0.1: "HindSiliguri-Regular"
        case ..<0.3: "HindSiliguri-Medium"
        case ..<0.4: "HindSiliguri-SemiBold"
        default: "HindSiliguri-Bold"
        }
    }

    /// Extra space between lines: the design's 1.65 line height, 1.85 for Bengali, which has taller glyphs.
    static func lineSpacing(size: CGFloat, bengali: Bool) -> CGFloat {
        size * (bengali ? 0.62 : 0.42)
    }
}
