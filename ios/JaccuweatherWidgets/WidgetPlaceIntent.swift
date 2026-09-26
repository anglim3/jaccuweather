import AppIntents
import Foundation

/// A city or coordinate pair chosen in the widget editor. The identifier carries
/// the name and coordinates so the extension can rebuild the place without another lookup.
struct WidgetPlace: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Place")
    static var defaultQuery = WidgetPlaceQuery()

    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static func make(name: String, latitude: Double, longitude: Double) -> WidgetPlace {
        let lat = (latitude * 100_000).rounded() / 100_000
        let lon = (longitude * 100_000).rounded() / 100_000
        let encoded = Data(name.utf8).base64EncodedString()
        let id = String(format: "%.5f,%.5f|%@", lat, lon, encoded)
        return WidgetPlace(id: id, name: name, latitude: lat, longitude: lon)
    }

    static func decode(_ id: String) -> WidgetPlace? {
        guard let bar = id.firstIndex(of: "|") else { return nil }
        let coords = id[..<bar].split(separator: ",")
        guard coords.count == 2,
              let latitude = Double(coords[0]),
              let longitude = Double(coords[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        let encoded = String(id[id.index(after: bar)...])
        guard let data = Data(base64Encoded: encoded),
              let name = String(data: data, encoding: .utf8),
              !name.isEmpty else { return nil }
        return WidgetPlace(id: id, name: name, latitude: latitude, longitude: longitude)
    }

    /// Accepts `47.61, -122.33`, `47.61 -122.33`, or `47.61,-122.33`.
    static func coordinate(from text: String) -> WidgetPlace? {
        let parts = coordinateParts(text)
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return nil }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let name = String(format: "%.2f, %.2f", latitude, longitude)
        return make(name: name, latitude: latitude, longitude: longitude)
    }

    static func looksLikeCoordinates(_ text: String) -> Bool {
        let parts = coordinateParts(text)
        return parts.count == 2 && Double(parts[0]) != nil && Double(parts[1]) != nil
    }

    private static func coordinateParts(_ text: String) -> [String] {
        text.split { $0 == "," || $0 == " " || $0 == ";" }.map(String.init).filter { !$0.isEmpty }
    }
}

struct WidgetPlaceQuery: EntityStringQuery {
    func entities(for identifiers: [WidgetPlace.ID]) async throws -> [WidgetPlace] {
        identifiers.compactMap(WidgetPlace.decode)
    }

    func entities(matching string: String) async throws -> [WidgetPlace] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if WidgetPlace.looksLikeCoordinates(trimmed) {
            return WidgetPlace.coordinate(from: trimmed).map { [$0] } ?? []
        }
        guard trimmed.count >= 2 else { return [] }
        return await Self.geocode(trimmed)
    }

    func suggestedEntities() async throws -> [WidgetPlace] {
        guard let stored = WidgetSnapshotStore.load() else { return [] }
        return [WidgetPlace.make(name: stored.locationName, latitude: stored.latitude, longitude: stored.longitude)]
    }

    private static func geocode(_ query: String) async -> [WidgetPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let payload = try JSONDecoder().decode(GeoPayload.self, from: data)
            return (payload.results ?? []).map { place in
                WidgetPlace.make(name: place.label, latitude: place.latitude, longitude: place.longitude)
            }
        } catch {
            return []
        }
    }
}

struct PlaceWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Current conditions"
    static var description = IntentDescription("Weather for a chosen place. A fresh reading from the app is used when sharing is available.")

    @Parameter(title: "Place", description: "Search for a city, or enter latitude and longitude.")
    var place: WidgetPlace?

    static var parameterSummary: some ParameterSummary {
        When(\.$place, .hasAnyValue) {
            Summary("Show \(\.$place)")
        } otherwise: {
            Summary("Choose a place")
        }
    }
}

private struct GeoPayload: Decodable {
    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country: String?

        var label: String {
            let region = admin1 ?? country
            if let region, !region.isEmpty, region != name {
                return "\(name), \(region)"
            }
            return name
        }
    }

    let results: [Place]?
}
