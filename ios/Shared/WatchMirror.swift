import Foundation

/// Compact reading the iPhone pushes to the Watch, and the Watch keeps locally.
///
/// Personal Team provisioning cannot create an App Group container, so this
/// store is the process's own UserDefaults. The Watch app and the complication
/// extension each keep their own copy of the conditions. The place they agree
/// on is `watch-place.json` from `WatchPlaceStore`.
enum WatchMirror {
    static let complicationKind = "cloud.janglim.jaccuweather.watch.conditions"
    /// Seattle, the same sample place the iOS widgets use before a forecast lands.
    static let defaultLatitude = 47.6062
    static let defaultLongitude = -122.3321

    static let defaultPlace = WidgetConditionsSnapshot.shell(
        locationId: String(format: "%.4f,%.4f", defaultLatitude, defaultLongitude),
        locationName: "Seattle",
        latitude: defaultLatitude,
        longitude: defaultLongitude
    )

    /// Gallery sample only. Not a live forecast.
    static let placeholder = WidgetConditionsSnapshot(
        locationId: defaultPlace.locationId,
        locationName: "Seattle",
        latitude: defaultLatitude,
        longitude: defaultLongitude,
        temperatureF: 62,
        feelsLikeF: 60,
        weatherCode: 2,
        isDay: true,
        conditionText: "Partly cloudy",
        symbolName: "cloud.sun.fill",
        precipChance: nil,
        highF: nil,
        lowF: nil,
        nextHoursHint: "",
        fetchedAt: Date()
    )

    static func samePlace(_ lhs: WidgetConditionsSnapshot, _ rhs: WidgetConditionsSnapshot) -> Bool {
        if !lhs.locationId.isEmpty, lhs.locationId == rhs.locationId { return true }
        return abs(lhs.latitude - rhs.latitude) < 0.01 && abs(lhs.longitude - rhs.longitude) < 0.01
    }
}

enum WatchMirrorPayload {
    static func dictionary(from snapshot: WidgetConditionsSnapshot) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return [:] }
        return ["snapshot": json]
    }

    static func snapshot(from dictionary: [String: Any]) -> WidgetConditionsSnapshot? {
        guard let json = dictionary["snapshot"] as? String,
              let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetConditionsSnapshot.self, from: data)
    }
}

enum WatchMirrorStore {
    private static let key = "jaccuweather.watch.mirror"

    static func load() -> WidgetConditionsSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetConditionsSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetConditionsSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
