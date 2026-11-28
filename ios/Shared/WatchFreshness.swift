import Foundation

/// How old the reading on the Watch glance is.
///
/// The line comes from the snapshot's `fetchedAt` and the clock the glance
/// passes in. A placeholder that has never been fetched (`Date.distantPast`)
/// has no line. This type does not request a forecast.
enum WatchFreshness {
    /// Readings older than this are marked stale. Exactly this age stays current.
    static let staleAfter: TimeInterval = 60 * 60

    struct Line: Equatable {
        /// Visible age, such as "Updated 12 min ago".
        var text: String
        /// True when the reading is older than `staleAfter`.
        var isStale: Bool
        /// VoiceOver. Adds "stale" when `isStale` is true.
        var spoken: String
    }

    static func line(fetchedAt: Date, now: Date = Date()) -> Line? {
        guard fetchedAt != .distantPast else { return nil }
        let age = max(0, now.timeIntervalSince(fetchedAt))
        let stale = age > staleAfter
        let visible = phrase(for: age)
        let spokenAge = spokenPhrase(for: age)
        return Line(
            text: "Updated \(visible)",
            isStale: stale,
            spoken: stale ? "Updated \(spokenAge), stale" : "Updated \(spokenAge)"
        )
    }

    /// Short label. Under a minute is "just now". Then whole minutes, hours, and days.
    private static func phrase(for age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private static func spokenPhrase(for age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}
