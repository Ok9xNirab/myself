import WidgetKit

/// A timeline entry: the data and the moment it describes.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static var sample: SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    static var empty: SnapshotEntry { SnapshotEntry(date: .now, snapshot: WidgetSnapshot()) }
}

extension WidgetSnapshot {
    /// The data for a timeline: the store's, or nothing (empty states) when there's no store yet.
    static func current() -> (snapshot: WidgetSnapshot, readable: Bool) {
        if let snapshot = WidgetStore.load() { return (snapshot, true) }
        return (WidgetSnapshot(disabled: SharedStore.disabledFeatures), false)
    }

    /// The gallery and the "add widget" preview show the sample data; a widget on the desktop shows the store's.
    static func forSnapshot(_ context: TimelineProviderContext) -> WidgetSnapshot {
        context.isPreview ? .sample : current().snapshot
    }
}

/// Entries for now, each class boundary in the rest of the day and midnight, then a new timeline. If the store
/// couldn't be read, it tries again in 30 minutes.
func makeTimeline<Entry: TimelineEntry>(_ snapshot: WidgetSnapshot, readable: Bool, now: Date = .now,
                                        entry: (Date) -> Entry) -> Timeline<Entry> {
    guard readable else {
        return Timeline(entries: [entry(now)], policy: .after(now.addingTimeInterval(30 * 60)))
    }
    let dates = [now] + snapshot.refreshDates(after: now)
    return Timeline(entries: dates.map(entry), policy: .atEnd)
}

/// The provider for the widgets without a configuration.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: .forSnapshot(context)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let (snapshot, readable) = WidgetSnapshot.current()
        completion(makeTimeline(snapshot, readable: readable) { SnapshotEntry(date: $0, snapshot: snapshot) })
    }
}
