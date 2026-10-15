import Foundation

@main
struct WatchComplicationFamiliesCheck {
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
    check(
        WatchComplicationCopy.families == [
            "accessoryCircular",
            "accessoryRectangular",
            "accessoryInline",
            "accessoryCorner"
        ],
        "circular and rectangular stay, with inline and corner"
    )

    check(WatchComplicationCopy.degrees(temperatureF: 41.4) == "41°", "rounds down")
    check(WatchComplicationCopy.degrees(temperatureF: 41.5) == "42°", "rounds half up")
    check(WatchComplicationCopy.degrees(temperatureF: nil) == "—", "missing temperature")
    check(WatchComplicationCopy.degrees(temperatureF: .nan) == "—", "non-finite temperature")

    let line = WatchComplicationCopy.inlineLine(
        temperatureF: 41.4,
        conditionText: "Light rain",
        feelsLikeF: 39
    )
    check(line == "41° Light rain", "inline leads with temperature")
    check(line.hasPrefix("41°"), "temperature is first")
    check(!line.contains(":"), "inline has no clock")
    check(!line.localizedCaseInsensitiveContains("uv"), "inline skips uv")
    check(!line.localizedCaseInsensitiveContains("wind"), "inline skips wind")
    check(!line.localizedCaseInsensitiveContains("sunrise"), "inline skips sunrise")
    check(!line.localizedCaseInsensitiveContains("sunset"), "inline skips sunset")

    let condition = WatchComplicationCopy.condition(conditionText: "Light rain", feelsLikeF: 39)
    check(condition == "Light rain", "corner label is the condition")
    check(WatchComplicationCopy.symbol(named: "cloud.rain.fill") == "cloud.rain.fill", "keeps the condition symbol")
    check(WatchComplicationCopy.symbol(named: "") == "cloud.fill", "empty symbol falls back")

    let feels = WatchComplicationCopy.inlineLine(temperatureF: 40, conditionText: "", feelsLikeF: 38.2)
    check(feels == "40° Feels 38°", "empty condition uses feels-like")
    check(!feels.contains(":"), "feels-like line has no clock")

    let quiet = WatchComplicationCopy.condition(conditionText: "", feelsLikeF: nil)
    check(quiet == "Conditions", "missing condition has a short fallback")

    let longer = WatchComplicationCopy.inlinePrimary(
        temperatureF: 52,
        conditionText: "Rain",
        feelsLikeF: 50,
        precipChance: 40,
        weatherCode: 61
    )
    check(longer == "52° Rain 40%", "longer inline line adds the chance")
    check(longer.hasPrefix("52°"), "chance line still leads with temperature")
    check(!longer.localizedCaseInsensitiveContains("uv"), "chance line skips uv")
    check(!longer.localizedCaseInsensitiveContains("wind"), "chance line skips wind")

    let compact = WatchComplicationCopy.inlineCompact(temperatureF: 52, precipChance: 40, weatherCode: 61)
    check(compact == "52° · 40%", "compact inline line is temperature and chance")

    let dry = WatchComplicationCopy.inlinePrimary(
        temperatureF: 52,
        conditionText: "Partly cloudy",
        feelsLikeF: 50,
        precipChance: 4,
        weatherCode: 2
    )
    check(dry == "52° Partly cloudy", "a chance under 10 percent stays off the longer line")
    check(
        WatchComplicationCopy.inlineCompact(temperatureF: 52, precipChance: 4, weatherCode: 2) == "52°",
        "a low chance falls back to temperature"
    )
    check(
        WatchComplicationCopy.inlinePrimary(
            temperatureF: 52,
            conditionText: "Rain",
            feelsLikeF: 50,
            precipChance: nil,
            weatherCode: 61
        ) == "52° Rain",
        "a missing chance stays off the longer line"
    )
    check(
        WatchComplicationCopy.inlineCompact(temperatureF: 52, precipChance: nil, weatherCode: 61) == "52°",
        "a missing chance falls back to temperature"
    )

    check(WatchComplicationCopy.inlinePrecipPercent(chance: 9, weatherCode: 2) == nil, "nine percent with no rain stays off")
    check(WatchComplicationCopy.inlinePrecipPercent(chance: 10, weatherCode: 2) == 10, "ten percent is the cutoff")
    check(WatchComplicationCopy.inlinePrecipPercent(chance: 9, weatherCode: 61) == 9, "rain keeps a smaller chance")
    check(WatchComplicationCopy.inlinePrecipPercent(chance: nil, weatherCode: 61) == nil, "rain without a chance stays off")
    check(WatchComplicationCopy.inlinePrecipPercent(chance: 140, weatherCode: 0) == 100, "chance clamps at 100")
    check(WatchComplicationCopy.inlinePrecipPercent(chance: -4, weatherCode: 2) == nil, "a negative chance with no cue stays off")

    let spoken = WatchComplicationCopy.inlineSpoken(
        place: "Juneau",
        temperatureF: 52,
        conditionText: "Rain",
        feelsLikeF: 50,
        precipChance: 40,
        weatherCode: 61
    )
    check(spoken == "Juneau, 52°, Rain, 40 percent chance of precipitation", "inline voiceover speaks the percent")

    let quietSpoken = WatchComplicationCopy.inlineSpoken(
        place: "Juneau",
        temperatureF: 52,
        conditionText: "Partly cloudy",
        feelsLikeF: 50,
        precipChance: 4,
        weatherCode: 2
    )
    check(quietSpoken == "Juneau, 52°, Partly cloudy", "inline voiceover skips a chance under 10 percent")
    check(
        WatchComplicationCopy.inlineSpoken(
            place: "",
            temperatureF: 52,
            conditionText: "Rain",
            feelsLikeF: nil,
            precipChance: nil,
            weatherCode: nil
        ) == "Jaccuweather, 52°, Rain",
        "a missing chance keeps the temperature and condition"
    )

    print("ok")
}
