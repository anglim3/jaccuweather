import Foundation
import WidgetKit

/// Compact current-conditions snapshot shared by the app and the widget extension.
struct WidgetConditionsSnapshot: Codable, Equatable {
    var locationId: String
    var locationName: String
    var latitude: Double
    var longitude: Double
    var temperatureF: Double?
    var feelsLikeF: Double?
    var weatherCode: Int?
    var isDay: Bool
    var conditionText: String
    var symbolName: String
    var precipChance: Int?
    var highF: Double?
    var lowF: Double?
    var nextHoursHint: String
    var fetchedAt: Date

    /// WidgetKit reloads on its own about every 20 minutes. Refetch only after this.
    static let refetchAfter: TimeInterval = 40 * 60
    /// Keep the last good reading if a stale refresh fails, then ask to open the app.
    static let showStaleUntil: TimeInterval = 6 * 60 * 60

    var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
    var isFresh: Bool { age < Self.refetchAfter }
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.cloud.janglim.jaccuweather"
    static let kind = "cloud.janglim.jaccuweather.conditions"
    private static let fileName = "widget-snapshot.json"

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> WidgetConditionsSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetConditionsSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetConditionsSnapshot, reloadWidgets: Bool = true) {
        guard let url = fileURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        guard reloadWidgets else { return }
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}

enum WidgetWeatherCode {
    static func shortText(_ code: Int?) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Rain showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }

    static func symbol(code: Int?, isDay: Bool) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

enum WidgetClock {
    static func compact(_ clock: String) -> String {
        let parts = clock.split(separator: " ")
        guard parts.count >= 2 else { return clock }
        let suffix = parts[1].uppercased().hasPrefix("P") ? "p" : "a"
        let hm = parts[0].split(separator: ":")
        if hm.count == 2, hm[1] == "00" {
            return "\(hm[0])\(suffix)"
        }
        return "\(parts[0])\(suffix)"
    }

    static func hint(times: [(label: String, temp: Double?, chance: Int?)]) -> String {
        times.prefix(4).compactMap { item in
            guard let temp = item.temp else { return nil }
            let label = compact(item.label)
            let degrees = "\(Int(temp.rounded()))°"
            if let chance = item.chance, chance >= 20 {
                return "\(label) \(degrees) \(chance)%"
            }
            return "\(label) \(degrees)"
        }.joined(separator: " · ")
    }
}
