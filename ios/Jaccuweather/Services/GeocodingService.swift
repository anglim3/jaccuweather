import Foundation

struct GeocodingService {
    func search(query: String) async throws -> [GeoResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let payload = try await HTTPClient.getJSON(APIEndpoints.geocoding(name: trimmed), as: OpenMeteoGeocodingResponse.self)
        return (payload.results ?? []).map { $0.asGeoResult() }
    }

    func reverse(latitude: Double, longitude: Double) async throws -> String {
        let payload = try await HTTPClient.getJSON(
            APIEndpoints.reverse(latitude: latitude, longitude: longitude),
            as: BigDataCloudReverse.self
        )
        return payload.displayName(fallbackLatitude: latitude, longitude: longitude)
    }
}
