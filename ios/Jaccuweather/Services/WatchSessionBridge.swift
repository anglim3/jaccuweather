import Foundation
import WatchConnectivity

/// Sends the latest in-app forecast to the paired Watch.
/// A missing watch, or a session that is not activated yet, is ignored.
final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    private let lock = NSLock()
    private var pending: [String: Any]?
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

    func push(_ snapshot: WidgetConditionsSnapshot) {
        guard snapshot.temperatureF != nil else { return }
        activate()
        deliver(WatchMirrorPayload.dictionary(from: snapshot))
    }

    private func deliver(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            store(payload)
            return
        }
        guard session.isPaired else { return }
        do {
            try session.updateApplicationContext(payload)
            store(nil)
        } catch {
            store(payload)
        }
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
