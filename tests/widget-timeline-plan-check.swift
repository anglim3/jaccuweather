import Foundation

@main
struct WidgetTimelinePlanCheck {
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
    let seattleLat = 47.60621
    let seattleLon = -122.33207
    let seattleSnapshotId = "47.6062,-122.3321"
    let seattleWidgetId = "47.60621,-122.33207|U2VhdHRsZQ=="
    let miamiLat = 25.76168
    let miamiLon = -80.19179

    check(
        WidgetTimelinePlan.samePlace(
            snapshotLatitude: seattleLat,
            snapshotLongitude: seattleLon,
            snapshotLocationId: seattleSnapshotId,
            placeLatitude: seattleLat,
            placeLongitude: seattleLon,
            placeId: seattleWidgetId
        ),
        "four-decimal snapshot id matches a five-decimal widget id for the same place"
    )
    check(
        WidgetTimelinePlan.placeKey(latitude: seattleLat, longitude: seattleLon) == seattleSnapshotId,
        "place key uses the snapshot's four-decimal form"
    )
    check(
        !WidgetTimelinePlan.samePlace(
            snapshotLatitude: seattleLat,
            snapshotLongitude: seattleLon,
            snapshotLocationId: seattleSnapshotId,
            placeLatitude: miamiLat,
            placeLongitude: miamiLon,
            placeId: "25.76168,-80.19179|TWlhbWk="
        ),
        "Seattle snapshot is not Miami"
    )
    check(
        WidgetTimelinePlan.samePlace(
            snapshotLatitude: miamiLat,
            snapshotLongitude: miamiLon,
            snapshotLocationId: seattleWidgetId,
            placeLatitude: seattleLat,
            placeLongitude: seattleLon,
            placeId: seattleWidgetId
        ),
        "identical configuration ids match even when the stored coordinates differ"
    )

    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: true,
            snapshotFresh: true,
            hasConfiguredPlace: false,
            snapshotMatchesPlace: false
        ) == .useSnapshot,
        "a widget with no chosen place follows a fresh app snapshot"
    )
    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: true,
            snapshotFresh: true,
            hasConfiguredPlace: true,
            snapshotMatchesPlace: true
        ) == .useSnapshot,
        "a fresh snapshot is used when it is the chosen place"
    )
    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: true,
            snapshotFresh: true,
            hasConfiguredPlace: true,
            snapshotMatchesPlace: false
        ) == .fetchConfiguredPlace,
        "a fresh snapshot for another place does not replace the chosen place"
    )
    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: true,
            snapshotFresh: false,
            hasConfiguredPlace: true,
            snapshotMatchesPlace: true
        ) == .fetchConfiguredPlace,
        "a stale snapshot of the chosen place is refreshed from Open-Meteo"
    )
    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: false,
            snapshotFresh: false,
            hasConfiguredPlace: true,
            snapshotMatchesPlace: false
        ) == .fetchConfiguredPlace,
        "Personal Team with no snapshot loads the chosen place"
    )
    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: true,
            snapshotFresh: false,
            hasConfiguredPlace: false,
            snapshotMatchesPlace: false
        ) == .refreshSnapshot,
        "a stale app snapshot is refreshed when the widget has no chosen place"
    )
    check(
        WidgetTimelinePlan.decide(
            hasSnapshot: false,
            snapshotFresh: false,
            hasConfiguredPlace: false,
            snapshotMatchesPlace: false
        ) == .empty,
        "no snapshot and no chosen place stays empty"
    )

    check(
        WidgetTimelinePlan.afterFailedFetch(
            hasSnapshot: true,
            snapshotMatchesPlace: false,
            hasConfiguredPlace: true
        ) == .unavailable,
        "a failed fetch does not fall back to another place's snapshot"
    )
    check(
        WidgetTimelinePlan.afterFailedFetch(
            hasSnapshot: true,
            snapshotMatchesPlace: true,
            hasConfiguredPlace: true
        ) == .refreshSnapshot,
        "a failed fetch can still refresh the matching snapshot"
    )
    check(
        WidgetTimelinePlan.afterFailedFetch(
            hasSnapshot: false,
            snapshotMatchesPlace: false,
            hasConfiguredPlace: true
        ) == .unavailable,
        "Personal Team fetch failure is unavailable"
    )
    check(
        WidgetTimelinePlan.afterFailedRefresh(
            hasConfiguredPlace: true,
            withinStaleWindow: true
        ) == .keepStaleSnapshot,
        "the matching snapshot stays up for the stale window"
    )
    check(
        WidgetTimelinePlan.afterFailedRefresh(
            hasConfiguredPlace: true,
            withinStaleWindow: false
        ) == .unavailable,
        "an expired matching snapshot becomes unavailable"
    )
    check(
        WidgetTimelinePlan.afterFailedRefresh(
            hasConfiguredPlace: false,
            withinStaleWindow: false
        ) == .empty,
        "an expired snapshot with no chosen place is empty"
    )

    print("ok")
}
