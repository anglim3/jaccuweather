import Foundation

@main
struct ConditionsShareCheck {
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
    let full = ConditionsShareReading(
        placeName: " Seattle ",
        temperatureF: 61.6,
        feelsLikeF: 58.2,
        conditionText: " Partly cloudy ",
        highF: 68.4,
        lowF: 51.2
    )
    let expected = """
    Seattle
    62°
    Feels like 58°
    Partly cloudy
    High 68° / Low 51°
    jaccuweather://now
    """
    let summary = ConditionsShareCopy.summary(full)
    check(summary == expected, "full summary, got \(summary ?? "nil")")
    check(summary?.hasSuffix(NowLink.url.absoluteString) == true, "summary ends with the now link")
    check(NowLink.opensNow(URL(string: summary!.split(separator: "\n").last.map(String.init) ?? "")!), "shared link opens now")

    let lines = ConditionsShareCopy.lines(full)
    check(lines == [
        "Seattle",
        "62°",
        "Feels like 58°",
        "Partly cloudy",
        "High 68° / Low 51°",
    ], "fact lines omit the link, got \(lines ?? [])")

    let noFeels = ConditionsShareReading(
        placeName: "Portland",
        temperatureF: 40,
        feelsLikeF: nil,
        conditionText: "Foggy",
        highF: 48,
        lowF: 35
    )
    check(ConditionsShareCopy.summary(noFeels) == """
    Portland
    40°
    Foggy
    High 48° / Low 35°
    jaccuweather://now
    """, "missing feels-like drops that line, got \(ConditionsShareCopy.summary(noFeels) ?? "nil")")

    let unknown = ConditionsShareReading(
        placeName: "   ",
        temperatureF: -0.4,
        feelsLikeF: .infinity,
        conditionText: "Unknown",
        highF: nil,
        lowF: nil
    )
    check(ConditionsShareCopy.summary(unknown) == """
    This place
    0°
    jaccuweather://now
    """, "blank place, unknown condition, and non-finite feels drop out, got \(ConditionsShareCopy.summary(unknown) ?? "nil")")

    let highOnly = ConditionsShareReading(
        placeName: "Denver",
        temperatureF: 12.2,
        feelsLikeF: 5,
        conditionText: " ",
        highF: 20,
        lowF: .nan
    )
    check(ConditionsShareCopy.summary(highOnly) == """
    Denver
    12°
    Feels like 5°
    High 20°
    jaccuweather://now
    """, "blank condition and non-finite low, got \(ConditionsShareCopy.summary(highOnly) ?? "nil")")

    let lowOnly = ConditionsShareReading(
        placeName: "Boston",
        temperatureF: 33,
        feelsLikeF: 30,
        conditionText: "Slight snow",
        highF: nil,
        lowF: 28.6
    )
    check(ConditionsShareCopy.summary(lowOnly)?.contains("Low 29°") == true, "low only")
    check(ConditionsShareCopy.summary(lowOnly)?.contains("High") == false, "low only has no high")

    let missingTemp = ConditionsShareReading(
        placeName: "Seattle",
        temperatureF: .nan,
        feelsLikeF: 60,
        conditionText: "Clear sky",
        highF: 70,
        lowF: 50
    )
    check(ConditionsShareCopy.summary(missingTemp) == nil, "non-finite temperature is not shared")
    check(ConditionsShareCopy.lines(missingTemp) == nil, "non-finite temperature has no lines")

    let custom = URL(string: "jaccuweather://now")!
    check(ConditionsShareCopy.summary(full, link: custom) == expected, "explicit now link matches the default")
    check(
        ConditionsShareCopy.previewTitle(full) == "Seattle 62° feels 58° Partly cloudy High 68° / Low 51°",
        "preview title is one line, got \(ConditionsShareCopy.previewTitle(full) ?? "nil")"
    )
    check(ConditionsShareCopy.previewTitle(missingTemp) == nil, "preview title needs a temperature")

    print("ok")
}
