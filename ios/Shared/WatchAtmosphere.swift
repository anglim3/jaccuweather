import Foundation

/// Place-local UV and wind shared by the phone snapshot and the Watch.
///
/// Numbers match the iPhone Now tab: Open-Meteo `uv_index`, `wind_speed_10m`,
/// `wind_direction_10m`, and `wind_gusts_10m`, with wind already in miles per hour.
/// UV bands match `uvCategoryLabel`. Compass points match `WindCompass`.
enum WatchAtmosphere {
    struct Metrics: Equatable {
        var uvIndex: Double?
        var windSpeedMph: Double?
        var windDirectionDegrees: Double?
        var windGustMph: Double?

        static let empty = Metrics(uvIndex: nil, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil)
    }

    struct UVChip: Equatable {
        var text: String
        var spoken: String
    }

    struct WindChip: Equatable {
        var text: String
        var spoken: String
        /// Degrees to rotate a north arrow so it points where the wind is going.
        var arrowDegrees: Double?
    }

    /// UV plus a wind speed or gust. Direction alone does not count.
    static func isComplete(_ metrics: Metrics) -> Bool {
        metrics.uvIndex != nil && (metrics.windSpeedMph != nil || metrics.windGustMph != nil)
    }

    /// Keep a phone reading, and fill only the fields it left empty.
    static func preferringExisting(_ existing: Metrics, fill: Metrics) -> Metrics {
        Metrics(
            uvIndex: existing.uvIndex ?? fill.uvIndex,
            windSpeedMph: existing.windSpeedMph ?? fill.windSpeedMph,
            windDirectionDegrees: existing.windDirectionDegrees ?? fill.windDirectionDegrees,
            windGustMph: existing.windGustMph ?? fill.windGustMph
        )
    }

    static func metrics(
        uvIndex: Double?,
        windSpeedMph: Double?,
        windDirectionDegrees: Double?,
        windGustMph: Double?
    ) -> Metrics {
        Metrics(
            uvIndex: finite(uvIndex),
            windSpeedMph: finite(windSpeedMph),
            windDirectionDegrees: finite(windDirectionDegrees),
            windGustMph: finite(windGustMph)
        )
    }

    /// Open-Meteo `current` object, or the same keys copied onto a context dictionary.
    static func metrics(fromCurrent object: [String: Any]) -> Metrics {
        metrics(
            uvIndex: finite(object["uv_index"]),
            windSpeedMph: finite(object["wind_speed_10m"]),
            windDirectionDegrees: finite(object["wind_direction_10m"]),
            windGustMph: finite(object["wind_gusts_10m"])
        )
    }

    static func uvChip(_ metrics: Metrics) -> UVChip? {
        guard let uv = metrics.uvIndex else { return nil }
        let shown = rounded(uv)
        return UVChip(text: "UV \(shown)", spoken: "UV index \(shown), \(category(uvIndex: uv))")
    }

    static func windChip(_ metrics: Metrics) -> WindChip? {
        let speed = metrics.windSpeedMph.map(rounded)
        let gust = metrics.windGustMph.map(rounded)
        guard speed != nil || gust != nil else { return nil }
        let direction = metrics.windDirectionDegrees
        var text = ""
        if let speed {
            text = "\(speed) mph"
            if let direction { text += " \(compass(direction))" }
            if let gust { text += " · G\(gust)" }
        } else if let gust {
            text = "G\(gust)"
            if let direction { text += " \(compass(direction))" }
        }
        var spoken: [String] = []
        if let speed {
            spoken.append("Wind \(speed) miles per hour")
        } else if let gust {
            spoken.append("Gust \(gust) miles per hour")
        }
        if let direction { spoken.append("from \(compass(direction))") }
        if speed != nil, let gust { spoken.append("gust \(gust)") }
        return WindChip(
            text: text,
            spoken: spoken.joined(separator: ", "),
            arrowDegrees: direction.map(arrowDegrees)
        )
    }

    struct GlanceLine: Equatable {
        var text: String
        var spoken: String
        var identifier: String
    }

    /// One visible metric for the glance. Wind wins when a speed or gust exists.
    /// The spoken line still includes a gust; the visible text does not.
    static func glanceLine(_ metrics: Metrics) -> GlanceLine? {
        if let wind = windChip(metrics) {
            let text = visibleWind(metrics)
            guard !text.isEmpty else { return nil }
            return GlanceLine(text: text, spoken: wind.spoken, identifier: "watch-wind")
        }
        if let uv = uvChip(metrics) {
            return GlanceLine(text: uv.text, spoken: uv.spoken, identifier: "watch-uv")
        }
        return nil
    }

    /// Speed and compass only. A gust stands in when the sustained speed is missing.
    static func visibleWind(_ metrics: Metrics) -> String {
        let speed = metrics.windSpeedMph.map(rounded)
        let gust = metrics.windGustMph.map(rounded)
        let direction = metrics.windDirectionDegrees
        if let speed {
            var text = "\(speed) mph"
            if let direction { text += " \(compass(direction))" }
            return text
        }
        if let gust {
            var text = "G\(gust)"
            if let direction { text += " \(compass(direction))" }
            return text
        }
        return ""
    }

    /// Rectangular and inline complication line. Nil when both chips are absent.
    static func detailLine(_ metrics: Metrics) -> String? {
        let parts = [uvChip(metrics)?.text, windChip(metrics)?.text].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// Short circular token. Wind speed wins; otherwise a gust or the UV index.
    static func circularToken(_ metrics: Metrics) -> String? {
        if let speed = metrics.windSpeedMph { return "\(rounded(speed)) mph" }
        if let gust = metrics.windGustMph { return "G\(rounded(gust))" }
        if let uv = metrics.uvIndex { return "UV \(rounded(uv))" }
        return nil
    }

    /// WHO bands used by `uvCategoryLabel` on the iPhone Now tab.
    static func category(uvIndex: Double) -> String {
        if uvIndex < 3 { return "Low" }
        if uvIndex < 6 { return "Moderate" }
        if uvIndex < 8 { return "High" }
        if uvIndex < 11 { return "Very high" }
        return "Extreme"
    }

    static func compass(_ degrees: Double) -> String {
        let wrapped = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((wrapped / 22.5).rounded()) % 16
        return points[index]
    }

    static func arrowDegrees(_ fromDegrees: Double) -> Double { fromDegrees + 180 }

    static func rounded(_ value: Double) -> Int { Int(value.rounded()) }

    static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    static func finite(_ raw: Any?) -> Double? {
        if raw is NSNull { return nil }
        if let value = raw as? Double { return finite(value) }
        if let value = raw as? Int { return finite(Double(value)) }
        if let value = raw as? NSNumber { return finite(value.doubleValue) }
        return nil
    }

    private static let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
}
