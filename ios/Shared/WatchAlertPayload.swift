import Foundation

/// Active NWS alert summary carried on the phone's WatchConnectivity context.
/// The Watch draws a badge only when title, severity, and a positive count
/// are all present. A missing field stays quiet.
struct WatchAlertSummary: Equatable {
    var title: String
    var severity: String
    var count: Int
}

enum WatchAlertPayload {
    static let titleKey = "alertTitle"
    static let severityKey = "alertSeverity"
    static let countKey = "alertCount"

    static func fields(_ summary: WatchAlertSummary?) -> [String: Any] {
        guard let summary, summary.count > 0 else { return [:] }
        let title = cleaned(summary.title)
        let severity = cleaned(summary.severity)
        guard let title, let severity else { return [:] }
        return [
            titleKey: title,
            severityKey: severity,
            countKey: summary.count
        ]
    }

    static func summary(from dictionary: [String: Any]) -> WatchAlertSummary? {
        guard let title = cleaned(dictionary[titleKey] as? String),
              let severity = cleaned(dictionary[severityKey] as? String),
              let count = countValue(dictionary[countKey]),
              count > 0 else { return nil }
        return WatchAlertSummary(title: title, severity: severity, count: count)
    }

    static func countValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        return nil
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Picks one title and severity from the phone's active alerts.
enum WatchAlertSummaryPlan {
    struct Item: Equatable {
        var title: String
        var severity: String
    }

    static func summary(from items: [Item]) -> WatchAlertSummary? {
        let usable = items.compactMap { item -> Item? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let severity = item.severity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !severity.isEmpty else { return nil }
            return Item(title: clip(title), severity: severity)
        }
        guard !usable.isEmpty else { return nil }
        var chosen = usable[0]
        var chosenRank = rank(chosen.severity)
        for item in usable.dropFirst() {
            let next = rank(item.severity)
            if next > chosenRank {
                chosen = item
                chosenRank = next
            }
        }
        return WatchAlertSummary(title: chosen.title, severity: chosen.severity, count: usable.count)
    }

    static func rank(_ severity: String) -> Int {
        switch severity.lowercased() {
        case "extreme": return 4
        case "severe": return 3
        case "moderate": return 2
        case "minor": return 1
        default: return 0
        }
    }

    private static func clip(_ title: String) -> String {
        guard title.count > 80 else { return title }
        return String(title.prefix(80))
    }
}
