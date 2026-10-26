import SwiftUI

enum Day {
    static var calendar: Calendar { .current }

    /// Start of today shifted by `n` days. Sample data is relative to today so the app always looks fresh.
    static func offset(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: .now))!
    }

    /// Whole days from today to `date` (negative = past).
    static func fromToday(_ date: Date?) -> Int? {
        guard let date else { return nil }
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day
    }

    /// Start of today, worked out again only once the day (or time zone) changes: lists call `fromToday` for every
    /// row each time they're drawn.
    private static var today: Date {
        let now = Date.now, zone = TimeZone.current
        if let cached = todayCache, cached.zone == zone, cached.range.contains(now) { return cached.range.lowerBound }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        todayCache = (start..<end, zone)
        return start
    }

    private static var todayCache: (range: Range<Date>, zone: TimeZone)?

    static func isToday(_ date: Date?) -> Bool { fromToday(date) == 0 }

    /// Next `count` dates (from today) that fall on any of `days`.
    static func sessions(on days: [Weekday], count: Int) -> [Date] {
        var out: [Date] = []
        var cursor = calendar.startOfDay(for: .now)
        var guardCount = 0
        while out.count < count && guardCount < 400 {
            if let wd = Weekday(rawValue: calendar.component(.weekday, from: cursor)), days.contains(wd) {
                out.append(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            guardCount += 1
        }
        return out
    }
}

enum Weekday: Int, CaseIterable, Hashable, Codable {
    case sun = 1, mon, tue, wed, thu, fri, sat

    var code: String { ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][rawValue - 1] }
    var initial: String { ["S", "M", "T", "W", "T", "F", "S"][rawValue - 1] }

    static var today: Weekday { Weekday(rawValue: Day.calendar.component(.weekday, from: .now))! }
    static func of(_ date: Date) -> Weekday { Weekday(rawValue: Day.calendar.component(.weekday, from: date))! }
}

struct ClockTime: Hashable, Comparable, Codable {
    var hour: Int
    var minute: Int

    var formatted: String {
        let h = (hour + 11) % 12 + 1
        return String(format: "%d:%02d %@", h, minute, hour >= 12 ? "PM" : "AM")
    }

    static func < (a: ClockTime, b: ClockTime) -> Bool { (a.hour, a.minute) < (b.hour, b.minute) }
}

struct DueMeta {
    enum Tone { case overdue, today, soon, later }
    let text: String
    let tone: Tone

    var color: Color {
        switch tone {
        case .overdue: Palette.red
        case .today: .accentColor
        case .soon: Palette.amber
        case .later: Palette.ink2
        }
    }

    init?(_ date: Date?) {
        guard let date, let n = Day.fromToday(date) else { return nil }
        switch n {
        case ..<0: (text, tone) = (n == -1 ? "Yesterday" : "\(-n)d overdue", .overdue)
        case 0: (text, tone) = ("Today", .today)
        case 1: (text, tone) = ("Tomorrow", .soon)
        case 2...6: (text, tone) = ("In \(n) days", .soon)
        default: (text, tone) = (date.monthDay, .later)
        }
    }
}

extension Date {
    /// "May 30"
    var monthDay: String { formatted(.dateTime.month(.abbreviated).day()) }
    /// "Saturday, May 30"
    var weekdayMonthDay: String { formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
}
