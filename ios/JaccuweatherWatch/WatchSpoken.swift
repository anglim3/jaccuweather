import Foundation

/// VoiceOver phrases for the Watch app.
///
/// Visible text keeps short forms such as 62°, UV, AQI, mph, and H/L.
/// These strings are the words VoiceOver should speak instead.
enum WatchSpoken {
    static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "unavailable" }
        return "\(Int(value.rounded())) degrees"
    }

    /// `62°` and `-3°` become words. A dash is a missing temperature.
    static func degrees(fromDisplay text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "—" || trimmed == "-" { return "Temperature unavailable" }
        let number = trimmed.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
        if let value = Int(number) { return "\(value) degrees" }
        if let value = Double(number), value.isFinite { return "\(Int(value.rounded())) degrees" }
        return trimmed.replacingOccurrences(of: "°", with: " degrees")
    }

    static func feelsLike(_ fahrenheit: Double?) -> String? {
        guard let fahrenheit, fahrenheit.isFinite else { return nil }
        return "Feels like \(Int(fahrenheit.rounded())) degrees"
    }

    static func windMilesPerHour(_ mph: Double?) -> String? {
        guard let mph, mph.isFinite, mph >= 0 else { return nil }
        return "Wind \(Int(mph.rounded())) miles per hour"
    }

    static func humidityPercent(_ percent: Int?) -> String? {
        guard let percent else { return nil }
        return "Humidity \(percent) percent"
    }

    /// Ultraviolet index plus the same band as the glance chip.
    static func ultraviolet(index value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let shown = Int(value.rounded())
        return "Ultraviolet index \(shown), \(WatchAtmosphere.category(uvIndex: value))"
    }

    static func airQuality(value: Int, category: String) -> String {
        "Air quality index \(value), \(category)"
    }

    /// One hourly column. `3p` and `62°` become "3 PM, 62 degrees, 20 percent chance of rain".
    static func hourlyCell(_ hour: WatchHourSlot) -> String {
        var parts: [String] = []
        let clock = WatchHourlyPlan.clock(for: hour.time)
        let time = clock.isEmpty ? WatchHourlyPlan.clock(fromAbbreviated: hour.label) : clock
        if !time.isEmpty {
            parts.append(time)
        } else if !hour.label.isEmpty {
            parts.append(hour.label)
        }
        parts.append(degrees(hour.temperatureF))
        if let phrase = chance(percent: hour.precipProbability, cue: hour.cue) {
            parts.append(phrase)
        }
        return parts.joined(separator: ", ")
    }

    /// One daily column, including the condition the symbol stands for.
    static func dailyCell(_ day: WatchDaySlot) -> String {
        var parts: [String] = []
        let name = weekdayName(date: day.date, label: day.label)
        if !name.isEmpty { parts.append(name) }
        let condition = conditionName(text: day.conditionText, symbolName: day.symbolName)
        if !condition.isEmpty { parts.append(condition) }
        parts.append("high \(degrees(day.highF))")
        parts.append("low \(degrees(day.lowF))")
        if let phrase = chance(percent: day.precipProbability, cue: WatchDailyPlan.stripCue(for: day)) {
            parts.append(phrase)
        }
        return parts.joined(separator: ", ")
    }

    /// The hour sheet, one sentence. Amounts stay off the strip.
    static func hourSheet(_ hour: WatchHourSlot) -> String {
        var parts: [String] = []
        let clock = WatchHourlyPlan.clock(for: hour.time)
        let time = clock.isEmpty ? WatchHourlyPlan.clock(fromAbbreviated: hour.label) : clock
        if !time.isEmpty { parts.append(time) }
        let condition = hour.conditionText ?? ""
        if !condition.isEmpty { parts.append(condition) }
        parts.append(degrees(hour.temperatureF))
        if let precip = hourPrecip(hour), !precip.isEmpty { parts.append(precip) }
        if let feels = feelsLike(hour.feelsLikeF) { parts.append(feels) }
        if let wind = windMilesPerHour(hour.windMph) { parts.append(wind) }
        if let humidity = humidityPercent(hour.humidity) { parts.append(humidity) }
        if let uv = ultraviolet(index: hour.uvIndex) { parts.append(uv) }
        return parts.joined(separator: ", ")
    }

    /// Chance and rain or snow amount for the hour sheet's precip row.
    static func hourPrecip(_ hour: WatchHourSlot) -> String? {
        joined(precipParts(
            percent: hour.precipProbability,
            cue: hour.cue,
            rainInches: hour.rainInches,
            snowInches: hour.snowInches
        ))
    }

    /// The day sheet, one sentence.
    static func daySheet(_ day: WatchDaySlot) -> String {
        var parts: [String] = []
        let title = WatchDailyPlan.title(for: day.date)
        if !title.isEmpty { parts.append(title) }
        let condition = conditionName(text: day.conditionText, symbolName: day.symbolName)
        if !condition.isEmpty { parts.append(condition) }
        parts.append("high \(degrees(day.highF))")
        parts.append("low \(degrees(day.lowF))")
        if let precip = dayPrecip(day), !precip.isEmpty { parts.append(precip) }
        if let uv = ultraviolet(index: day.uvMax) { parts.append(uv) }
        return parts.joined(separator: ", ")
    }

    static func dayPrecip(_ day: WatchDaySlot) -> String? {
        joined(precipParts(
            percent: day.precipProbability,
            cue: WatchDailyPlan.stripCue(for: day),
            rainInches: day.rainInches,
            snowInches: day.snowInches
        ))
    }

    /// Header summary. Hour and day cells speak for themselves.
    static func glance(
        place: String,
        temperatureText: String,
        condition: String,
        feelsSpoken: String?,
        dewSpoken: String?,
        aqiSpoken: String?,
        atmosphere: [String],
        sunSpoken: String?,
        alertSpoken: String?
    ) -> String {
        var parts: [String] = []
        if !place.isEmpty { parts.append(place) }
        parts.append(degrees(fromDisplay: temperatureText))
        if let dewSpoken, !dewSpoken.isEmpty { parts.append(dewSpoken) }
        if let feelsSpoken, !feelsSpoken.isEmpty { parts.append(feelsSpoken) }
        if !condition.isEmpty { parts.append(condition) }
        if let aqiSpoken, !aqiSpoken.isEmpty { parts.append(aqiSpoken) }
        parts.append(contentsOf: atmosphere.filter { !$0.isEmpty })
        if let sunSpoken, !sunSpoken.isEmpty { parts.append(sunSpoken) }
        if let alertSpoken, !alertSpoken.isEmpty { parts.append(alertSpoken) }
        return parts.joined(separator: ", ")
    }

    static func chance(percent: Int?, cue: WatchPrecipCue) -> String? {
        let clamped = percent.map { min(100, max(0, $0)) }
        switch (clamped, cue) {
        case let (value?, .rain):
            return "\(value) percent chance of rain"
        case let (value?, .snow):
            return "\(value) percent chance of snow"
        case let (value?, .none):
            return "\(value) percent chance of precipitation"
        case (nil, .rain):
            return "rain"
        case (nil, .snow):
            return "snow"
        case (nil, .none):
            return nil
        }
    }

    static func conditionName(text: String?, symbolName: String?) -> String {
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        switch symbolName {
        case "sun.max.fill", "moon.stars.fill":
            return "Clear"
        case "cloud.sun.fill", "cloud.moon.fill":
            return "Partly cloudy"
        case "cloud.fill":
            return "Cloudy"
        case "cloud.fog.fill":
            return "Fog"
        case "cloud.rain.fill":
            return "Rain"
        case "cloud.snow.fill":
            return "Snow"
        case "cloud.bolt.rain.fill":
            return "Thunderstorm"
        default:
            return ""
        }
    }

    static func weekdayName(date: String, label: String) -> String {
        let civil = WatchDailyPlan.civilDay(date)
        if civil.count == 10,
           let midnight = WatchHourlyPlan.absoluteSeconds(localISO: civil + "T00:00", utcOffsetSeconds: 0) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEEE"
            let name = formatter.string(from: Date(timeIntervalSince1970: midnight))
            if !name.isEmpty { return name }
        }
        return shortWeekdays[label] ?? label
    }

    static func amountPhrase(_ inches: Double?, kind: String) -> String? {
        guard WatchHourlyPlan.hasAmount(inches), let inches, inches.isFinite else { return nil }
        return String(format: "%.2f inches of \(kind)", inches)
    }

    private static func precipParts(percent: Int?, cue: WatchPrecipCue, rainInches: Double?, snowInches: Double?) -> [String] {
        var parts: [String] = []
        if let phrase = chance(percent: percent, cue: cue) { parts.append(phrase) }
        if let snow = amountPhrase(snowInches, kind: "snow") { parts.append(snow) }
        if let rain = amountPhrase(rainInches, kind: "rain") { parts.append(rain) }
        return parts
    }

    private static func joined(_ parts: [String]) -> String? {
        let text = parts.joined(separator: ", ")
        return text.isEmpty ? nil : text
    }

    private static let shortWeekdays = [
        "Sun": "Sunday",
        "Mon": "Monday",
        "Tue": "Tuesday",
        "Wed": "Wednesday",
        "Thu": "Thursday",
        "Fri": "Friday",
        "Sat": "Saturday"
    ]
}
