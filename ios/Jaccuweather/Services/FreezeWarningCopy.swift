import Foundation

/// Overnight low chosen from the daily forecast already loaded in the app.
struct FreezeNight: Equatable {
    var day: String
    var lowF: Double
}

/// Title, body, overnight selection, and dedupe for local freeze notices.
/// Daily `temperature_2m_min` is the low for that calendar day. Before 08:00
/// local, today's minimum is the overnight still in progress. From 08:00, the
/// next daily minimum is tonight.
enum FreezeWarningCopy {
    static let freezeF = 32.0
    static let hardFreezeF = 28.0
    static let morningCutoffHour = 8
    static let routeKey = "jaccuweatherRoute"
    static let routeValue = "forecast"
    static let sampleKey = "freezeSample"
    static let dayKey = "freezeDay"
    static let dedupeKeyName = "freezeKey"
    static let openedForecast = Notification.Name("jaccuweather.openForecast")

    static func title(lowF: Double) -> String? {
        guard lowF.isFinite else { return nil }
        if lowF <= hardFreezeF { return "Hard freeze tonight" }
        if lowF <= freezeF { return "Freeze warning tonight" }
        return nil
    }

    static func body(lowF: Double, placeName: String) -> String {
        let shown = Int(lowF.rounded())
        return "Low near \(shown)° in \(displayPlace(placeName))"
    }

    static func dedupeKey(placeName: String, day: String) -> String {
        displayPlace(placeName).lowercased() + "|" + day
    }

    static func notificationIdentifier(for key: String) -> String {
        let slug = key.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" { return character }
            return "-"
        }
        return "jaccuweather.freeze.\(String(slug.prefix(120)))"
    }

    /// First daily minimum whose overnight has not ended. Skips days with no finite low.
    static func nextOvernight(
        days: [String],
        lows: [Double?],
        now: Date,
        utcOffsetSeconds: Int
    ) -> FreezeNight? {
        guard let today = localDay(now: now, utcOffsetSeconds: utcOffsetSeconds) else { return nil }
        let hour = localHour(now: now, utcOffsetSeconds: utcOffsetSeconds)
        let count = min(days.count, lows.count)
        for index in 0..<count {
            let day = days[index]
            guard isDayToken(day), day >= today else { continue }
            if day == today && hour >= morningCutoffHour { continue }
            guard let low = lows[index], low.isFinite else { continue }
            return FreezeNight(day: day, lowF: low)
        }
        return nil
    }

    static func periodHasPassed(day: String, now: Date, utcOffsetSeconds: Int) -> Bool {
        guard isDayToken(day), let today = localDay(now: now, utcOffsetSeconds: utcOffsetSeconds) else { return false }
        if day < today { return true }
        if day > today { return false }
        return localHour(now: now, utcOffsetSeconds: utcOffsetSeconds) >= morningCutoffHour
    }

    static func shouldPost(key: String, alreadyPosted: Set<String>) -> Bool {
        !key.isEmpty && !alreadyPosted.contains(key)
    }

    /// Drop a delivered notice once its morning has passed, or when this refresh's
    /// overnight no longer meets the freeze threshold.
    static func shouldRemoveNotice(
        noticeDay: String,
        now: Date,
        utcOffsetSeconds: Int,
        activeDay: String?,
        activeLowF: Double?
    ) -> Bool {
        if periodHasPassed(day: noticeDay, now: now, utcOffsetSeconds: utcOffsetSeconds) { return true }
        guard let activeDay else { return true }
        guard noticeDay == activeDay else { return false }
        guard let activeLowF, title(lowF: activeLowF) != nil else { return true }
        return false
    }

    static func opensForecast(_ url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare("jaccuweather") == .orderedSame else { return false }
        if url.host?.caseInsensitiveCompare(routeValue) == .orderedSame { return true }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.caseInsensitiveCompare(routeValue) == .orderedSame
    }

    static var forecastURL: URL {
        URL(string: "jaccuweather://forecast")!
    }

    static func isForecastRoute(_ info: [AnyHashable: Any]) -> Bool {
        if let route = info[routeKey] as? String, route.caseInsensitiveCompare(routeValue) == .orderedSame {
            return true
        }
        if let raw = info["url"] as? String, let url = URL(string: raw), opensForecast(url) {
            return true
        }
        return false
    }

    static func isSample(_ info: [AnyHashable: Any]) -> Bool {
        (info[sampleKey] as? String) == "1"
    }

    static func displayPlace(_ name: String) -> String {
        let collapsed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? "this place" : collapsed
    }

    private static func isDayToken(_ day: String) -> Bool {
        guard day.count == 10 else { return false }
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    private static func calendar(utcOffsetSeconds: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func localDay(now: Date, utcOffsetSeconds: Int) -> String? {
        let parts = calendar(utcOffsetSeconds: utcOffsetSeconds).dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func localHour(now: Date, utcOffsetSeconds: Int) -> Int {
        calendar(utcOffsetSeconds: utcOffsetSeconds).component(.hour, from: now)
    }
}

/// On/off preference and posted place+day keys. Missing preference stays off.
enum FreezeNotificationStore {
    private static let preferenceKey = "jaccuweather.freezeNotifications.preference"
    private static let postedKey = "jaccuweather.freezeNotifications.postedNights"
    private static let maxKeys = 200

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: preferenceKey) == "on"
    }

    static func setOn(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on ? "on" : "off", forKey: preferenceKey)
    }

    static func postedKeys(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: postedKey) ?? [])
    }

    static func remember(_ key: String, in defaults: UserDefaults = .standard) {
        guard !key.isEmpty else { return }
        var ordered = defaults.stringArray(forKey: postedKey) ?? []
        if !ordered.contains(key) {
            ordered.append(key)
        }
        if ordered.count > maxKeys {
            ordered.removeFirst(ordered.count - maxKeys)
        }
        defaults.set(ordered, forKey: postedKey)
    }
}
