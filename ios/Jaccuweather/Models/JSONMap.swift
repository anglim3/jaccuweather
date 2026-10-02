import Foundation

struct JSONMap {
    let raw: [String: Any]

    init(_ any: Any?) {
        if let dict = any as? [String: Any] {
            raw = dict
        } else if let dict = any as? NSDictionary {
            var mapped: [String: Any] = [:]
            for (key, value) in dict {
                if let key = key as? String { mapped[key] = value }
            }
            raw = mapped
        } else {
            raw = [:]
        }
    }

    func map(_ key: String) -> JSONMap { JSONMap(raw[key]) }

    func any(_ key: String) -> Any? { raw[key] }

    func string(_ key: String) -> String? { raw[key] as? String }

    func bool(_ key: String) -> Bool {
        if let b = raw[key] as? Bool { return b }
        if let n = number(key) { return n != 0 }
        return false
    }

    func number(_ key: String) -> Double? {
        Self.toDouble(raw[key])
    }

    func int(_ key: String) -> Int? {
        guard let n = number(key) else { return nil }
        return Int(n.rounded())
    }

    func strings(_ key: String) -> [String] {
        (raw[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    func numbers(_ key: String) -> [Double?] {
        guard let arr = raw[key] as? [Any] else { return [] }
        return arr.map(Self.toDouble)
    }

    func maps(_ key: String) -> [JSONMap] {
        (raw[key] as? [Any])?.map { JSONMap($0) } ?? []
    }

    static func toDouble(_ value: Any?) -> Double? {
        if value == nil || value is NSNull { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

struct WeatherBundle {
    let root: JSONMap
    var current: JSONMap { root.map("current") }
    var hourly: JSONMap { root.map("hourly") }
    var daily: JSONMap { root.map("daily") }
    var latitude: Double { root.number("latitude") ?? 0 }
    var longitude: Double { root.number("longitude") ?? 0 }
    var elevation: Double? { root.number("elevation") }
    var timezone: String? { root.string("timezone") }
    var utcOffset: Int { root.int("utc_offset_seconds") ?? 0 }

    var todayIndex: Int {
        let times = daily.strings("time")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffset) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        if let idx = times.firstIndex(of: today) { return idx }
        return min(2, max(0, times.count - 1))
    }

    /// Current conditions follow the location's wall clock, not the phone's.
    /// Ensemble `current` is filled by parsing naive hourly stamps with `Date`,
    /// which uses the device zone.
    func alignedToLocationHour(now: Date = Date()) -> WeatherBundle {
        let times = hourly.strings("time")
        let index = LocationHour.nearestIndex(times: times, utcOffsetSeconds: utcOffset, now: now)
        guard times.indices.contains(index) else { return self }
        var payload = root.raw
        var current = JSONMap(payload["current"]).raw
        let hourlyMap = hourly.raw
        current["time"] = times[index]
        for key in Self.locationHourKeys {
            if let value = Self.hourValue(hourlyMap[key], index: index) {
                current[key] = value
            }
        }
        payload["current"] = current
        return WeatherBundle(root: JSONMap(payload))
    }

    private static let locationHourKeys = [
        "temperature_2m", "relative_humidity_2m", "apparent_temperature",
        "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
        "precipitation", "weather_code", "cloud_cover", "surface_pressure",
        "is_day", "uv_index", "dewpoint_2m"
    ]

    private static func hourValue(_ series: Any?, index: Int) -> Any? {
        if let array = series as? [Any] {
            guard array.indices.contains(index) else { return nil }
            return array[index]
        }
        guard let array = series as? NSArray, index >= 0, index < array.count else { return nil }
        return array[index]
    }
}

/// Open-Meteo `timezone=auto` stamps are local wall clocks with no offset.
enum LocationHour {
    static func nearestIndex(times: [String], utcOffsetSeconds: Int, now: Date = Date()) -> Int {
        guard !times.isEmpty else { return 0 }
        let nowSeconds = now.timeIntervalSince1970
        var best = 0
        var bestDelta = Double.greatestFiniteMagnitude
        for (index, stamp) in times.enumerated() {
            guard let seconds = absoluteSeconds(localISO: stamp, utcOffsetSeconds: utcOffsetSeconds) else { continue }
            let delta = abs(seconds - nowSeconds)
            if delta < bestDelta {
                bestDelta = delta
                best = index
            }
        }
        return best
    }

    /// Absolute instant for a location-local `yyyy-MM-dd'T'HH:mm` stamp.
    static func absoluteSeconds(localISO: String, utcOffsetSeconds: Int) -> TimeInterval? {
        if localISO.range(of: #"[zZ]$|[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil {
            return ISO8601DateFormatter().date(from: localISO)?.timeIntervalSince1970
        }
        guard let naiveStamp,
              let match = naiveStamp.firstMatch(in: localISO, range: NSRange(localISO.startIndex..., in: localISO)),
              let year = integer(localISO, match, 1),
              let month = integer(localISO, match, 2),
              let day = integer(localISO, match, 3),
              let hour = integer(localISO, match, 4),
              let minute = integer(localISO, match, 5) else { return nil }
        var parts = DateComponents()
        parts.calendar = utcCalendar
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = integer(localISO, match, 6) ?? 0
        guard let utc = utcCalendar.date(from: parts) else { return nil }
        return utc.timeIntervalSince1970 - TimeInterval(utcOffsetSeconds)
    }

    private static func integer(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static let utcCalendar = Calendar(identifier: .gregorian)
    private static let naiveStamp = try? NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?"#
    )
}
