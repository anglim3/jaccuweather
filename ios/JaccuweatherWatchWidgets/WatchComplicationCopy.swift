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
}
