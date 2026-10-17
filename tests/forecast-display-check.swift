import Foundation

@main
struct ForecastDisplayCheck {
    static func main() {
        run()
        print("ok")
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

func utcDate(hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var parts = DateComponents()
    parts.calendar = calendar
    parts.timeZone = calendar.timeZone
    parts.year = 2026
    parts.month = 10
    parts.day = 17
    parts.hour = hour
    parts.minute = minute
    return calendar.date(from: parts)!
}

func run() {
    check(ForecastDisplay.compactClock("1:00 AM") == "1 AM", "on-the-hour morning drops :00")
    check(ForecastDisplay.compactClock("12:00 PM") == "12 PM", "noon drops :00")
    check(ForecastDisplay.compactClock("12:00 AM") == "12 AM", "midnight drops :00")
    check(ForecastDisplay.compactClock("3:30 PM") == "3:30 PM", "a half hour keeps minutes")
    check(ForecastDisplay.compactClock("  11:00 pm ") == "11 PM", "suffix is uppercase")

    let saturday = "2026-10-17T01:00"
    check(ForecastDisplay.chipClock(clock: "1:00 AM", stamp: saturday, markDay: true) == "Sat 1 AM", "first hour of a day names the weekday")
    check(ForecastDisplay.chipClock(clock: "2:00 AM", stamp: "2026-10-17T02:00", markDay: false) == "2 AM", "later hours stay a clock")
    check(ForecastDisplay.marksNewDay(stamp: saturday, previous: nil), "the first hour marks the day")
    check(!ForecastDisplay.marksNewDay(stamp: "2026-10-17T02:00", previous: saturday), "the same civil day does not mark again")
    check(ForecastDisplay.marksNewDay(stamp: "2026-10-18T00:00", previous: "2026-10-17T23:00"), "midnight starts the next day")

    check(ForecastDisplay.axisLabel(date: utcDate(hour: 0, minute: 0), hourly: true) == "12 AM\nSat", "midnight axis is 12 AM plus the weekday")
    check(ForecastDisplay.axisLabel(date: utcDate(hour: 15, minute: 0), hourly: true) == "3 PM", "15:00 axis is 3 PM")
    check(ForecastDisplay.axisLabel(date: utcDate(hour: 12, minute: 0), hourly: true) == "12 PM", "noon axis is 12 PM")
    check(!ForecastDisplay.axisLabel(date: utcDate(hour: 15, minute: 0), hourly: true).contains("15"), "axis hour is not 24-hour")
    check(ForecastDisplay.axisLabel(date: utcDate(hour: 0, minute: 0), hourly: false) == "Sat\n17", "daily axis is weekday and day of month")

    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let tide = ForecastDisplay.tideReadout(date: utcDate(hour: 15, minute: 5), feet: 2.5, calendar: utc)
    check(tide == "Sat 3:05 PM  2.5 ft", "tide readout is 12-hour, got \(tide)")
    check(!tide.contains("15:"), "tide readout is not 24-hour")
    check(ForecastDisplay.clock(hour: 0, minute: 0, dropZeroMinutes: false) == "12:00 AM", "tide midnight keeps minutes")

    check(ForecastDisplay.precipCue(chance: 0, amount: 0, snow: 0) == nil, "a dry day stays off the collapsed row")
    check(ForecastDisplay.precipCue(chance: 2, amount: 0.004, snow: 0) == nil, "a trace under 0.01 in stays off the row")
    check(ForecastDisplay.precipCue(chance: 48, amount: 0.07, snow: 0) == "48%", "a real chance is the glance cue")
    check(ForecastDisplay.precipCue(chance: 2, amount: 0.07, snow: 0) == "0.07 in", "measurable rain shows the amount when the chance is small")
    check(ForecastDisplay.precipCue(chance: 80, amount: 0.2, snow: 0.4) == "0.4 in snow", "snow replaces the rain cue")

    check(ForecastDisplay.inches(0) == "0 in", "zero is 0 in")
    check(ForecastDisplay.inches(0.07) == "0.07 in", "rain uses inches, not a quote mark")
    check(!ForecastDisplay.inches(0.07).contains("\""), "inch text has no quote mark")
    check(ForecastDisplay.inches(nil) == "—", "missing inches stay blank")
    check(ForecastDisplay.pressure(hPa: 1013) == "29.91 inHg", "pressure is inches of mercury")
    check(ForecastDisplay.pressure(inHg: 0) == "—", "missing pressure stays blank")
    check(ForecastDisplay.moonPercent(0.42) == "42%", "moon phase is a percent")
    check(ForecastDisplay.niceScore(6.4) == "6/10", "nice weather keeps the scale")
    check(ForecastDisplay.rainDetail(chance: 0, amount: 0) == "0 in", "a dry detail omits a zero chance")
    check(ForecastDisplay.rainDetail(chance: 48, amount: 0.07) == "0.07 in · 48%", "rain detail keeps amount and chance")
    check(ForecastDisplay.windDetail(speed: 13, gust: 0) == "13 mph", "a zero gust stays off the wind line")
    check(ForecastDisplay.windDetail(speed: 13, gust: 18) == "13 mph · gust 18", "a real gust stays reachable")
    check(ForecastDisplay.temperaturePair(59, 47) == "59° / 47°", "feels-like pair")
}
