import Foundation

@main
struct WatchDailyAlertCheck {
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

func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func sampleDays() -> [WatchDaySample] {
    let codes = [0, 2, 61, 73, 0, 95, 1, 45, 2, 3]
    let start = utcDate(year: 2026, month: 9, day: 30, hour: 0, minute: 0)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return (0..<10).map { offset in
        let date = calendar.date(byAdding: .day, value: offset, to: start)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return WatchDaySample(
            date: stamp,
            highF: Double(60 + offset),
            lowF: Double(40 + offset),
            weatherCode: codes[offset]
        )
    }
}

func run() {
    let tokyo = 9 * 3600
    let oct2Morning = utcDate(year: 2026, month: 10, day: 2, hour: 2, minute: 20)
    check(WatchDailyPlan.placeLocalDay(now: oct2Morning, utcOffsetSeconds: tokyo) == "2026-10-02", "utc+9 morning is still Oct 2")
    let midnight = WatchDailyPlan.midnightSeconds(day: "2026-10-02", utcOffsetSeconds: tokyo)
    let expectedMidnight = utcDate(year: 2026, month: 10, day: 1, hour: 15, minute: 0).timeIntervalSince1970
    check(midnight != nil && abs(midnight! - expectedMidnight) < 1, "Oct 2 midnight in utc+9 is Oct 1 15:00 UTC")

    let tokyoDays = WatchDailyPlan.slots(samples: sampleDays(), utcOffsetSeconds: tokyo, now: oct2Morning)
    check(tokyoDays.count == 7, "seven upcoming place-local days")
    check(tokyoDays.first?.date == "2026-10-02", "starts on the place day, not the previous row")
    check(tokyoDays.first?.label == "Fri", "Oct 2 2026 is Friday")
    check(tokyoDays.last?.date == "2026-10-08", "seventh day is Oct 8")
    check(tokyoDays.first?.symbolName == "cloud.rain.fill", "rain code uses the rain symbol")
    check(tokyoDays.contains { $0.date == "2026-10-03" && $0.symbolName == "cloud.snow.fill" }, "snow code uses the snow symbol")
    check(tokyoDays.contains { $0.date == "2026-10-05" && $0.symbolName == "cloud.bolt.rain.fill" }, "thunder code uses the bolt symbol")
    check(tokyoDays.first?.highF == 62 && tokyoDays.first?.lowF == 42, "high and low stay on that row")

    let hawaii = -10 * 3600
    let stillThursday = utcDate(year: 2026, month: 10, day: 2, hour: 4, minute: 0)
    check(WatchDailyPlan.placeLocalDay(now: stillThursday, utcOffsetSeconds: hawaii) == "2026-10-01", "utc-10 is still Thursday")
    let hawaiiDays = WatchDailyPlan.slots(samples: sampleDays(), utcOffsetSeconds: hawaii, now: stillThursday)
    check(hawaiiDays.first?.date == "2026-10-01" && hawaiiDays.first?.label == "Thu", "strip starts at the place-local Thursday")
    check(!hawaiiDays.contains { $0.date == "2026-09-30" }, "yesterday's row is left off")

    let india = (5 * 3600) + (30 * 60)
    let afterMidnightIndia = utcDate(year: 2026, month: 10, day: 2, hour: 19, minute: 0)
    check(WatchDailyPlan.placeLocalDay(now: afterMidnightIndia, utcOffsetSeconds: india) == "2026-10-03", "utc+5:30 has crossed into Oct 3")
    let indiaDays = WatchDailyPlan.slots(samples: sampleDays(), utcOffsetSeconds: india, now: afterMidnightIndia, count: 5)
    check(indiaDays.count == 5 && indiaDays.first?.date == "2026-10-03", "a five-day request starts on the place day")
    check(WatchDailyPlan.slots(samples: sampleDays(), utcOffsetSeconds: tokyo, now: oct2Morning, count: 10).count == 7, "the strip stops at seven days")

    let clear = WatchDailyPlan.symbolName(code: 0)
    check(clear == "sun.max.fill", "clear day symbol")
    check(WatchDailyPlan.symbolName(code: nil) == "cloud.fill", "missing code stays a cloud")
    check(WatchDailyPlan.label(for: "2026-10-02T00:00") == "Fri", "a timestamp prefix still labels the civil day")

    let pastOnly = [WatchDaySample(date: "2026-09-30", highF: 50, lowF: 40, weatherCode: 0)]
    check(WatchDailyPlan.slots(samples: pastOnly, utcOffsetSeconds: tokyo, now: oct2Morning).isEmpty, "no future row stays empty")

    let wind = WatchAlertPayload.summary(from: [
        WatchAlertPayload.titleKey: "Wind Advisory",
        WatchAlertPayload.severityKey: "Moderate",
        WatchAlertPayload.countKey: NSNumber(value: 2)
    ])
    check(wind?.title == "Wind Advisory" && wind?.severity == "Moderate" && wind?.count == 2, "payload count may arrive as a number")
    check(WatchAlertPayload.summary(from: [WatchAlertPayload.titleKey: "Wind Advisory", WatchAlertPayload.countKey: 1]) == nil, "missing severity stays quiet")
    check(WatchAlertPayload.summary(from: [WatchAlertPayload.severityKey: "Severe", WatchAlertPayload.countKey: 1]) == nil, "missing title stays quiet")
    check(WatchAlertPayload.summary(from: [WatchAlertPayload.titleKey: "Flood", WatchAlertPayload.severityKey: "Minor"]) == nil, "missing count stays quiet")
    check(WatchAlertPayload.summary(from: [
        WatchAlertPayload.titleKey: "  ",
        WatchAlertPayload.severityKey: "Minor",
        WatchAlertPayload.countKey: 1
    ]) == nil, "blank title stays quiet")
    check(WatchAlertPayload.summary(from: [
        WatchAlertPayload.titleKey: "Flood",
        WatchAlertPayload.severityKey: "Minor",
        WatchAlertPayload.countKey: 0
    ]) == nil, "a zero count stays quiet")
    check(WatchAlertPayload.fields(nil).isEmpty, "no summary adds no fields")

    let ranked = WatchAlertSummaryPlan.summary(from: [
        WatchAlertSummaryPlan.Item(title: "Wind Advisory", severity: "Moderate"),
        WatchAlertSummaryPlan.Item(title: "Tornado Warning", severity: "Extreme"),
        WatchAlertSummaryPlan.Item(title: " ", severity: "Severe")
    ])
    check(ranked?.title == "Tornado Warning" && ranked?.severity == "Extreme" && ranked?.count == 2, "the stronger titled alert is the badge")
    let tied = WatchAlertSummaryPlan.summary(from: [
        WatchAlertSummaryPlan.Item(title: "Flood Watch", severity: "Moderate"),
        WatchAlertSummaryPlan.Item(title: "Wind Advisory", severity: "moderate")
    ])
    check(tied?.title == "Flood Watch" && tied?.count == 2, "the first alert at the top severity stays the title")
    check(WatchAlertSummaryPlan.summary(from: [WatchAlertSummaryPlan.Item(title: "Flood", severity: "")]) == nil, "an alert without severity is not invented")
    check(WatchAlertSummaryPlan.summary(from: []) == nil, "an empty alert list stays quiet")

    print("ok")
}
