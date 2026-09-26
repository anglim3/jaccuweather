import Foundation

@main
struct WeeklySnowCheck {
    static func main() {
        run()
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

func run() {
    let none = WeeklySnowTotals.periods(days: [
        (date: "2026-09-26", snowfall: 0),
        (date: "2026-09-27", snowfall: 0)
    ])
    check(none.isEmpty, "no snow days should hide the section")

    let trace = WeeklySnowTotals.periods(days: [(date: "2026-09-28", snowfall: 0.04)])
    check(trace.count == 1, "snowfall above zero is kept before rounding")
    check(trace[0].headline == "Snowfall on Monday (Sep 28) is 0.0 inches", "trace snow rounds to 0.0 inches, got \(trace[0].headline)")

    let oneInch = WeeklySnowTotals.periods(days: [(date: "2026-09-28", snowfall: 1.04)])
    check(oneInch.count == 1, "single snow day")
    check(oneInch[0].headline == "Snowfall on Monday (Sep 28) is 1.0 inch", "singular inch, got \(oneInch[0].headline)")
    check(oneInch[0].breakdown == nil, "single day has no breakdown")
    check(oneInch[0].totalInches == 1, "single day total")

    let split = WeeklySnowTotals.periods(days: [
        (date: "2026-09-28", snowfall: 1.24),
        (date: "2026-09-29", snowfall: 0.26),
        (date: "2026-09-30", snowfall: 0),
        (date: "2026-10-01", snowfall: 0.34)
    ])
    check(split.count == 2, "a dry day splits periods, got \(split.count)")
    check(split[0].headline == "Snowfall between Monday (Sep 28) and Tuesday (Sep 29) is 1.5 inches", "multi-day headline, got \(split[0].headline)")
    check(split[0].breakdown == "Mon: 1.2 inches • Tue: 0.3 inches", "breakdown, got \(split[0].breakdown ?? "nil")")
    check(split[0].totalInches == 1.5, "period sum of rounded days")
    check(split[1].headline == "Snowfall on Thursday (Oct 1) is 0.3 inches", "second period, got \(split[1].headline)")

    var longWindow: [(date: String, snowfall: Double)] = []
    var day = DateComponents()
    day.calendar = Calendar(identifier: .gregorian)
    day.year = 2026
    day.month = 9
    day.day = 26
    let start = day.date!
    for offset in 0..<16 {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: start)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let snow = offset == 14 ? 4.0 : 0
        longWindow.append((date: formatter.string(from: date), snowfall: snow))
    }
    check(WeeklySnowTotals.periods(days: longWindow).isEmpty, "day 15 is outside the 14-day window")

    let now = ISO8601DateFormatter().date(from: "2026-09-26T00:00:00Z")!
    let full = NWSSnowWindow.totalInches(entries: [
        NWSSnowWindow.Entry(validTime: "2026-09-26T00:00:00Z/PT24H", value: 25.4, period: nil)
    ], now: now)
    check(abs(full - 1) < 0.0001, "24h of 25.4 mm inside the window is 1 inch, got \(full)")

    let half = NWSSnowWindow.totalInches(entries: [
        NWSSnowWindow.Entry(validTime: "2026-09-25T18:00:00Z/PT12H", value: 25.4, period: nil)
    ], now: now)
    check(abs(half - 0.5) < 0.0001, "partial overlap prorates millimeters, got \(half)")

    let outside = NWSSnowWindow.totalInches(entries: [
        NWSSnowWindow.Entry(validTime: "2026-09-20T00:00:00Z/PT6H", value: 100, period: nil)
    ], now: now)
    check(outside == 0, "ranges outside the next 48h add nothing")

    let dayDuration = NWSSnowWindow.extractDurationHours("P1DT6H30M")
    check(abs(dayDuration - 30.5) < 0.0001, "ISO duration days hours minutes, got \(dayDuration)")

    let emptyDuration = NWSSnowWindow.totalInches(entries: [
        NWSSnowWindow.Entry(validTime: "2026-09-26T00:00:00Z/", value: 25.4, period: "PT6H")
    ], now: now)
    check(abs(emptyDuration - 1) < 0.0001, "empty duration falls back to period, got \(emptyDuration)")

    let payload = """
    {"properties":{"snowfallAmount":{"uom":"wmoUnit:mm","values":[{"validTime":"2026-09-26T00:00:00+00:00/PT24H","value":25.4},{"validTime":"2026-09-20T00:00:00+00:00/PT1H","value":null}]}}}
    """.data(using: .utf8)!
    let parsed = NWSSnowWindow.entries(from: payload)
    check(parsed.count == 2, "grid values parse, including null")
    check(parsed[1].value == 0, "null snowfall is zero")
    let parsedInches = NWSSnowWindow.totalInches(entries: parsed, now: now)
    check(abs(parsedInches - 1) < 0.0001, "parsed grid totals 1 inch, got \(parsedInches)")

    let summary = WeeklySnowSummary(periods: oneInch, nwsInches: 0.14)
    check(summary.nwsLine == "NWS 48h forecast: 0.1 in", "NWS line copy, got \(summary.nwsLine ?? "nil")")
    check(WeeklySnowSummary(periods: oneInch, nwsInches: nil).nwsLine == nil, "missing NWS stays quiet")

    print("ok")
}
