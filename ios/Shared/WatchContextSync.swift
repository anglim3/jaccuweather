import Foundation

/// Decides when the iPhone should call `updateApplicationContext`.
///
/// The bridge keeps the latest payload and applies these rules. Tests cover
/// them without a paired watch. Context keys stay `snapshot`, `favorites`,
/// and the existing `alert*` fields.
enum WatchContextSync {
    struct State: Equatable {
        /// Fingerprint accepted by `updateApplicationContext` for this activation
        /// while the watch could receive it.
        var acceptedFingerprint: String? = nil
        /// Set after activation, deactivation, a failed send, or the watch
        /// becoming able to receive again. Forces one resend of the same payload.
        var mustResend: Bool = true
        /// True after a send was accepted while the watch was paired and the app installed.
        var counterpartReady: Bool = false
    }

    struct Readiness: Equatable {
        var activated: Bool
        var paired: Bool
        var watchAppInstalled: Bool

        var canDeliver: Bool { activated && paired && watchAppInstalled }
    }

    enum Hold: Equatable {
        case inactive
        case notPaired
        case watchAppNotInstalled

        var logLine: String {
            switch self {
            case .inactive:
                return "Watch context waiting for session activation"
            case .notPaired:
                return "Watch context not sent: no paired watch"
            case .watchAppNotInstalled:
                return "Watch context not sent: watch app is not installed"
            }
        }
    }

    enum Decision: Equatable {
        case hold(Hold)
        case skip
        case send
    }

    /// Picks the payload to hand the session.
    ///
    /// A full snapshot in memory replaces anything older, so a cleared alert
    /// does not linger. A favorites update that has no snapshot keeps the
    /// stored snapshot and alert fields instead of wiping them.
    static func base(
        memory: [String: Any]?,
        persisted: [String: Any]?,
        sessionContext: [String: Any]
    ) -> [String: Any] {
        let memory = memory ?? [:]
        if memory[snapshotKey] != nil { return memory }
        if let persisted, persisted[snapshotKey] != nil {
            return merged(update: memory, stored: persisted)
        }
        if sessionContext[snapshotKey] != nil {
            return merged(update: memory, stored: sessionContext)
        }
        if !memory.isEmpty { return memory }
        if let persisted, !persisted.isEmpty { return persisted }
        return sessionContext
    }

    /// A snapshot, or a non-empty favorites list, is worth delivering.
    /// Favorites `[]` alone would replace a previous context with nothing.
    static func isDeliverable(_ payload: [String: Any]) -> Bool {
        if payload[snapshotKey] is String { return true }
        guard let favorites = payload[WatchFavoritesPlan.contextKey] as? String else { return false }
        let trimmed = favorites.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "[]"
    }

    /// Stable identity for dedupe. Key order inside `snapshot` and `favorites`
    /// JSON does not change the result. Favorite row order does.
    static func fingerprint(for payload: [String: Any]) -> String {
        let normalized = normalize(payload)
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "invalid:" + payload.keys.sorted().joined(separator: ",")
        }
        return text
    }

    static func decide(fingerprint: String, state: State, readiness: Readiness) -> Decision {
        guard readiness.activated else { return .hold(.inactive) }
        guard readiness.paired else { return .hold(.notPaired) }
        guard readiness.watchAppInstalled else { return .hold(.watchAppNotInstalled) }
        if state.mustResend || state.acceptedFingerprint != fingerprint { return .send }
        return .skip
    }

    /// A new activation can drop a context that was queued for the previous watch.
    static func afterActivation(_ state: State) -> State {
        var state = state
        state.mustResend = true
        state.counterpartReady = false
        return state
    }

    /// Outstanding transfers are cancelled when the session deactivates.
    static func afterDeactivation(_ state: State) -> State {
        var state = state
        state.mustResend = true
        state.acceptedFingerprint = nil
        state.counterpartReady = false
        return state
    }

    /// `isPaired` and `isWatchAppInstalled` are meaningful only after activation.
    /// Becoming ready again resends. Leaving ready forgets the last accept.
    static func afterWatchStateChange(_ state: State, readiness: Readiness) -> State {
        var state = state
        guard readiness.activated else {
            state.mustResend = true
            return state
        }
        if readiness.canDeliver {
            if !state.counterpartReady { state.mustResend = true }
            return state
        }
        state.mustResend = true
        state.acceptedFingerprint = nil
        state.counterpartReady = false
        return state
    }

    static func afterAcceptedSend(_ state: State, fingerprint: String) -> State {
        var state = state
        state.acceptedFingerprint = fingerprint
        state.mustResend = false
        state.counterpartReady = true
        return state
    }

    static func afterFailedSend(_ state: State) -> State {
        var state = state
        state.mustResend = true
        state.counterpartReady = false
        return state
    }

    private static let snapshotKey = "snapshot"
    /// JSON text on the context, parsed so key order does not change the fingerprint.
    private static let jsonValueKeys: Set<String> = [snapshotKey, WatchFavoritesPlan.contextKey]

    private static func merged(update: [String: Any], stored: [String: Any]) -> [String: Any] {
        var merged = stored
        for (key, value) in update {
            merged[key] = value
        }
        return merged
    }

    private static func normalize(_ payload: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in payload {
            if jsonValueKeys.contains(key), let text = value as? String, let parsed = parsedJSON(text) {
                result[key] = parsed
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func parsedJSON(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if object is NSDictionary || object is NSArray { return object }
        return nil
    }
}
