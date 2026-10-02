import Foundation

struct NWSPointResponse: Decodable {
    let properties: NWSPointProperties?
}

struct NWSPointProperties: Decodable {
    let forecastZone: String?
    let forecastGridData: String?
}

struct NWSAlertsResponse: Decodable {
    let features: [NWSAlertFeature]
}

struct NWSAlertFeature: Decodable, Identifiable, Hashable {
    let properties: NWSAlertProperties
    /// NWS `properties.id` when it is present. Alerts without one stay distinct
    /// by headline and schedule so a list tap and a notification tap agree.
    var id: String {
        let primary = properties.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        let parts = [properties.event, properties.headline, properties.ends, properties.expires, properties.severity]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "alert" : parts.joined(separator: "|")
    }

    static func == (lhs: NWSAlertFeature, rhs: NWSAlertFeature) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The list row for a notification. More than one row with the same id is
    /// not a match: the notification payload is the alert that was tapped.
    static func routedMatch(id: String, headline: String?, event: String?, alerts: [NWSAlertFeature]) -> NWSAlertFeature? {
        let wanted = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let matches = alerts.filter { $0.id == wanted }
        if matches.count == 1 { return matches[0] }
        guard matches.count > 1 else { return nil }
        if let headline {
            let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
            let byHeadline = matches.filter { ($0.properties.headline ?? "") == trimmed }
            if byHeadline.count == 1 { return byHeadline[0] }
        }
        if let event {
            let trimmed = event.trimmingCharacters(in: .whitespacesAndNewlines)
            let byEvent = matches.filter { ($0.properties.event ?? "") == trimmed }
            if byEvent.count == 1 { return byEvent[0] }
        }
        return nil
    }

    /// "Ends …" from `ends`, or "Expires …" when the event end is missing.
    var scheduleLine: String? {
        if let ends = properties.ends, let text = AlertClock.string(from: ends) {
            return "Ends \(text)"
        }
        if let expires = properties.expires, let text = AlertClock.string(from: expires) {
            return "Expires \(text)"
        }
        return nil
    }
}

struct NWSAlertProperties: Decodable, Hashable {
    let id: String?
    let headline: String?
    let event: String?
    let severity: String?
    let urgency: String?
    let status: String?
    let description: String?
    let instruction: String?
    let ends: String?
    let expires: String?
    let senderName: String?
}

/// NWS `ends` and `expires` are absolute instants with an offset. The clock
/// shown is that offset, so a phone in another zone does not move the hour.
enum AlertClock {
    static func string(from iso: String) -> String? {
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let date = parsed(trimmed) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone(in: trimmed) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, h:mm a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter.string(from: date)
    }

    private static func parsed(_ iso: String) -> Date? {
        if let date = internet.date(from: iso) { return date }
        return fractional.date(from: iso)
    }

    private static func timeZone(in iso: String) -> TimeZone? {
        if iso.hasSuffix("Z") || iso.hasSuffix("z") { return TimeZone(secondsFromGMT: 0) }
        guard let match = offset.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)),
              match.numberOfRanges >= 4,
              let signRange = Range(match.range(at: 1), in: iso),
              let hourRange = Range(match.range(at: 2), in: iso),
              let minuteRange = Range(match.range(at: 3), in: iso),
              let hours = Int(iso[hourRange]),
              let minutes = Int(iso[minuteRange]) else { return nil }
        let seconds = (hours * 3600) + (minutes * 60)
        return TimeZone(secondsFromGMT: iso[signRange] == "-" ? -seconds : seconds)
    }

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let offset = try! NSRegularExpression(pattern: #"([+-])(\d{2}):?(\d{2})$"#)
}
