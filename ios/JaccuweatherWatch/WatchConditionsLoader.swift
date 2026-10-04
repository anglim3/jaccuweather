import Foundation

/// Watch face and complication reading.
///
/// A pinned place (launch argument, complication tap, or favorites pick)
/// wins. A place the person already picked, stored in `watch-place.json`,
/// stays ahead of the phone's current city. Otherwise a fresh
/// WatchConnectivity context wins. Conditions for that place come from the
/// phone context when it is still fresh, then from the saved reading, then
/// from `api.open-meteo.com/v1/forecast`. Today's sunrise and sunset use a
/// fresh snapshot's `sunriseISO` and `sunsetISO` when those stamps are
/// present, and otherwise the Open-Meteo daily row for that same place.
/// UV and wind come from that fresh phone snapshot when it includes them,
/// and from Open-Meteo otherwise. US AQI uses a fresh snapshot's `usAqi`
/// when that field is present, and otherwise Open-Meteo air quality for the
/// same coordinates. The complication passes an empty context and reads the
/// place the glance published. It does not request air quality.
enum WatchConditionsLoader {
    struct Reading {
        var snapshot: WidgetConditionsSnapshot
        var hours: [WatchHourSlot]
        var days: [WatchDaySlot]
        var sun: WatchSunTimes?
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
            shared: shared?.choice(hasReading: false),
            sharedExplicit: shared?.explicit == true
        )
        let place = snapshot(matching: choice, phone: phone, saved: saved, shared: shared)
        let cached = WatchHourCache.load(matching: place)
        let explicit = keepsExplicitSelection(pinned: pinned, shared: shared, choice: choice)
        let source = WatchConditionsSource.pick(
            phoneMatchesAndFresh: phone.map { $0.isFresh && $0.temperatureF != nil && same($0, choice) } ?? false,
            savedMatchesAndFresh: saved.map { $0.isFresh && $0.temperatureF != nil && same($0, choice) } ?? false
        )

        if source == .phone, let phone {
            var filled = await complete(phone, cached: cached)
            filled.snapshot = await withAirQuality(filled.snapshot, enabled: publishPlace)
            publish(filled.snapshot, enabled: publishPlace, explicit: explicit)
            return filled
        }

        if source == .saved, let saved {
            var filled = await complete(saved, cached: cached)
            filled.snapshot = await withAirQuality(filled.snapshot, enabled: publishPlace)
            publish(filled.snapshot, enabled: publishPlace, explicit: explicit)
            return filled
        }

        if publishPlace {
            WatchPlaceStore.save(WatchPlace(place, explicit: explicit))
        }
        if let fetched = await WatchForecastClient.fetch(place) {
            var snapshot = fetched.snapshot
            if !place.locationName.isEmpty {
                snapshot.locationName = place.locationName
            }
            if !place.locationId.isEmpty {
                snapshot.locationId = place.locationId
            }
            snapshot = await withAirQuality(snapshot, enabled: publishPlace)
            WatchMirrorStore.save(snapshot)
            publish(snapshot, enabled: publishPlace, explicit: explicit)
            WatchHourCache.save(hours: fetched.hours, days: fetched.days, sun: fetched.sun, snapshot: snapshot)
            return Reading(
                snapshot: snapshot,
                hours: fetched.hours,
                days: fetched.days,
                sun: displayedSun(snapshot: snapshot, fetched: fetched.sun)
            )
        }

