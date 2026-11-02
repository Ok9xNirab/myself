import Foundation
import SwiftData
import WidgetKit

/// Asks WidgetKit to redraw the widgets after the data they show changes. Bursts (a reload, a batch of saves) are
/// coalesced into one request a moment later.
enum WidgetRefresh {
    private static var pending: Task<Void, Never>?

    static func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Whether a save touches anything a widget shows. Notes, Product Dev and labels don't, so typing in a note never
    /// redraws the widgets.
    static func affectsWidgets(_ context: ModelContext) -> Bool {
        (context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray).contains { model in
            model is TodoModel || model is OfficeTaskModel || model is UniClassModel || model is SyllabusSubjectModel
                || model is SyllabusTopicModel || model is AssignmentModel || model is ExamModel
                || model is StudySubjectModel || model is StudyTopicModel
        }
    }

    /// Calls `body` on the main actor whenever the widget extension has written to the store (ticked a task, added a
    /// revision).
    static func observeWidgetWrites(_ body: @escaping @MainActor () -> Void) {
        onWidgetWrite = body
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { WidgetRefresh.onWidgetWrite() } }
        }, SharedStore.didChangeNotification as CFString, nil, .deliverImmediately)
    }

    private static var onWidgetWrite: @MainActor () -> Void = {}
}
