import Foundation

/// One forecast day with measurable snow, already rounded to the nearest 0.1 inch.
struct SnowDay: Equatable, Identifiable {
    let index: Int
    let weekday: String
    let shortWeekday: String
    let monthDay: String
    let inches: Double

    var id: Int { index }
}

/// Consecutive snow days from the 14-day window, matching `displayWeeklySnowTotals`.
struct SnowPeriod: Equatable, Identifiable {
    let id: Int
    let days: [SnowDay]
    let totalInches: Double
    let headline: String
    let breakdown: String?
}

struct WeeklySnowSummary: Equatable {
    var periods: [SnowPeriod]
    var nwsInches: Double?

    var nwsLine: String? {
        guard let nwsInches else { return nil }
        return String(format: "NWS 48h forecast: %.1f in", nwsInches)
    }
}

enum WeeklySnowTotals {
    /// `days` is the forecast window that already skipped `past_days` (today onward).
    /// The website starts at daily index 2 and reads the next 14 days.
    static func periods(days: [(date: String, snowfall: Double)]) -> [SnowPeriod] {
        var snowDays: [SnowDay] = []
        for (offset, day) in days.prefix(14).enumerated() where day.snowfall > 0 {
            let inches = roundTenth(day.snowfall)
            let labels = dayLabels(day.date)
            snowDays.append(SnowDay(
                index: offset,
                weekday: labels.weekday,
                shortWeekday: labels.shortWeekday,
                monthDay: labels.monthDay,
                inches: inches
            ))
        }
        guard !snowDays.isEmpty else { return [] }

        var groups: [[SnowDay]] = []
        var current: [SnowDay] = []
        for day in snowDays {
            if let last = current.last, day.index != last.index + 1 {
                groups.append(current)
                current = [day]
            } else {
                current.append(day)
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.enumerated().map { offset, group in
            let total = roundTenth(group.reduce(0) { $0 + $1.inches })
            let (number, unit) = amount(total)
            let headline: String
            let breakdown: String?
            if group.count == 1 {
                let day = group[0]
                headline = "Snowfall on \(day.weekday) (\(day.monthDay)) is \(number) \(unit)"
                breakdown = nil
            } else {
                let first = group[0]
                let last = group[group.count - 1]
                headline = "Snowfall between \(first.weekday) (\(first.monthDay)) and \(last.weekday) (\(last.monthDay)) is \(number) \(unit)"
                breakdown = group.map { day in
                    let (dayNumber, dayUnit) = amount(day.inches)
                    return "\(day.shortWeekday): \(dayNumber) \(dayUnit)"
                }.joined(separator: " • ")
            }
            return SnowPeriod(id: offset, days: group, totalInches: total, headline: headline, breakdown: breakdown)
        }
    }

    static func roundTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func amount(_ inches: Double) -> (String, String) {
        let rounded = roundTenth(inches)
        let unit = rounded == 1 ? "inch" : "inches"
        return (String(format: "%.1f", rounded), unit)
    }

    private static func dayLabels(_ ymd: String) -> (weekday: String, shortWeekday: String, monthDay: String) {
        guard let date = calendarDate(ymd) else {
            return (ymd, ymd, ymd)
        }
        return (longWeekday.string(from: date), shortWeekday.string(from: date), monthDay.string(from: date))
    }

    private static func calendarDate(_ ymd: String) -> Date? {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    private static let longWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let shortWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

/// NWS `snowfallAmount` overlap for the next 48 hours. Values are millimeters (`wmoUnit:mm`).
enum NWSSnowWindow {
    struct Entry: Equatable {
        var validTime: String
        var value: Double
        var period: String?
    }

    static func entries(from data: Data) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = root["properties"] as? [String: Any],
              let amount = properties["snowfallAmount"] as? [String: Any],
              let values = amount["values"] as? [Any] else { return [] }
        return values.compactMap { item in
            guard let row = item as? [String: Any] else { return nil }
            return Entry(
                validTime: row["validTime"] as? String ?? "",
                value: millimeters(row["value"]),
                period: row["period"] as? String
            )
        }
    }

    static func totalInches(entries: [Entry], now: Date) -> Double {
        totalMillimeters(entries: entries, now: now) / 25.4
    }

    static func totalMillimeters(entries: [Entry], now: Date) -> Double {
        let end = now.addingTimeInterval(48 * 60 * 60)
        var total = 0.0
        for entry in entries {
            let parts = entry.validTime.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let startIso = parts.first ?? ""
            let durationIso = parts.count > 1 ? parts[1] : "PT0H"
            guard let rangeStart = parseISO(startIso) else { continue }
            let durationSource = durationIso.isEmpty ? (entry.period ?? "") : durationIso
            let durationHours = extractDurationHours(durationSource)
            let safeDuration = durationHours > 0 ? durationHours : 1
            let rangeEnd = rangeStart.addingTimeInterval(safeDuration * 60 * 60)
            let overlap = overlapHours(rangeStart: rangeStart, rangeEnd: rangeEnd, targetStart: now, targetEnd: end)
            if overlap <= 0 { continue }
            total += entry.value * (overlap / safeDuration)
        }
        return total
    }

    static func extractDurationHours(_ duration: String) -> Double {
        let days = firstNumber("(\\d+)D", in: duration)
        let hours = firstNumber("(\\d+)H", in: duration)
        let minutes = firstNumber("(\\d+)M", in: duration)
        return days * 24 + hours + (minutes / 60)
    }

    static func overlapHours(rangeStart: Date, rangeEnd: Date, targetStart: Date, targetEnd: Date) -> Double {
        let start = max(rangeStart.timeIntervalSince1970, targetStart.timeIntervalSince1970)
        let end = min(rangeEnd.timeIntervalSince1970, targetEnd.timeIntervalSince1970)
        if end <= start { return 0 }
        return (end - start) / 3600
    }

    private static func millimeters(_ value: Any?) -> Double {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text) ?? 0
        default:
            return 0
        }
    }

    private static func parseISO(_ string: String) -> Date? {
        if let date = isoFractional.date(from: string) { return date }
        return iso.date(from: string)
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Double {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return 0 }
        return Double(text[range]) ?? 0
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