        if let saved, saved.temperatureF != nil, same(saved, choice) {
            let shown = await withAirQuality(saved, enabled: publishPlace)
            if publishPlace, shown.usAqi != nil {
                WatchMirrorStore.save(shown)
            }
            return Reading(
                snapshot: shown,
                hours: cached?.hours ?? [],
                days: cached?.days ?? [],
                sun: displayedSun(snapshot: shown, fetched: cached?.sun)
            )
        }
        let shown = await withAirQuality(place, enabled: publishPlace)
        return Reading(
            snapshot: shown,
            hours: cached?.hours ?? [],
            days: cached?.days ?? [],
            sun: displayedSun(snapshot: shown, fetched: cached?.sun)
        )
    }

    /// Keep a usable `usAqi` already on the snapshot. Otherwise ask Open-Meteo
    /// air quality. A failed or empty response leaves the chip hidden.
    /// The complication skips this request.
    private static func withAirQuality(_ snapshot: WidgetConditionsSnapshot, enabled: Bool) async -> WidgetConditionsSnapshot {
        guard enabled else { return snapshot }
        if WatchAQI.chip(usAqi: snapshot.usAqi, category: snapshot.usAqiCategory) != nil {
            return snapshot
        }
        guard let value = await WatchAirQualityClient.current(latitude: snapshot.latitude, longitude: snapshot.longitude),
              WatchAQI.chip(usAqi: value) != nil else {
            return snapshot
        }
        var copy = snapshot
        copy.usAqi = value
        copy.usAqiCategory = WatchAQI.chip(usAqi: value)?.category
        return copy
    }

    /// A fresh snapshot that already includes sunrise and sunset wins.
    /// Otherwise the Open-Meteo daily row for this place is used.
    private static func displayedSun(snapshot: WidgetConditionsSnapshot, fetched: WatchSunTimes?) -> WatchSunTimes? {
        if snapshot.isFresh, let carried = WatchSunPlan.carried(sunriseISO: snapshot.sunriseISO, sunsetISO: snapshot.sunsetISO) {
            return carried
        }
        guard let fetched, fetched.hasAny else { return nil }
        return fetched
    }

    /// Hours, days, and sun come from the cache when they are already stored.
    /// UV and wind stay on the phone or saved reading when those fields are
    /// present, and Open-Meteo fills whichever of them is missing.
    /// A cache from before the day sheet or the hour sheet is refreshed so
    /// those precip, condition, and UV fields are stored.
    private static func complete(_ snapshot: WidgetConditionsSnapshot, cached: WatchHourCache.Hit?) async -> Reading {
        let cachedHours = cached?.hours ?? []
        let cachedDays = cached?.days ?? []
        let hoursReady = !cachedHours.isEmpty && !cachedDays.isEmpty
        let sunReady = cached?.sun != nil
        let detailsReady = cached?.includesDayDetail == true && cached?.includesHourDetail == true
        if hoursReady && sunReady && detailsReady && WatchAtmosphere.isComplete(snapshot.atmosphereMetrics) {
            return Reading(
                snapshot: snapshot,
                hours: cachedHours,
                days: cachedDays,
                sun: displayedSun(snapshot: snapshot, fetched: cached?.sun)
            )
        }
        guard let fetched = await WatchForecastClient.fetch(snapshot) else {
            return Reading(
                snapshot: snapshot,
                hours: cachedHours,
                days: cachedDays,
                sun: displayedSun(snapshot: snapshot, fetched: cached?.sun)
            )
        }
        let merged = snapshot.applyingAtmosphere(
            WatchAtmosphere.preferringExisting(snapshot.atmosphereMetrics, fill: fetched.snapshot.atmosphereMetrics)
        )
        WatchHourCache.save(hours: fetched.hours, days: fetched.days, sun: fetched.sun, snapshot: merged)
        return Reading(
            snapshot: merged,
            hours: fetched.hours,
            days: fetched.days,
            sun: displayedSun(snapshot: merged, fetched: fetched.sun)
        )
    }

    private static func publish(_ snapshot: WidgetConditionsSnapshot, enabled: Bool, explicit: Bool) {
        WatchMirrorStore.save(snapshot)
        guard enabled else { return }
        WatchPlaceStore.save(WatchPlace(snapshot, explicit: explicit))
    }

    /// A pick on the watch, or a file that already recorded one, stays explicit
    /// when this load is still showing that place.
    private static func keepsExplicitSelection(
        pinned: WatchPlace?,
        shared: WatchPlace?,
        choice: WatchPlaceChoice
    ) -> Bool {
        if pinned?.explicit == true { return true }
        guard pinned == nil, let shared, shared.explicit else { return false }
        return WatchPlacePlan.same(shared.choice(hasReading: false), choice)
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
    init(_ snapshot: WidgetConditionsSnapshot, explicit: Bool = false) {
        self.init(
            locationId: snapshot.locationId,
            locationName: snapshot.locationName,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            explicit: explicit
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
