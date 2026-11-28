import Foundation

@main
struct WatchContextSyncCheck {
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
    let snapshot = #"{"locationName":"Seattle","latitude":47.6062,"longitude":-122.3321,"fetchedAt":"2026-10-15T12:00:00Z"}"#
    let snapshotReordered = #"{"fetchedAt":"2026-10-15T12:00:00Z","longitude":-122.3321,"latitude":47.6062,"locationName":"Seattle"}"#
    let portland = #"[{"name":"Portland","longitude":-122.6784,"latitude":45.5152}]"#
    let portlandSorted = #"[{"latitude":45.5152,"longitude":-122.6784,"name":"Portland"}]"#
    let denverFirst = #"[{"latitude":39.7392,"longitude":-104.9903,"name":"Denver"},{"latitude":45.5152,"longitude":-122.6784,"name":"Portland"}]"#

    let messy: [String: Any] = [
        "favorites": portland,
        "alertCount": 2,
        "alertTitle": "Wind Advisory",
        "snapshot": snapshot
    ]
    let tidy: [String: Any] = [
        "snapshot": snapshotReordered,
        "alertTitle": "Wind Advisory",
        "alertCount": 2.0,
        "favorites": portlandSorted
    ]
    let same = WatchContextSync.fingerprint(for: messy)
    check(same == WatchContextSync.fingerprint(for: tidy), "key order and 2 versus 2.0 stay one fingerprint, got \(same)")
    check(same == WatchContextSync.fingerprint(for: tidy), "the fingerprint does not change between calls")

    let otherPlace = snapshot.replacingOccurrences(of: "Seattle", with: "Portland")
    check(
        WatchContextSync.fingerprint(for: ["snapshot": otherPlace, "favorites": portlandSorted]) != same,
        "a different place is a different context"
    )
    check(
        WatchContextSync.fingerprint(for: ["snapshot": snapshot, "favorites": denverFirst]) != same,
        "favorite order is part of the context"
    )

    let places = WatchFavoritesPlan.compact([
        WatchFavoritesPlan.Input(name: "Portland", latitude: 45.5152, longitude: -122.6784),
        WatchFavoritesPlan.Input(name: "Denver", latitude: 39.7392, longitude: -104.9903)
    ])
    let once = WatchFavoritesPlan.fields(places)[WatchFavoritesPlan.contextKey] as? String
    let twice = WatchFavoritesPlan.fields(places)[WatchFavoritesPlan.contextKey] as? String
    check(once == twice && (once?.isEmpty == false), "favorites JSON is stable, got \(once ?? "nil")")
    if let json = once, let latitude = json.range(of: "\"latitude\""), let name = json.range(of: "\"name\"") {
        check(latitude.lowerBound < name.lowerBound, "favorite keys are sorted, got \(json)")
    } else {
        check(false, "favorites JSON contains latitude and name")
    }

    let stored: [String: Any] = [
        "snapshot": snapshot,
        "favorites": "[]",
        "alertTitle": "Wind Advisory",
        "alertCount": 1
    ]
    let favoritesOnly: [String: Any] = ["favorites": portlandSorted]
    let kept = WatchContextSync.base(memory: favoritesOnly, persisted: stored, sessionContext: [:])
    check(kept["snapshot"] as? String == snapshot, "a favorites update keeps the stored snapshot")
    check(kept["alertTitle"] as? String == "Wind Advisory", "a favorites update keeps the stored alert")
    check(kept["favorites"] as? String == portlandSorted, "a favorites update replaces the favorites list")

    let replacement: [String: Any] = ["snapshot": otherPlace]
    let replaced = WatchContextSync.base(memory: replacement, persisted: stored, sessionContext: [:])
    check(replaced["snapshot"] as? String == otherPlace, "a new snapshot replaces the stored one")
    check(replaced["alertTitle"] == nil, "a new snapshot does not keep a cleared alert")

    let fromSession = WatchContextSync.base(memory: nil, persisted: nil, sessionContext: stored)
    check(fromSession["snapshot"] as? String == snapshot, "the last session context is used when nothing newer is stored")
    check(WatchContextSync.isDeliverable(fromSession), "a snapshot context is deliverable")
    check(WatchContextSync.isDeliverable(["favorites": "[]"]) == false, "an empty favorites list alone is not sent")
    check(WatchContextSync.isDeliverable(["favorites": portlandSorted]), "a favorites list without a snapshot can still be sent")

