import SwiftUI
import WidgetKit

/// A widget's header: a 7 pt coloured dot, the title in small caps, and an optional note on the right.
struct Caption: View {
    let title: String
    var dot: Color?
    var trailing: String?
    /// Overrides the secondary colour (the Next exam widget is white on red).
    var tint: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7).widgetAccentable()
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }
}
