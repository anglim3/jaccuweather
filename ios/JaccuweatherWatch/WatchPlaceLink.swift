import Foundation

/// Complication tap URL. The Watch app opens the glance for that place.
enum WatchPlaceLink {
    static func url(for place: WatchPlace) -> URL? {
        var components = URLComponents()
        components.scheme = "jaccuweather"
        components.host = "place"
        components.queryItems = [
            URLQueryItem(name: "name", value: place.locationName),
            URLQueryItem(name: "lat", value: String(place.latitude)),
            URLQueryItem(name: "lon", value: String(place.longitude)),
            URLQueryItem(name: "id", value: place.locationId)
        ]
        return components.url
    }

    static func place(from url: URL) -> WatchPlace? {
        guard url.scheme == "jaccuweather", url.host == "place" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let latitude = value("lat").flatMap(Double.init),
              let longitude = value("lon").flatMap(Double.init),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        let trimmed = value("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? "Place" : trimmed
        let rawID = value("id")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let locationId = rawID.isEmpty ? String(format: "%.4f,%.4f", latitude, longitude) : rawID
        return WatchPlace(
            locationId: locationId,
            locationName: name,
            latitude: latitude,
            longitude: longitude
        )
    }
}

enum WatchLaunchPlace {
    /// Simulator launches can pin a city with `-name Chicago -lat 41.8781 -lon -87.6298`.
    static func pinned() -> WatchPlace? {
        let args = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            guard let index = args.firstIndex(of: "-\(name)"), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        guard let latitude = value("lat").flatMap(Double.init),
              let longitude = value("lon").flatMap(Double.init),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        let trimmed = value("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? "Place" : trimmed
        return WatchPlace(
            locationId: String(format: "%.4f,%.4f", latitude, longitude),
            locationName: name,
            latitude: latitude,
            longitude: longitude
        )
    }
}
