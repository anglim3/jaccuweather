import Foundation
import os
import UIKit
import WatchConnectivity

/// Sends the latest place, forecast, and favorites to the paired Watch.
///
/// The transfer uses `updateApplicationContext`, which the system can finish
/// after this app leaves the foreground. The same context is handed to the
/// session again when activation completes and when the watch becomes paired
/// or the watch app is installed. An unchanged context is not sent twice.
/// A watch that is not paired, or a watch app that is not installed, keeps
/// the payload until a later session callback can deliver it.
final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    private let log = Logger(subsystem: "cloud.janglim.jaccuweather", category: "WatchSync")
    private let lock = NSLock()
    private var started = false
    private var latest: [String: Any]?
    private var delivery = WatchContextSync.State()
    private var loggedHold: WatchContextSync.Hold?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    private static let persistedKey = "jaccuweather.watch.context.v1"

    private override init() {
        super.init()
        latest = Self.loadPersisted()
    }

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
            WatchAlertSummaryPlan.item(
                event: feature.properties.event,
                headline: feature.properties.headline,
                severity: feature.properties.severity,
                instruction: feature.properties.instruction,
                ends: feature.scheduleLine
            )
        })
        for (key, value) in WatchAlertPayload.fields(summary) {
            payload[key] = value
        }
        onMain {
            // A forecast replaces the previous context, including cleared alerts.
            self.latest = payload
            self.attemptDelivery()
        }
    }

    /// Favorites changed without a new forecast. The snapshot and alert fields
    /// already stored are kept, and `favorites` is read again from disk.
    func favoritesChanged() {
        activate()
        onMain { self.attemptDelivery() }
    }

    /// The scene moved to the background. Queue the latest context before the
    /// process is suspended, and keep running if activation is still pending.
    func prepareForBackground() {
        activate()
        onMain {
            self.beginBackgroundTaskIfNeeded()
            self.attemptDelivery()
        }
    }

    private func attemptDelivery() {
        let sessionContext = WCSession.isSupported() ? WCSession.default.applicationContext : [:]
        let resolved = WatchContextSync.base(
            memory: latest,
            persisted: Self.loadPersisted(),
            sessionContext: sessionContext
        )
        let payload = attachingFavorites(resolved)
        guard WatchContextSync.isDeliverable(payload) else {
            finishBackgroundWork()
            return
        }
        latest = payload
        persist(payload)
        guard WCSession.isSupported() else {
            log.error("Watch context not sent: WatchConnectivity is unavailable")
            finishBackgroundWork()
            return
        }
        let readiness = currentReadiness()
        let fingerprint = WatchContextSync.fingerprint(for: payload)
        switch WatchContextSync.decide(fingerprint: fingerprint, state: delivery, readiness: readiness) {
        case .skip:
            loggedHold = nil
            finishBackgroundWork()
        case .hold(let reason):
            logHold(reason)
            if reason == .inactive {
                beginBackgroundTaskIfNeeded()
            } else {
                finishBackgroundWork()
            }
        case .send:
            beginBackgroundTaskIfNeeded()
            send(payload, fingerprint: fingerprint)
        }
    }

    private func send(_ payload: [String: Any], fingerprint: String) {
        do {
            try WCSession.default.updateApplicationContext(payload)
            delivery = WatchContextSync.afterAcceptedSend(delivery, fingerprint: fingerprint)
            loggedHold = nil
            finishBackgroundWork()
        } catch {
            delivery = WatchContextSync.afterFailedSend(delivery)
            logFailure(error)
            if Self.waitsForActivation(error) {
                beginBackgroundTaskIfNeeded()
            } else {
                finishBackgroundWork()
            }
        }
    }

    /// `favorites` is a JSON array of `{name, latitude, longitude}`, deduped
    /// and capped. An empty list is sent as `[]` so the watch clears old rows
    /// when a snapshot is sent with them.
    private func attachingFavorites(_ payload: [String: Any]) -> [String: Any] {
        var payload = payload
        let places = WatchFavoritesPlan.compact(WatchFavoritesReader.load())
        for (key, value) in WatchFavoritesPlan.fields(places) {
            payload[key] = value
        }
        return payload
    }

    private func currentReadiness() -> WatchContextSync.Readiness {
        let session = WCSession.default
        let activated = session.activationState == .activated
        // Pair and install flags are only valid once the session is activated.
        return WatchContextSync.Readiness(
            activated: activated,
            paired: activated && session.isPaired,
            watchAppInstalled: activated && session.isWatchAppInstalled
        )
    }

    private func logHold(_ reason: WatchContextSync.Hold) {
        guard loggedHold != reason else { return }
        loggedHold = reason
        switch reason {
        case .inactive:
            log.debug("\(reason.logLine, privacy: .public)")
        case .notPaired, .watchAppNotInstalled:
            log.error("\(reason.logLine, privacy: .public)")
        }
    }

    private func logFailure(_ error: Error) {
        let ns = error as NSError
        log.error("Watch context update failed (\(ns.domain, privacy: .public) \(ns.code)): \(ns.localizedDescription, privacy: .public)")
    }

    private static func waitsForActivation(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == WCErrorDomain else { return false }
        switch WCError.Code(rawValue: ns.code) {
        case .sessionNotActivated, .sessionInactive:
            return true
        default:
            return false
        }
    }

    private func persist(_ payload: [String: Any]) {
        guard PropertyListSerialization.propertyList(payload, isValidFor: .binary) else {
            log.error("Watch context not stored: payload is not a property list")
            return
        }
        UserDefaults.standard.set(payload, forKey: Self.persistedKey)
    }

    private static func loadPersisted() -> [String: Any]? {
        guard let stored = UserDefaults.standard.dictionary(forKey: persistedKey), !stored.isEmpty else { return nil }
        return stored
    }

    private func beginBackgroundTaskIfNeeded() {
        lock.lock()
        let already = backgroundTask != .invalid
        lock.unlock()
        guard !already else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "WatchContext") { [weak self] in
            self?.finishBackgroundWork()
        }
        lock.lock()
        if backgroundTask == .invalid {
            backgroundTask = task
            lock.unlock()
        } else {
            lock.unlock()
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
    }

    private func finishBackgroundWork() {
        lock.lock()
        let task = backgroundTask
        backgroundTask = .invalid
        lock.unlock()
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Delegate callbacks arrive on a session queue. Sends hop to the main
    /// queue so they do not call back into that queue, and so the background
    /// task is balanced on one thread.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        onMain {
            if let error { self.logFailure(error) }
            guard activationState == .activated else { return }
            self.delivery = WatchContextSync.afterActivation(self.delivery)
            self.attemptDelivery()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        onMain {
            self.delivery = WatchContextSync.afterDeactivation(self.delivery)
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        onMain {
            self.delivery = WatchContextSync.afterDeactivation(self.delivery)
        }
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        onMain {
            let readiness = self.currentReadiness()
            self.delivery = WatchContextSync.afterWatchStateChange(self.delivery, readiness: readiness)
            self.attemptDelivery()
        }
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
