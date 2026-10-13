import Foundation

@main
struct HealthAlertsCheck {
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

func feature(id: String?, event: String?, headline: String?, ends: String? = nil, expires: String? = nil) -> NWSAlertFeature {
    NWSAlertFeature(properties: NWSAlertProperties(
        id: id,
        headline: headline,
        event: event,
        severity: "Severe",
        urgency: "Future",
        status: "Actual",
        description: nil,
        instruction: nil,
        ends: ends,
        expires: expires,
        senderName: nil
    ))
}

func run() {
    check(USAQIDisplay.from(current: nil) == nil, "missing current hides AQI")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": NSNull()])) == nil, "null us_aqi hides AQI")
    check(USAQIDisplay.from(current: JSONMap([:])) == nil, "absent us_aqi hides AQI")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": Double.nan])) == nil, "nan hides AQI")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": Double.infinity])) == nil, "infinity hides AQI")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": -1])) == nil, "a negative reading hides AQI")
    let bands: [(Double, Int, String, String)] = [
        (0, 0, "Good", "green"),
        (50, 50, "Good", "green"),
        (50.4, 50, "Good", "green"),
        (50.5, 51, "Moderate", "yellow"),
        (50.6, 51, "Moderate", "yellow"),
        (79, 79, "Moderate", "yellow"),
        (100, 100, "Moderate", "yellow"),
        (100.5, 101, "Unhealthy for Sensitive Groups", "orange"),
        (101, 101, "Unhealthy for Sensitive Groups", "orange"),
        (150, 150, "Unhealthy for Sensitive Groups", "orange"),
        (151, 151, "Unhealthy", "red"),
        (200, 200, "Unhealthy", "red"),
        (201, 201, "Very Unhealthy", "purple"),
        (300, 300, "Very Unhealthy", "purple"),
        (301, 301, "Hazardous", "maroon"),
        (500, 500, "Hazardous", "maroon")
    ]
    for (raw, value, category, color) in bands {
        let got = USAQIDisplay.from(current: JSONMap(["us_aqi": raw]))
        check(got?.value == value, "\(raw) rounds to \(value), got \(String(describing: got?.value))")
        check(got?.category == category, "\(raw) is \(category), got \(String(describing: got?.category))")
        check(got?.colorToken == color, "\(raw) is \(color), got \(String(describing: got?.colorToken))")
    }

    let primary = JSONMap([
        "current": ["us_aqi": NSNull(), "grass_pollen": 10, "tree_pollen": 20] as [String: Any],
        "pollen_source": "google"
    ])
    let openMeteo = JSONMap([
        "current": ["us_aqi": 42, "grass_pollen": 99] as [String: Any],
        "pollen_source": "open-meteo"
    ])
    let merged = PollenUsAqi.merge(primary: primary, openMeteo: openMeteo)
    check(merged.map("current").number("us_aqi") == 42.0, "google keeps open-meteo us_aqi")
    check(merged.map("current").number("grass_pollen") == 10.0, "merge leaves grass pollen")
    check(merged.map("current").number("tree_pollen") == 20.0, "merge leaves tree pollen")
    check(merged.string("pollen_source") == "google", "merge leaves the pollen source")
    check(primary.map("current").number("us_aqi") == nil, "merge does not mutate the primary payload")
    let shown = USAQIDisplay.from(current: merged.map("current"))
    check(shown?.value == 42 && shown?.category == "Good" && shown?.colorToken == "green", "merged 42 is Good")

    let kept = PollenUsAqi.merge(
        primary: JSONMap(["current": ["us_aqi": 12] as [String: Any], "pollen_source": "tomorrow"]),
        openMeteo: openMeteo
    )
    check(kept.map("current").number("us_aqi") == 12.0, "an existing us_aqi is not replaced")
    check(kept.string("pollen_source") == "tomorrow", "tomorrow source stays")

    let stillMissing = PollenUsAqi.merge(
        primary: JSONMap(["current": ["us_aqi": NSNull()] as [String: Any], "pollen_source": "google"]),
        openMeteo: JSONMap(["current": ["us_aqi": NSNull()] as [String: Any], "pollen_source": "open-meteo"])
    )
    check(stillMissing.map("current").number("us_aqi") == nil, "missing on both sides stays missing")
    check(USAQIDisplay.from(current: stillMissing.map("current")) == nil, "a missing merged reading stays hidden")

    check(PollenReading.countText(nil) == "—", "null pollen is not zero")
    check(PollenReading.countText(0) == "0", "measured zero stays zero")
    check(PollenReading.countText(12.4) == "12", "pollen rounds")
    check(PollenReading.levelText(nil, nullAsNone: false) == "n/a", "unreported pollen is n/a")
    check(PollenReading.levelText(nil, nullAsNone: true) == "None", "reported-without-index is None")
    check(PollenReading.levelText(0, nullAsNone: false) == "None", "zero grains is None")
    check(PollenReading.levelText(20, nullAsNone: false) == "Low", "20 is Low")
    check(PollenReading.levelText(21, nullAsNone: false) == "Moderate", "21 is Moderate")
    check(PollenReading.levelText(200, nullAsNone: false) == "High", "200 is High")
    check(PollenReading.levelText(201, nullAsNone: false) == "Very High", "201 is Very High")

    let ends = AlertClock.string(from: "2026-10-02T19:00:00-05:00")
    check(ends == "Oct 2, 7:00 PM", "ends uses the alert offset, got \(ends ?? "nil")")
    check(AlertClock.string(from: "not-a-date") == nil, "unparsed ends is omitted")
    let withEnds = feature(id: "a", event: "Flood Watch", headline: "h", ends: "2026-10-02T19:00:00-05:00", expires: "2026-10-02T10:00:00-05:00")
    check(withEnds.scheduleLine == "Ends Oct 2, 7:00 PM", "ends wins over expires, got \(withEnds.scheduleLine ?? "nil")")
    let expiresOnly = feature(id: "b", event: "Wind Advisory", headline: "h", expires: "2026-10-02T10:00:00-05:00")
    check(expiresOnly.scheduleLine == "Expires Oct 2, 10:00 AM", "expires fills a missing end, got \(expiresOnly.scheduleLine ?? "nil")")
    check(feature(id: "c", event: "Test", headline: "h", ends: "soon").scheduleLine == nil, "raw text is not shown as an end time")

    let first = feature(id: "shared", event: "Flood Watch", headline: "First watch")
    let second = feature(id: "shared", event: "Flood Watch", headline: "Second watch")
    let match = NWSAlertFeature.routedMatch(id: "shared", headline: "Second watch", event: "Flood Watch", alerts: [first, second])
    check(match?.properties.headline == "Second watch", "notification headline picks the matching alert")
    check(
        NWSAlertFeature.routedMatch(id: "shared", headline: nil, event: "Flood Watch", alerts: [first, second]) == nil,
        "an ambiguous id does not open the first alert"
    )
    check(
        NWSAlertFeature.routedMatch(id: "other", headline: "Second watch", event: "Flood Watch", alerts: [first, second]) == nil,
        "a missing id does not fall through to another alert"
    )
    let only = feature(id: "only", event: "Tornado Warning", headline: "Tornado")
    check(NWSAlertFeature.routedMatch(id: "only", headline: nil, event: nil, alerts: [only])?.id == "only", "one id matches")

    let bareA = feature(id: nil, event: "Special Weather Statement", headline: "Morning")
    let bareB = feature(id: nil, event: "Special Weather Statement", headline: "Evening")
    check(bareA.id != bareB.id, "alerts without an NWS id stay distinct")
    check(NWSAlertFeature.routedMatch(id: bareB.id, headline: nil, event: nil, alerts: [bareA, bareB])?.properties.headline == "Evening", "the evening statement is the one opened")

    print("ok")
}
