import Foundation
import WatchConnectivity

/// Sends the latest in-app forecast to the paired Watch.
/// A missing watch, or a session that is not activated yet, is ignored.
final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    private let lock = NSLock()
    private var pending: [String: Any]?
    private var lastSent: [String: Any]?
    private var started = false

    func activate() {
        guard WCSession.isSupported() else { return }
        lock.lock()
        let needsStart = !started
        if needsStart { started = true }
        lock.unlock()
        guard needsStart else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func push(_ snapshot: WidgetConditionsSnapshot, alerts: [NWSAlertFeature] = []) {
        guard snapshot.temperatureF != nil else { return }
        activate()
        var payload = WatchMirrorPayload.dictionary(from: snapshot)
        let summary = WatchAlertSummaryPlan.summary(from: alerts.map { feature in
            let event = feature.properties.event?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let headline = feature.properties.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = event.isEmpty ? headline : event
            let severity = feature.properties.severity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WatchAlertSummaryPlan.Item(title: title, severity: severity)
        })
        for (key, value) in WatchAlertPayload.fields(summary) {
            payload[key] = value
        }
        deliver(attachingFavorites(payload))
    }

    /// Favorites changed without a new forecast. The next context keeps the
    /// last snapshot and alert fields and replaces `favorites`.
    func favoritesChanged() {
        activate()
        lock.lock()
        let base = pending ?? lastSent ?? [:]
        lock.unlock()
        deliver(attachingFavorites(base))
    }

    /// `favorites` is a JSON array of `{name, latitude, longitude}`, deduped
    /// and capped. An empty list is sent as `[]` so the watch clears old rows.
    private func attachingFavorites(_ payload: [String: Any]) -> [String: Any] {
        var payload = payload
        let places = WatchFavoritesPlan.compact(WatchFavoritesReader.load())
        for (key, value) in WatchFavoritesPlan.fields(places) {
            payload[key] = value
        }
        return payload
    }

    private func deliver(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        remember(payload)
        let session = WCSession.default
        guard session.activationState == .activated else {
            store(payload)
            return
        }
        guard session.isPaired else {
            store(payload)
            return
        }
        do {
            try session.updateApplicationContext(payload)
            store(nil)
        } catch {
            store(payload)
        }
    }

    private func remember(_ payload: [String: Any]) {
        lock.lock()
        lastSent = payload
        lock.unlock()
    }

    private func store(_ payload: [String: Any]?) {
        lock.lock()
        pending = payload
        lock.unlock()
    }

    private func flushPending() {
        lock.lock()
        let payload = pending
        lock.unlock()
        guard let payload else { return }
        deliver(payload)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated { flushPending() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        flushPending()
    }
}

enum WatchFavoritesReader {
    /// Display names, in the saved favorite order. Coordinate identity matches
    /// `GeoResult.id`, and `WatchFavoritesPlan` drops duplicates before send.
    static func load(defaults: UserDefaults = .standard) -> [WatchFavoritesPlan.Input] {
        guard let data = defaults.data(forKey: "weatherFavorites"),
              let places = try? JSONDecoder().decode([GeoResult].self, from: data) else { return [] }
        return places.map {
            WatchFavoritesPlan.Input(name: $0.displayName, latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}
