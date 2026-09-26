import Foundation

/// NWS points + zone alerts. Direct `api.weather.gov` (Worker `/api/nws-points` + `/api/alerts`).
struct AlertsService {
    static let conus = (minLat: 24.0, maxLat: 50.0, minLon: -125.0, maxLon: -66.0)

    static func isLikelyUS(latitude: Double, longitude: Double) -> Bool {
        latitude >= conus.minLat && latitude <= conus.maxLat
            && longitude >= conus.minLon && longitude <= conus.maxLon
    }

    func alerts(latitude: Double, longitude: Double) async -> [NWSAlertFeature] {
        guard Self.isLikelyUS(latitude: latitude, longitude: longitude) else { return [] }
        do {
            let nwsHeaders = ["Accept": "application/geo+json"]
            let point = try await HTTPClient.getJSON(
                APIEndpoints.nwsPoints(latitude: latitude, longitude: longitude),
                as: NWSPointResponse.self,
                extraHeaders: nwsHeaders,
                userAgent: Secrets.nwsUserAgent
            )
            guard let zoneURL = point.properties?.forecastZone,
                  let zoneId = zoneURL.split(separator: "/").last.map(String.init)
            else { return [] }
            let payload = try await HTTPClient.getJSON(
                APIEndpoints.nwsAlerts(zoneId: zoneId),
                as: NWSAlertsResponse.self,
                extraHeaders: nwsHeaders,
                userAgent: Secrets.nwsUserAgent
            )
            return payload.features.filter { ($0.properties.status ?? "Actual") == "Actual" }
        } catch {
            return []
        }
    }
}
