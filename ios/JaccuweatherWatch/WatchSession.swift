import Foundation
import Observation
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchWeatherModel {
    var snapshot: WidgetConditionsSnapshot
    var hours: [WatchHourSlot] = []
    var days: [WatchDaySlot] = []
    var sun: WatchSunTimes?
    var alert: WatchAlertSummary?
    var favorites: [WatchFavoritePlace] = []
    private let hub = WatchSessionHub()
    private var generation = 0
    private var pinned: WatchPlace?

    init() {
        snapshot = WatchMirrorStore.load() ?? WatchMirror.defaultPlace
        if let launch = WatchLaunchPlace.pinned() {
            pinned = launch
            snapshot = launch.shell()
        }
        favorites = WatchFavoritesSample.places(in: [:])
    }

    /// Current place, then phone favorites that are not that same coordinate.
    var places: [WatchFavoritePlace] {
        WatchFavoritesPlan.switcher(
            current: WatchFavoritePlace(
                name: placeName,
                latitude: snapshot.latitude,
                longitude: snapshot.longitude
            ),
            favorites: favorites
        )
    }

    func isSelected(_ place: WatchFavoritePlace) -> Bool {
        WatchFavoritesPlan.sameCoordinates(
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            otherLatitude: place.latitude,
            otherLongitude: place.longitude
        )
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
        if let dew = WatchDewPoint.chip(fahrenheit: snapshot.dewPointF) {
            parts.append(dew.spoken)
        }
        if !detailText.isEmpty, detailText != "Updating" { parts.append(detailText) }
        if !conditionText.isEmpty { parts.append(conditionText) }
        if let aqi = WatchAQI.chip(usAqi: snapshot.usAqi, category: snapshot.usAqiCategory) {
            parts.append(aqi.spoken)
        }
        let atmosphere = snapshot.atmosphereMetrics
        if let uv = WatchAtmosphere.uvChip(atmosphere) { parts.append(uv.spoken) }
        if let wind = WatchAtmosphere.windChip(atmosphere) { parts.append(wind.spoken) }
        if let humidity = WatchAtmosphere.humidityLine(atmosphere) { parts.append(humidity.spoken) }
        let upcoming = hours.prefix(4).map { slot in
            let degrees = slot.temperatureF.map { "\(Int($0.rounded()))°" } ?? "—"
            return "\(slot.label) \(degrees)"
        }
        if !upcoming.isEmpty {
            parts.append(upcoming.joined(separator: ", "))
        }
        let upcomingDays = days.prefix(4).map { day in
            let high = day.highF.map { "\(Int($0.rounded()))°" } ?? "—"
            let low = day.lowF.map { "\(Int($0.rounded()))°" } ?? "—"
            return "\(day.label) \(high) \(low)"
        }
        if !upcomingDays.isEmpty {
            parts.append(upcomingDays.joined(separator: ", "))
        }
        if let sun, sun.hasAny, !sun.spoken.isEmpty {
            parts.append(sun.spoken)
        }
        if let alert {
            if alert.count > 1 {
                parts.append("\(alert.count) alerts, \(alert.title), \(alert.severity)")
            } else {
                parts.append("\(alert.title), \(alert.severity)")
            }
        }
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

    /// Complication tap, or `jaccuweather://place?...` from the simulator.
    func open(_ url: URL) {
        guard var place = WatchPlaceLink.place(from: url) else { return }
        place.explicit = true
        show(place)
    }

    /// Favorites row. Writes `watch-place.json` before the forecast returns
    /// so the complication can move with the pick.
    func select(_ favorite: WatchFavoritePlace) {
        show(WatchPlace(
            locationId: String(format: "%.4f,%.4f", favorite.latitude, favorite.longitude),
            locationName: favorite.name,
            latitude: favorite.latitude,
            longitude: favorite.longitude,
            explicit: true
        ))
    }

    private func show(_ place: WatchPlace) {
        let changed = !WatchFavoritesPlan.sameCoordinates(
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            otherLatitude: place.latitude,
            otherLongitude: place.longitude
        )
        pinned = place
        if changed {
            snapshot = place.shell()
            hours = []
            days = []
            sun = nil
            alert = nil
        } else if snapshot.locationName != place.locationName {
            snapshot.locationName = place.locationName
        }
        WatchPlaceStore.save(place)
        WidgetCenter.shared.reloadTimelines(ofKind: WatchMirror.complicationKind)
        Task { await refresh() }
    }

    func refresh() async {
        generation += 1
        let token = generation
        let context = WatchAlertSample.context(hub.context)
        favorites = WatchFavoritesSample.places(in: context)
        let reading = await WatchConditionsLoader.load(phoneContext: context, pinned: pinned, publishPlace: true)
        guard token == generation else { return }
        snapshot = reading.snapshot
        hours = reading.hours
        days = reading.days
        sun = reading.sun
        alert = Self.alert(from: context, displayed: reading.snapshot)
        #if DEBUG
        WatchPlaceStore.writeProbe(role: "app")
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: WatchMirror.complicationKind)
    }

    /// The badge follows the phone payload for the place on screen.
    /// A payload for a different city, or one missing title, severity, or count, stays quiet.
    private static func alert(from context: [String: Any], displayed: WidgetConditionsSnapshot) -> WatchAlertSummary? {
        guard let summary = WatchAlertPayload.summary(from: context) else { return nil }
        if let phone = WatchMirrorPayload.snapshot(from: context), !WatchMirror.samePlace(phone, displayed) {
            return nil
        }
        return summary
    }

    private static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

enum WatchFavoritesSample {
    /// Debug launches can seed a phone favorites list with `-watchFavoritesSample 1`
    /// when the context has no `favorites` field. `-watchPlaces 1` opens the list.
    static var presentsList: Bool {
        #if DEBUG
        return flag("watchPlaces")
        #else
        return false
        #endif
    }

    static func places(in context: [String: Any]) -> [WatchFavoritePlace] {
        let decoded = WatchFavoritesPlan.places(from: context)
        #if DEBUG
        if !decoded.isEmpty || !flag("watchFavoritesSample") { return decoded }
        return WatchFavoritesPlan.compact([
            WatchFavoritesPlan.Input(name: "Portland", latitude: 45.5152, longitude: -122.6784),
            WatchFavoritesPlan.Input(name: "Denver", latitude: 39.7392, longitude: -104.9903),
            WatchFavoritesPlan.Input(name: "Juneau", latitude: 58.3019, longitude: -134.4197)
        ])
        #else
        return decoded
        #endif
    }

    #if DEBUG
    private static func flag(_ name: String) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-\(name)"), index + 1 < args.count else { return false }
        return args[index + 1] == "1"
    }
    #endif
}

