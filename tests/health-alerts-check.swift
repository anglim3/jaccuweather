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
    let good = USAQIDisplay.from(current: JSONMap(["us_aqi": 0]))
    check(good?.value == 0 && good?.category == "Good", "zero is Good, got \(String(describing: good))")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 50]))?.category == "Good", "50 is Good")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 50.6]))?.value == 51, "rounded value")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 50.6]))?.category == "Moderate", "rounded 51 is Moderate")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 79]))?.category == "Moderate", "79 is Moderate")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 101]))?.category == "Unhealthy for Sensitive Groups", "101")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 151]))?.category == "Unhealthy", "151")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 201]))?.category == "Very Unhealthy", "201")
    check(USAQIDisplay.from(current: JSONMap(["us_aqi": 301]))?.category == "Hazardous", "301")

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
