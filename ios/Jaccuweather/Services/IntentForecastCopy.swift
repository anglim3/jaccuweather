import Foundation

/// Current conditions kept for Siri and Shortcuts. Written after a successful
/// in-app forecast and read back by Get Current Weather.
struct IntentForecastReading: Codable, Equatable {
    var placeName: String
    var latitude: Double
    var longitude: Double
    var temperatureF: Double
    var feelsLikeF: Double?
    var conditionText: String
    var symbolName: String
    var fetchedAt: Date
}

enum IntentForecastCopy {
    /// Same window as the in-app stale refresh (`staleAfterMs` on the view model).
    static let freshInterval: TimeInterval = 15 * 60

    static func placeKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.3f,%.3f", latitude, longitude)
    }

    static func isFresh(fetchedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < freshInterval
    }

    /// Matches `getWeatherDescription` in the shared logic file.
    static func conditionText(weatherCode: Int?) -> String {
        switch weatherCode {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45: return "Foggy"
        case 48: return "Depositing rime fog"
        case 51: return "Light drizzle"
        case 53: return "Moderate drizzle"
        case 55: return "Dense drizzle"
        case 56: return "Light freezing drizzle"
        case 57: return "Dense freezing drizzle"
        case 61: return "Slight rain"
        case 63: return "Moderate rain"
        case 65: return "Heavy rain"
        case 66: return "Light freezing rain"
        case 67: return "Heavy freezing rain"
        case 71: return "Slight snow"
        case 73: return "Moderate snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80: return "Slight rain showers"
        case 81: return "Moderate rain showers"
        case 82: return "Violent rain showers"
        case 85: return "Slight snow showers"
        case 86: return "Heavy snow showers"
        case 95: return "Thunderstorm"
        case 96: return "Thunderstorm with slight hail"
        case 99: return "Thunderstorm with heavy hail"
        default: return "Unknown"
        }
    }

    static func spoken(
        placeName: String,
        temperatureF: Double,
        conditionText: String,
        feelsLikeF: Double?,
        stale: Bool
    ) -> String {
        let place = cleaned(placeName) ?? "This place"
        let temp = degrees(temperatureF)
        let condition = cleaned(conditionText)
        var sentence = "\(place) is \(temp) degrees"
        if let condition, condition.caseInsensitiveCompare("Unknown") != .orderedSame {
            sentence += " and \(condition.lowercased())"
        }
        sentence += "."
        if let feelsLikeF {
            sentence += " Feels like \(degrees(feelsLikeF))."
        }
        if stale {
            return "Last saved reading. \(sentence)"
        }
        return sentence
    }

    /// Shortcut output: place, temperature, condition, and feels-like on their own lines.
    static func resultText(
        placeName: String,
        temperatureF: Double,
        conditionText: String,
        feelsLikeF: Double?
    ) -> String {
        let place = cleaned(placeName) ?? "This place"
        let condition = cleaned(conditionText) ?? "Unknown"
        let feels = feelsLikeF.map { "\(degrees($0))°" } ?? "—"
        return """
        \(place)
        \(degrees(temperatureF))°
        \(condition)
        Feels like \(feels)
        """
    }

    static func supportingLine(
        placeName: String,
        temperatureF: Double,
        conditionText: String,
        feelsLikeF: Double?
    ) -> String {
        let place = cleaned(placeName) ?? "This place"
        let condition = cleaned(conditionText) ?? "Unknown"
        let feels = feelsLikeF.map { "Feels like \(degrees($0))°" } ?? "Feels like —"
        return "\(place) · \(degrees(temperatureF))° · \(condition) · \(feels)"
    }

    private static func degrees(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
