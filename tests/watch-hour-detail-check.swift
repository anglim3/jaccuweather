import Foundation

@main
struct WatchHourDetailCheck {
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
    check(WatchHourlyPlan.clock(for: "2026-10-02T00:00") == "12 AM", "midnight is 12 AM")
    check(WatchHourlyPlan.clock(for: "2026-10-02T09:00") == "9 AM", "morning is 12-hour")
    check(WatchHourlyPlan.clock(for: "2026-10-02T12:00") == "12 PM", "noon is 12 PM")
    check(WatchHourlyPlan.clock(for: "2026-10-02T15:00") == "3 PM", "15:00 is 3 PM")
    check(WatchHourlyPlan.clock(for: "2026-10-02T15:30") == "3:30 PM", "a half hour keeps minutes")
    check(WatchHourlyPlan.clock(for: "2026-10-02T23:05") == "11:05 PM", "23:05 is 11:05 PM")
    check(WatchHourlyPlan.clock(fromAbbreviated: "3p") == "3 PM", "the strip label expands to 12-hour")
    for stamp in ["2026-10-02T00:00", "2026-10-02T15:00", "2026-10-02T15:30", "2026-10-02T23:05"] {
        let clock = WatchHourlyPlan.clock(for: stamp)
        check(clock.hasSuffix("AM") || clock.hasSuffix("PM"), "\(stamp) stays 12-hour")
        check(!clock.hasPrefix("00") && !clock.hasPrefix("15") && !clock.hasPrefix("23"), "\(stamp) is not a 24-hour clock")
    }

    check(WatchHourlyPlan.conditionText(code: 61) == "Light rain", "rain code uses the short condition")
    check(WatchHourlyPlan.conditionText(code: 0) == "Clear", "clear code uses the short condition")
    check(WatchHourlyPlan.symbolName(code: 61, isDay: true) == "cloud.rain.fill", "rain uses the WMO symbol")
    check(WatchHourlyPlan.symbolName(code: 0, isDay: true) == "sun.max.fill", "daytime clear uses the sun")
    check(WatchHourlyPlan.symbolName(code: 0, isDay: false) == "moon.stars.fill", "night clear uses the moon")
    check(WatchHourlyPlan.symbolName(code: 2, isDay: false) == "cloud.moon.fill", "night partly cloudy uses the moon")

    check(WatchHourlyPlan.probability(72.6) == 73, "probability rounds")
    check(WatchHourlyPlan.probability(0) == 0, "a zero chance stays a number")
    check(WatchHourlyPlan.probability(nil) == nil, "a missing chance stays off the sheet")
    check(WatchHourlyPlan.probability(140) == 100, "probability stays within 0 to 100")

    check(WatchHourlyPlan.amountText(0.009) == nil, "a trace under 0.01 inch is not a cue")
    check(WatchHourlyPlan.amountText(0.42) == "0.42\"", "a light amount keeps two decimals")
    check(WatchHourlyPlan.amountText(1.2) == "1.2\"", "an inch and more keeps one decimal")
    check(WatchHourlyPlan.amountText(2) == "2\"", "a whole inch drops the decimal")
    check(WatchHourlyPlan.amountText(12.6) == "13\"", "a larger amount rounds to inches")

    check(WatchHourlyPlan.displayedRain(rain: 0.2, precipitation: 0.8, snow: 0.4) == 0.2, "rain wins over the combined total")
    check(WatchHourlyPlan.displayedRain(rain: 0, precipitation: 0.4, snow: 0.4) == 0, "an explicit zero rain does not borrow the snow total")
    check(WatchHourlyPlan.displayedRain(rain: nil, precipitation: 0.4, snow: 0.4) == nil, "precipitation is not shown as rain when snow is present")
    check(WatchHourlyPlan.displayedRain(rain: nil, precipitation: 0.33, snow: 0) == 0.33, "precipitation fills in when rain is missing and there is no snow")

