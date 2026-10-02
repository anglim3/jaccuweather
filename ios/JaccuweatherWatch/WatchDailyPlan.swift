import Foundation

/// One Open-Meteo daily row before it is clipped to the glance.
struct WatchDaySample {
    var date: String
    var highF: Double?
    var lowF: Double?
    var weatherCode: Int?
    var precipProbability: Double? = nil
    /// Open-Meteo `rain_sum`, inches. Nil when that field was not in the payload.
    var rainInches: Double? = nil
    /// Open-Meteo `precipitation_sum`, inches. Used as rain only when `rain_sum` is missing and there is no snow.
    var precipitationInches: Double? = nil
    /// Open-Meteo `snowfall_sum`, inches.
    var snowInches: Double? = nil
    var uvMax: Double? = nil
}

/// One place-local day on the Watch glance.
struct WatchDaySlot: Codable, Equatable, Identifiable {
    var date: String
    var label: String
    var highF: Double?
    var lowF: Double?
    var symbolName: String
    /// Short WMO condition. Missing on a cache written before the day sheet.
    var conditionText: String? = nil
    var precipProbability: Int? = nil
    /// Rain amount to show, inches. Nil when the day has no rain sum.
    var rainInches: Double? = nil
    /// Snow amount to show, inches. Nil when the day has no snow sum.
    var snowInches: Double? = nil
    /// Daily UV max. Nil when the forecast omitted it.
    var uvMax: Double? = nil

    var id: String { date }
}

/// Copy for the day sheet. The glance strip does not show these lines.
struct WatchDayDetailCopy: Equatable {
    var title: String
    var condition: String
    var high: String
    var low: String
    var probability: String?
    var rain: String?
    var snow: String?
    var uv: String?
    var spoken: String
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
            let rain = displayedRain(
                rain: sample.rainInches,
                precipitation: sample.precipitationInches,
                snow: sample.snowInches
            )
            return WatchDaySlot(
                date: day,
                label: label(for: day),
                highF: sample.highF,
                lowF: sample.lowF,
                symbolName: symbolName(code: sample.weatherCode),
                conditionText: conditionText(code: sample.weatherCode),
                precipProbability: probability(sample.precipProbability),
                rainInches: finite(rain),
                snowInches: finite(sample.snowInches),
                uvMax: uvValue(sample.uvMax)
            )
        }
    }

    /// `Friday, Oct 2` from a `yyyy-MM-dd` civil day. The stamp is not read in the device zone.
    static func title(for day: String) -> String {
        let civil = civilDay(day)
        guard let midnight = WatchHourlyPlan.absoluteSeconds(localISO: civil + "T00:00", utcOffsetSeconds: 0) else {
            return ""
        }
        let date = Date(timeIntervalSince1970: midnight)
        let weekday = formatted(date, "EEEE")
        let monthDay = formatted(date, "MMM d")
        if weekday.isEmpty { return monthDay }
        if monthDay.isEmpty { return weekday }
        return "\(weekday), \(monthDay)"
    }

    /// Short WMO condition. Same words as `WidgetWeatherCode.shortText`.
    static func conditionText(code: Int?) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Rain showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }

    static func probability(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, Int(value.rounded())))
    }

    /// Rain inches for the sheet.
    ///
    /// `rain_sum` wins when the payload has it, including zero. `precipitation_sum`
    /// includes snow, so it fills in only when rain is missing and snow is not.
    static func displayedRain(rain: Double?, precipitation: Double?, snow: Double?) -> Double? {
        if let rain = finite(rain) { return rain }
        if hasAmount(snow) { return nil }
        return finite(precipitation)
    }

    /// An amount is worth a cue at a hundredth of an inch. Smaller traces stay off the sheet.
    static func hasAmount(_ inches: Double?) -> Bool {
        guard let inches = finite(inches) else { return false }
        return inches >= 0.01
    }

    static func amountText(_ inches: Double?) -> String? {
        guard hasAmount(inches), let inches = finite(inches) else { return nil }
        if inches >= 10 {
            return "\(Int(inches.rounded()))\""
        }
        if inches >= 1 {
            let tenths = String(format: "%.1f", inches)
            if tenths.hasSuffix(".0"), let whole = Int(tenths.dropLast(2)) {
                return "\(whole)\""
            }
            return "\(tenths)\""
        }
        return String(format: "%.2f\"", inches)
    }

    static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    /// `UV 6` when the forecast included a max. Missing and negative values stay off the sheet.
    static func uvText(_ value: Double?) -> String? {
        guard let value = uvValue(value) else { return nil }
        return "UV \(Int(value.rounded()))"
    }

    static func detail(for day: WatchDaySlot) -> WatchDayDetailCopy {
        let probability = day.precipProbability.map { "\($0)%" }
        let rain = amountText(day.rainInches)
        let snow = amountText(day.snowInches)
        let uv = uvText(day.uvMax)
        let condition = day.conditionText ?? ""
        var spoken = [title(for: day.date)]
        if !condition.isEmpty { spoken.append(condition) }
        spoken.append("high \(degrees(day.highF))")
        spoken.append("low \(degrees(day.lowF))")
        if let chance = day.precipProbability {
            spoken.append("\(chance) percent chance of precipitation")
        }
        if snow != nil {
            spoken.append("\(spokenAmount(day.snowInches)) of snow")
        }
        if rain != nil {
            spoken.append("\(spokenAmount(day.rainInches)) of rain")
        }
        if let uv {
            spoken.append(uv)
        }
        return WatchDayDetailCopy(
            title: title(for: day.date),
            condition: condition,
            high: degrees(day.highF),
            low: degrees(day.lowF),
            probability: probability,
            rain: rain,
            snow: snow,
            uv: uv,
            spoken: spoken.joined(separator: ", ")
        )
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

    private static func formatted(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func uvValue(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private static func spokenAmount(_ inches: Double?) -> String {
        guard let inches = finite(inches) else { return "" }
        return String(format: "%.2f inches", inches)
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

    /// `7:04 AM` and `6:27 PM` from `yyyy-MM-dd'T'HH:mm`. The hour is always
    /// 12-hour. AM and PM come from `locale`. The stamp is a place-local wall
    /// clock, so the device time zone is not applied.
    static func clock(from iso: String?, locale: Locale = .current) -> String? {
        let trimmed = iso?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let match = clockPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let hour = integer(trimmed, match, 1),
              let minute = integer(trimmed, match, 2),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve):" + String(format: "%02d", minute) + " " + dayPeriod(morning: hour < 12, locale: locale)
    }

    private static func dayPeriod(morning: Bool, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbol = morning ? formatter.amSymbol : formatter.pmSymbol
        if let symbol, !symbol.isEmpty { return symbol }
        return morning ? "AM" : "PM"
    }

    private static func integer(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static let clockPattern = try! NSRegularExpression(pattern: #"T(\d{2}):(\d{2})"#)
}
