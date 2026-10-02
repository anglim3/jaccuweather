import Foundation

@main
struct WatchDayDetailCheck {
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

func run() {
    check(WatchDailyPlan.title(for: "2026-10-02") == "Friday, Oct 2", "Oct 2 2026 is Friday, Oct 2")
    check(WatchDailyPlan.title(for: "2026-10-02T00:00") == "Friday, Oct 2", "a timestamp prefix still uses the civil day")
    check(WatchDailyPlan.conditionText(code: 61) == "Light rain", "rain code uses the short condition")
    check(WatchDailyPlan.conditionText(code: 73) == "Snow", "snow code uses the short condition")
    check(WatchDailyPlan.conditionText(code: nil) == "Cloudy", "a missing code stays cloudy")

    check(WatchDailyPlan.probability(72.6) == 73, "probability rounds")
    check(WatchDailyPlan.probability(0) == 0, "a zero chance stays a number")
    check(WatchDailyPlan.probability(nil) == nil, "a missing chance stays off the sheet")
    check(WatchDailyPlan.probability(140) == 100, "probability stays within 0 to 100")

    check(WatchDailyPlan.amountText(0.009) == nil, "a trace under 0.01 inch is not a cue")
    check(WatchDailyPlan.amountText(0.42) == "0.42\"", "a light amount keeps two decimals")
    check(WatchDailyPlan.amountText(1.2) == "1.2\"", "an inch and more keeps one decimal")
    check(WatchDailyPlan.amountText(2) == "2\"", "a whole inch drops the decimal")
    check(WatchDailyPlan.amountText(12.6) == "13\"", "a larger amount rounds to inches")

    check(WatchDailyPlan.displayedRain(rain: 0.2, precipitation: 0.8, snow: 0.4) == 0.2, "rain_sum wins over the combined total")
    check(WatchDailyPlan.displayedRain(rain: 0, precipitation: 0.4, snow: 0.4) == 0, "an explicit zero rain sum does not borrow the snow total")
    check(WatchDailyPlan.displayedRain(rain: nil, precipitation: 0.4, snow: 0.4) == nil, "precipitation_sum is not shown as rain when snow is present")
    check(WatchDailyPlan.displayedRain(rain: nil, precipitation: 0.33, snow: 0) == 0.33, "precipitation_sum fills in when rain is missing and there is no snow")

    check(WatchDailyPlan.uvText(3.4) == "UV 3", "UV max rounds to a whole number")
    check(WatchDailyPlan.uvText(0) == "UV 0", "a zero UV max is still shown")
    check(WatchDailyPlan.uvText(nil) == nil, "a missing UV max stays off the sheet")
    check(WatchDailyPlan.uvText(-1) == nil, "a negative UV max stays off the sheet")

    let juneau = -8 * 3600
    let juneauAfternoon = utcDate(year: 2026, month: 10, day: 2, hour: 21, minute: 0)
    let samples = [
        WatchDaySample(date: "2026-10-01", highF: 48, lowF: 36, weatherCode: 3, precipProbability: 10, rainInches: 0, precipitationInches: 0, snowInches: 0, uvMax: 1),
        WatchDaySample(date: "2026-10-02", highF: 51, lowF: 40, weatherCode: 61, precipProbability: 72.4, rainInches: 0.42, precipitationInches: 0.42, snowInches: 0, uvMax: 2.2),
        WatchDaySample(date: "2026-10-03", highF: 34, lowF: 28, weatherCode: 73, precipProbability: 80, rainInches: 0, precipitationInches: 0.6, snowInches: 1.2, uvMax: nil),
        WatchDaySample(date: "2026-10-04", highF: 40, lowF: 31, weatherCode: 2, precipProbability: nil, rainInches: nil, precipitationInches: nil, snowInches: nil, uvMax: nil)
    ]
    let days = WatchDailyPlan.slots(samples: samples, utcOffsetSeconds: juneau, now: juneauAfternoon)
    check(days.first?.date == "2026-10-02", "Juneau afternoon is still Oct 2")
    let today = WatchDailyPlan.detail(for: days[0])
    check(today.title == "Friday, Oct 2", "the sheet uses the place-local weekday and date")
    check(today.condition == "Light rain", "the sheet uses the short condition")
    check(today.high == "51°" && today.low == "40°", "the sheet keeps that day's high and low")
    check(today.probability == "72%", "the sheet shows the day's precipitation probability")
    check(today.rain == "0.42\"" && today.snow == nil, "rain at 0.42 inch is a rain cue")
    check(today.uv == "UV 2", "UV max is shown when the forecast has it")

    let snowDay = WatchDailyPlan.detail(for: days[1])
    check(snowDay.snow == "1.2\"" && snowDay.rain == nil, "snow amount is a snow cue and the rain total stays off")
    check(snowDay.uv == nil && snowDay.probability == "80%", "a day without UV omits it and still shows the chance")

    let quiet = WatchDailyPlan.detail(for: days[2])
    check(quiet.probability == nil && quiet.rain == nil && quiet.snow == nil && quiet.uv == nil, "a day without those fields omits them")
    check(quiet.condition == "Partly cloudy", "the condition still comes from the weather code")

    print("ok")
}
