import Foundation

@main
struct IntentForecastCheck {
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
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    check(IntentForecastCopy.isFresh(fetchedAt: now.addingTimeInterval(-14 * 60), now: now), "14 minutes is fresh")
    check(IntentForecastCopy.isFresh(fetchedAt: now.addingTimeInterval(-15 * 60 + 1), now: now), "just under 15 minutes is fresh")
    check(!IntentForecastCopy.isFresh(fetchedAt: now.addingTimeInterval(-15 * 60), now: now), "15 minutes is stale")
    check(!IntentForecastCopy.isFresh(fetchedAt: now.addingTimeInterval(30), now: now), "future timestamp is not fresh")

    check(IntentForecastCopy.placeKey(latitude: 47.60621, longitude: -122.33207) == "47.606,-122.332", "place key rounds to 3 decimals")
    check(IntentForecastCopy.conditionText(weatherCode: 2) == "Partly cloudy", "code 2")
    check(IntentForecastCopy.conditionText(weatherCode: 0) == "Clear sky", "code 0")
    check(IntentForecastCopy.conditionText(weatherCode: nil) == "Unknown", "missing code")
    check(IntentForecastCopy.conditionText(weatherCode: 999) == "Unknown", "unknown code")

    let spoken = IntentForecastCopy.spoken(
        placeName: " Seattle ",
        temperatureF: 61.6,
        conditionText: "Partly cloudy",
        feelsLikeF: 59.2,
        stale: false
    )
    check(spoken == "Seattle is 62 degrees and partly cloudy. Feels like 59.", "spoken summary, got \(spoken)")

    let stale = IntentForecastCopy.spoken(
        placeName: "Seattle",
        temperatureF: 61.6,
        conditionText: "Unknown",
        feelsLikeF: nil,
        stale: true
    )
    check(stale == "Last saved reading. Seattle is 62 degrees.", "stale unknown condition, got \(stale)")

    let text = IntentForecastCopy.resultText(
        placeName: "Seattle",
        temperatureF: 61.6,
        conditionText: "Partly cloudy",
        feelsLikeF: 59.2
    )
    check(text.contains("Seattle"), "result names the place")
    check(text.contains("62°"), "result has the temperature")
    check(text.contains("Partly cloudy"), "result has the condition")
    check(text.contains("Feels like 59°"), "result has feels-like")

    let missingFeels = IntentForecastCopy.resultText(
        placeName: "Seattle",
        temperatureF: 40,
        conditionText: " ",
        feelsLikeF: nil
    )
    check(missingFeels.contains("Feels like —"), "missing feels-like stays visible")
    check(missingFeels.contains("Unknown"), "blank condition becomes Unknown")

    let line = IntentForecastCopy.supportingLine(
        placeName: "Seattle",
        temperatureF: 61.6,
        conditionText: "Partly cloudy",
        feelsLikeF: 59.2
    )
    check(line == "Seattle · 62° · Partly cloudy · Feels like 59°", "supporting line, got \(line)")

    print("ok")
}
