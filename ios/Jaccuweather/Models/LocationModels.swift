import Foundation

struct GeoResult: Identifiable, Hashable, Codable {
    var id: String { "\(latitude),\(longitude)" }
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?

    var displayName: String {
        let region = admin1 ?? country
        if let region, !region.isEmpty, region != name {
            return "\(name), \(region)"
        }
        return name
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
    let principalSubdivision: String?
    let countryName: String?

    func displayName(fallbackLatitude lat: Double, longitude lon: Double) -> String {
        let cityName = city ?? locality
        let country = countryName ?? ""
        let isUS = country.contains("United States") || country == "US" || country == "USA"
        if let cityName {
            if let state = principalSubdivision, isUS {
                return "\(cityName), \(state)"
            }
            if !isUS, !country.isEmpty {
                return "\(cityName), \(country)"
            }
            return cityName
        }
        return String(format: "%.2f, %.2f", lat, lon)
    }
}
