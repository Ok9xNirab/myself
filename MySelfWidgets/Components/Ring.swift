import SwiftUI
import WidgetKit

/// A ring split into coloured segments by value, on a quaternary track, starting at 12 o'clock.
struct Ring: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var lineWidth: CGFloat = 9

    var body: some View {
        let shown = segments.filter { $0.value > 0 }
        let total = shown.reduce(0) { $0 + $1.value }
        // A small gap between segments (the round caps would otherwise overlap).
        let gap = shown.count > 1 ? 0.045 : 0
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, segment in
                let start = shown.prefix(index).reduce(0) { $0 + $1.value } / total
                let end = start + segment.value / total
                Circle()
                    .trim(from: start, to: max(start + 0.001, end - gap))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .widgetAccentable()
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
    }
}
