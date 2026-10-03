import Foundation

/// Place-local UV, wind, and relative humidity shared by the phone snapshot and the Watch.
///
/// Numbers match the iPhone Now tab: Open-Meteo `uv_index`, `wind_speed_10m`,
/// `wind_direction_10m`, `wind_gusts_10m`, and `relative_humidity_2m`, with wind
/// already in miles per hour. UV bands match `uvCategoryLabel`. Compass points
/// match `WindCompass`.
enum WatchAtmosphere {
    /// Drop shown beside the humidity percent on the glance.
    static let humiditySymbol = "drop.fill"

    struct Metrics: Equatable {
        var uvIndex: Double?
        var windSpeedMph: Double?
        var windDirectionDegrees: Double?
        var windGustMph: Double?
        /// Open-Meteo `relative_humidity_2m`, percent. Nil when the forecast omitted it.
        var humidityPercent: Double?

        static let empty = Metrics(
            uvIndex: nil,
            windSpeedMph: nil,
            windDirectionDegrees: nil,
            windGustMph: nil,
            humidityPercent: nil
        )
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

    /// UV, a wind speed or gust, and relative humidity. Direction alone does not count.
    static func isComplete(_ metrics: Metrics) -> Bool {
        metrics.uvIndex != nil
            && (metrics.windSpeedMph != nil || metrics.windGustMph != nil)
            && metrics.humidityPercent != nil
    }

    /// Keep a phone reading, and fill only the fields it left empty.
    static func preferringExisting(_ existing: Metrics, fill: Metrics) -> Metrics {
        Metrics(
            uvIndex: existing.uvIndex ?? fill.uvIndex,
            windSpeedMph: existing.windSpeedMph ?? fill.windSpeedMph,
            windDirectionDegrees: existing.windDirectionDegrees ?? fill.windDirectionDegrees,
            windGustMph: existing.windGustMph ?? fill.windGustMph,
            humidityPercent: existing.humidityPercent ?? fill.humidityPercent
        )
    }

    static func metrics(
        uvIndex: Double?,
        windSpeedMph: Double?,
        windDirectionDegrees: Double?,
        windGustMph: Double?,
        humidityPercent: Double? = nil
    ) -> Metrics {
        Metrics(
            uvIndex: finite(uvIndex),
            windSpeedMph: finite(windSpeedMph),
            windDirectionDegrees: finite(windDirectionDegrees),
            windGustMph: finite(windGustMph),
            humidityPercent: percent(humidityPercent)
        )
    }

    /// Open-Meteo `current` object, or the same keys copied onto a context dictionary.
    static func metrics(fromCurrent object: [String: Any]) -> Metrics {
        metrics(
            uvIndex: finite(object["uv_index"]),
            windSpeedMph: finite(object["wind_speed_10m"]),
            windDirectionDegrees: finite(object["wind_direction_10m"]),
            windGustMph: finite(object["wind_gusts_10m"]),
            humidityPercent: finite(object["relative_humidity_2m"])
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
        /// SF Symbol drawn before `text`. Humidity uses `humiditySymbol`.
        var symbolName: String? = nil
    }

    private static func windLine(_ metrics: Metrics, includeDirection: Bool = true) -> GlanceLine? {
        guard let wind = windChip(metrics) else { return nil }
        let text = visibleWind(metrics, includeDirection: includeDirection)
        guard !text.isEmpty else { return nil }
        return GlanceLine(text: text, spoken: wind.spoken, identifier: "watch-wind")
    }

    private static func uvLine(_ metrics: Metrics) -> GlanceLine? {
        guard let uv = uvChip(metrics) else { return nil }
        return GlanceLine(text: uv.text, spoken: uv.spoken, identifier: "watch-uv")
    }

    /// Relative humidity as a percent. A missing or negative value stays off the glance.
    static func humidityLine(_ metrics: Metrics) -> GlanceLine? {
        guard let percent = metrics.humidityPercent else { return nil }
        let shown = rounded(percent)
        guard shown >= 0 else { return nil }
        return GlanceLine(
            text: "\(shown)%",
            spoken: "Humidity \(shown) percent",
            identifier: "watch-humidity",
            symbolName: humiditySymbol
        )
    }

    /// One visible metric when the header can show only one.
    /// Order is wind, then humidity, then UV. The spoken wind line still includes a gust.
    static func glanceLine(_ metrics: Metrics) -> GlanceLine? {
        if let wind = windLine(metrics) { return wind }
        if let humidity = humidityLine(metrics) { return humidity }
        return uvLine(metrics)
    }

    /// Header chips.
    ///
    /// A short face keeps wind and the humidity percent on one line and shows UV
    /// only when both are missing. The visible wind drops its compass point when
    /// humidity shares that line; VoiceOver still speaks the direction and gust.
    /// A roomy face shows wind, or UV when wind is missing, and puts humidity beside it.
    static func glanceChips(_ metrics: Metrics, roomy: Bool) -> [GlanceLine] {
        let humidity = humidityLine(metrics)
        if roomy {
            var chips: [GlanceLine] = []
            if let wind = windLine(metrics) {
                chips.append(wind)
            } else if let uv = uvLine(metrics) {
                chips.append(uv)
            }
            if let humidity { chips.append(humidity) }
            return chips
        }
        var chips: [GlanceLine] = []
        if let wind = windLine(metrics, includeDirection: humidity == nil) {
            chips.append(wind)
        }
        if let humidity { chips.append(humidity) }
        if chips.isEmpty, let uv = uvLine(metrics) { chips.append(uv) }
        return chips
    }

    /// Speed and compass. A gust stands in when the sustained speed is missing.
    static func visibleWind(_ metrics: Metrics, includeDirection: Bool = true) -> String {
        let speed = metrics.windSpeedMph.map(rounded)
        let gust = metrics.windGustMph.map(rounded)
        let direction = includeDirection ? metrics.windDirectionDegrees : nil
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

    /// Rectangular and inline complication line. Humidity stays off this string.
    /// Nil when both UV and wind are absent.
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

    /// A usable relative-humidity percent. Negative and non-finite values stay empty.
    static func percent(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
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
