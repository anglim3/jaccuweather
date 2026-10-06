import Foundation

@main
struct WatchFeelsLikeCheck {
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
    let shown = WatchFeelsLike.chip(temperatureF: 62.4, feelsLikeF: 63.6)
    check(shown?.text == "Feels like 64°", "formats the rounded feels-like")
    check(shown?.fahrenheit == 64, "chip keeps the rounded degrees")
    check(shown?.spoken == "Feels like 64 degrees", "voiceover says degrees")

    let colder = WatchFeelsLike.chip(temperatureF: -2.2, feelsLikeF: -5.4)
    check(colder?.text == "Feels like -5°", "negative feels-like stays signed")
    check(colder?.spoken == "Feels like -5 degrees", "negative voiceover stays signed")

    check(WatchFeelsLike.chip(temperatureF: 70.4, feelsLikeF: 71.6)?.text == "Feels like 72°", "a two-degree rounded gap shows")
    check(WatchFeelsLike.chip(temperatureF: 70, feelsLikeF: 68) != nil, "exactly two degrees cooler shows")
    check(WatchFeelsLike.chip(temperatureF: 70.4, feelsLikeF: 71.4) == nil, "a one-degree rounded gap stays hidden")
    check(WatchFeelsLike.chip(temperatureF: 64.2, feelsLikeF: 64.4) == nil, "matching rounded temperatures stay hidden")
    check(WatchFeelsLike.chip(temperatureF: 70.6, feelsLikeF: 72.4) == nil, "raw gap that rounds to one degree stays hidden")
    check(WatchFeelsLike.chip(temperatureF: nil, feelsLikeF: 40) == nil, "missing temperature stays hidden")
    check(WatchFeelsLike.chip(temperatureF: 40, feelsLikeF: nil) == nil, "missing feels-like stays hidden")
    check(WatchFeelsLike.chip(temperatureF: 40, feelsLikeF: .infinity) == nil, "non-finite feels-like stays hidden")
    check(WatchFeelsLike.chip(temperatureF: .nan, feelsLikeF: 30) == nil, "non-finite temperature stays hidden")
    check(WatchFeelsLike.chip(temperatureF: 0, feelsLikeF: -2)?.text == "Feels like -2°", "zero is a real temperature")

    check(WatchFeelsLike.filled(existingFeelsLikeF: 64, preferExisting: true, openMeteoFeelsLikeF: 70) == 64, "fresh phone feels-like wins")
    check(WatchFeelsLike.filled(existingFeelsLikeF: nil, preferExisting: true, openMeteoFeelsLikeF: 70) == 70, "missing phone value uses open-meteo")
    check(WatchFeelsLike.filled(existingFeelsLikeF: 64, preferExisting: false, openMeteoFeelsLikeF: 70) == 70, "a non-preferred reading yields to open-meteo")
    check(WatchFeelsLike.filled(existingFeelsLikeF: .nan, preferExisting: true, openMeteoFeelsLikeF: 70) == 70, "non-finite phone value uses open-meteo")
    check(WatchFeelsLike.filled(existingFeelsLikeF: 64, preferExisting: false, openMeteoFeelsLikeF: nil) == 64, "previous value remains when open-meteo has none")
    check(WatchFeelsLike.filled(existingFeelsLikeF: nil, preferExisting: false, openMeteoFeelsLikeF: nil) == nil, "nothing to show stays empty")

    check(WatchFeelsLike.openMeteo(currentApparentF: 70.2, nearestHourApparentF: 66) == 70.2, "current apparent temperature wins")
    check(WatchFeelsLike.openMeteo(currentApparentF: nil, nearestHourApparentF: 66.4) == 66.4, "nearest hour fills a missing current value")
    check(WatchFeelsLike.openMeteo(currentApparentF: .infinity, nearestHourApparentF: 66) == 66, "non-finite current falls through to the hour")
    check(WatchFeelsLike.openMeteo(currentApparentF: nil, nearestHourApparentF: nil) == nil, "omitted current and hour stay empty")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let hour: TimeInterval = 3600
    let stamps = [now.timeIntervalSince1970 - hour, now.timeIntervalSince1970 + 10 * 60, now.timeIntervalSince1970 + hour]
    let nearest = WatchFeelsLike.nearestApparent(stamps: stamps, values: [61, 64.5, 70], now: now)
    check(nearest == 64.5, "nearest hour is the closest stamp")

    let skipped = WatchFeelsLike.nearestApparent(
        stamps: [now.timeIntervalSince1970 - hour, now.timeIntervalSince1970 + 10 * 60, now.timeIntervalSince1970 + 20 * 60],
        values: [61, nil, 70],
        now: now
    )
    check(skipped == 70, "a nil nearest sample uses the next closest finite hour")

    let tie = WatchFeelsLike.nearestApparent(
        stamps: [now.timeIntervalSince1970 - 1800, now.timeIntervalSince1970 + 1800],
        values: [50, 55],
        now: now
    )
    check(tie == 50, "an exact tie keeps the earlier hour")
    check(WatchFeelsLike.nearestApparent(stamps: [now.timeIntervalSince1970], values: [nil], now: now) == nil, "no finite hour stays empty")

    print("ok")
}
