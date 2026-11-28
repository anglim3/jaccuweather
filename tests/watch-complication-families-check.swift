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

    let metrics = WatchAtmosphere.metrics(
        uvIndex: 4,
        windSpeedMph: 12.4,
        windDirectionDegrees: 315,
        windGustMph: 20.2,
        humidityPercent: 62.4
    )
    let detail = WatchComplicationCopy.rectangularDetail(metrics)
    check(detail == WatchAtmosphere.detailLine(metrics), "rectangular reuses the atmosphere line")
    check(detail == "UV 4 · 12 mph NW · G20", "rectangular joins uv and wind")
    check(detail?.contains("%") == false, "rectangular skips the humidity percent")
    check(detail?.localizedCaseInsensitiveContains("humidity") != true, "rectangular skips the word humidity")

    let humidOnly = WatchAtmosphere.metrics(
        uvIndex: nil,
        windSpeedMph: nil,
        windDirectionDegrees: nil,
        windGustMph: nil,
        humidityPercent: 80
    )
    check(WatchComplicationCopy.rectangularDetail(humidOnly) == nil, "humidity alone stays off the complication")
    check(WatchComplicationCopy.rectangularDetail(.empty) == nil, "missing uv and wind keeps the condition line")

    let uvOnly = WatchAtmosphere.metrics(uvIndex: 9.2, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil)
    check(WatchComplicationCopy.rectangularDetail(uvOnly) == "UV 9", "uv alone is the rectangular line")

    print("ok")
}
