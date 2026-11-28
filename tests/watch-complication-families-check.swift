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

    check(WatchComplicationCopy.precipText(chance: 9, weatherCode: 2) == nil, "nine percent with no rain stays off")
    check(WatchComplicationCopy.precipText(chance: 10, weatherCode: 2) == "10%", "ten percent is the cutoff")
    check(WatchComplicationCopy.precipText(chance: 40, weatherCode: 0) == "40%", "a clear sky can still carry a chance")
    check(WatchComplicationCopy.precipText(chance: 9, weatherCode: 61) == "9%", "rain keeps a smaller chance")
    check(WatchComplicationCopy.precipText(chance: 0, weatherCode: 71) == "0%", "snow keeps a zero chance")
    check(WatchComplicationCopy.precipText(chance: nil, weatherCode: 61) == nil, "rain without a chance keeps the condition")
    check(WatchComplicationCopy.precipText(chance: nil, weatherCode: nil) == nil, "missing chance stays off")
    check(WatchComplicationCopy.precipText(chance: 140, weatherCode: 2) == "100%", "chance clamps at 100")
    check(WatchComplicationCopy.precipText(chance: -4, weatherCode: 2) == nil, "a negative chance with no cue stays off")
    check(WatchComplicationCopy.precipSymbol(weatherCode: 73) == "snowflake", "snow uses a snowflake")
    check(WatchComplicationCopy.precipSymbol(weatherCode: 61) == "drop.fill", "rain uses a drop")
    check(WatchComplicationCopy.precipSymbol(weatherCode: 2) == "drop.fill", "a chance that has not started uses a drop")
    check(
        WatchComplicationCopy.precipSpoken(chance: 40, weatherCode: 61) == "40 percent chance of precipitation",
        "voiceover names the chance"
    )
    check(WatchComplicationCopy.precipSpoken(chance: 4, weatherCode: 1) == nil, "a low chance is not spoken")

    let rainyCorner = WatchComplicationCopy.cornerLabel(
        conditionText: "Light rain",
        feelsLikeF: 39,
        precipChance: 40,
        weatherCode: 61
    )
    check(rainyCorner == "Light rain 40%", "corner label keeps the condition and the chance")
    check(rainyCorner.contains("40%"), "corner chance is visible")

    let longCorner = WatchComplicationCopy.cornerLabel(
        conditionText: "Freezing drizzle",
        feelsLikeF: nil,
        precipChance: 100,
        weatherCode: 56
    )
    check(longCorner == "100% chance", "a long corner label keeps the chance")
    check(longCorner.count <= WatchComplicationCopy.cornerLabelBudget, "short corner fallback stays within the budget")

    let dryCorner = WatchComplicationCopy.cornerLabel(
        conditionText: "Partly cloudy",
        feelsLikeF: 60,
        precipChance: 5,
        weatherCode: 2
    )
    check(dryCorner == "Partly cloudy", "a low chance leaves the corner condition")

    let inlinePrecip = WatchComplicationCopy.inlineWithPrecip(
        temperatureF: 41.4,
        conditionText: "Light rain",
        feelsLikeF: 39,
        precipChance: 40,
        weatherCode: 61
    )
    check(inlinePrecip == "41° Light rain 40%", "inline can append the chance")
    check(inlinePrecip.hasPrefix("41°"), "inline with a chance still leads with temperature")
    check(!inlinePrecip.localizedCaseInsensitiveContains("uv"), "inline chance skips uv")
    check(!inlinePrecip.localizedCaseInsensitiveContains("wind"), "inline chance skips wind")

    let inlineDry = WatchComplicationCopy.inlineWithPrecip(
        temperatureF: 41.4,
        conditionText: "Light rain",
        feelsLikeF: 39,
        precipChance: 5,
        weatherCode: 2
    )
    check(inlineDry == "41° Light rain", "a low chance leaves the inline line")

    print("ok")
}
