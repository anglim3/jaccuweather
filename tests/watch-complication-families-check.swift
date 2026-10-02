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

    print("ok")
}
