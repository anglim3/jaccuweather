import Foundation

struct PollenService {
    func load(latitude: Double, longitude: Double) async -> JSONMap? {
        if !Secrets.googlePollenAPIKey.isEmpty {
            if let google = try? await fetchGoogle(latitude: latitude, longitude: longitude) {
                return await fillingUsAqi(google, latitude: latitude, longitude: longitude)
            }
        }
        if !Secrets.tomorrowAPIKey.isEmpty {
            if let tomorrow = try? await fetchTomorrow(latitude: latitude, longitude: longitude) {
                return await fillingUsAqi(tomorrow, latitude: latitude, longitude: longitude)
            }
        }
        return try? await fetchOpenMeteo(latitude: latitude, longitude: longitude)
    }

    /// Open-Meteo pollen already includes `us_aqi`. Google and Tomorrow do not,
    /// so copy that one field when it is missing. A failed fill leaves pollen as-is.
    private func fillingUsAqi(_ primary: JSONMap, latitude: Double, longitude: Double) async -> JSONMap {
        if let existing = primary.map("current").number("us_aqi"), existing.isFinite {
            return primary
        }
        guard let openMeteo = try? await fetchOpenMeteo(latitude: latitude, longitude: longitude),
              let merged = LogicEngine.shared.object("mergeOpenMeteoUsAqi", [primary.raw, openMeteo.raw]) else {
            return primary
        }
        return JSONMap(merged)
    }

    private func fetchOpenMeteo(latitude: Double, longitude: Double) async throws -> JSONMap {
        let raw = try await HTTPClient.getJSONObject(APIEndpoints.openMeteoPollen(latitude: latitude, longitude: longitude))
        var dict = JSONMap(raw).raw
        dict["pollen_source"] = "open-meteo"
        return JSONMap(dict)
    }

    private func fetchGoogle(latitude: Double, longitude: Double) async throws -> JSONMap? {
        let raw = try await HTTPClient.getJSONObject(
            APIEndpoints.googlePollen(latitude: latitude, longitude: longitude, apiKey: Secrets.googlePollenAPIKey)
        )
        guard let normalized = LogicEngine.shared.object("normalizeGooglePollen", [raw]) else { return nil }
        let map = JSONMap(normalized)
        let usable = LogicEngine.shared.bool("hasAnyUsablePollen", [normalized])
        return usable ? map : nil
    }

    private func fetchTomorrow(latitude: Double, longitude: Double) async throws -> JSONMap? {
        let raw = try await HTTPClient.getJSONObject(
            APIEndpoints.tomorrowForecast(latitude: latitude, longitude: longitude, apiKey: Secrets.tomorrowAPIKey)
        )
        guard let normalized = LogicEngine.shared.object("normalizeTomorrowPollen", [raw]) else { return nil }
        let usable = LogicEngine.shared.bool("hasAnyUsablePollen", [normalized])
        return usable ? JSONMap(normalized) : nil
    }
}
