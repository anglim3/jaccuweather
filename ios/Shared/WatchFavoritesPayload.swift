import Foundation

/// One saved place on the WatchConnectivity application context.
///
/// The phone sends `favorites`: a JSON array of `{name, latitude, longitude}`.
/// Names are the favorite's display name. Coordinates are deduped with the
/// same id the iPhone favorites list uses (`"\(latitude),\(longitude)"`),
/// first row kept. The array is capped so the context stays small.
struct WatchFavoritePlace: Codable, Equatable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double

    var id: String { WatchFavoritesPlan.coordinateID(latitude: latitude, longitude: longitude) }
}

enum WatchFavoritesPlan {
    static let contextKey = "favorites"
    /// Twelve rows is enough for a watch list and stays far under the
    /// WatchConnectivity context limit.
    static let cap = 12
    static let maxNameLength = 48

    struct Input: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    /// Same identity `GeoResult.id` uses for favorite dedupe.
    static func coordinateID(latitude: Double, longitude: Double) -> String {
        "\(latitude),\(longitude)"
    }

    static func sameCoordinates(
        latitude: Double,
        longitude: Double,
        otherLatitude: Double,
        otherLongitude: Double
    ) -> Bool {
        coordinateID(latitude: latitude, longitude: longitude)
            == coordinateID(latitude: otherLatitude, longitude: otherLongitude)
    }

    /// Drops blank names and coordinates outside the valid range, collapses
    /// duplicate coordinates, then keeps the first `limit` rows.
    static func compact(_ places: [Input], limit: Int = cap) -> [WatchFavoritePlace] {
        let capped = max(0, limit)
        var seen = Set<String>()
        var rows: [WatchFavoritePlace] = []
        for place in places {
            guard rows.count < capped else { break }
            guard place.latitude.isFinite, place.longitude.isFinite else { continue }
            guard (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else { continue }
            guard let name = clippedName(place.name) else { continue }
            let id = coordinateID(latitude: place.latitude, longitude: place.longitude)
            guard seen.insert(id).inserted else { continue }
            rows.append(WatchFavoritePlace(name: name, latitude: place.latitude, longitude: place.longitude))
        }
        return rows
    }

    static func fields(_ places: [WatchFavoritePlace]) -> [String: Any] {
        guard let json = jsonString(places) else { return [:] }
        return [contextKey: json]
    }

    static func places(from dictionary: [String: Any]) -> [WatchFavoritePlace] {
        guard let json = dictionary[contextKey] as? String, let data = json.data(using: .utf8) else { return [] }
        guard let decoded = try? JSONDecoder().decode([WatchFavoritePlace].self, from: data) else { return [] }
        return compact(decoded.map { Input(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) })
    }

    /// Current place first, then favorites that are not that same coordinate.
    static func switcher(current: WatchFavoritePlace, favorites: [WatchFavoritePlace]) -> [WatchFavoritePlace] {
        let currentRow = compact(
            [Input(name: current.name, latitude: current.latitude, longitude: current.longitude)],
            limit: 1
        )
        let head: WatchFavoritePlace
        if let currentRow = currentRow.first {
            head = currentRow
        } else if current.latitude.isFinite, current.longitude.isFinite,
                  (-90...90).contains(current.latitude), (-180...180).contains(current.longitude) {
            head = WatchFavoritePlace(name: "Place", latitude: current.latitude, longitude: current.longitude)
        } else {
            head = WatchFavoritePlace(name: "Place", latitude: 0, longitude: 0)
        }
        let rest = compact(favorites.map { Input(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) })
        return [head] + rest.filter { $0.id != head.id }
    }

    static func clippedName(_ name: String) -> String? {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix(",") { return nil }
        if text.count > maxNameLength {
            text = String(text.prefix(maxNameLength))
        }
        return text
    }

    private static func jsonString(_ places: [WatchFavoritePlace]) -> String? {
        guard let data = try? JSONEncoder().encode(places) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
