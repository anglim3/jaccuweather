import Foundation

/// Text for the Watch complication slots.
///
/// Every slot shows the temperature, and the condition when the slot has room.
/// These strings stay off the glance's sun line and off UV and wind.
enum WatchComplicationCopy {
    /// Slots this complication offers. Circular and rectangular stay first.
    static let families = [
        "accessoryCircular",
        "accessoryRectangular",
        "accessoryInline",
        "accessoryCorner"
    ]

    static func degrees(temperatureF: Double?) -> String {
        guard let value = temperatureF, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    static func condition(conditionText: String, feelsLikeF: Double?) -> String {
        if !conditionText.isEmpty { return conditionText }
        if let feels = feelsLikeF, feels.isFinite {
            return "Feels \(Int(feels.rounded()))°"
        }
        return "Conditions"
    }

    static func symbol(named name: String) -> String {
        name.isEmpty ? "cloud.fill" : name
    }

    /// Inline slot, one line: temperature, then the short condition.
    static func inlineLine(temperatureF: Double?, conditionText: String, feelsLikeF: Double?) -> String {
        let degrees = degrees(temperatureF: temperatureF)
        let condition = condition(conditionText: conditionText, feelsLikeF: feelsLikeF)
        return "\(degrees) \(condition)"
    }

    /// Longer inline line. Temperature and condition, plus the chance when it is useful.
    /// Example: `52° Rain 40%`. Faces that cannot fit this use `inlineCompact`, then the temperature.
    static func inlinePrimary(
        temperatureF: Double?,
        conditionText: String,
        feelsLikeF: Double?,
        precipChance: Int?,
        weatherCode: Int?
    ) -> String {
        let base = inlineLine(temperatureF: temperatureF, conditionText: conditionText, feelsLikeF: feelsLikeF)
        guard let percent = inlinePrecipPercent(chance: precipChance, weatherCode: weatherCode) else {
            return base
        }
        return "\(base) \(percent)%"
    }

    /// Compact inline line for a common face that cannot fit the condition and the chance.
    /// Example: `52° · 40%`. Temperature only when the chance stays off.
    static func inlineCompact(temperatureF: Double?, precipChance: Int?, weatherCode: Int?) -> String {
        let degrees = degrees(temperatureF: temperatureF)
        guard let percent = inlinePrecipPercent(chance: precipChance, weatherCode: weatherCode) else {
            return degrees
        }
        return "\(degrees) · \(percent)%"
    }

    /// Chance to show on the inline slot. Nil when it is missing or under the glance-strip cutoff.
    /// A rain or snow condition still shows a smaller chance, matching those strips.
    static func inlinePrecipPercent(chance: Int?, weatherCode: Int?) -> Int? {
        guard let chance else { return nil }
        let percent = min(100, max(0, chance))
        let cue = WatchHourlyPlan.cue(code: weatherCode, precipitation: nil, snowfall: nil)
        guard WatchDailyPlan.showsStripPrecip(probability: percent, cue: cue) else { return nil }
        return percent
    }

    /// VoiceOver for the inline slot. The percent is spoken only when that cue is shown.
    static func inlineSpoken(
        place: String,
        temperatureF: Double?,
        conditionText: String,
        feelsLikeF: Double?,
        precipChance: Int?,
        weatherCode: Int?
    ) -> String {
        let placeName = place.isEmpty ? "Jaccuweather" : place
        let degrees = degrees(temperatureF: temperatureF)
        let condition = condition(conditionText: conditionText, feelsLikeF: feelsLikeF)
        let base = "\(placeName), \(degrees), \(condition)"
        guard let percent = inlinePrecipPercent(chance: precipChance, weatherCode: weatherCode) else {
            return base
        }
        return "\(base), \(percent) percent chance of precipitation"
    }
}
