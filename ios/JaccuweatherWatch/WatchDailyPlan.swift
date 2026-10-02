import Foundation

/// One Open-Meteo daily row before it is clipped to the glance.
struct WatchDaySample {
    var date: String
    var highF: Double?
    var lowF: Double?
    var weatherCode: Int?
}

/// One place-local day on the Watch glance.
struct WatchDaySlot: Codable, Equatable, Identifiable {
    var date: String
    var label: String
    var highF: Double?
    var lowF: Double?
    var symbolName: String

    var id: String { date }
}

/// Next place-local days for the Watch strip.
///
/// Open-Meteo `timezone=auto` daily dates are civil days with no offset. The
/// row that contains now is that day's place-local midnight, placed with
/// `utc_offset_seconds` the same way the iPhone picks `todayIndex`. A watch
/// set to another zone still starts on the place's day.
enum WatchDailyPlan {
    static let defaultCount = 7
    static let maximumCount = 7

    static func slots(
        samples: [WatchDaySample],
        utcOffsetSeconds: Int,
        now: Date = Date(),
        count: Int = defaultCount
    ) -> [WatchDaySlot] {
        let start = startIndex(samples: samples, utcOffsetSeconds: utcOffsetSeconds, now: now)
        guard samples.indices.contains(start) else { return [] }
        let limit = min(maximumCount, max(1, count))
        return samples[start..<min(samples.count, start + limit)].map { sample in
            let day = civilDay(sample.date)
            return WatchDaySlot(
                date: day,
                label: label(for: day),
                highF: sample.highF,
                lowF: sample.lowF,
                symbolName: symbolName(code: sample.weatherCode)
            )
        }
    }

    /// Place-local `yyyy-MM-dd`, matching the iPhone forecast's today row.
    static func placeLocalDay(now: Date, utcOffsetSeconds: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Absolute instant of that civil day's place-local midnight.
    static func midnightSeconds(day: String, utcOffsetSeconds: Int) -> TimeInterval? {
        let civil = civilDay(day)
        guard civil.count == 10 else { return nil }
        return WatchHourlyPlan.absoluteSeconds(localISO: civil + "T00:00", utcOffsetSeconds: utcOffsetSeconds)
    }

    /// First daily row whose place-local midnight is today or later.
    static func startIndex(samples: [WatchDaySample], utcOffsetSeconds: Int, now: Date) -> Int {
        let today = placeLocalDay(now: now, utcOffsetSeconds: utcOffsetSeconds)
        guard let todayMidnight = midnightSeconds(day: today, utcOffsetSeconds: utcOffsetSeconds) else {
            return samples.count
        }
        for (index, sample) in samples.enumerated() {
            guard let midnight = midnightSeconds(day: sample.date, utcOffsetSeconds: utcOffsetSeconds) else { continue }
            if midnight >= todayMidnight { return index }
        }
        return samples.count
    }

    /// `Fri` from a `yyyy-MM-dd` civil day. The stamp is not read in the device zone.
    static func label(for day: String) -> String {
        let civil = civilDay(day)
        guard let midnight = WatchHourlyPlan.absoluteSeconds(localISO: civil + "T00:00", utcOffsetSeconds: 0) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE"
        return formatter.string(from: Date(timeIntervalSince1970: midnight))
    }

    /// Daytime WMO SF Symbol. Same names as `WidgetWeatherCode.symbol(isDay: true)`.
    static func symbolName(code: Int?) -> String {
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func civilDay(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return trimmed }
        return String(trimmed.prefix(10))
    }
}

/// Today's sunrise and sunset for the Watch glance.
struct WatchSunTimes: Codable, Equatable {
    var sunriseLabel: String?
    var sunsetLabel: String?

    var hasAny: Bool { sunriseLabel != nil || sunsetLabel != nil }

    var line: String? {
        switch (sunriseLabel, sunsetLabel) {
        case let (rise?, set?):
            return "↑ \(rise) · ↓ \(set)"
        case let (rise?, nil):
            return "↑ \(rise)"
        case let (nil, set?):
            return "↓ \(set)"
        default:
            return nil
        }
    }

    var spoken: String {
        switch (sunriseLabel, sunsetLabel) {
        case let (rise?, set?):
            return "Sunrise \(rise), sunset \(set)"
        case let (rise?, nil):
            return "Sunrise \(rise)"
        case let (nil, set?):
            return "Sunset \(set)"
        default:
            return ""
        }
    }
}

/// One Open-Meteo daily sunrise and sunset before today's row is chosen.
struct WatchSunSample {
    var date: String
    var sunriseISO: String?
    var sunsetISO: String?
}

/// Place-local sunrise and sunset.
///
/// Open-Meteo `timezone=auto` stamps are wall clocks. The clock is read from
/// the stamp, the same way the iPhone formats `formatIsoLocalClock`, so a
/// watch set to another zone still shows the place's sunrise and sunset.
/// The row is today's civil day in `utc_offset_seconds`.
enum WatchSunPlan {
    struct Match {
        var times: WatchSunTimes
        var sunriseISO: String?
        var sunsetISO: String?
    }

    /// Today's row. An empty match means that day had no rise or set.
    static func resolved(samples: [WatchSunSample], utcOffsetSeconds: Int, now: Date = Date()) -> Match {
        let day = WatchDailyPlan.placeLocalDay(now: now, utcOffsetSeconds: utcOffsetSeconds)
        guard let sample = samples.first(where: { WatchDailyPlan.civilDay($0.date) == day }) else {
            return Match(times: WatchSunTimes(sunriseLabel: nil, sunsetLabel: nil), sunriseISO: nil, sunsetISO: nil)
        }
        let rise = clock(from: sample.sunriseISO)
        let set = clock(from: sample.sunsetISO)
        return Match(
            times: WatchSunTimes(sunriseLabel: rise, sunsetLabel: set),
            sunriseISO: rise == nil ? nil : sample.sunriseISO,
            sunsetISO: set == nil ? nil : sample.sunsetISO
        )
    }

    /// A fresh phone snapshot already carried today's stamps.
    static func carried(sunriseISO: String?, sunsetISO: String?) -> WatchSunTimes? {
        let rise = clock(from: sunriseISO)
        let set = clock(from: sunsetISO)
        guard rise != nil || set != nil else { return nil }
        return WatchSunTimes(sunriseLabel: rise, sunsetLabel: set)
    }

    /// `6:42` and `18:51` from `yyyy-MM-dd'T'HH:mm`. Minutes stay two digits.
    static func clock(from iso: String?) -> String? {
        let trimmed = iso?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let match = clockPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let hour = integer(trimmed, match, 1),
              let minute = integer(trimmed, match, 2),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return String(format: "%d:%02d", hour, minute)
    }

    private static func integer(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static let clockPattern = try! NSRegularExpression(pattern: #"T(\d{2}):(\d{2})"#)
}
