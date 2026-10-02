import Foundation

/// Watch face and complication reading.
///
/// A pinned place (launch argument or complication tap) wins. Otherwise a
/// fresh WatchConnectivity context wins. The complication passes an empty
/// context and reads the place the glance published, then loads
/// `api.open-meteo.com/v1/forecast` for those coordinates.
enum WatchConditionsLoader {
    struct Reading {
        var snapshot: WidgetConditionsSnapshot
        var hours: [WatchHourSlot]
        var days: [WatchDaySlot]
    }

    static func load(
        phoneContext: [String: Any],
        pinned: WatchPlace? = nil,
        publishPlace: Bool = true
    ) async -> Reading {
        let phone = WatchMirrorPayload.snapshot(from: phoneContext)
        let saved = WatchMirrorStore.load()
        let shared = WatchPlaceStore.load()
        let choice = WatchPlacePlan.choose(
            pinned: pinned?.choice(hasReading: false),
            phone: phone?.placeChoice,
            saved: saved?.placeChoice,
            shared: shared?.choice(hasReading: false)
        )
        let place = snapshot(matching: choice, phone: phone, saved: saved, shared: shared)
        let cached = WatchHourCache.load(matching: place)

        if pinned == nil, let phone, phone.isFresh, phone.temperatureF != nil, same(phone, choice) {
            publish(phone, enabled: publishPlace)
            let forecast = await forecast(for: phone, cached: cached)
            return Reading(snapshot: phone, hours: forecast.hours, days: forecast.days)
        }

        if let saved, saved.isFresh, saved.temperatureF != nil, same(saved, choice) {
            publish(saved, enabled: publishPlace)
            let forecast = await forecast(for: saved, cached: cached)
            return Reading(snapshot: saved, hours: forecast.hours, days: forecast.days)
        }

        if publishPlace {
            WatchPlaceStore.save(WatchPlace(place))
        }
        if let fetched = await WatchForecastClient.fetch(place) {
            var snapshot = fetched.snapshot
            if !place.locationName.isEmpty {
                snapshot.locationName = place.locationName
            }
            if !place.locationId.isEmpty {
                snapshot.locationId = place.locationId
            }
            WatchMirrorStore.save(snapshot)
            publish(snapshot, enabled: publishPlace)
            WatchHourCache.save(hours: fetched.hours, days: fetched.days, snapshot: snapshot)
            return Reading(snapshot: snapshot, hours: fetched.hours, days: fetched.days)
        }

        if let saved, saved.temperatureF != nil, same(saved, choice) {
            return Reading(snapshot: saved, hours: cached?.hours ?? [], days: cached?.days ?? [])
        }
        return Reading(snapshot: place, hours: cached?.hours ?? [], days: cached?.days ?? [])
    }

    private static func forecast(for snapshot: WidgetConditionsSnapshot, cached: WatchHourCache.Hit?) async -> (hours: [WatchHourSlot], days: [WatchDaySlot]) {
        if let cached, !cached.hours.isEmpty, !cached.days.isEmpty {
            return (cached.hours, cached.days)
        }
        guard let fetched = await WatchForecastClient.fetch(snapshot) else {
            return (cached?.hours ?? [], cached?.days ?? [])
        }
        WatchHourCache.save(hours: fetched.hours, days: fetched.days, snapshot: snapshot)
        return (fetched.hours, fetched.days)
    }

    private static func publish(_ snapshot: WidgetConditionsSnapshot, enabled: Bool) {
        WatchMirrorStore.save(snapshot)
        guard enabled else { return }
        WatchPlaceStore.save(WatchPlace(snapshot))
    }

    private static func same(_ snapshot: WidgetConditionsSnapshot, _ choice: WatchPlaceChoice) -> Bool {
        WatchPlacePlan.same(snapshot.placeChoice, choice)
    }

    private static func snapshot(
        matching choice: WatchPlaceChoice,
        phone: WidgetConditionsSnapshot?,
        saved: WidgetConditionsSnapshot?,
        shared: WatchPlace?
    ) -> WidgetConditionsSnapshot {
        if let phone, same(phone, choice) { return phone }
        if let saved, same(saved, choice) { return saved }
        if let shared, WatchPlacePlan.same(shared.choice(hasReading: false), choice) {
            return shared.shell()
        }
        return WidgetConditionsSnapshot.shell(
            locationId: choice.locationId,
            locationName: choice.locationName,
            latitude: choice.latitude,
            longitude: choice.longitude
        )
    }
}

extension WatchPlace {
    init(_ snapshot: WidgetConditionsSnapshot) {
        self.init(
            locationId: snapshot.locationId,
            locationName: snapshot.locationName,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude
        )
    }

    func shell() -> WidgetConditionsSnapshot {
        WidgetConditionsSnapshot.shell(
            locationId: locationId,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude
        )
    }
}

extension WidgetConditionsSnapshot {
    var placeChoice: WatchPlaceChoice {
        WatchPlaceChoice(
            locationId: locationId,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            hasReading: temperatureF != nil
        )
    }
}
