import Foundation

/// Coordinates the glance and the complication agree on.
struct WatchPlace: Codable, Equatable {
    var locationId: String
    var locationName: String
    var latitude: Double
    var longitude: Double

    func choice(hasReading: Bool) -> WatchPlaceChoice {
        WatchPlaceChoice(
            locationId: locationId,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            hasReading: hasReading
        )
    }
}

struct WatchPlaceChoice: Equatable {
    var locationId: String
    var locationName: String
    var latitude: Double
    var longitude: Double
    var hasReading: Bool
}

/// Which place the Watch face or the complication should load.
///
/// A shared place from the glance wins over the complication's own last
/// reading when they differ, so the complication does not stay on the sample
/// city after the glance has moved.
enum WatchPlacePlan {
    static let defaultLatitude = 47.6062
    static let defaultLongitude = -122.3321

    static var seattle: WatchPlaceChoice {
        WatchPlaceChoice(
            locationId: String(format: "%.4f,%.4f", defaultLatitude, defaultLongitude),
            locationName: "Seattle",
            latitude: defaultLatitude,
            longitude: defaultLongitude,
            hasReading: false
        )
    }

    static func same(_ lhs: WatchPlaceChoice, _ rhs: WatchPlaceChoice) -> Bool {
        if !lhs.locationId.isEmpty, lhs.locationId == rhs.locationId { return true }
        return abs(lhs.latitude - rhs.latitude) < 0.01 && abs(lhs.longitude - rhs.longitude) < 0.01
    }

    static func choose(
        pinned: WatchPlaceChoice?,
        phone: WatchPlaceChoice?,
        saved: WatchPlaceChoice?,
        shared: WatchPlaceChoice?
    ) -> WatchPlaceChoice {
        if let pinned { return pinned }
        if let phone, phone.hasReading { return phone }
        if let shared {
            if let saved, saved.hasReading, same(saved, shared) { return saved }
            return shared
        }
        if let phone { return phone }
        if let saved { return saved }
        return seattle
    }
}
