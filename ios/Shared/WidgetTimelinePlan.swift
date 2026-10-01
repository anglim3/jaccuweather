import Foundation

/// Decides which reading a widget timeline may show.
/// The app writes one App Group snapshot for the place it has open.
/// A widget configured for a different place must not display that snapshot.
enum WidgetTimelinePlan: Equatable {
    /// The snapshot is fresh and it belongs to this widget.
    case useSnapshot
    /// Load the configured place from Open-Meteo.
    case fetchConfiguredPlace
    /// Refresh the snapshot's own coordinates. Only when that snapshot is this widget's place.
    case refreshSnapshot
    /// The refresh failed. Keep the last reading while it is still inside the stale window.
    case keepStaleSnapshot
    /// A place was chosen and neither a matching snapshot nor Open-Meteo produced a reading.
    case unavailable
    /// No chosen place and no snapshot.
    case empty

    /// App snapshots store `locationId` as four-decimal coordinates (`47.6062,-122.3321`).
    /// Widget configuration ids are five-decimal coordinates plus a name (`47.60620,-122.33210|…`).
    /// Compare the coordinates, not the raw id strings.
    static func samePlace(
        snapshotLatitude: Double,
        snapshotLongitude: Double,
        snapshotLocationId: String,
        placeLatitude: Double,
        placeLongitude: Double,
        placeId: String
    ) -> Bool {
        if !snapshotLocationId.isEmpty, snapshotLocationId == placeId { return true }
        let snapshotKey = placeKey(latitude: snapshotLatitude, longitude: snapshotLongitude)
        let placeKey = placeKey(latitude: placeLatitude, longitude: placeLongitude)
        if snapshotKey == placeKey { return true }
        return snapshotLocationId == placeKey
    }

    static func placeKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// First choice before any network call.
    /// `snapshotMatchesPlace` is ignored when the widget has no chosen place: it follows the app.
    static func decide(
        hasSnapshot: Bool,
        snapshotFresh: Bool,
        hasConfiguredPlace: Bool,
        snapshotMatchesPlace: Bool
    ) -> WidgetTimelinePlan {
        let aligned = hasSnapshot && (!hasConfiguredPlace || snapshotMatchesPlace)
        if aligned && snapshotFresh { return .useSnapshot }
        if hasConfiguredPlace { return .fetchConfiguredPlace }
        if hasSnapshot { return .refreshSnapshot }
        return .empty
    }

    /// What to do after the configured-place fetch fails.
    /// A snapshot for a different place is not a fallback.
    static func afterFailedFetch(
        hasSnapshot: Bool,
        snapshotMatchesPlace: Bool,
        hasConfiguredPlace: Bool
    ) -> WidgetTimelinePlan {
        if hasSnapshot && (!hasConfiguredPlace || snapshotMatchesPlace) {
            return .refreshSnapshot
        }
        if hasConfiguredPlace { return .unavailable }
        return .empty
    }

    /// What to do after refreshing the matching snapshot fails.
    static func afterFailedRefresh(
        hasConfiguredPlace: Bool,
        withinStaleWindow: Bool
    ) -> WidgetTimelinePlan {
        if withinStaleWindow { return .keepStaleSnapshot }
        if hasConfiguredPlace { return .unavailable }
        return .empty
    }
}
