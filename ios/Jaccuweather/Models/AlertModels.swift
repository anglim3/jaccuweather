import Foundation

struct NWSPointResponse: Decodable {
    let properties: NWSPointProperties?
}

struct NWSPointProperties: Decodable {
    let forecastZone: String?
    let forecastGridData: String?
}

struct NWSAlertsResponse: Decodable {
    let features: [NWSAlertFeature]
}

struct NWSAlertFeature: Decodable, Identifiable, Hashable {
    let properties: NWSAlertProperties
    var id: String {
        properties.id ?? properties.headline ?? properties.event ?? properties.severity ?? "alert"
    }

    static func == (lhs: NWSAlertFeature, rhs: NWSAlertFeature) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct NWSAlertProperties: Decodable, Hashable {
    let id: String?
    let headline: String?
    let event: String?
    let severity: String?
    let urgency: String?
    let status: String?
    let description: String?
    let instruction: String?
    let ends: String?
    let senderName: String?
}
