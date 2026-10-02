import Foundation

/// One upcoming hour on the Watch glance.
struct WatchHourSlot: Codable, Equatable, Identifiable {
    var time: String
    var label: String
    var temperatureF: Double?
    var precipProbability: Int?
    var cue: WatchPrecipCue
    /// WMO SF Symbol. Nil on a cache written before the hour sheet.
    var symbolName: String? = nil
    /// Short WMO condition. Nil on a cache written before the hour sheet.
    var conditionText: String? = nil
    /// Rain amount to show, inches. Nil when this hour has no rain sum.
    var rainInches: Double? = nil
    /// Snow amount to show, inches. Nil when this hour has no snow sum.
    var snowInches: Double? = nil
    var feelsLikeF: Double? = nil
    var windMph: Double? = nil
    /// Relative humidity, percent.
    var humidity: Int? = nil
    var uvIndex: Double? = nil

    var id: String { time }
}

enum WatchPrecipCue: String, Codable {
    case none
    case rain
    case snow
}

/// One Open-Meteo hourly row before it is clipped to the glance.
struct WatchHourSample {
    var time: String
    var temperatureF: Double?
    var precipProbability: Double?
    var weatherCode: Int?
    var precipitation: Double?
    var snowfall: Double?
    /// Open-Meteo `rain`, inches. Nil when that field was not in the payload.
    var rainInches: Double? = nil
    var feelsLikeF: Double? = nil
    var windMph: Double? = nil
    var humidity: Double? = nil
    var uvIndex: Double? = nil
    /// Open-Meteo `is_day`. Nil when that field was not in the payload.
    var isDay: Bool? = nil
}

/// Copy for the hour sheet. The glance strip does not show these lines.
struct WatchHourDetailCopy: Equatable {
    var title: String
    var condition: String
    var temperature: String
    var probability: String?
    var rain: String?
    var snow: String?
    var feels: String?
    var wind: String?
    var humidity: String?
    var uv: String?
    var spoken: String
}

/// Place-local hours for the Watch strip.
///
/// Open-Meteo `timezone=auto` stamps are wall clocks with no offset. The
/// absolute instant uses `utc_offset_seconds`, the same way the iPhone Now
/// and Forecast tabs pick the current hour. Labels come from that stamp, so
/// a watch set to another zone still shows the place's hour.
enum WatchHourlyPlan {
    static let defaultCount = 8
    private static let snowCodes: Set<Int> = [71, 73, 75, 77, 85, 86]
    private static let rainCodes: Set<Int> = [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]

    static func slots(
        samples: [WatchHourSample],
        utcOffsetSeconds: Int,
        now: Date = Date(),
        count: Int = defaultCount
    ) -> [WatchHourSlot] {
        let start = startIndex(samples: samples, utcOffsetSeconds: utcOffsetSeconds, now: now)
        guard samples.indices.contains(start) else { return [] }
        let limit = max(1, count)
        return samples[start..<min(samples.count, start + limit)].map { sample in
            let rain = displayedRain(
                rain: sample.rainInches,
                precipitation: sample.precipitation,
                snow: sample.snowfall
            )
            return WatchHourSlot(
                time: sample.time,
                label: label(for: sample.time),
                temperatureF: sample.temperatureF,
                precipProbability: probability(sample.precipProbability),
                cue: cue(code: sample.weatherCode, precipitation: sample.precipitation, snowfall: sample.snowfall),
                symbolName: symbolName(code: sample.weatherCode, isDay: sample.isDay ?? true),
                conditionText: conditionText(code: sample.weatherCode),
                rainInches: finite(rain),
                snowInches: finite(sample.snowfall),
                feelsLikeF: finite(sample.feelsLikeF),
                windMph: finiteNonNegative(sample.windMph),
                humidity: humidityPercent(sample.humidity),
                uvIndex: uvValue(sample.uvIndex)
            )
        }
    }

    /// `3 PM` and `3:30 PM` from a `yyyy-MM-dd'T'HH:mm` stamp. Always 12-hour.
    static func clock(for stamp: String) -> String {
        guard let hour = hour(from: stamp), (0...23).contains(hour) else { return "" }
        let minute = minute(from: stamp) ?? 0
        guard (0...59).contains(minute) else { return "" }
        let suffix = hour < 12 ? "AM" : "PM"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 { return "\(twelve) \(suffix)" }
        return String(format: "%d:%02d %@", twelve, minute, suffix)
    }

    /// `3 PM` from the strip's `3p` label, when the stamp cannot be read.
    static func clock(fromAbbreviated label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        let suffix: String
        switch last {
        case "a", "A": suffix = "AM"
        case "p", "P": suffix = "PM"
        default: return ""
        }
        let body = String(trimmed.dropLast())
        guard !body.isEmpty else { return "" }
        return "\(body) \(suffix)"
    }

