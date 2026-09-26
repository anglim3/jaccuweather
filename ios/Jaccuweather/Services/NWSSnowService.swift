import Foundation

/// Optional NWS 48-hour snowfall for the Now card.
/// Uses the same `HTTPClient` path and `Secrets.nwsUserAgent` as `AlertsService`.
enum NWSSnowService {
    /// Inches to show, or nil when the place is outside the alerts US box, the total is under 0.1 in, or the request fails.
    static func inchesNext48Hours(latitude: Double, longitude: Double, now: Date = Date()) async -> Double? {
        guard AlertsService.isLikelyUS(latitude: latitude, longitude: longitude) else { return nil }
        let headers = ["Accept": "application/geo+json"]
        do {
            let point = try await HTTPClient.getJSON(
                APIEndpoints.nwsPoints(latitude: latitude, longitude: longitude),
                as: NWSPointResponse.self,
                extraHeaders: headers,
                userAgent: Secrets.nwsUserAgent
            )
            guard let grid = point.properties?.forecastGridData, let url = URL(string: grid) else { return nil }
            let data = try await HTTPClient.getData(url, extraHeaders: headers, userAgent: Secrets.nwsUserAgent)
            let inches = NWSSnowWindow.totalInches(entries: NWSSnowWindow.entries(from: data), now: now)
            return inches >= 0.1 ? inches : nil
        } catch {
            return nil
        }
    }
}
