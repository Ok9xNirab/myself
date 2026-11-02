import SwiftUI
import WidgetKit

/// Type and colour tokens from `MySelf Widgets.html`.
enum WidgetFont {
    /// `.t`: row titles.
    static let title = Font.system(size: 13, weight: .semibold)
    /// `.t` at medium weight, for list rows (focus, revision queue).
    static let row = Font.system(size: 13, weight: .medium)
    /// `.s`: secondary lines.
    static let subtitle = Font.system(size: 11.5)
    /// `.big`: the headline numbers.
    static let big = Font.system(size: 44, weight: .bold)
}

/// The widget colours: the system ones the design names.
enum WidgetColor {
    static let blue = Color.blue
    static let red = Color.red
    static let orange = Color.orange
    static let green = Color.green
    static let purple = Color.purple
    static let cyan = Color.cyan
    /// The soft fill behind buttons and the capture field (`--soft`).
    static let soft = Color.primary.opacity(0.06)
}

/// The 0.5 pt line between rows.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }
}

/// What a widget shows when there's nothing to list: one short secondary line, centred.
struct EmptyMessage: View {
    let text: String
    var systemImage: String?

    var body: some View {
        VStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 18, weight: .medium)).foregroundStyle(.tertiary)
            }
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown instead of a widget's content while its feature is turned off in Settings › Features.
struct FeatureOffMessage: View {
    let feature: String

    var body: some View {
        EmptyMessage(text: "\(feature) is turned off in MySelf Settings", systemImage: "eye.slash")
    }
}

extension View {
    /// The standard widget background: the system's, so it follows light, dark, the desktop tint and accented mode.
    func widgetBackground() -> some View {
        containerBackground(.background, for: .widget)
    }
}