    static func detail(for hour: WatchHourSlot) -> WatchHourDetailCopy {
        let titled = clock(for: hour.time)
        let title = titled.isEmpty ? clock(fromAbbreviated: hour.label) : titled
        let condition = hour.conditionText ?? ""
        let probability = probabilityText(hour.precipProbability)
        let rain = amountText(hour.rainInches)
        let snow = amountText(hour.snowInches)
        let feels = feelsText(hour.feelsLikeF)
        let wind = windText(hour.windMph)
        let humidity = humidityText(hour.humidity)
        let uv = uvText(hour.uvIndex)
        var spoken = [title]
        if !condition.isEmpty { spoken.append(condition) }
        spoken.append(degrees(hour.temperatureF))
        if let chance = hour.precipProbability {
            spoken.append("\(min(100, max(0, chance))) percent chance of precipitation")
        }
        if snow != nil {
            spoken.append("\(spokenAmount(hour.snowInches)) of snow")
        }
        if rain != nil {
            spoken.append("\(spokenAmount(hour.rainInches)) of rain")
        }
        if let feels { spoken.append(feels) }
        if let wind { spoken.append(wind) }
        if let humidity { spoken.append(humidity) }
        if let uv { spoken.append(uv) }
        return WatchHourDetailCopy(
            title: title,
            condition: condition,
            temperature: degrees(hour.temperatureF),
            probability: probability,
            rain: rain,
            snow: snow,
            feels: feels,
            wind: wind,
            humidity: humidity,
            uv: uv,
            spoken: spoken.joined(separator: ", ")
        )
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

    /// WMO SF Symbol. Same names as `WidgetWeatherCode.symbol`.
    static func symbolName(code: Int?, isDay: Bool) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func probability(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, Int(value.rounded())))
    }

    /// Rain inches for the sheet.
    ///
    /// `rain` wins when the payload has it, including zero. `precipitation`
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

    static func feelsText(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return "Feels \(degrees(value))"
    }

    static func windText(_ mph: Double?) -> String? {
        guard let mph = finiteNonNegative(mph) else { return nil }
        return "Wind \(Int(mph.rounded())) mph"
    }

    static func humidityText(_ percent: Int?) -> String? {
        guard let percent else { return nil }
        return "Humidity \(percent)%"
    }

    /// `UV 6` when the forecast included an index. Missing and negative values stay off the sheet.
    static func uvText(_ value: Double?) -> String? {
        guard let value = uvValue(value) else { return nil }
        return "UV \(Int(value.rounded()))"
    }

    static func probabilityText(_ value: Int?) -> String? {
        guard let value else { return nil }
        return "\(min(100, max(0, value)))%"
    }

    /// The place-local hour that contains `now`, then the hours after it.
    static func startIndex(samples: [WatchHourSample], utcOffsetSeconds: Int, now: Date) -> Int {
        guard !samples.isEmpty else { return 0 }
        let nowSeconds = now.timeIntervalSince1970
        var containing: Int?
        for (index, sample) in samples.enumerated() {
            guard let seconds = absoluteSeconds(localISO: sample.time, utcOffsetSeconds: utcOffsetSeconds) else { continue }
            if seconds <= nowSeconds {
                containing = index
            } else if containing == nil {
                return index
            } else {
                break
            }
        }
        return containing ?? 0
    }

    /// `9a`, `12p`, `3p` from a `yyyy-MM-dd'T'HH:mm` stamp.
    static func label(for stamp: String) -> String {
        guard let hour = hour(from: stamp) else { return "" }
        let suffix = hour < 12 ? "a" : "p"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve)\(suffix)"
    }

    static func cue(code: Int?, precipitation: Double?, snowfall: Double?) -> WatchPrecipCue {
        if let snowfall, snowfall > 0 { return .snow }
        if let code, snowCodes.contains(code) { return .snow }
        if let precipitation, precipitation > 0 { return .rain }
        if let code, rainCodes.contains(code) { return .rain }
        return .none
    }

    /// Absolute instant for a location-local `yyyy-MM-dd'T'HH:mm` stamp.
    static func absoluteSeconds(localISO: String, utcOffsetSeconds: Int) -> TimeInterval? {
        guard let match = stampPattern.firstMatch(in: localISO, range: NSRange(localISO.startIndex..., in: localISO)),
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
        guard let utc = utcCalendar.date(from: parts) else { return nil }
        return utc.timeIntervalSince1970 - TimeInterval(utcOffsetSeconds)
    }

    static func hour(from stamp: String) -> Int? {
        guard let match = stampPattern.firstMatch(in: stamp, range: NSRange(stamp.startIndex..., in: stamp)) else { return nil }
        return integer(stamp, match, 4)
    }

    static func minute(from stamp: String) -> Int? {
        guard let match = stampPattern.firstMatch(in: stamp, range: NSRange(stamp.startIndex..., in: stamp)) else { return nil }
        return integer(stamp, match, 5)
    }

    private static func integer(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static let utcCalendar = Calendar(identifier: .gregorian)
    private static let stampPattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})"#
    )

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func finiteNonNegative(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private static func humidityPercent(_ value: Double?) -> Int? {
        guard let value = finite(value) else { return nil }
        return min(100, max(0, Int(value.rounded())))
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
