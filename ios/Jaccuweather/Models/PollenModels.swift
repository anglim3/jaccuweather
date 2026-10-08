import Foundation

/// Normalized pollen/AQI payload, aligned with Worker `/api/pollen`.
/// Open-Meteo fills AQI + species fields it actually reports. Google/Tomorrow
/// must not invent alder/birch/olive from category TREE.
struct PollenSnapshot: Equatable {
    var source: String
    var usAqi: Double?
    var treePollen: Double?
    var grassPollen: Double?
    var weedPollen: Double?
    var alderPollen: Double?
    var birchPollen: Double?
    var olivePollen: Double?
    var mugwortPollen: Double?
    var ragweedPollen: Double?
    var daily: [PollenDay]

    var hasAnyPollen: Bool {
        [treePollen, grassPollen, weedPollen, alderPollen, birchPollen, olivePollen, mugwortPollen, ragweedPollen]
            .contains { value in
                if let value { return !value.isNaN } else { return false }
            }
    }

    var maxPollen: Double? {
        let values = [treePollen, grassPollen, weedPollen, alderPollen, birchPollen, olivePollen, mugwortPollen, ragweedPollen]
            .compactMap { $0 }
        return values.max()
    }
}

/// US AQI bands from the website `displayAirQuality` path.
/// The integer on screen is the rounded reading, and the band uses that same integer.
struct USAQIDisplay: Equatable {
    let value: Int
    let category: String
    let colorToken: String

    static func from(current: JSONMap?) -> USAQIDisplay? {
        guard let raw = current?.number("us_aqi"), raw.isFinite, raw >= 0 else { return nil }
        let value = Int(raw.rounded())
        switch value {
        case ...50: return USAQIDisplay(value: value, category: "Good", colorToken: "green")
        case ...100: return USAQIDisplay(value: value, category: "Moderate", colorToken: "yellow")
        case ...150: return USAQIDisplay(value: value, category: "Unhealthy for Sensitive Groups", colorToken: "orange")
        case ...200: return USAQIDisplay(value: value, category: "Unhealthy", colorToken: "red")
        case ...300: return USAQIDisplay(value: value, category: "Very Unhealthy", colorToken: "purple")
        default: return USAQIDisplay(value: value, category: "Hazardous", colorToken: "maroon")
        }
    }
}

/// Copies Open-Meteo `us_aqi` onto a Google or Tomorrow payload that omitted it.
/// An existing finite reading stays put, and pollen fields plus the source label stay put.
enum PollenUsAqi {
    static func merge(primary: JSONMap, openMeteo: JSONMap) -> JSONMap {
        if let existing = primary.map("current").number("us_aqi"), existing.isFinite {
            return primary
        }
        guard let aqi = openMeteo.map("current").number("us_aqi"), aqi.isFinite else {
            return primary
        }
        var root = primary.raw
        var current = JSONMap(root["current"]).raw
        current["us_aqi"] = aqi
        root["current"] = current
        return JSONMap(root)
    }
}

/// Null pollen is not a measured zero. A provider that reported the plant with
/// no index can still be shown as None.
enum PollenReading {
    static func countText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(Int(value.rounded()))
    }

    static func levelText(_ value: Double?, nullAsNone: Bool) -> String {
        guard let value, value.isFinite else { return nullAsNone ? "None" : "n/a" }
        if value <= 0 { return "None" }
        if value <= 20 { return "Low" }
        if value <= 80 { return "Moderate" }
        if value <= 200 { return "High" }
        return "Very High"
    }
}

struct PollenDay: Identifiable, Equatable {
    var id: String { time }
    let time: String
    let grass: Double?
    let weed: Double?
    let tree: Double?
}

struct OpenMeteoAirQuality: Decodable {
    let current: CurrentAir?
    let hourly: HourlyPollen?

    struct CurrentAir: Decodable {
        let usAqi: Double?
        let alderPollen: Double?
        let birchPollen: Double?
        let grassPollen: Double?
        let mugwortPollen: Double?
        let olivePollen: Double?
        let ragweedPollen: Double?

        enum CodingKeys: String, CodingKey {
            case usAqi = "us_aqi"
            case alderPollen = "alder_pollen"
            case birchPollen = "birch_pollen"
            case grassPollen = "grass_pollen"
            case mugwortPollen = "mugwort_pollen"
            case olivePollen = "olive_pollen"
            case ragweedPollen = "ragweed_pollen"
        }
    }

    struct HourlyPollen: Decodable {
        let time: [String]
        let grassPollen: [Double?]?
        let alderPollen: [Double?]?
        let birchPollen: [Double?]?
        let mugwortPollen: [Double?]?
        let olivePollen: [Double?]?
        let ragweedPollen: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case grassPollen = "grass_pollen"
            case alderPollen = "alder_pollen"
            case birchPollen = "birch_pollen"
            case mugwortPollen = "mugwort_pollen"
            case olivePollen = "olive_pollen"
            case ragweedPollen = "ragweed_pollen"
        }
    }

    func snapshot(source: String = "open-meteo") -> PollenSnapshot {
        let current = current
        let days: [PollenDay] = (hourly?.time ?? []).prefix(5).enumerated().map { index, time in
            PollenDay(
                time: time,
                grass: hourly?.grassPollen?[safe: index] ?? nil,
                weed: hourly?.mugwortPollen?[safe: index] ?? hourly?.ragweedPollen?[safe: index] ?? nil,
                tree: hourly?.alderPollen?[safe: index] ?? hourly?.birchPollen?[safe: index] ?? hourly?.olivePollen?[safe: index] ?? nil
            )
        }
        return PollenSnapshot(
            source: source,
            usAqi: current?.usAqi,
            treePollen: nil,
            grassPollen: current?.grassPollen,
            weedPollen: current?.mugwortPollen ?? current?.ragweedPollen,
            alderPollen: current?.alderPollen,
            birchPollen: current?.birchPollen,
            olivePollen: current?.olivePollen,
            mugwortPollen: current?.mugwortPollen,
            ragweedPollen: current?.ragweedPollen,
            daily: days
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