    check(WatchHourlyPlan.uvText(1.6) == "UV 2", "UV rounds to a whole number")
    check(WatchHourlyPlan.uvText(0) == "UV 0", "a zero UV index is still shown")
    check(WatchHourlyPlan.uvText(nil) == nil, "a missing UV index stays off the sheet")
    check(WatchHourlyPlan.uvText(-1) == nil, "a negative UV index stays off the sheet")
    check(WatchHourlyPlan.feelsText(nil) == nil, "a missing feels-like stays off the sheet")
    check(WatchHourlyPlan.windText(nil) == nil, "a missing wind stays off the sheet")
    check(WatchHourlyPlan.windText(-3) == nil, "a negative wind stays off the sheet")
    check(WatchHourlyPlan.humidityText(nil) == nil, "a missing humidity stays off the sheet")

    let juneau = -8 * 3600
    let juneauAfternoon = utcDate(year: 2026, month: 10, day: 2, hour: 23, minute: 10)
    let samples = [
        WatchHourSample(time: "2026-10-02T14:00", temperatureF: 48, precipProbability: 10, weatherCode: 3, precipitation: 0, snowfall: 0, rainInches: 0, feelsLikeF: 46, windMph: 8, humidity: 70, uvIndex: 1, isDay: true),
        WatchHourSample(time: "2026-10-02T15:00", temperatureF: 47, precipProbability: 72.4, weatherCode: 61, precipitation: 0.5, snowfall: 0, rainInches: 0.42, feelsLikeF: 44.2, windMph: 12.6, humidity: 81.4, uvIndex: 1.2, isDay: true),
        WatchHourSample(time: "2026-10-02T16:00", temperatureF: 34, precipProbability: 80, weatherCode: 73, precipitation: 0.3, snowfall: 0.6, rainInches: 0, feelsLikeF: nil, windMph: nil, humidity: nil, uvIndex: nil, isDay: true),
        WatchHourSample(time: "2026-10-02T21:00", temperatureF: 31, precipProbability: nil, weatherCode: 0, precipitation: 0.004, snowfall: 0, rainInches: nil, feelsLikeF: nil, windMph: 0, humidity: 90, uvIndex: 0, isDay: false)
    ]
    let hours = WatchHourlyPlan.slots(samples: samples, utcOffsetSeconds: juneau, now: juneauAfternoon)
    check(hours.first?.label == "3p", "the strip label stays the short 12-hour form")
    check(hours.first?.time == "2026-10-02T15:00", "Juneau 23:10 UTC is the 3 PM hour")

    let wet = WatchHourlyPlan.detail(for: hours[0])
    check(wet.title == "3 PM", "the sheet uses 12-hour time")
    check(!wet.title.contains("15"), "the sheet never shows 15:00")
    check(wet.condition == "Light rain", "the sheet uses the short condition")
    check(hours[0].symbolName == "cloud.rain.fill", "the sheet keeps the WMO symbol")
    check(wet.temperature == "47°", "the sheet shows that hour's temperature")
    check(wet.probability == "72%", "the sheet shows the precipitation probability")
    check(wet.rain == "0.42\"" && wet.snow == nil, "rain at 0.42 inch is a rain cue")
    check(wet.feels == "Feels 44°", "feels-like is shown when the forecast has it")
    check(wet.wind == "Wind 13 mph", "wind is shown in miles per hour")
    check(wet.humidity == "Humidity 81%", "humidity is shown when the forecast has it")
    check(wet.uv == "UV 1", "UV is shown when the forecast has it")

    let snow = WatchHourlyPlan.detail(for: hours[1])
    check(snow.snow == "0.60\"" && snow.rain == nil, "snow amount is a snow cue and the rain total stays off")
    check(snow.feels == nil && snow.wind == nil && snow.humidity == nil && snow.uv == nil, "missing extras stay off the sheet")
    check(snow.probability == "80%", "the chance still shows without those extras")

    let night = hours.first { $0.time == "2026-10-02T21:00" }
    check(night?.symbolName == "moon.stars.fill", "a night hour uses the night symbol")
    check(night?.label == "9p", "the strip label for 21:00 stays 9p")
    let quiet = WatchHourlyPlan.detail(for: night!)
    check(quiet.title == "9 PM", "21:00 is 9 PM")
    check(quiet.probability == nil && quiet.rain == nil && quiet.snow == nil, "a dry hour omits the precip lines")
    check(quiet.wind == "Wind 0 mph" && quiet.humidity == "Humidity 90%" && quiet.uv == "UV 0", "zero wind, humidity, and UV still count as present")
    check(quiet.feels == nil, "feels-like stays off when the hour did not include it")

    print("ok")
}