    let ready = WatchContextSync.Readiness(activated: true, paired: true, watchAppInstalled: true)
    let fingerprint = WatchContextSync.fingerprint(for: stored)
    var state = WatchContextSync.State()
    check(
        WatchContextSync.decide(fingerprint: fingerprint, state: state, readiness: WatchContextSync.Readiness(activated: false, paired: true, watchAppInstalled: true)) == .hold(.inactive),
        "activation has to finish before a send"
    )
    check(
        WatchContextSync.decide(fingerprint: fingerprint, state: state, readiness: WatchContextSync.Readiness(activated: true, paired: false, watchAppInstalled: false)) == .hold(.notPaired),
        "an unpaired watch does not count as a successful send"
    )
    check(
        WatchContextSync.decide(fingerprint: fingerprint, state: state, readiness: WatchContextSync.Readiness(activated: true, paired: true, watchAppInstalled: false)) == .hold(.watchAppNotInstalled),
        "a missing watch app does not count as a successful send"
    )

    state = WatchContextSync.afterWatchStateChange(
        state,
        readiness: WatchContextSync.Readiness(activated: false, paired: false, watchAppInstalled: false)
    )
    check(state.acceptedFingerprint == nil && state.mustResend, "a watch callback before activation still needs a send")

    check(WatchContextSync.decide(fingerprint: fingerprint, state: state, readiness: ready) == .send, "the first ready session sends")
    state = WatchContextSync.afterAcceptedSend(state, fingerprint: fingerprint)
    check(WatchContextSync.decide(fingerprint: fingerprint, state: state, readiness: ready) == .skip, "the same context is not sent twice")
    let changed = WatchContextSync.fingerprint(for: ["snapshot": otherPlace, "favorites": portlandSorted])
    check(WatchContextSync.decide(fingerprint: changed, state: state, readiness: ready) == .send, "a new place is sent")

    state = WatchContextSync.afterAcceptedSend(state, fingerprint: changed)
    state = WatchContextSync.afterFailedSend(state)
    check(WatchContextSync.decide(fingerprint: changed, state: state, readiness: ready) == .send, "a failed send is tried again")

    state = WatchContextSync.afterAcceptedSend(state, fingerprint: changed)
    state = WatchContextSync.afterActivation(state)
    check(WatchContextSync.decide(fingerprint: changed, state: state, readiness: ready) == .send, "activation sends the current context again")

    state = WatchContextSync.afterAcceptedSend(state, fingerprint: changed)
    state = WatchContextSync.afterDeactivation(state)
    state = WatchContextSync.afterActivation(state)
    check(state.acceptedFingerprint == nil, "deactivation forgets the last accept")
    check(WatchContextSync.decide(fingerprint: changed, state: state, readiness: ready) == .send, "the next activation sends after the watch changes")

    state = WatchContextSync.afterAcceptedSend(state, fingerprint: changed)
    state = WatchContextSync.afterWatchStateChange(
        state,
        readiness: WatchContextSync.Readiness(activated: true, paired: true, watchAppInstalled: false)
    )
    check(state.acceptedFingerprint == nil && state.counterpartReady == false, "uninstalling the watch app drops the accept")
    check(
        WatchContextSync.decide(
            fingerprint: changed,
            state: state,
            readiness: WatchContextSync.Readiness(activated: true, paired: true, watchAppInstalled: false)
        ) == .hold(.watchAppNotInstalled),
        "the payload stays queued while the watch app is missing"
    )
    state = WatchContextSync.afterWatchStateChange(state, readiness: ready)
    check(WatchContextSync.decide(fingerprint: changed, state: state, readiness: ready) == .send, "installing the watch app sends the queued context")

    state = WatchContextSync.afterAcceptedSend(state, fingerprint: changed)
    let stillReady = WatchContextSync.afterWatchStateChange(state, readiness: ready)
    check(WatchContextSync.decide(fingerprint: changed, state: stillReady, readiness: ready) == .skip, "a later watch callback does not repeat the same context")

    print("ok")
}
