import Foundation
import Observation
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchWeatherModel {
    var snapshot: WidgetConditionsSnapshot
    private let hub = WatchSessionHub()
    private var generation = 0

    init() {
        snapshot = WatchMirrorStore.load() ?? WatchMirror.defaultPlace
    }

    var placeName: String {
        snapshot.locationName.isEmpty ? "Jaccuweather" : snapshot.locationName
    }

    var symbolName: String {
        snapshot.symbolName.isEmpty ? "cloud.fill" : snapshot.symbolName
    }

    var temperatureText: String {
        Self.degrees(snapshot.temperatureF)
    }

    /// Feels-like when the forecast has it, otherwise the condition.
    var detailText: String {
        if snapshot.temperatureF == nil { return "Updating" }
        if let feels = snapshot.feelsLikeF, feels.isFinite {
            return "Feels \(Self.degrees(feels))"
        }
        if !snapshot.conditionText.isEmpty { return snapshot.conditionText }
        return ""
    }

    var conditionText: String {
        if snapshot.temperatureF == nil { return "" }
        if snapshot.feelsLikeF != nil { return snapshot.conditionText }
        return ""
    }

    var accessibilityLabel: String {
        var parts = [placeName, temperatureText]
        if !detailText.isEmpty, detailText != "Updating" { parts.append(detailText) }
        if !conditionText.isEmpty { parts.append(conditionText) }
        return parts.joined(separator: ", ")
    }

    func start() async {
        hub.onContext = { [weak self] in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        hub.activate()
        await refresh()
    }

    func refresh() async {
        generation += 1
        let token = generation
        let next = await WatchConditionsLoader.load(phoneContext: hub.context)
        guard token == generation else { return }
        snapshot = next
        WidgetCenter.shared.reloadTimelines(ofKind: WatchMirror.complicationKind)
    }

    private static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

final class WatchSessionHub: NSObject, WCSessionDelegate {
    var onContext: (() -> Void)?
    private var started = false

    var context: [String: Any] {
        guard WCSession.isSupported() else { return [:] }
        return WCSession.default.receivedApplicationContext
    }

    func activate() {
        guard WCSession.isSupported(), !started else { return }
        started = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated { onContext?() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        onContext?()
    }
}
