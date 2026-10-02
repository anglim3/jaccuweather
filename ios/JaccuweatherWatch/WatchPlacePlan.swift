import Foundation

/// Coordinates the glance and the complication agree on.
struct WatchPlace: Codable, Equatable {
    var locationId: String
    var locationName: String
    var latitude: Double
    var longitude: Double
    /// True after a person picks a place on the watch. That file then stays
    /// ahead of the phone's current city. Older files omit the flag.
    var explicit: Bool

    init(locationId: String, locationName: String, latitude: Double, longitude: Double, explicit: Bool = false) {
        self.locationId = locationId
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.explicit = explicit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        locationId = try container.decode(String.self, forKey: .locationId)
        locationName = try container.decode(String.self, forKey: .locationName)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(locationId, forKey: .locationId)
        try container.encode(locationName, forKey: .locationName)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(explicit, forKey: .explicit)
    }

    func choice(hasReading: Bool) -> WatchPlaceChoice {
        WatchPlaceChoice(
            locationId: locationId,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            hasReading: hasReading
        )
    }

    private enum CodingKeys: String, CodingKey {
        case locationId, locationName, latitude, longitude, explicit
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
/// city after the glance has moved. An explicit shared place is a selection
/// the person made on the watch, and it stays ahead of a newer phone city.
/// Without that flag, a phone reading still wins.
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
        shared: WatchPlaceChoice?,
        sharedExplicit: Bool = false
    ) -> WatchPlaceChoice {
        if let pinned { return pinned }
        if sharedExplicit, let shared { return shared }
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

/// Where the glance reads conditions for the place it already chose.
///
/// A fresh phone context for that place wins, including when the person
/// pinned the place. Otherwise a fresh saved reading. Otherwise Open-Meteo.
enum WatchConditionsSource: Equatable {
    case phone
    case saved
    case fetch

    static func pick(phoneMatchesAndFresh: Bool, savedMatchesAndFresh: Bool) -> WatchConditionsSource {
        if phoneMatchesAndFresh { return .phone }
        if savedMatchesAndFresh { return .saved }
        return .fetch
    }
}
