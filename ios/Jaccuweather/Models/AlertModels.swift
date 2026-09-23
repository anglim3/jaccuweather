import Foundation

struct NWSPointResponse: Decodable {
    let properties: NWSPointProperties?
}

struct NWSPointProperties: Decodable {
    let forecastZone: String?
}

struct NWSAlertsResponse: Decodable {
    let features: [NWSAlertFeature]
}

struct NWSAlertFeature: Decodable, Identifiable {
    let properties: NWSAlertProperties
    var id: String { properties.headline ?? properties.event ?? properties.severity ?? "alert" }
}

struct NWSAlertProperties: Decodable {
    let headline: String?
    let event: String?
    let severity: String?
    let status: String?
    let description: String?
    let instruction: String?
}
