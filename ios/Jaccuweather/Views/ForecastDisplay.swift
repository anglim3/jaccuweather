import Foundation

/// Copy for the Forecast tab. Clocks stay 12-hour, including where the
/// device prefers a 24-hour clock. Chart dates are location wall clocks
/// parsed as UTC, so axis labels use that same calendar.
enum ForecastDisplay {
    static let hPaToInHg = 0.02953

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    static func temperaturePair(_ high: Double?, _ low: Double?) -> String {
        "\(temperature(high)) / \(temperature(low))"
    }

    static func inches(_ value: Double?, places: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        if abs(value) < 0.005 { return "0 in" }
        if places == 1 { return String(format: "%.1f in", value) }
        return String(format: "%.2f in", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func moonPercent(_ phase: Double) -> String {
        guard phase.isFinite else { return "—" }
        return "\(Int((phase * 100).rounded()))%"
    }

    static func pressure(inHg: Double) -> String {
        guard inHg.isFinite, inHg > 0 else { return "—" }
        return String(format: "%.2f inHg", inHg)
    }

    static func pressure(hPa: Double?) -> String {
        guard let hPa, hPa.isFinite else { return "—" }
        return pressure(inHg: hPa * hPaToInHg)
    }

    static func milesPerHour(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded())) mph"
    }

    static func niceScore(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int(value.rounded()))/10"
    }

    /// "1:00 AM" becomes "1 AM". A non-zero minute stays.
    static func compactClock(_ clock: String) -> String {
        let trimmed = clock.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = zeroMinuteClock.firstMatch(in: trimmed, range: range),
              let hourRange = Range(match.range(at: 1), in: trimmed),
              let suffixRange = Range(match.range(at: 2), in: trimmed) else { return trimmed }
        return "\(trimmed[hourRange]) \(trimmed[suffixRange].uppercased())"
    }

    static func marksNewDay(stamp: String, previous: String?) -> Bool {
        guard let previous else { return true }
        return stamp.prefix(10) != previous.prefix(10)
    }

    static func chipClock(clock: String, stamp: String, markDay: Bool) -> String {
        let compact = compactClock(clock)
        guard markDay, let day = weekday(fromStamp: stamp) else { return compact }
        return "\(day) \(compact)"
    }

    /// Chance, amount, or snow worth a glance on a collapsed day row.
    /// Dry hours stay off the row; the expanded detail still lists them.
    static func precipCue(chance: Int?, amount: Double?, snow: Double) -> String? {
        if snow > 0 {
            return "\(inches(snow, places: snow >= 0.1 ? 1 : 2)) snow"
        }
        if let chance, chance >= 10 {
            return "\(chance)%"
        }
        if let amount, amount >= 0.01 {
            return inches(amount)
        }
        return nil
    }

    static func rainDetail(chance: Int?, amount: Double?) -> String {
        let amountText = inches(amount ?? 0)
        if let chance, chance > 0 {
            return "\(amountText) · \(chance)%"
        }
        return amountText
    }

    static func windDetail(speed: Double?, gust: Double) -> String {
        let speedText = milesPerHour(speed)
        guard gust.isFinite, gust >= 1 else { return speedText }
        return "\(speedText) · gust \(Int(gust.rounded()))"
    }

    static func cloudDetail(low: Double, mid: Double, high: Double) -> String {
        "L \(Int(low.rounded()))% · M \(Int(mid.rounded()))% · H \(Int(high.rounded()))%"
    }

    static func cloudPercent(total: Double?, low: Double?, mid: Double?, high: Double?) -> String {
        if let total, total.isFinite { return percent(total) }
        let parts = [low, mid, high].compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard !parts.isEmpty else { return "—" }
        return percent(parts.reduce(0, +) / Double(parts.count))
    }

    static func axisLabel(date: Date, hourly: Bool) -> String {
        let calendar = utcCalendar
        if hourly {
            let hour = calendar.component(.hour, from: date)
            let clock = clock(hour: hour, minute: 0, dropZeroMinutes: true)
            if hour == 0 {
                return "\(clock)\n\(weekdayName(date, calendar: calendar))"
            }
            return clock
        }
        return "\(weekdayName(date, calendar: calendar))\n\(calendar.component(.day, from: date))"
    }

    static func tideReadout(date: Date, feet: Double, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let clock = clock(hour: hour, minute: minute, dropZeroMinutes: false)
        let day = weekdayName(date, calendar: calendar)
        return "\(day) \(clock)  \(String(format: "%.1f ft", feet))"
    }

    static func clock(hour: Int, minute: Int, dropZeroMinutes: Bool) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let hour12 = normalized % 12 == 0 ? 12 : normalized % 12
        let suffix = normalized >= 12 ? "PM" : "AM"
        if dropZeroMinutes && minute == 0 {
            return "\(hour12) \(suffix)"
        }
        return String(format: "%d:%02d %@", hour12, minute, suffix)
    }

    private static func weekday(fromStamp stamp: String) -> String? {
        guard let date = dayParser.date(from: String(stamp.prefix(10))) else { return nil }
        return weekdayName(date, calendar: utcCalendar)
    }

    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.calendar = calendar
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private static let zeroMinuteClock = try! NSRegularExpression(pattern: #"^(\d{1,2}):00\s*([AaPp][Mm])$"#)

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
