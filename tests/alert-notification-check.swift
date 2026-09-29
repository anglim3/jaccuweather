import Foundation

@main
struct AlertNotificationCheck {
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
    check(AlertNotificationCopy.title(event: "Flood Watch", severity: "Severe") == "Severe: Flood Watch", "severe title")
    check(AlertNotificationCopy.title(event: "Tornado Warning", severity: "Extreme") == "Extreme: Tornado Warning", "extreme title")
    check(AlertNotificationCopy.title(event: "Wind Advisory", severity: "Moderate") == "Moderate: Wind Advisory", "moderate title")
    check(AlertNotificationCopy.title(event: "Frost Advisory", severity: "Minor") == "Minor: Frost Advisory", "minor title")
    check(AlertNotificationCopy.title(event: "Special Weather Statement", severity: "Unknown") == "Special Weather Statement", "unknown severity stays the event name")
    check(AlertNotificationCopy.title(event: "  ", severity: "Severe") == "Severe: Weather alert", "blank event")
    check(AlertNotificationCopy.title(event: nil, severity: nil) == "Weather alert", "missing fields")

    let headline = "Flood Watch issued September 29 at 3:46AM MST until September 29 at 9:00PM MST by NWS Phoenix AZ"
    check(AlertNotificationCopy.body(headline: headline, placeName: "Phoenix") == headline, "headline is the body")
    check(AlertNotificationCopy.body(headline: "  ", placeName: "Phoenix") == "A new alert is active for Phoenix.", "blank headline uses the place")
    check(AlertNotificationCopy.body(headline: nil, placeName: " ") == "A new alert is active for this place.", "blank place fallback")
    let long = String(repeating: "a", count: 200)
    check(AlertNotificationCopy.body(headline: long, placeName: "Phoenix").count == 178, "long headline is clipped")
    check(AlertNotificationCopy.body(headline: long, placeName: "Phoenix").hasSuffix("…"), "clipped headline keeps an ellipsis")

    let fresh = AlertNotificationCopy.idsToNotify(
        activeIDs: ["a", "b", "a", " ", "c"],
        alreadyNotified: ["b"]
    )
    check(fresh == ["a", "c"], "skips notified ids and blanks, got \(fresh)")
    let capped = AlertNotificationCopy.idsToNotify(activeIDs: ["a", "b", "c", "d", "e"], alreadyNotified: [], limit: 2)
    check(capped == ["a", "b"], "caps a single refresh, got \(capped)")
    check(AlertNotificationCopy.idsToNotify(activeIDs: ["a"], alreadyNotified: ["a"]).isEmpty, "already notified stays quiet")

    print("ok")
}
