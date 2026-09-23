import Foundation

struct WeatherService {
    func ensemble(latitude: Double, longitude: Double) async throws -> WeatherBundle {
        let raw = try await HTTPClient.getJSONObject(APIEndpoints.ensemble(latitude: latitude, longitude: longitude))
        let normalized = LogicEngine.shared.normalizeEnsemble(raw, latitude: latitude, longitude: longitude)
        return WeatherBundle(root: normalized)
    }
}
