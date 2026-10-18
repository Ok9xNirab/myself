import SwiftUI
import CoreText

/// Fonts for note pages. Latin text uses the system font in the page's design (sans, serif, rounded) and
/// Bengali falls back, through the font's cascade list, to the bundled typeface picked in the "Aa অ" menu.
enum NoteTypeface {
    /// Registers the bundled `Fonts/*.ttf` for this process. Runs once, the first time a note font is made.
    private static let registered: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    private static var cache: [String: PlatformFont] = [:]

    static func platformFont(_ typography: NoteFont, size: CGFloat, weight: PlatformFont.Weight = .regular,
                             italic: Bool = false, monospaced: Bool = false) -> PlatformFont {
        _ = registered
        let key = "\(typography.latin.rawValue)|\(typography.bengali.rawValue)|\(size)|\(weight.rawValue)|\(italic)|\(monospaced)"
        if let font = cache[key] { return font }

        var base = monospaced ? PlatformFont.monospacedSystemFont(ofSize: size, weight: weight) : PlatformFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        #if os(macOS)
        if !monospaced, let design = typography.latin.systemDesign, let designed = descriptor.withDesign(design) { descriptor = designed }
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        let bengali = NSFontDescriptor(fontAttributes: [.family: typography.bengali.family, .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        descriptor = descriptor.addingAttributes([.cascadeList: [bengali]])
        base = NSFont(descriptor: descriptor, size: size) ?? base
        #else
        if !monospaced, let design = typography.latin.systemDesign, let designed = descriptor.withDesign(design) { descriptor = designed }
        if italic, let slanted = descriptor.withSymbolicTraits(.traitItalic) { descriptor = slanted }
        let bengali = UIFontDescriptor(fontAttributes: [.family: typography.bengali.family, .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
        descriptor = descriptor.addingAttributes([.cascadeList: [bengali]])
        base = UIFont(descriptor: descriptor, size: size)
        #endif
        cache[key] = base
        return base
    }

    static func font(_ typography: NoteFont, size: CGFloat, weight: PlatformFont.Weight = .regular,
                     italic: Bool = false, monospaced: Bool = false) -> Font {
        Font(platformFont(typography, size: size, weight: weight, italic: italic, monospaced: monospaced) as CTFont)
    }

    /// A sample of one Bengali typeface, for the typography menu.
    static func sample(_ bengali: NoteFont.Bengali, size: CGFloat) -> Font {
        _ = registered
        return .custom(bengali.family, size: size)
    }

    /// Extra space between lines: the design's 1.65 line height, 1.85 for Bengali, which has taller glyphs.
    static func lineSpacing(size: CGFloat, bengali: Bool) -> CGFloat {
        size * (bengali ? 0.62 : 0.42)
    }
}

extension NoteFont.Latin {
    #if os(macOS)
    var systemDesign: NSFontDescriptor.SystemDesign? {
        switch self {
        case .sans: nil
        case .serif: .serif
        case .rounded: .rounded
        }
    }
    #else
    var systemDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .sans: nil
        case .serif: .serif
        case .rounded: .rounded
        }
    }
    #endif
}

extension NoteFont.Bengali {
    /// Font family name of the bundled file.
    var family: String { title }
}
