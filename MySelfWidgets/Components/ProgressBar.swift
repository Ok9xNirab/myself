import SwiftUI
import WidgetKit

/// A 4 pt capsule bar on a quaternary track. `value` is 0–1.
struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if value > 0 {
                    Capsule().fill(tint)
                        .frame(width: max(4, proxy.size.width * min(1, value)))
                        .widgetAccentable()
                }
            }
        }
        .frame(height: 4)
    }
}
