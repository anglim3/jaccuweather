import Foundation

/// Text for the Watch complication slots.
///
/// Every slot shows the temperature, and the condition when the slot has room.
/// The rectangular slot adds a UV and wind line when the reading has them.
/// Inline and corner stay off that line. Humidity stays off every slot.
/// These strings stay off the glance's sun line.
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

    /// Rectangular slot. Place and temperature stay in the view.
    /// This line is UV and wind when either exists, and humidity stays off it.
    /// Nil keeps the condition on that third line.
    static func rectangularDetail(_ metrics: WatchAtmosphere.Metrics) -> String? {
        WatchAtmosphere.detailLine(metrics)
    }
}
