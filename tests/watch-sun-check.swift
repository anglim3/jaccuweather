import Foundation

@main
struct WatchSunCheck {
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

func samples() -> [WatchSunSample] {
    [
        WatchSunSample(date: "2026-10-01", sunriseISO: "2026-10-01T07:01", sunsetISO: "2026-10-01T18:40"),
        WatchSunSample(date: "2026-10-02", sunriseISO: "2026-10-02T07:12", sunsetISO: "2026-10-02T18:51"),
        WatchSunSample(date: "2026-10-03", sunriseISO: "2026-10-03T07:20", sunsetISO: "2026-10-03T18:48"),
        WatchSunSample(date: "2026-10-04", sunriseISO: nil, sunsetISO: nil)
    ]
}

func run() {
    let us = Locale(identifier: "en_US")
    check(WatchSunPlan.clock(from: "2026-10-02T06:42", locale: us) == "6:42 AM", "morning clock is 12-hour")
    check(WatchSunPlan.clock(from: "2026-10-02T18:51", locale: us) == "6:51 PM", "evening clock is 12-hour")
    check(WatchSunPlan.clock(from: "2026-10-02T18:27", locale: us) == "6:27 PM", "Juneau sunset is 6:27 PM")
    check(WatchSunPlan.clock(from: "2026-10-02T00:05", locale: us) == "12:05 AM", "midnight is 12 AM")
    check(WatchSunPlan.clock(from: "2026-10-02T12:00", locale: us) == "12:00 PM", "noon is 12 PM")
    check(WatchSunPlan.clock(from: "2026-10-02T07:12:00", locale: us) == "7:12 AM", "seconds on the stamp are ignored")
    check(WatchSunPlan.clock(from: "  2026-06-21T03:12  ", locale: us) == "3:12 AM", "the stamp is read as written")
    check(WatchSunPlan.clock(from: "2026-10-02T18:27", locale: Locale(identifier: "en_GB")) == "6:27 pm", "a 24-hour locale still uses 12-hour")
    check(WatchSunPlan.clock(from: nil) == nil, "missing stamp stays empty")
    check(WatchSunPlan.clock(from: "") == nil, "blank stamp stays empty")
    check(WatchSunPlan.clock(from: "2026-10-02") == nil, "a date without a clock stays empty")
    check(WatchSunPlan.clock(from: "2026-10-02T24:00") == nil, "an hour past 23 stays empty")

    let juneau = -8 * 3600
    let juneauMorning = utcDate(year: 2026, month: 10, day: 2, hour: 16, minute: 0)
    check(WatchDailyPlan.placeLocalDay(now: juneauMorning, utcOffsetSeconds: juneau) == "2026-10-02", "Juneau morning is still Oct 2")
    let juneauSun = WatchSunPlan.resolved(samples: samples(), utcOffsetSeconds: juneau, now: juneauMorning)
    check(juneauSun.times.line == "↑ 7:12 AM · ↓ 6:51 PM", "Juneau uses that civil day's rise and set")
    check(juneauSun.times.spoken == "Sunrise 7:12 AM, sunset 6:51 PM", "spoken line names both events")
    check(juneauSun.sunriseISO == "2026-10-02T07:12", "the matched sunrise stamp is kept")
    check(juneauSun.sunsetISO == "2026-10-02T18:51", "the matched sunset stamp is kept")
    check(juneauSun.times.line != "↑ 7:01 AM · ↓ 6:40 PM", "yesterday's row is left off")

    let tokyo = 9 * 3600
    let tokyoAfterMidnight = utcDate(year: 2026, month: 10, day: 2, hour: 16, minute: 0)
    let tokyoSun = WatchSunPlan.resolved(samples: samples(), utcOffsetSeconds: tokyo, now: tokyoAfterMidnight)
    check(tokyoSun.times.sunriseLabel == "7:20 AM" && tokyoSun.times.sunsetLabel == "6:48 PM", "utc+9 has crossed into Oct 3")

    let polar = WatchSunPlan.resolved(samples: samples(), utcOffsetSeconds: 0, now: utcDate(year: 2026, month: 10, day: 4, hour: 12, minute: 0))
    check(polar.times.line == nil && !polar.times.hasAny, "a day with neither event stays quiet")
    check(polar.sunriseISO == nil && polar.sunsetISO == nil, "unreadable stamps are not stored")

    let riseOnly = WatchSunPlan.carried(sunriseISO: "2026-10-02T06:42", sunsetISO: nil)
    check(riseOnly?.line == "↑ 6:42 AM", "sunrise alone still draws")
    check(riseOnly?.spoken == "Sunrise 6:42 AM", "sunrise alone is spoken")
    let setOnly = WatchSunPlan.carried(sunriseISO: "", sunsetISO: "2026-10-02T18:51")
    check(setOnly?.line == "↓ 6:51 PM", "sunset alone still draws")
    check(WatchSunPlan.carried(sunriseISO: nil, sunsetISO: " ") == nil, "blank snapshot fields stay off the glance")

    let carried = WatchSunPlan.carried(sunriseISO: "2026-10-02T06:42", sunsetISO: "2026-10-02T18:51")
    check(carried?.line == "↑ 6:42 AM · ↓ 6:51 PM", "a fresh snapshot formats the same clocks")

    print("ok")
}
