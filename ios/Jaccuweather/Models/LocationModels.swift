import Foundation

struct GeoResult: Identifiable, Hashable, Codable {
    var id: String { "\(latitude),\(longitude)" }
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?

    /// Same coordinates, even when the stored name changed after a reverse geocode.
    func samePlace(as other: GeoResult) -> Bool {
        id == other.id
    }

    /// US places keep the state. Everywhere else keeps the country.
    var displayName: String {
        let admin = PlaceName.filled(admin1)
        let countryName = PlaceName.filled(country)
        if PlaceName.isUnitedStates(countryName), let admin, !PlaceName.sameText(admin, name) {
            return "\(name), \(admin)"
        }
        if let countryName, !PlaceName.isUnitedStates(countryName), !PlaceName.sameText(countryName, name) {
            return "\(name), \(countryName)"
        }
        if let admin, !PlaceName.sameText(admin, name) {
            return "\(name), \(admin)"
        }
        return name
    }

    /// Region line under a search result. The city name stays on the row title.
    var subtitle: String {
        let admin = PlaceName.filled(admin1)
        let countryName = PlaceName.filled(country)
        var parts: [String] = []
        if let admin, !PlaceName.sameText(admin, name) {
            parts.append(admin)
        }
        if let countryName, !PlaceName.sameText(countryName, name), parts.contains(where: { PlaceName.sameText($0, countryName) }) == false {
            parts.append(countryName)
        }
        return parts.joined(separator: ", ")
    }
}

enum PlaceName {
    static func filled(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else { return nil }
        if let range = text.range(of: #"\s*\(the\)\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }

    static func sameText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    static func isUnitedStates(_ country: String?) -> Bool {
        guard let country = filled(country) else { return false }
        return country.contains("United States") || country == "US" || country == "USA"
    }

    /// Blank and comma-led labels (a blank city plus a country) are not a place name.
    static func isUsable(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(",") { return false }
        return true
    }
}

enum CitySearch {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldSearch(_ query: String) -> Bool {
        normalizedQuery(query).count >= 2
    }

    /// A response is applied only when it is still the latest keystroke.
    static func matchesRequest(generation: Int, currentGeneration: Int) -> Bool {
        generation == currentGeneration
    }

    static func uniquePlaces(_ results: [GeoResult]) -> [GeoResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    enum Outcome: Equatable {
        case ignore
        case empty
        case failed
        case results([GeoResult])

        static func resolve(generation: Int, currentGeneration: Int, query: String, results: [GeoResult]?, failed: Bool) -> Outcome {
            guard CitySearch.matchesRequest(generation: generation, currentGeneration: currentGeneration) else { return .ignore }
            guard CitySearch.shouldSearch(query) else { return .empty }
            if failed { return .failed }
            return .results(CitySearch.uniquePlaces(results ?? []))
        }
    }
}

struct OpenMeteoGeocodingResponse: Decodable {
    let results: [OpenMeteoPlace]?
}

struct OpenMeteoPlace: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?

    func asGeoResult() -> GeoResult {
        GeoResult(name: name, latitude: latitude, longitude: longitude, admin1: admin1, country: country)
    }
}

struct BigDataCloudReverse: Decodable {
    let city: String?
    let locality: String?
    let town: String?
    let village: String?
    let municipality: String?
    let county: String?
    let principalSubdivision: String?
    let countryName: String?

    /// A blank `city` is missing data. Fall through to locality instead of
    /// building a name like ", Antarctica". Nil leaves whatever place is already showing.
    func placeName() -> String? {
        let cityName = PlaceName.filled(city)
            ?? PlaceName.filled(locality)
            ?? PlaceName.filled(town)
            ?? PlaceName.filled(village)
            ?? PlaceName.filled(municipality)
            ?? PlaceName.filled(county)
        let state = PlaceName.filled(principalSubdivision)
        let country = PlaceName.filled(countryName)
        let isUS = PlaceName.isUnitedStates(country)
        if let cityName {
            if isUS, let state, !PlaceName.sameText(state, cityName) {
                return "\(cityName), \(state)"
            }
            if !isUS, let country, !PlaceName.sameText(country, cityName) {
                return "\(cityName), \(country)"
            }
            return cityName
        }
        if isUS, let state { return state }
        if let country { return country }
        return nil
    }
}
