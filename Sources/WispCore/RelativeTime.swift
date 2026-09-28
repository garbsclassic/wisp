import Foundation

/// "just now", "5 min ago", "yesterday": how long ago something happened, as coarse as a glance
/// at the footer wants it.
public enum RelativeTime {
    /// Under a minute is `just now`, as is a date in the future — a clock skewed by sync is not
    /// worth a stranger phrase. Under a day counts elapsed minutes or hours, so 23:59 reads as
    /// `2 min ago` at 00:01. Past that it counts calendar days, so 10:00 two days back reads as
    /// `2 days ago` at 09:00, 47 hours on. Past a week it's the date.
    public static func coarse(
        _ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) hr ago" }

        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
            ).day ?? 0
        if days <= 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }
}
