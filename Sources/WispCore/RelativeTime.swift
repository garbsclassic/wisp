import Foundation

/// "just now", "5 min ago", "yesterday": as coarse as a glance at the footer wants.
public enum RelativeTime {
    /// Elapsed minutes or hours under a day, calendar days under a week, then the date. A
    /// future date, from a clock skewed by sync, is `just now`.
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
