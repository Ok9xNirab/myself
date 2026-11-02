import SwiftUI
import WidgetKit

/// MySelf's desktop and Notification Center widgets. They read the app's SwiftData store from the App Group
/// (`WidgetStore`); the app reloads them whenever data they show changes (`WidgetRefresh`).
@main
struct MySelfWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WeekWidget()
        FocusWidget()
        TodayWidget()
        NextExamWidget()
        NextClassesWidget()
        JobStudyWidget()
        CaptureWidget()
        SyllabusWidget()
        ReviseWidget()
        OfficeWidget()
    }
}
