import Foundation

/// Watch face and complication reading.
///
/// A fresh WatchConnectivity context wins. Otherwise this fetches
/// `api.open-meteo.com/v1/forecast` for the last saved place. The complication
/// extension passes an empty context: Personal Team cannot share an App Group
/// with the Watch app, so the complication keeps its own last place.
enum WatchConditionsLoader {
    static func load(phoneContext: [String: Any]) async -> WidgetConditionsSnapshot {
        let phone = WatchMirrorPayload.snapshot(from: phoneContext)
        if let phone, phone.isFresh, phone.temperatureF != nil {
            WatchMirrorStore.save(phone)
            return phone
        }
        let saved = WatchMirrorStore.load()
        let place = phone ?? saved ?? WatchMirror.defaultPlace
        if let saved, saved.isFresh, saved.temperatureF != nil, WatchMirror.samePlace(saved, place) {
            return saved
        }
        let name = place.locationName.isEmpty ? WatchMirror.defaultPlace.locationName : place.locationName
        if let fetched = await WidgetCurrentRefresh.fetch(
            name: name,
            latitude: place.latitude,
            longitude: place.longitude,
            locationId: place.locationId
        ) {
            WatchMirrorStore.save(fetched)
            return fetched
        }
        if let saved, saved.temperatureF != nil { return saved }
        if let phone, phone.temperatureF != nil { return phone }
        return place
    }
}
