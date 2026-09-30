import Foundation

/// One ensemble hourly row used to decide whether damaging wind is ahead.
struct WindHourSample: Equatable {
    var time: String
    var clock: String
    var speed: Double?
    var gust: Double?

    init(time: String, clock: String = "", speed: Double? = nil, gust: Double? = nil) {
        self.time = time
        self.clock = clock
        self.speed = speed
        self.gust = gust
    }
}

/// The stronger of sustained wind and gust for one hour. Miles per hour, as stored.
struct WindReading: Equatable {
    var mph: Double
    var usesGust: Bool
}

/// The first hour in the lookahead window that meets the damaging-wind threshold.
struct WindGustNotice: Equatable {
    var hourKey: String
    var mph: Double
    var usesGust: Bool
    var startClock: String
    var endClock: String
    var dedupeKey: String
    var identifier: String
}

/// Title, body, hour selection, and dedupe for local high-wind notices.
/// Hourly `wind_speed_10m` and `wind_gusts_10m` are already miles per hour.
/// Open-Meteo stamps are place-local wall times; `utc_offset_seconds` places them
/// on the same clock the forecast charts use.
enum WindGustNotificationCopy {
    static let thresholdMph = 40.0
    static let lookaheadHours = 24
    static let routeKey = "windGustRoute"
    static let routeValue = "forecast"
    static let sampleKey = "windGustSample"
    static let hourKeyName = "windHour"
    static let dedupeKeyName = "windKey"
    static let openedForecast = Notification.Name("jaccuweather.windGust.openForecast")

    static func reading(speed: Double?, gust: Double?) -> WindReading? {
        let sustained = finite(speed)
        let gusting = finite(gust)
        switch (sustained, gusting) {
        case let (speed?, gust?):
            if gust >= speed { return WindReading(mph: gust, usesGust: true) }
            return WindReading(mph: speed, usesGust: false)
        case let (nil, gust?):
            return WindReading(mph: gust, usesGust: true)
        case let (speed?, nil):
            return WindReading(mph: speed, usesGust: false)
        default:
            return nil
        }
    }

    static func title(usesGust: Bool) -> String {
        usesGust ? "Damaging gusts expected" : "High winds expected"
    }

    static func body(mph: Double, usesGust: Bool, placeName: String, startClock: String, endClock: String) -> String {
        let shown = Int(mph.rounded())
        let kind = usesGust ? "Gusts" : "Wind"
        let place = displayPlace(placeName)
        return "\(place). \(kind) near \(shown) mph, \(windowPhrase(start: startClock, end: endClock))."
    }

    static func dedupeKey(placeName: String, hourKey: String) -> String {
        displayPlace(placeName).lowercased() + "|" + hourKey
    }

