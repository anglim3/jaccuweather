import Foundation

struct TideStation {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let distance: Double
}

struct TideExtreme: Identifiable {
    var id: String { "\(time.timeIntervalSince1970)-\(type)" }
    let time: Date
    let value: Double
    let type: String
}

struct TideSnapshot {
    let station: TideStation
    let extremes: [TideExtreme]
    let curve: [TideExtreme]
}

struct TideService {
    private let maxDistanceKm = 50.0
    private let maxElevationM = 20.0
    private static var stationCache: [TideStation]?
    private static var stationCacheAt: Date?

    func load(latitude: Double, longitude: Double, elevation: Double?) async -> TideSnapshot? {
        guard let elevation, elevation <= maxElevationM else { return nil }
        guard let stations = try? await cachedStations() else { return nil }
        let nearby = stations
            .map { station -> TideStation in
                let d = haversineKm(latitude, longitude, station.lat, station.lon)
                return TideStation(id: station.id, name: station.name, lat: station.lat, lon: station.lon, distance: d)
            }
            .filter { $0.distance <= maxDistanceKm }
            .sorted { $0.distance < $1.distance }
        guard !nearby.isEmpty else { return nil }

        let begin = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 14, to: begin) ?? begin

        for station in nearby {
            if let snapshot = try? await predictions(for: station, begin: begin, end: end) {
                return snapshot
            }
        }
        return nil
    }

    private func cachedStations() async throws -> [TideStation] {
        if let cache = Self.stationCache, let at = Self.stationCacheAt, Date().timeIntervalSince(at) < 24 * 60 * 60 {
            return cache
        }
        let stations = try await fetchStations()
        Self.stationCache = stations
        Self.stationCacheAt = Date()
        return stations
    }

    private func fetchStations() async throws -> [TideStation] {
        let raw = try await HTTPClient.getJSONObject(URL(string: APIEndpoints.noaaStations)!)
        let list = JSONMap(raw).raw["stations"] as? [Any] ?? []
        return list.compactMap { item in
            let map = JSONMap(item)
            guard let id = map.string("id") ?? map.string("name") else { return nil }
            let lat = map.number("lat") ?? 0
            let lon = map.number("lng") ?? map.number("lon") ?? 0
            return TideStation(id: id, name: map.string("name") ?? id, lat: lat, lon: lon, distance: 0)
        }
    }

    private func predictions(for station: TideStation, begin: Date, end: Date) async throws -> TideSnapshot? {
        var c = URLComponents(string: APIEndpoints.noaaDatagetter)!
        c.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "jaccuweather"),
            URLQueryItem(name: "begin_date", value: yyyymmdd(begin)),
            URLQueryItem(name: "end_date", value: yyyymmdd(end)),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "station", value: station.id),
            URLQueryItem(name: "time_zone", value: "lst_ldt"),
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "interval", value: "hilo"),
            URLQueryItem(name: "format", value: "json")
        ]
        let raw = try await HTTPClient.getJSONObject(c.url!)
        let rows = JSONMap(raw).raw["predictions"] as? [Any] ?? []
        let extremes: [TideExtreme] = rows.compactMap { item in
            let map = JSONMap(item)
            guard let t = map.string("t"), let value = map.number("v"), let time = parseNoaa(t) else { return nil }
            return TideExtreme(time: time, value: value, type: map.string("type") ?? "")
        }
        guard extremes.count >= 2 else { return nil }
        return TideSnapshot(station: station, extremes: extremes, curve: interpolate(extremes))
    }

    private func interpolate(_ hilo: [TideExtreme]) -> [TideExtreme] {
        let sorted = hilo.sorted { $0.time < $1.time }
        guard sorted.count >= 2 else { return [] }
        let interval: TimeInterval = 15 * 60
        var curve: [TideExtreme] = []
        for i in 0..<(sorted.count - 1) {
            let start = sorted[i]
            let end = sorted[i + 1]
            let span = end.time.timeIntervalSince(start.time)
            guard span > 0 else { continue }
            var t = start.time
            while t < end.time {
                let frac = t.timeIntervalSince(start.time) / span
                let value = start.value + (end.value - start.value) * ((1 - cos(Double.pi * frac)) / 2)
                curve.append(TideExtreme(time: t, value: value, type: ""))
                t = t.addingTimeInterval(interval)
            }
            curve.append(end)
        }
        return curve
    }

    private func yyyymmdd(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    private func parseNoaa(_ value: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: value)
    }

    private func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
