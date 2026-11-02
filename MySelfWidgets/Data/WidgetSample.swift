import Foundation

/// Placeholder and gallery data, matching `MySelf Widgets.html`: 5 things due today (4 office, 1 University),
/// "Electronic Devices & Circuit Lab" in 2 days, 171 topics due with 15% covered. Dates are relative to `now`.
extension WidgetSnapshot {
    static var sample: WidgetSnapshot { sample(now: .now) }

    static func sample(now: Date) -> WidgetSnapshot {
        let calendar = Day.calendar
        let today = calendar.startOfDay(for: now)
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today)! }
        func weekday(_ n: Int) -> Weekday { Weekday.of(day(n)) }
        func at(_ n: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(n))!
        }

        var s = WidgetSnapshot()
        s.office = [
            OfficeTask(id: "o1", title: "Password change", due: day(-13), createdAt: day(-20)),
            OfficeTask(id: "o2", title: "Subscription purchase, upgrade & downgrade", due: day(-13), createdAt: day(-19)),
            OfficeTask(id: "o3", title: "Quarterly access review", due: day(-2), createdAt: day(-9)),
            OfficeTask(id: "o4", title: "Send the release notes", due: day(0), createdAt: day(-3)),
        ]
        s.university.classes = [
            UniClass(id: "c1", subject: "Professional Ethics & Env. Protection", code: "0223-201", days: [weekday(1)],
                     time: ClockTime(hour: 18, minute: 0), room: "Online", hex: 0x9B4FD0, createdAt: day(-60)),
            UniClass(id: "c2", subject: "Computer Architecture", code: "0613-203", days: [weekday(1), weekday(5)],
                     time: ClockTime(hour: 19, minute: 40), room: "Online", hex: 0xE08600, createdAt: day(-59)),
            UniClass(id: "c3", subject: "Electronic Devices & Circuit Lab", code: "0714-205", days: [weekday(0), weekday(2)],
                     time: ClockTime(hour: 18, minute: 0), room: "EEE Lab-2", hex: 0xFF3B30, createdAt: day(-58)),
            UniClass(id: "c4", subject: "Object-Oriented Programming Languages Lab", code: "0613-206", days: [weekday(2)],
                     time: ClockTime(hour: 19, minute: 40), room: "CSE Lab-5", hex: 0x9B4FD0, createdAt: day(-57)),
            UniClass(id: "c5", subject: "Differential Equations", code: "0541-201", days: [weekday(6)],
                     time: ClockTime(hour: 10, minute: 0), room: "Room 402", hex: 0x28A745, createdAt: day(-56)),
        ]
        s.university.assignments = [
            Assignment(id: "a1", title: "Assignment · Diff. Equations", subject: "Differential Equations", due: day(-1), createdAt: day(-8)),
            Assignment(id: "a2", title: "Lab report", subject: "Electronic Devices & Circuit Lab", due: day(2), createdAt: day(-5)),
        ]
        s.university.exams = [
            Exam(id: "e1", subject: "Electronic Devices & Circuit Lab", kind: .final, date: at(2, 18), prep: 40),
            Exam(id: "e2", subject: "Computer Architecture", kind: .midterm, date: day(9), prep: 10),
        ]
        func subject(_ name: String, done: Int, of total: Int) -> SyllabusSubject {
            SyllabusSubject(id: name, subject: name, topics: (0..<total).map { SyllabusTopic(id: "\(name)-\($0)", name: "Topic \($0 + 1)", done: $0 < done) })
        }
        s.university.syllabus = [
            subject("Chemistry", done: 1, of: 16),
            subject("Object-Oriented Programming", done: 1, of: 20),
            subject("Electronic Devices & Circuit", done: 0, of: 4),
        ]

        // 200 topics: 30 revised (15%), 29 of them this week, so 171 are due.
        let bangla = ["আদিযুগ - চর্যাপদ : ছন্দ", "আদিযুগ - চর্যাপদ : কবি", "মধ্যযুগ - শ্রীকৃষ্ণকীর্তন", "মধ্যযুগ - মঙ্গলকাব্য", "বৈষ্ণব পদাবলি"]
        var literature = StudySubject(id: "j1", subject: "Bangla Literature", hex: 0xE08600, createdAt: day(-30))
        literature.topics = bangla.enumerated().map { StudyTopic(id: "b\($0.offset)", name: $0.element) }
            + (5..<120).map { StudyTopic(id: "b\($0)", name: "সাহিত্য পাঠ \($0 - 4)") }
        var english = StudySubject(id: "j2", subject: "English Grammar", hex: 0x2B7BBF, createdAt: day(-29))
        english.topics = (0..<80).map { i in
            StudyTopic(id: "g\(i)", name: "Grammar topic \(i + 1)", revisions: i < 30 ? 1 : 0,
                       lastRevised: i < 29 ? day(-2) : i < 30 ? day(-20) : nil)
        }
        s.jobStudy = [literature, english]
        return s
    }
}
