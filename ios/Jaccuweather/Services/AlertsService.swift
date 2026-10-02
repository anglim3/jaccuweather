import Foundation

enum AlertsLoad: Equatable {
    /// No zone, or NWS has no coverage here (HTTP 404). Not an error.
    case none
    case list([NWSAlertFeature])
    /// The points or alerts request failed after a place that NWS may cover.
    case failed
}

/// NWS points + zone alerts. Direct `api.weather.gov` (Worker `/api/nws-points` + `/api/alerts`).
struct AlertsService {
    /// Lower-48 box still used by the optional NWS snow line. Alerts do not use it:
    /// a `/points/` 404 is what skips places NWS does not cover, including ocean.
    static let conus = (minLat: 24.0, maxLat: 50.0, minLon: -125.0, maxLon: -66.0)

    static func isLikelyUS(latitude: Double, longitude: Double) -> Bool {
        latitude >= conus.minLat && latitude <= conus.maxLat
            && longitude >= conus.minLon && longitude <= conus.maxLon
    }

    func load(latitude: Double, longitude: Double) async -> AlertsLoad {
        do {
            let nwsHeaders = ["Accept": "application/geo+json"]
            let point = try await HTTPClient.getJSON(
                APIEndpoints.nwsPoints(latitude: latitude, longitude: longitude),
                as: NWSPointResponse.self,
                extraHeaders: nwsHeaders,
                userAgent: Secrets.nwsUserAgent
            )
            guard let zoneURL = point.properties?.forecastZone,
                  let zoneId = zoneURL.split(separator: "/").last.map(String.init),
                  !zoneId.isEmpty
            else { return .none }
            let payload = try await HTTPClient.getJSON(
                APIEndpoints.nwsAlerts(zoneId: zoneId),
                as: NWSAlertsResponse.self,
                extraHeaders: nwsHeaders,
                userAgent: Secrets.nwsUserAgent
            )
            let rows = payload.features.filter { ($0.properties.status ?? "Actual") == "Actual" }
            return .list(rows)
        } catch let HTTPClientError.badStatus(404, _) {
            return .none
        } catch {
            return .failed
        }
    }
}
