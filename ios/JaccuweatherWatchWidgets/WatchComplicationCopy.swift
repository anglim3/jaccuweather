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

    /// Same cutoff as the glance strips. A smaller chance still shows when the
    /// condition is rain or snow. The rectangular slot does not use this text.
    static func precipText(chance: Int?, weatherCode: Int?) -> String? {
        guard let percent = displayedPrecipPercent(chance: chance, weatherCode: weatherCode) else { return nil }
        return "\(percent)%"
    }

    /// Drop for rain and for a chance that has not started. Snowflake when the condition is snow.
    static func precipSymbol(weatherCode: Int?) -> String {
        switch WatchHourlyPlan.cue(code: weatherCode, precipitation: nil, snowfall: nil) {
        case .snow: return "snowflake"
        case .rain, .none: return "drop.fill"
        }
    }

    /// VoiceOver for the chance. Nil when the slot keeps temperature and condition.
    static func precipSpoken(chance: Int?, weatherCode: Int?) -> String? {
        guard let percent = displayedPrecipPercent(chance: chance, weatherCode: weatherCode) else { return nil }
        return "\(percent) percent chance of precipitation"
    }

    /// Curved corner label. The condition stays with its symbol. The chance is
    /// added when the line is still about as long as the longest condition
    /// already shown there. A longer line keeps the symbol and the chance.
    static let cornerLabelBudget = 20

    static func cornerLabel(conditionText: String, feelsLikeF: Double?, precipChance: Int?, weatherCode: Int?) -> String {
        let words = condition(conditionText: conditionText, feelsLikeF: feelsLikeF)
        guard let precip = precipText(chance: precipChance, weatherCode: weatherCode) else { return words }
        let combined = "\(words) \(precip)"
        if combined.count <= cornerLabelBudget { return combined }
        return "\(precip) chance"
    }

    /// Inline slot with the chance appended. Callers that run out of room use `inlineLine`.
    static func inlineWithPrecip(temperatureF: Double?, conditionText: String, feelsLikeF: Double?, precipChance: Int?, weatherCode: Int?) -> String {
        let base = inlineLine(temperatureF: temperatureF, conditionText: conditionText, feelsLikeF: feelsLikeF)
        guard let precip = precipText(chance: precipChance, weatherCode: weatherCode) else { return base }
        return "\(base) \(precip)"
    }

    /// Percent to show, or nil. Matches the glance strip rule, including a low chance while rain or snow is the condition.
    private static func displayedPrecipPercent(chance: Int?, weatherCode: Int?) -> Int? {
        let percent = clampedPercent(chance)
        let cue = WatchHourlyPlan.cue(code: weatherCode, precipitation: nil, snowfall: nil)
        guard WatchDailyPlan.showsStripPrecip(probability: percent, cue: cue) else { return nil }
        return percent
    }

    private static func clampedPercent(_ chance: Int?) -> Int? {
        guard let chance else { return nil }
        return min(100, max(0, chance))
    }

    /// Inline slot, one line: temperature, then the short condition.
    static func inlineLine(temperatureF: Double?, conditionText: String, feelsLikeF: Double?) -> String {
        let degrees = degrees(temperatureF: temperatureF)
        let condition = condition(conditionText: conditionText, feelsLikeF: feelsLikeF)
        return "\(degrees) \(condition)"
    }
}
