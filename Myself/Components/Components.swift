import SwiftUI

// MARK: Page scaffolding

private struct PageWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 1000 }

extension EnvironmentValues {
    /// Width of the scrolling page, used for responsive column layouts.
    var pageWidth: CGFloat {
        get { self[PageWidthKey.self] }
        set { self[PageWidthKey.self] = newValue }
    }
}

/// Scrollable page body with the design's padding and max width.
struct PageScroll<Content: View>: View {
    var maxWidth: CGFloat? = 1140
    @ViewBuilder var content: Content

    var body: some View {
        // GeometryReader hands over the width while laying out, so a page is built at its real width the first
        // time, not at a guess and then again (switching between one and two columns on the way).
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(.horizontal, width < 700 ? 18 : 28)
                    .padding(.top, 18)
                    .padding(.bottom, 56)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.pageWidth, width)
            }
        }
        .background(Palette.background)
    }
}

/// Two columns side by side on wide pages, stacked on narrow ones.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var threshold: CGFloat = 820
    var ratio: CGFloat = 1
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.pageWidth) private var width

    var body: some View {
        if width >= threshold {
            RatioColumns(ratio: ratio, spacing: 16) {
                VStack(spacing: 16) { leading }
                VStack(spacing: 16) { trailing }
            }
        } else {
            VStack(spacing: 16) { leading; trailing }
        }
    }
}

/// Lays out exactly two subviews side by side, top-aligned, splitting width `ratio : 1`.
private struct RatioColumns: Layout {
    var ratio: CGFloat
    var spacing: CGFloat

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let lead = (total - spacing) * ratio / (1 + ratio)
        return (lead, total - spacing - lead)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 800
        let (a, b) = widths(total)
        let ha = subviews[0].sizeThatFits(ProposedViewSize(width: a, height: nil)).height
        let hb = subviews[1].sizeThatFits(ProposedViewSize(width: b, height: nil)).height
        return CGSize(width: total, height: max(ha, hb))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (a, b) = widths(bounds.width)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: a, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY), proposal: ProposedViewSize(width: b, height: nil))
    }
}

/// Equal-width tiles that stretch to fill the row (CSS `auto-fit`), wrapping when narrower than `minimum`.
struct StatGrid<Content: View>: View {
    var minimum: CGFloat = 150
    var count = 4
    @ViewBuilder var content: Content
    @Environment(\.pageWidth) private var width

    var body: some View {
        var columns = max(1, min(count, Int((width - 56 + 14) / (minimum + 14))))
        // Prefer a balanced 2×2 over a 3 + 1 orphan row.
        if columns < count, columns > count / 2 { columns = max(1, count / 2) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 14) { content }
    }
}

// MARK: Cards

struct Card<Accessory: View, Content: View>: View {
    var title: String
    var systemImage: String
    var tint: Color = Palette.ink3
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(tint).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .semibold))
                accessory
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 40)
            Divider().overlay(Palette.border)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, systemImage: String, tint: Color = Palette.ink3, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

/// Right-aligned count in a card header.
struct CountText: View {
    var value: Int
    var body: some View {
        Text("\(value)").font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.ink3)
    }
}

/// Small accent-coloured header button ("Add class", "Open boards ›").
struct GhostButton: View {
    var title: String
    var systemImage: String?
    var trailingChevron = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                if trailingChevron { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.borderless)
    }
}

struct StatTile: View {
    var systemImage: String
    var label: String
    var value: String
    var foot: String?
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(label).foregroundStyle(Palette.ink2)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(color)
            }
            .font(.system(size: 12, weight: .medium))
            Text(value).font(.numeral(28)).foregroundStyle(color).padding(.top, 8)
            if let foot {
                Text(foot).font(.system(size: 11)).foregroundStyle(Palette.ink3).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardBackground()
    }
}

struct Callout<Content: View>: View {
    var systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            content.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.ink3).padding(.bottom, 6)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink2)
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.ink3) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: Badges & chips

struct Badge: View {
    var text: String
    var systemImage: String?
    var color: Color = Palette.ink2

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .fixedSize()
    }
}

struct PriorityBadge: View {
    var priority: Priority
    var locked = false

    var body: some View {
        Badge(text: priority.title + (locked ? " · locked" : ""), systemImage: "flag.fill", color: priority.color)
    }
}

struct DueBadge: View {
    var date: Date?

    var body: some View {
        if let meta = DueMeta(date) {
            Badge(text: meta.text, systemImage: "clock", color: meta.color)
        }
    }
}

