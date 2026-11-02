import SwiftUI
import WidgetKit

/// A widget view drawn at its desktop size outside WidgetKit, for the dark-mode previews (`#Preview(as:)` only draws
/// the light appearance; the canvas's Color Scheme variants also work).
struct WidgetPreviewCard<Content: View>: View {
    let family: WidgetFamily
    var scheme: ColorScheme = .dark
    var background: AnyShapeStyle = AnyShapeStyle(.background)
    @ViewBuilder let content: Content

    static func size(of family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemLarge: CGSize(width: 356, height: 356)
        default: CGSize(width: 356, height: 170)
        }
    }

    var body: some View {
        let size = Self.size(of: family)
        content
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(width: size.width, height: size.height)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(24)
            .environment(\.colorScheme, scheme)
    }
}
