import Foundation

struct ConditionsShareReading: Equatable {
    var placeName: String
    var temperatureF: Double?
    var feelsLikeF: Double?
    var conditionText: String
    var highF: Double?
    var lowF: Double?
}

/// Plain-text current conditions for the system share sheet.
enum ConditionsShareCopy {
    /// Place, temperature, feels-like, condition, and today's high/low. No link.
    static func lines(_ reading: ConditionsShareReading) -> [String]? {
        guard let temperature = degrees(reading.temperatureF) else { return nil }
        var lines = [cleaned(reading.placeName) ?? "This place", "\(temperature)°"]
        if let feels = degrees(reading.feelsLikeF) {
            lines.append("Feels like \(feels)°")
        }
        if let condition = cleaned(reading.conditionText),
           condition.caseInsensitiveCompare("Unknown") != .orderedSame {
            lines.append(condition)
        }
        if let range = rangeLine(high: reading.highF, low: reading.lowF) {
            lines.append(range)
        }
        return lines
    }

    /// `lines` plus the Now deep link. Place-specific URLs are not supported.
    static func summary(_ reading: ConditionsShareReading, link: URL = NowLink.url) -> String? {
        guard let lines = lines(reading) else { return nil }
        return (lines + [link.absoluteString]).joined(separator: "\n")
    }

    /// One line for the share sheet header. The shared text stays `summary`.
    static func previewTitle(_ reading: ConditionsShareReading) -> String? {
        guard let lines = lines(reading) else { return nil }
        return lines.map { line in
            guard line.hasPrefix("Feels like ") else { return line }
            return "feels " + line.dropFirst("Feels like ".count)
        }.joined(separator: " ")
    }

    private static func rangeLine(high: Double?, low: Double?) -> String? {
        switch (degrees(high), degrees(low)) {
        case let (high?, low?):
            return "High \(high)° / Low \(low)°"
        case let (high?, nil):
            return "High \(high)°"
        case let (nil, low?):
            return "Low \(low)°"
        default:
            return nil
        }
    }

    private static func degrees(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(value.rounded())
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
