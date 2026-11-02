import SwiftUI
import WidgetKit

/// A small tinted label ("13d overdue", "Oldest 13d"). It never wraps.
struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .widgetAccentable()
    }
}

/// The due-date chip of a focus row: "13d overdue" / "Yesterday" in red, "Today" in blue, "Tomorrow" / "In 2 days"
/// in orange.
struct DueChip: View {
    let due: Date?
    let now: Date

    var body: some View {
        if let (text, tint) = Self.label(due, now: now) {
            Chip(text: text, tint: tint)
        }
    }

    static func label(_ due: Date?, now: Date) -> (String, Color)? {
        guard let n = Day.between(now, due) else { return nil }
        switch n {
        case ..<(-1): return ("\(-n)d overdue", WidgetColor.red)
        case -1: return ("Yesterday", WidgetColor.red)
        case 0: return ("Today", WidgetColor.blue)
        case 1: return ("Tomorrow", WidgetColor.orange)
        case 2...6: return ("In \(n) days", WidgetColor.orange)
        default: return (due?.formatted(.dateTime.day().month(.abbreviated)) ?? "", .secondary)
        }
    }
}
