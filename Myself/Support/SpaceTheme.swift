import SwiftUI

/// Settings › General › Theme: the colours of the soft mesh behind the top of every page ("space background" in
/// the v2 design). Ink is the one dark theme.
enum SpaceTheme: String, CaseIterable, Identifiable {
    case dawn, dusk, ember, lagoon, meadow, orchid, paper, ink

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// The three gradient stops (top left, top middle, top right), from the design's `THP`.
    var colors: [UInt32] {
        switch self {
        case .dawn: [0xFFD3B0, 0xC9D5FF, 0xF7C6E0]
        case .dusk: [0xD9C6FF, 0xF4C6EA, 0xBCCAFF]
        case .ember: [0xFFC996, 0xFFE3A8, 0xFFAE93]
        case .lagoon: [0xB9DCFF, 0xC2EFF2, 0xD0CAFF]
        case .meadow: [0xC6ECCA, 0xE6F3B9, 0xB6E6DB]
        case .orchid: [0xF8C3E1, 0xE2CDFC, 0xFFD2C9]
        case .paper: [0xEBE4D6, 0xF4EFE5, 0xE2DBCF]
        case .ink: [0x3B3F8F, 0x5B2F7A, 0x1F4F7A]
        }
    }

    var isDark: Bool { self == .ink }

    static let `default` = SpaceTheme.dawn
}

/// Settings › General › Theme › Match system appearance. On: light or dark follows Appearance (Auto follows the
/// Mac). Off: the theme decides, so Ink is dark and the others are light.
enum ThemeAppearance: String, CaseIterable, Identifiable {
    case system, theme

    var id: Self { self }
    var title: String { self == .system ? "On" : "Off" }
}

/// Settings › General › Theme › Paper width: how wide pages and notes may grow.
enum PaperWidth: String, CaseIterable, Identifiable {
    case comfortable, wide

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// Maximum width of a page's content (`PageScroll`).
    var page: CGFloat? { self == .comfortable ? 1140 : nil }
    /// Maximum width of a note's text column.
    var note: CGFloat { self == .comfortable ? 720 : 1000 }
}

/// Cover gradients a note can use, from the design's `PAL` (name and the three mesh colours).
enum CoverGradient: String, CaseIterable, Identifiable {
    case meadow, dawn, dusk, ember, lagoon, orchid, teal, paper

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var colors: [UInt32] {
        switch self {
        case .meadow: [0xC6ECCA, 0xE6F3B9, 0xB6E6DB]
        case .dawn: [0xFFD3B0, 0xC9D5FF, 0xF7C6E0]
        case .dusk: [0xD9C6FF, 0xF4C6EA, 0xBCCAFF]
        case .ember: [0xFFC996, 0xFFE3A8, 0xFFAE93]
        case .lagoon: [0xB9DCFF, 0xC2EFF2, 0xD0CAFF]
        case .orchid: [0xF8C3E1, 0xE2CDFC, 0xFFD2C9]
        case .teal: [0xB3E7EE, 0xCDEEDD, 0xC3D6FF]
        case .paper: [0xEBE4D6, 0xF4EFE5, 0xE2DBCF]
        }
    }
}

/// The colour scheme the theme settings ask for, or nil to follow the Mac.
func themedColorScheme(appearance: String, theme: SpaceTheme, mode: ThemeAppearance) -> ColorScheme? {
    if mode == .theme { return theme.isDark ? .dark : .light }
    return appearance == "dark" ? .dark : appearance == "light" ? .light : nil
}

// MARK: Mesh

/// Three soft radial blobs over a base colour, with faint concentric rings: the design's `.mesh` (note covers,
/// theme swatches) and, fading out at the bottom, `.scape` (the band behind the top of each page).
struct MeshGradientView: View {
    var colors: [UInt32]
    /// Fill the whole rect with the middle colour first (`.mesh`); the page band leaves the page colour showing.
    var filled = true
    var rings = true

    var body: some View {
        Canvas { context, size in
            let c = colors.map { Color(hex: $0) }
            guard c.count == 3 else { return }
            let w = size.width, h = size.height
            if filled { context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c[1])) }
            // (centre x, centre y, radius x, radius y) as fractions of the size, from the CSS radial-gradients.
            let blobs: [(Color, CGFloat, CGFloat, CGFloat, CGFloat)] = filled
                ? [(c[0], 0.06, -0.10, 0.75, 1.5), (c[1], 0.62, -0.20, 0.60, 1.3), (c[2], 1.04, 0.70, 0.55, 1.4)]
                : [(c[0], 0.08, -0.12, 0.60, 1.1), (c[1], 0.58, -0.22, 0.48, 0.95), (c[2], 1.02, 0.08, 0.42, 1.1)]
            for (color, x, y, rx, ry) in blobs {
                var blob = context
                blob.translateBy(x: x * w, y: y * h)
                blob.scaleBy(x: rx * w, y: ry * h)
                let gradient = Gradient(stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: 0.72)])
                blob.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                          with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
            }
            guard rings else { return }
            // Faint rings around a point above the top right corner, fading towards the bottom.
            let center = CGPoint(x: w * 0.86, y: -h * 0.18)
            let spacing: CGFloat = filled ? 10 : 22
            let reach = hypot(w, h * 1.2)
            var ring: CGFloat = spacing
            var path = Path()
            while ring < reach {
                path.addEllipse(in: CGRect(x: center.x - ring * 1.3, y: center.y - ring * 0.95, width: ring * 2.6, height: ring * 1.9))
                ring += spacing
            }
            var stroke = context
            stroke.opacity = filled ? 0.35 : 0.3
            stroke.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: h * 0.88)))
            stroke.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.7), .white.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.88)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The theme's colour band behind the top of a page, fading into the page background. Dimmer in dark mode.
struct ScapeBackground: View {
    var height: CGFloat = 300
    @AppStorage(PrefKey.spaceTheme) private var theme = SpaceTheme.default
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
            MeshGradientView(colors: theme.colors, filled: false)
                .frame(height: height)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(scheme == .dark ? (theme.isDark ? 0.8 : 0.4) : 1)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Puts the theme's band behind the page (pages that don't use `PageScroll`).
    func scapeBackground(height: CGFloat = 300) -> some View {
        background { ScapeBackground(height: height) }
    }
}

// MARK: Theme picker

/// A row of theme swatches, as in Settings › General.
struct SpaceThemePicker: View {
    @Binding var selection: SpaceTheme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            ForEach(SpaceTheme.allCases) { theme in
                let on = theme == selection
                Button { selection = theme } label: {
                    VStack(spacing: 5) {
                        MeshGradientView(colors: theme.colors)
                            .frame(height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                        Text(theme.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(on ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(theme.title) theme")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
