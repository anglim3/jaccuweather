import Foundation

@main
struct LiveActivityPlanCheck {
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
    let seattle = "47.6062,-122.3321"
    let miami = "25.7617,-80.1918"

    check(
        LiveActivityPlan.decide(existingPlaceIDs: [], placeID: seattle) == .start(placeID: seattle),
        "first place starts an activity"
    )
    check(
        LiveActivityPlan.decide(existingPlaceIDs: [seattle], placeID: seattle) == .update(placeID: seattle),
        "the same place updates the existing activity"
    )
    check(
        LiveActivityPlan.decide(existingPlaceIDs: [seattle], placeID: miami) == .replace(placeID: miami),
        "a different place replaces the activity instead of keeping the old place id"
    )
    check(
        LiveActivityPlan.decide(existingPlaceIDs: [seattle, seattle], placeID: seattle) == .update(placeID: seattle),
        "duplicate activities for one place stay on an update"
    )
    check(
        LiveActivityPlan.decide(existingPlaceIDs: [seattle, miami], placeID: miami) == .update(placeID: miami),
        "a matching activity is kept when another place is also running"
    )
    check(
        LiveActivityPlan.decide(existingPlaceIDs: [seattle, miami], placeID: "40.7128,-74.0060") == .replace(placeID: "40.7128,-74.0060"),
        "a third place replaces every current activity"
    )
    check(LiveActivityPlan.decide(existingPlaceIDs: [seattle], placeID: nil) == .end, "no place ends a running activity")
    check(LiveActivityPlan.decide(existingPlaceIDs: [seattle], placeID: "   ") == .end, "a blank place id ends a running activity")
    check(LiveActivityPlan.decide(existingPlaceIDs: [], placeID: nil) == .idle, "no activity and no place is idle")
    check(LiveActivityPlan.decide(existingPlaceIDs: [], placeID: "") == .idle, "an empty place id with no activity is idle")
    check(
        LiveActivityPlan.decide(existingPlaceIDs: [], placeID: "  \(miami)  ") == .start(placeID: miami),
        "the place id is trimmed before start"
    )

    print("ok")
}
