import Foundation
import Testing

@testable import WispCore

/// A fixed calendar and locale so buckets don't depend on the machine; January avoids DST.
@Suite("RelativeTime.coarse")
struct RelativeTimeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    private func coarse(_ date: Date, now: Date) -> String {
        RelativeTime.coarse(date, now: now, calendar: calendar, locale: locale)
    }

    @Test("59 seconds elapsed reads as just now")
    func fiftyNineSeconds() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(-59), now: now) == "just now")
    }

    @Test("A date in the future reads as just now, not a negative duration")
    func future() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(60), now: now) == "just now")
    }

    @Test("60 seconds elapsed reads as 1 min ago")
    func sixtySeconds() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(-60), now: now) == "1 min ago")
    }

    @Test("59 minutes 59 seconds elapsed reads as 59 min ago, floored")
    func fiftyNineMinutesFiftyNineSeconds() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(-3599), now: now) == "59 min ago")
    }

    @Test("60 minutes elapsed reads as 1 hr ago")
    func sixtyMinutes() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(-3600), now: now) == "1 hr ago")
    }

    @Test("23 hours 59 minutes elapsed reads as 23 hr ago, floored")
    func twentyThreeHoursFiftyNineMinutes() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(-86_340), now: now) == "23 hr ago")
    }

    @Test("24 hours elapsed lands one calendar day back, which reads as yesterday")
    func twentyFourHours() {
        let now = date(2026, 1, 15, 12, 0, 0)
        #expect(coarse(now.addingTimeInterval(-86_400), now: now) == "yesterday")
    }

    @Test("23:00 yesterday to 01:00 today reads as 2 hr ago, not a day-based bucket")
    func crossesMidnightWithinTwoHours() {
        let now = date(2026, 1, 15, 1, 0, 0)
        let then = date(2026, 1, 14, 23, 0, 0)
        #expect(coarse(then, now: now) == "2 hr ago")
    }

    @Test("36 elapsed hours that span two calendar days reads as 2 days ago")
    func thirtySixHoursAcrossTwoCalendarDays() {
        let now = date(2026, 1, 15, 1, 0, 0)
        let then = now.addingTimeInterval(-36 * 3600)
        #expect(coarse(then, now: now) == "2 days ago")
    }

    @Test("6 calendar days elapsed reads as 6 days ago")
    func sixDays() {
        let now = date(2026, 1, 15, 12, 0, 0)
        let then = date(2026, 1, 9, 12, 0, 0)
        #expect(coarse(then, now: now) == "6 days ago")
    }

    @Test("7 calendar days elapsed switches to a localized date instead of days ago")
    func sevenDays() {
        let now = date(2026, 1, 15, 12, 0, 0)
        let then = date(2026, 1, 8, 12, 0, 0)
        #expect(coarse(then, now: now) == "Jan 8")
    }

    @Test("A previous-year date formats with the year")
    func previousYear() {
        let now = date(2026, 1, 15, 12, 0, 0)
        let then = date(2025, 12, 20, 12, 0, 0)
        #expect(coarse(then, now: now) == "Dec 20, 2025")
    }
}