enum WatchDayDetailLaunch {
    /// Debug launches can open the first day sheet with `-watchDayDetail 1`.
    static var opensFirst: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-watchDayDetail"), index + 1 < args.count else { return false }
        return args[index + 1] == "1"
        #else
        return false
        #endif
    }
}

enum WatchHourDetailLaunch {
    /// Debug launches can open the first hour sheet with `-watchHourDetail 1`.
    static var opensFirst: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-watchHourDetail"), index + 1 < args.count else { return false }
        return args[index + 1] == "1"
        #else
        return false
        #endif
    }
}

enum WatchAlertSample {
    /// Debug launches can seed a phone payload with `-watchAlertSample 1`.
    /// A context that already has title, severity, and count is left as the phone sent it.
    /// Pair with `-name Juneau -lat 58.3019 -lon -134.4197` to pin that city.
    /// `-watchAlertDetail 1` opens the sheet once an alert is on screen.
    static var presentsDetail: Bool {
        #if DEBUG
        return flag("watchAlertDetail")
        #else
        return false
        #endif
    }

    static func context(_ base: [String: Any]) -> [String: Any] {
        #if DEBUG
        guard flag("watchAlertSample") else { return base }
        if WatchAlertPayload.summary(from: base) != nil { return base }
        var merged = base
        // A leftover phone snapshot for another city would hide this sample.
        merged.removeValue(forKey: "snapshot")
        merged[WatchAlertPayload.titleKey] = "Wind Advisory"
        merged[WatchAlertPayload.severityKey] = "Moderate"
        merged[WatchAlertPayload.countKey] = 2
        merged[WatchAlertPayload.eventKey] = "Wind Advisory"
        merged[WatchAlertPayload.headlineKey] = "Wind Advisory for Juneau until Saturday evening"
        merged[WatchAlertPayload.endsKey] = "Ends Oct 3, 6:00 PM"
        merged[WatchAlertPayload.instructionKey] = "Secure loose outdoor objects."
        return merged
        #else
        return base
        #endif
    }

    #if DEBUG
    private static func flag(_ name: String) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-\(name)"), index + 1 < args.count else { return false }
        return args[index + 1] == "1"
    }
    #endif
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