struct LabelChip: View {
    var label: TaskLabel

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(label.color).frame(width: 6, height: 6)
            Text(label.name)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(label.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(label.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .fixedSize()
    }
}

struct ColorDot: View {
    var color: Color
    var size: CGFloat = 9
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: Controls

/// Round macOS-style completion checkbox.
struct CheckCircle: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? Color.accentColor : Color.primary.opacity(0.3), lineWidth: 1.5)
                    .background(Circle().fill(isOn ? Color.accentColor : .clear))
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Palette.surface3)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, value / 100)))
                }
            }
            .frame(height: height)
            .animation(.smooth, value: value)
    }
}

/// "Label ............ 45%" above a progress bar.
struct LabeledProgress: View {
    var label: String
    var value: Int
    var color: Color = .accentColor
    var height: CGFloat = 5

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(label).foregroundStyle(Palette.ink2)
                Spacer()
                Text("\(value)%").monospacedDigit().foregroundStyle(Palette.ink3)
            }
            .font(.system(size: 11))
            ProgressBar(value: Double(value), color: color, height: height)
        }
    }
}

struct Donut<Content: View>: View {
    var value: Double
    var size: CGFloat = 96
    var lineWidth: CGFloat = 9
    var color: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(Palette.surface3, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, value / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.7), value: value)
            content
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

extension Donut where Content == Text {
    /// Donut with a centred percentage.
    init(percent: Int, size: CGFloat, lineWidth: CGFloat, color: Color) {
        self.init(value: Double(percent), size: size, lineWidth: lineWidth, color: color) {
            Text("\(percent)%").font(.system(size: size < 50 ? 11 : 12, weight: .semibold)).monospacedDigit()
        }
    }
}

/// Segmented-style tab strip used for products.
struct ColorTabs<Item: Identifiable>: View {
    var items: [Item]
    var selection: Item.ID?
    var title: (Item) -> String
    var color: (Item) -> Color
    var onSelect: (Item.ID) -> Void
    var addHelp = "Add"
    var onAdd: () -> Void = {}

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(items) { item in
                let active = item.id == selection
                Button { onSelect(item.id) } label: {
                    HStack(spacing: 7) {
                        ColorDot(color: color(item))
                        Text(title(item))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? Color.primary : Palette.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.surface)
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink3)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(addHelp)
        }
    }
}

/// Whether the pointer is over a row. A row keeps one in `@State` and sets it from `onHover`; only the views that
/// read `isOn` (its highlight, `RowActions`) redraw when it changes. Hover in plain `@State` redraws the whole row,
/// and scrolling a long list moves rows under the pointer one after another.
@Observable final class HoverState {
    var isOn = false
}

/// Fades a view in on hover (`off` opacity otherwise, or full while `forced`); always shown on touch platforms.
struct HoverOpacity: ViewModifier {
    var hover: HoverState
    var off: Double = 0
    var forced = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content.opacity(hover.isOn || forced ? 1 : off)
        #else
        content
        #endif
    }
}

/// Fills a row's background with `color` on hover.
struct HoverFill: View {
    var hover: HoverState
    var color: Color

    var body: some View { hover.isOn ? color : .clear }
}

/// Edit / delete buttons that appear on hover (always visible on touch platforms).
struct RowActions: View {
    var hover: HoverState
    var onEdit: (() -> Void)? = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            if let onEdit { iconButton("pencil", "Edit", onEdit) }
            iconButton("trash", "Delete", onDelete)
        }
        .modifier(HoverOpacity(hover: hover))
    }

    private func iconButton(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12)).foregroundStyle(Palette.ink2).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Inline "+ Add topic…" field.
struct InlineAdder: View {
    var placeholder: String
    var onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink3).frame(width: 18)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(commit)
        }
        .padding(.vertical, 4)
    }

    private func commit() {
        onAdd(text)
        text = ""
    }
}

// MARK: Layout

/// Wrapping horizontal layout for badges and chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let added = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if added > maxWidth, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Row container with the design's padding and hairline separator.
struct ListRow<Content: View>: View {
    var verticalPadding: CGFloat = 10
    @ViewBuilder var content: Content
    @Environment(\.rowDensity) private var density

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding + density.paddingDelta)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }
    }
}

/// Centered card shown over a blurred page that isn't ready yet (`Page.isComingSoon`).
struct ComingSoonCard: View {
    var page: Page

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: page.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(page.featureColor)
                .frame(width: 48, height: 48)
                .background(page.featureColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Badge(text: "Coming soon", systemImage: "sparkles", color: Color.accentColor)
            Text(page.title).font(.system(size: 17, weight: .bold))
            Text("\(page.featureDescription) are on the way.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 300)
        .cardBackground()
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }
}
