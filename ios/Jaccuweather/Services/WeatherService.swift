import Foundation

struct WeatherService {
    func forecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        try await HTTPClient.getJSON(APIEndpoints.forecast(latitude: latitude, longitude: longitude), as: ForecastResponse.self)
    }
}