    static func notificationIdentifier(for key: String) -> String {
        let slug = key.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" { return character }
            return "-"
        }
        return "jaccuweather.wind.\(String(slug.prefix(120)))"
    }

    /// First hour that has not ended, starts within the next 24 hours, and whose
    /// stronger wind reading is at least 40 mph.
    static func upcoming(
        hours: [WindHourSample],
        placeName: String,
        now: Date,
        utcOffsetSeconds: Int
    ) -> WindGustNotice? {
        let windowEnd = now.addingTimeInterval(TimeInterval(lookaheadHours) * 3600)
        var best: (start: Date, notice: WindGustNotice)?
        for sample in hours {
            guard let start = absoluteDate(localISO: sample.time, utcOffsetSeconds: utcOffsetSeconds) else { continue }
            let end = start.addingTimeInterval(3600)
            if end <= now || start >= windowEnd { continue }
            guard let hourKey = hourKey(sample.time) else { continue }
            guard let reading = reading(speed: sample.speed, gust: sample.gust), reading.mph >= thresholdMph else { continue }
            if let best, start >= best.start { continue }
            let clocks = clocks(for: sample)
            let key = dedupeKey(placeName: placeName, hourKey: hourKey)
            best = (start, WindGustNotice(
                hourKey: hourKey,
                mph: reading.mph,
                usesGust: reading.usesGust,
                startClock: clocks.start,
                endClock: clocks.end,
                dedupeKey: key,
                identifier: notificationIdentifier(for: key)
            ))
        }
        return best?.notice
    }

    static func shouldPost(key: String, alreadyPosted: Set<String>) -> Bool {
        !key.isEmpty && !alreadyPosted.contains(key)
    }

    /// Drop a delivered notice once its hour has ended, or when this refresh no
    /// longer selects that same hour at or above the threshold.
    static func shouldRemoveNotice(
        noticeHour: String,
        now: Date,
        utcOffsetSeconds: Int,
        activeHour: String?
    ) -> Bool {
        if noticeHour.isEmpty || hourHasPassed(noticeHour, now: now, utcOffsetSeconds: utcOffsetSeconds) { return true }
        guard let activeHour, !activeHour.isEmpty else { return true }
        return noticeHour != activeHour
    }

    static func hourHasPassed(_ hourKey: String, now: Date, utcOffsetSeconds: Int) -> Bool {
        guard let start = absoluteDate(localISO: hourKey + ":00", utcOffsetSeconds: utcOffsetSeconds) else { return true }
        return start.addingTimeInterval(3600) <= now
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

    static func userInfo(hourKey: String, dedupeKey: String) -> [String: String] {
        [
            routeKey: routeValue,
            "url": forecastURL.absoluteString,
            hourKeyName: hourKey,
            dedupeKeyName: dedupeKey
        ]
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func windowPhrase(start: String, end: String) -> String {
        if start.isEmpty { return "in the next 24 hours" }
        if end.isEmpty || end == start { return start }
        return "\(start)–\(end)"
    }

    private static func clocks(for sample: WindHourSample) -> (start: String, end: String) {
        guard let parts = parseLocal(sample.time) else {
            let start = sample.clock.trimmingCharacters(in: .whitespacesAndNewlines)
            return (start, "")
        }
        let start = sample.clock.trimmingCharacters(in: .whitespacesAndNewlines)
        let startClock = start.isEmpty ? clockLabel(hour: parts.hour, minute: parts.minute) : start
        let endClock = clockLabel(hour: parts.hour + 1, minute: parts.minute)
        return (startClock, endClock)
    }

    static func hourKey(_ time: String) -> String? {
        let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 13 else { return nil }
        let prefix = String(trimmed.prefix(13))
        guard prefix.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return prefix
    }

    private static func clockLabel(hour: Int, minute: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let suffix = wrapped >= 12 ? "PM" : "AM"
        let hour12 = wrapped % 12 == 0 ? 12 : wrapped % 12
        return String(format: "%d:%02d %@", hour12, minute, suffix)
    }

    private struct LocalStamp {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
    }

    /// Place-local wall time to an absolute instant, matching `parseLocationLocalIso`.
    static func absoluteDate(localISO: String, utcOffsetSeconds: Int) -> Date? {
        guard let stamp = parseLocal(localISO) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = stamp.year
        parts.month = stamp.month
        parts.day = stamp.day
        parts.hour = stamp.hour
        parts.minute = stamp.minute
        guard let utc = calendar.date(from: parts) else { return nil }
        return utc.addingTimeInterval(TimeInterval(-utcOffsetSeconds))
    }

    private static func parseLocal(_ time: String) -> LocalStamp? {
        let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 else { return nil }
        let prefix = String(trimmed.prefix(16))
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$"#
        guard let match = prefix.range(of: pattern, options: .regularExpression) else { return nil }
        let text = String(prefix[match])
        let datePart = text.prefix(10)
        let clockPart = text.suffix(5)
        let datePieces = datePart.split(separator: "-")
        let clockPieces = clockPart.split(separator: ":")
        guard datePieces.count == 3, clockPieces.count == 2,
              let year = Int(datePieces[0]), let month = Int(datePieces[1]), let day = Int(datePieces[2]),
              let hour = Int(clockPieces[0]), let minute = Int(clockPieces[1]),
              (1...12).contains(month), (1...31).contains(day),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return LocalStamp(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}

/// On/off preference and posted place+hour keys. Missing preference stays off.
enum WindGustNotificationStore {
    private static let preferenceKey = "jaccuweather.windGustNotifications.preference"
    private static let postedKey = "jaccuweather.windGustNotifications.postedHours"
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
