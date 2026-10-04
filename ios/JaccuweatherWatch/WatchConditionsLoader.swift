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
/// and from Open-Meteo otherwise. Apparent temperature prefers that same
/// fresh phone `feelsLikeF` when the phone already has one for the place.
/// Otherwise Open-Meteo `current.apparent_temperature` fills it, or the
/// nearest hourly `apparent_temperature` when current omits it. The
/// complication passes an empty context and reads the place the glance published.
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
            let filled = await complete(phone, cached: cached)
            publish(filled.snapshot, enabled: publishPlace, explicit: explicit)
            return filled
        }

        if source == .saved, let saved {
            let filled = await complete(saved, cached: cached)
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
            return Reading(
                snapshot: saved,
                hours: cached?.hours ?? [],
                days: cached?.days ?? [],
                sun: displayedSun(snapshot: saved, fetched: cached?.sun)
            )
        }
        return Reading(
            snapshot: place,
            hours: cached?.hours ?? [],
            days: cached?.days ?? [],
            sun: displayedSun(snapshot: place, fetched: cached?.sun)
        )
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
    /// A fresh feels-like on that reading stays. Open-Meteo fills it only
    /// when the reading left it empty.
    /// A cache from before the day sheet or the hour sheet is refreshed so
    /// those precip, condition, and UV fields are stored.
    private static func complete(_ snapshot: WidgetConditionsSnapshot, cached: WatchHourCache.Hit?) async -> Reading {
        let cachedHours = cached?.hours ?? []
        let cachedDays = cached?.days ?? []
        let hoursReady = !cachedHours.isEmpty && !cachedDays.isEmpty
        let sunReady = cached?.sun != nil
        let detailsReady = cached?.includesDayDetail == true && cached?.includesHourDetail == true
        let feelsReady = WatchFeelsLike.usable(snapshot.feelsLikeF) != nil
        if hoursReady && sunReady && detailsReady && WatchAtmosphere.isComplete(snapshot.atmosphereMetrics) && feelsReady {
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
        var merged = snapshot.applyingAtmosphere(
            WatchAtmosphere.preferringExisting(snapshot.atmosphereMetrics, fill: fetched.snapshot.atmosphereMetrics)
        )
        merged.feelsLikeF = WatchFeelsLike.filled(
            existingFeelsLikeF: snapshot.feelsLikeF,
            preferExisting: true,
            openMeteoFeelsLikeF: fetched.snapshot.feelsLikeF
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
