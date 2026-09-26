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

/// Integer US AQI plus the website category. Nil when `current.us_aqi` is missing.
struct USAQIDisplay: Equatable {
    let value: Int
    let category: String
    let colorToken: String

    static func from(pollen: JSONMap?) -> USAQIDisplay? {
        guard let pollen else { return nil }
        guard let raw = LogicEngine.shared.object("usAqiDisplay", [pollen.raw]) else { return nil }
        let map = JSONMap(raw)
        guard let value = map.int("value"), let category = map.string("category") else { return nil }
        return USAQIDisplay(value: value, category: category, colorToken: map.string("color") ?? "green")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
