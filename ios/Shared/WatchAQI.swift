import Foundation

/// US AQI chip for the Watch glance.
///
/// Bands match the iPhone Now and Health cards (`USAQIDisplay`): the integer
/// on screen is the rounded reading, and the band uses that same integer.
/// A missing, negative, or non-finite reading stays off the glance.
enum WatchAQI {
    struct Chip: Equatable {
        var value: Int
        /// Visible reading, such as "AQI 42".
        var text: String
        /// Short band word drawn beside `text`.
        var shortWord: String
        /// Full iPhone category, including "Unhealthy for Sensitive Groups".
        var category: String
        /// Same token as `JWTone.color(forAQI:)`.
        var colorToken: String
        /// VoiceOver line, matching the iPhone air-quality card.
        var spoken: String
    }

    /// Chip for a phone snapshot or an Open-Meteo `us_aqi` value.
    ///
    /// `category` is the optional phone band name. The number picks the band,
    /// so a missing category is filled in and a name for a different band
    /// cannot relabel the reading. A category with no number stays hidden.
    static func chip(usAqi: Double?, category _: String? = nil) -> Chip? {
        guard let raw = usAqi, raw.isFinite, raw >= 0 else { return nil }
        let value = Int(raw.rounded())
        let band = band(for: value)
        return Chip(
            value: value,
            text: "AQI \(value)",
            shortWord: band.shortWord,
            category: band.category,
            colorToken: band.colorToken,
            spoken: "Air Quality \(value), \(band.category)"
        )
    }

    private struct Band {
        var category: String
        var shortWord: String
        var colorToken: String
    }

    private static func band(for value: Int) -> Band {
        switch value {
        case ...50:
            return Band(category: "Good", shortWord: "Good", colorToken: "green")
        case ...100:
            return Band(category: "Moderate", shortWord: "Moderate", colorToken: "yellow")
        case ...150:
            return Band(category: "Unhealthy for Sensitive Groups", shortWord: "Sensitive", colorToken: "orange")
        case ...200:
            return Band(category: "Unhealthy", shortWord: "Unhealthy", colorToken: "red")
        case ...300:
            return Band(category: "Very Unhealthy", shortWord: "Very Unhealthy", colorToken: "purple")
        default:
            return Band(category: "Hazardous", shortWord: "Hazardous", colorToken: "maroon")
        }
    }
}
