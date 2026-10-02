import Foundation

/// Active NWS alert summary carried on the phone's WatchConnectivity context.
/// The Watch draws a badge only when title, severity, and a positive count
/// are all present. A missing field stays quiet. Instruction, ends, event, and
/// headline are optional and never create a badge on their own.
struct WatchAlertSummary: Equatable {
    var title: String
    var severity: String
    var count: Int
    var event: String? = nil
    var headline: String? = nil
    var instruction: String? = nil
    /// Phone schedule line, already a 12-hour clock (`Ends Oct 3, 6:00 PM`).
    var ends: String? = nil

    var spokenLabel: String {
        if count > 1 {
            return "\(count) alerts, \(severity), \(title)"
        }
        return "\(severity), \(title)"
    }

    /// Lines for the detail sheet. Exact repeats of the title are left off.
    var detailLines: WatchAlertDetailLines {
        WatchAlertDetailLines(
            severity: severity,
            title: title,
            countLine: count == 1 ? "1 alert" : "\(count) alerts",
            headline: Self.distinct(headline, from: title),
            event: Self.distinct(event, from: title),
            ends: WatchAlertPayload.cleaned(ends),
            instruction: WatchAlertPayload.cleaned(instruction)
        )
    }

    private static func distinct(_ value: String?, from title: String) -> String? {
        guard let text = WatchAlertPayload.cleaned(value) else { return nil }
        if text.caseInsensitiveCompare(title) == .orderedSame { return nil }
        return text
    }
}

/// What the alert sheet shows. Optional lines are nil when the phone omitted them.
struct WatchAlertDetailLines: Equatable {
    var severity: String
    var title: String
    var countLine: String
    var headline: String?
    var event: String?
    var ends: String?
    var instruction: String?
}

enum WatchAlertPayload {
    static let titleKey = "alertTitle"
    static let severityKey = "alertSeverity"
    static let countKey = "alertCount"
    static let eventKey = "alertEvent"
    static let headlineKey = "alertHeadline"
    static let instructionKey = "alertInstruction"
    static let endsKey = "alertEnds"

    static func fields(_ summary: WatchAlertSummary?) -> [String: Any] {
        guard let summary, summary.count > 0 else { return [:] }
        let title = cleaned(summary.title)
        let severity = cleaned(summary.severity)
        guard let title, let severity else { return [:] }
        var payload: [String: Any] = [
            titleKey: title,
            severityKey: severity,
            countKey: summary.count
        ]
        if let event = clip(summary.event, limit: 80) { payload[eventKey] = event }
        if let headline = clip(summary.headline, limit: 160) { payload[headlineKey] = headline }
        if let instruction = clip(summary.instruction, limit: 280) { payload[instructionKey] = instruction }
        if let ends = clip(summary.ends, limit: 80) { payload[endsKey] = ends }
        return payload
    }

    static func summary(from dictionary: [String: Any]) -> WatchAlertSummary? {
        guard let title = cleaned(dictionary[titleKey] as? String),
              let severity = cleaned(dictionary[severityKey] as? String),
              let count = countValue(dictionary[countKey]),
              count > 0 else { return nil }
        return WatchAlertSummary(
            title: title,
            severity: severity,
            count: count,
            event: cleaned(dictionary[eventKey] as? String),
            headline: cleaned(dictionary[headlineKey] as? String),
            instruction: cleaned(dictionary[instructionKey] as? String),
            ends: cleaned(dictionary[endsKey] as? String)
        )
    }

    static func countValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        return nil
    }

    static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Keeps the watch context short. A cut ends on a word when one is near.
    private static func clip(_ value: String?, limit: Int) -> String? {
        guard let text = cleaned(value) else { return nil }
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > limit / 2 {
            return String(head[..<space]) + "…"
        }
        return head + "…"
    }
}

/// Picks one title and severity from the phone's active alerts.
enum WatchAlertSummaryPlan {
    struct Item: Equatable {
        var title: String
        var severity: String
        var event: String? = nil
        var headline: String? = nil
        var instruction: String? = nil
        var ends: String? = nil
    }

    /// Title is the event when NWS sent one, otherwise the headline.
    /// `ends` is the phone's existing schedule line (`Ends …` or `Expires …`).
    static func item(
        event: String?,
        headline: String?,
        severity: String?,
        instruction: String?,
        ends: String?
    ) -> Item {
        let eventText = WatchAlertPayload.cleaned(event)
        let headlineText = WatchAlertPayload.cleaned(headline)
        let title = eventText ?? headlineText ?? ""
        return Item(
            title: title,
            severity: WatchAlertPayload.cleaned(severity) ?? "",
            event: eventText,
            headline: headlineText,
            instruction: WatchAlertPayload.cleaned(instruction),
            ends: WatchAlertPayload.cleaned(ends)
        )
    }

    static func summary(from items: [Item]) -> WatchAlertSummary? {
        let usable = items.compactMap { item -> Item? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let severity = item.severity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !severity.isEmpty else { return nil }
            return Item(
                title: clip(title),
                severity: severity,
                event: item.event,
                headline: item.headline,
                instruction: item.instruction,
                ends: item.ends
            )
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
        return WatchAlertSummary(
            title: chosen.title,
            severity: chosen.severity,
            count: usable.count,
            event: chosen.event,
            headline: chosen.headline,
            instruction: chosen.instruction,
            ends: chosen.ends
        )
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
