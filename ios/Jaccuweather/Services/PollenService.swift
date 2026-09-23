import Foundation

/// Google → Tomorrow.io → Open-Meteo, same order as `handlePollenRequest` in build.js.
/// Same-origin / POLLEN_RATE_LIMIT do not apply off-Worker. Keys stay in xcconfig, never in source.
struct PollenService {
    func load(latitude: Double, longitude: Double) async -> PollenSnapshot? {
        if !Secrets.googlePollenAPIKey.isEmpty {
            if let google = try? await fetchGoogle(latitude: latitude, longitude: longitude) {
                return google
            }
        }
        if !Secrets.tomorrowAPIKey.isEmpty {
            if let tomorrow = try? await fetchTomorrow(latitude: latitude, longitude: longitude) {
                return tomorrow
            }
        }
        return try? await fetchOpenMeteo(latitude: latitude, longitude: longitude)
    }

    func fetchOpenMeteo(latitude: Double, longitude: Double) async throws -> PollenSnapshot {
        let payload = try await HTTPClient.getJSON(
            APIEndpoints.openMeteoPollen(latitude: latitude, longitude: longitude),
            as: OpenMeteoAirQuality.self
        )
        return payload.snapshot(source: "open-meteo")
    }

    /// Minimal Google lookup. Full `normalizeGooglePollen` (null-vs-none metadata) is a follow-up.
    /// TREE category maps to tree_pollen only — species stay nil unless plants are present.
    private func fetchGoogle(latitude: Double, longitude: Double) async throws -> PollenSnapshot? {
        struct GooglePollen: Decodable {
            let dailyInfo: [Day]?
            struct Day: Decodable {
                let date: DateParts?
                let pollenTypeInfo: [TypeInfo]?
                let plantInfo: [TypeInfo]?
            }
            struct DateParts: Decodable { let year: Int?; let month: Int?; let day: Int? }
            struct TypeInfo: Decodable {
                let code: String?
                let indexInfo: IndexInfo?
            }
            struct IndexInfo: Decodable { let value: Double? }
        }

        let payload = try await HTTPClient.getJSON(
            APIEndpoints.googlePollen(latitude: latitude, longitude: longitude, apiKey: Secrets.googlePollenAPIKey),
            as: GooglePollen.self
        )
        guard let first = payload.dailyInfo?.first else { return nil }

        func value(_ info: GooglePollen.TypeInfo?) -> Double? {
            guard let raw = info?.indexInfo?.value else { return nil }
            return max(0, raw) * 50
        }

        func type(_ code: String) -> GooglePollen.TypeInfo? {
            first.pollenTypeInfo?.first { ($0.code ?? "").uppercased() == code }
        }

        func plant(_ code: String) -> GooglePollen.TypeInfo? {
            first.plantInfo?.first { ($0.code ?? "").uppercased() == code }
        }

        let days: [PollenDay] = (payload.dailyInfo ?? []).prefix(5).map { day in
            let label: String
            if let d = day.date, let y = d.year, let m = d.month, let dd = d.day {
                label = String(format: "%04d-%02d-%02d", y, m, dd)
            } else {
                label = "day"
            }
            let grass = day.pollenTypeInfo?.first { ($0.code ?? "").uppercased() == "GRASS" }
            let weed = day.pollenTypeInfo?.first { ($0.code ?? "").uppercased() == "WEED" }
            let tree = day.pollenTypeInfo?.first { ($0.code ?? "").uppercased() == "TREE" }
            return PollenDay(time: label, grass: value(grass), weed: value(weed), tree: value(tree))
        }

        let snapshot = PollenSnapshot(
            source: "google",
            usAqi: nil,
            treePollen: value(type("TREE")),
            grassPollen: value(type("GRASS")) ?? value(plant("GRASS")) ?? value(plant("GRAMINALES")),
            weedPollen: value(type("WEED")),
            alderPollen: value(plant("ALDER")),
            birchPollen: value(plant("BIRCH")),
            olivePollen: value(plant("OLIVE")),
            mugwortPollen: value(plant("MUGWORT")),
            ragweedPollen: value(plant("RAGWEED")),
            daily: days
        )
        return snapshot.hasAnyPollen ? snapshot : nil
    }

    private func fetchTomorrow(latitude: Double, longitude: Double) async throws -> PollenSnapshot? {
        struct TomorrowForecast: Decodable {
            let timelines: Timelines?
            struct Timelines: Decodable { let daily: [Interval]? }
            struct Interval: Decodable {
                let time: String?
                let values: Values?
            }
            struct Values: Decodable {
                let grassIndex: Double?
                let weedIndex: Double?
            }
        }

        let payload = try await HTTPClient.getJSON(
            APIEndpoints.tomorrowForecast(latitude: latitude, longitude: longitude, apiKey: Secrets.tomorrowAPIKey),
            as: TomorrowForecast.self
        )
        let intervals = payload.timelines?.daily ?? []
        guard !intervals.isEmpty else { return nil }
        let first = intervals[0].values
        let days = intervals.prefix(5).map { interval in
            PollenDay(
                time: interval.time ?? "",
                grass: interval.values?.grassIndex.map { max(0, $0) * 50 },
                weed: interval.values?.weedIndex.map { max(0, $0) * 50 },
                tree: nil
            )
        }
        let snapshot = PollenSnapshot(
            source: "tomorrow",
            usAqi: nil,
            treePollen: nil,
            grassPollen: first?.grassIndex.map { max(0, $0) * 50 },
            weedPollen: first?.weedIndex.map { max(0, $0) * 50 },
            alderPollen: nil,
            birchPollen: nil,
            olivePollen: nil,
            mugwortPollen: nil,
            ragweedPollen: nil,
            daily: Array(days)
        )
        return snapshot.hasAnyPollen ? snapshot : nil
    }
}
