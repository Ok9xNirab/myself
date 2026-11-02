import AppIntents
import SwiftUI
import WidgetKit

/// 7. Capture (small): opens MySelf on a new note or a new todo.
struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.capture, provider: SnapshotProvider()) { entry in
            CaptureWidgetView(entry: entry)
                .widgetBackground()
                .widgetURL((entry.snapshot.notesOn ? DeepLink.newNote : .newTodo).url)
        }
        .configurationDisplayName("Capture")
        .description("Start a note or a todo in one click.")
        .supportedFamilies([.systemSmall])
    }
}

struct CaptureWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let notes = entry.snapshot.notesOn
        VStack(alignment: .leading, spacing: 0) {
            Caption(title: "Capture", dot: WidgetColor.purple)
            Button(intent: OpenURLIntent((notes ? DeepLink.newNote : .newTodo).url)) {
                Text(notes ? "Jot a note\u{2026}" : "Add a todo\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(WidgetColor.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)

            HStack(spacing: 6) {
                if notes { CaptureButton(title: "Note", link: .newNote) }
                CaptureButton(title: "Todo", link: .newTodo)
            }
        }
    }
}

private struct CaptureButton: View {
    let title: String
    let link: DeepLink

    var body: some View {
        Button(intent: OpenURLIntent(link.url)) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WidgetColor.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(WidgetColor.soft, in: Capsule())
                .widgetAccentable()
        }
        .buttonStyle(.plain)
    }
}

#Preview("Capture", as: .systemSmall) {
    CaptureWidget()
} timeline: {
    SnapshotEntry.sample
}

#Preview("Capture · dark") {
    WidgetPreviewCard(family: .systemSmall) { CaptureWidgetView(entry: .sample) }
}
