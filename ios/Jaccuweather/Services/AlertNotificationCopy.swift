import Foundation

/// Title, body, and id selection for local NWS alert notifications.
enum AlertNotificationCopy {
    static let maxPerRefresh = 4

    static func title(event: String?, severity: String?) -> String {
        let name = cleaned(event) ?? "Weather alert"
        switch cleaned(severity)?.lowercased() {
        case "extreme": return "Extreme: \(name)"
        case "severe": return "Severe: \(name)"
        case "moderate": return "Moderate: \(name)"
        case "minor": return "Minor: \(name)"
        default: return name
        }
    }

    static func body(headline: String?, placeName: String) -> String {
        if let headline = cleaned(headline) {
            return clipped(headline)
        }
        if let place = cleaned(placeName) {
            return "A new alert is active for \(place)."
        }
        return "A new alert is active for this place."
    }

    /// Active ids that have not been posted yet, in arrival order.
    static func idsToNotify(activeIDs: [String], alreadyNotified: Set<String>, limit: Int = maxPerRefresh) -> [String] {
        let cap = max(0, limit)
        var chosen: [String] = []
        var seen = Set<String>()
        for raw in activeIDs {
            guard let id = cleaned(raw), !alreadyNotified.contains(id), seen.insert(id).inserted else { continue }
            chosen.append(id)
            if chosen.count >= cap { break }
        }
        return chosen
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
