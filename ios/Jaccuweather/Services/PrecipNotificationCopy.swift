import Foundation

/// One ensemble hourly row used to decide whether precipitation is about to start.
struct PrecipHourSample: Equatable {
    var time: String
    var clock: String
    var precipChance: Int?
    var precip: Double?
    var snow: Double?

    init(time: String, clock: String = "", precipChance: Int? = nil, precip: Double? = nil, snow: Double? = nil) {
        self.time = time
        self.clock = clock
        self.precipChance = precipChance
        self.precip = precip
        self.snow = snow
    }
}

enum PrecipKind: String, Equatable {
    case rain
    case snow
    case precipitation
}

struct PrecipStartNotice: Equatable {
    var kind: PrecipKind
    var startTime: String
    var clock: String
    var dedupeKey: String
    var identifier: String
}

struct PrecipPostedRecord: Codable, Equatable {
    var identifier: String
    var placeKey: String
    var startTime: String
}

/// Title, body, and start-hour selection for local precipitation notifications.
enum PrecipNotificationCopy {
    static let probabilityThreshold = 50
    static let lookaheadHours = 6
    static let routeKey = "openForecast"
    static let sampleIdentifier = "debug-sample-precip"

    /// Row 0 is the current hour. A positive precip or snow amount there means
    /// precipitation has already started. Otherwise the first of those six hours
    /// whose probability is at least 50 (or, when probability is missing, whose
    /// amount is positive) is the upcoming start.
    static func upcoming(hours: [PrecipHourSample], placeKey: String) -> PrecipStartNotice? {
        let place = cleaned(placeKey)
        guard let place, let current = hours.first, !isPrecipitating(current) else { return nil }
        let window = hours.prefix(lookaheadHours)
        guard let start = window.first(where: crossesThreshold) else { return nil }
        let hour = hourKey(start.time)
        guard !hour.isEmpty else { return nil }
        let clock = cleaned(start.clock) ?? clockFrom(start.time) ?? ""
        return PrecipStartNotice(
            kind: kind(of: start),
            startTime: start.time,
            clock: clock,
            dedupeKey: "\(place)|\(hour)",
            identifier: "precip.\(place).\(hour.replacingOccurrences(of: "-", with: ""))"
        )
    }

    static func title(kind: PrecipKind) -> String {
        switch kind {
        case .rain: return "Rain starting soon"
        case .snow: return "Snow starting soon"
        case .precipitation: return "Precipitation starting soon"
        }
    }

    static func body(placeName: String, time: String, clock: String) -> String {
        let sentence = windowSentence(time: time, clock: clock)
        if let place = cleaned(placeName) {
            return clipped("\(place). \(sentence)")
        }
        return clipped(sentence)
    }

    static func sampleBody(placeName: String) -> String {
        if let place = cleaned(placeName) {
            return "Sample for \(place). Around 3:00 PM. This is not a live forecast."
        }
        return "Sample. Around 3:00 PM. This is not a live forecast."
    }

    static func userInfo(startTime: String) -> [String: String] {
        [routeKey: "forecast", "startTime": startTime]
    }

    static func isForecastRoute(_ info: [AnyHashable: Any]) -> Bool {
        (info[routeKey] as? String) == "forecast"
    }

    static func placeKey(latitude: Double, longitude: Double) -> String {
        guard latitude.isFinite, longitude.isFinite else { return "" }
        return String(format: "%.2f_%.2f", latitude, longitude)
    }

    /// Delivered notices to remove: the hour has passed, or this place no longer
    /// has that same start. Notices for another place stay until their hour passes.
    static func identifiersToCancel(
        posted: [PrecipPostedRecord],
        activeIdentifier: String?,
        placeKey: String,
        currentTime: String
    ) -> [String] {
        let current = hourKey(currentTime)
        var chosen: [String] = []
        var seen = Set<String>()
        for record in posted {
            let identifier = record.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
            let start = hourKey(record.startTime)
            let passed = !current.isEmpty && !start.isEmpty && start < current
            let replaced = record.placeKey == placeKey && identifier != activeIdentifier
            if passed || replaced {
                chosen.append(identifier)
            }
        }
        return chosen
    }

    private static func isPrecipitating(_ hour: PrecipHourSample) -> Bool {
        positive(hour.precip) || positive(hour.snow)
    }

    private static func crossesThreshold(_ hour: PrecipHourSample) -> Bool {
        if let chance = hour.precipChance {
            return chance >= probabilityThreshold
        }
        return isPrecipitating(hour)
    }

    private static func kind(of hour: PrecipHourSample) -> PrecipKind {
        if positive(hour.snow) { return .snow }
        if positive(hour.precip) { return .rain }
        return .precipitation
    }

    private static func positive(_ value: Double?) -> Bool {
        guard let value, value.isFinite else { return false }
        return value > 0
    }

    static func hourKey(_ time: String) -> String {
        let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 13 else { return "" }
        let prefix = String(trimmed.prefix(13))
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}$"#
        guard prefix.range(of: pattern, options: .regularExpression) != nil else { return "" }
        return prefix
    }

    private static func windowSentence(time: String, clock: String) -> String {
        let phrase = windowPhrase(time: time, clock: clock)
        if phrase == "in the next few hours" { return "In the next few hours." }
        return "\(phrase)."
    }

    private static func windowPhrase(time: String, clock: String) -> String {
        let start = cleaned(clock) ?? clockFrom(time)
        guard let start else { return "in the next few hours" }
        guard let parts = parseHourMinute(time) else { return "around \(start)" }
        let end = clockLabel(hour: parts.hour + 1, minute: parts.minute)
        return "\(start)–\(end)"
    }

    private static func clockFrom(_ time: String) -> String? {
        guard let parts = parseHourMinute(time) else { return nil }
        return clockLabel(hour: parts.hour, minute: parts.minute)
    }

    private static func parseHourMinute(_ time: String) -> (hour: Int, minute: Int)? {
        guard let tRange = time.range(of: "T") else { return nil }
        let rest = time[tRange.upperBound...]
        let pieces = rest.split(separator: ":")
        guard pieces.count >= 2, let hour = Int(pieces[0]), let minute = Int(pieces[1].prefix(2)) else { return nil }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func clockLabel(hour: Int, minute: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let suffix = wrapped >= 12 ? "PM" : "AM"
        let hour12 = wrapped % 12 == 0 ? 12 : wrapped % 12
        return String(format: "%d:%02d %@", hour12, minute, suffix)
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clipped(_ value: String) -> String {
        if value.count <= 180 { return value }
        let end = value.index(value.startIndex, offsetBy: 177)
        return String(value[..<end]) + "…"
    }
}
