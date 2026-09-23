import Foundation
import CoreLocation
import Observation
import SwiftUI

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocationCoordinate2D) -> Void)?
    var onFail: ((Error) -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.last?.coordinate { onUpdate?(coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFail?(error)
    }
}

struct HourRow: Identifiable {
    let id: Int
    let time: String
    let clock: String
    let code: Int?
    let isDay: Bool
    let temp: Double?
    let precip: Double?
    let precipChance: Int?
    let wind: Double?
    let windDir: Double?
    let uv: Double?
    let pressure: Double?
    let cloud: Double?
    let humidity: Double?
    let iconFile: String
}

struct DayRow: Identifiable {
    let id: Int
    let date: String
    let label: String
    let code: Int?
    let high: Double?
    let low: Double?
    let precip: Double?
    let precipChance: Int?
    let uv: Double?
    let wind: Double?
    let feelsHigh: Double?
    let feelsLow: Double?
    let sunrise: String?
    let sunset: String?
    let iconFile: String
}

@Observable
@MainActor
final class WeatherViewModel {
    var locationName = "Seattle, Washington"
    var coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    var weather: WeatherBundle?
    var pollen: JSONMap?
    var alerts: [NWSAlertFeature] = []
    var tides: TideSnapshot?
    var isLoading = false
    var errorMessage: String?
    var searchQuery = ""
    var searchResults: [GeoResult] = []
    var isSearching = false
    var lastFetchMs: Double = 0
    var lastUpdatedLabel = ""
    var hourlyMode = "conditions"

    let favorites = FavoritesStore()
    let staleAfterMs: Double = 15 * 60 * 1000

    private let weatherService = WeatherService()
    private let geocoding = GeocodingService()
    private let pollenService = PollenService()
    private let alertsService = AlertsService()
    private let tideService = TideService()
    private let locator = LocationProvider()
    private var searchTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var fetchInFlight = false

    var currentPlace: GeoResult {
        GeoResult(name: locationName, latitude: coordinate.latitude, longitude: coordinate.longitude, admin1: nil, country: nil)
    }

    var hourlyRows: [HourRow] {
        guard let weather else { return [] }
        let hourly = weather.hourly
        let times = hourly.strings("time")
        let start = Self.hourlyStartIndex(times: times, utcOffset: weather.utcOffset)
        let logic = LogicEngine.shared
        return (0..<48).compactMap { offset in
            let i = start + offset
            guard i < times.count else { return nil }
            let code = hourly.numbers("weather_code")[safe: i] ?? nil
            let isDay = (hourly.numbers("is_day")[safe: i] ?? 1) ?? 1 != 0
            let precipChance = hourly.numbers("precipitation_probability")[safe: i] ?? nil
            let icon = logic.weatherIconFile(code: code.map { Int($0) }, isDay: isDay)
            return HourRow(
                id: i,
                time: times[i],
                clock: logic.string("formatIsoLocalClock", [times[i]]) ?? times[i],
                code: code.map { Int($0) },
                isDay: isDay,
                temp: hourly.numbers("temperature_2m")[safe: i] ?? nil,
                precip: hourly.numbers("precipitation")[safe: i] ?? nil,
                precipChance: precipChance.map { Int($0) },
                wind: hourly.numbers("wind_speed_10m")[safe: i] ?? nil,
                windDir: hourly.numbers("wind_direction_10m")[safe: i] ?? nil,
                uv: hourly.numbers("uv_index")[safe: i] ?? nil,
                pressure: hourly.numbers("surface_pressure")[safe: i] ?? nil,
                cloud: hourly.numbers("cloud_cover")[safe: i] ?? nil,
                humidity: hourly.numbers("relative_humidity_2m")[safe: i] ?? nil,
                iconFile: icon
            )
        }
    }

    var dailyRows: [DayRow] {
        guard let weather else { return [] }
        let daily = weather.daily
        let times = daily.strings("time")
        let start = weather.todayIndex
        let logic = LogicEngine.shared
        return times.enumerated().compactMap { index, date in
            guard index >= start else { return nil }
            let code = daily.numbers("weather_code")[safe: index] ?? nil
            let chance = daily.numbers("precipitation_probability_max")[safe: index] ?? nil
            let icon = logic.weatherIconFile(code: code.map { Int($0) }, isDay: true, precipProbability: chance)
            return DayRow(
                id: index,
                date: date,
                label: Self.dayLabel(date),
                code: code.map { Int($0) },
                high: daily.numbers("temperature_2m_max")[safe: index] ?? nil,
                low: daily.numbers("temperature_2m_min")[safe: index] ?? nil,
                precip: daily.numbers("precipitation_sum")[safe: index] ?? nil,
                precipChance: chance.map { Int($0) },
                uv: daily.numbers("uv_index_max")[safe: index] ?? nil,
                wind: daily.numbers("wind_speed_10m_max")[safe: index] ?? nil,
                feelsHigh: daily.numbers("apparent_temperature_max")[safe: index] ?? nil,
                feelsLow: daily.numbers("apparent_temperature_min")[safe: index] ?? nil,
                sunrise: daily.strings("sunrise")[safe: index],
                sunset: daily.strings("sunset")[safe: index],
                iconFile: icon
            )
        }
    }

    init() {
        locator.onUpdate = { [weak self] coordinate in
            Task { @MainActor in
                guard let self else { return }
                self.coordinate = coordinate
                self.locationName = "Current location"
                await self.refresh()
            }
        }
        locator.onFail = { [weak self] error in
            Task { @MainActor in
                if self?.weather == nil {
                    self?.errorMessage = "Location unavailable. Showing Seattle. \(error.localizedDescription)"
                }
            }
        }
        startTicker()
    }

    func bootstrap() async { await refresh() }

    func refresh() async {
        if fetchInFlight { return }
        fetchInFlight = true
        isLoading = true
        errorMessage = nil
        defer {
            fetchInFlight = false
            isLoading = false
        }
        do {
            async let weatherTask = weatherService.ensemble(latitude: coordinate.latitude, longitude: coordinate.longitude)
            async let pollenTask = pollenService.load(latitude: coordinate.latitude, longitude: coordinate.longitude)
            async let alertsTask = alertsService.alerts(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let bundle = try await weatherTask
            weather = bundle
            pollen = await pollenTask
            alerts = await alertsTask
            tides = await tideService.load(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: bundle.elevation)
            if locationName == "Current location" || !locationName.contains(",") {
                locationName = (try? await geocoding.reverse(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? locationName
            }
            lastFetchMs = Date().timeIntervalSince1970 * 1000
            tickLastUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ place: GeoResult) async {
        coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        locationName = place.displayName
        searchQuery = ""
        searchResults = []
        await refresh()
    }

    func requestDeviceLocation() { locator.request() }

    func updateSearch(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    func handleBecameActive() async {
        tickLastUpdated()
        let now = Date().timeIntervalSince1970 * 1000
        let should = LogicEngine.shared.invoke("shouldRefetchStaleForecast", [now, lastFetchMs, staleAfterMs])?.toBool ?? false
        if should { await refresh() }
    }

    func tickLastUpdated() {
        let now = Date().timeIntervalSince1970 * 1000
        lastUpdatedLabel = LogicEngine.shared.string("formatLastUpdatedBetween", [now, lastFetchMs]) ?? ""
    }

    var precipTiming: String {
        guard let first = hourlyRows.first(where: { ($0.precip ?? 0) > 0 || false }) else {
            return "No precipitation expected in the next 48 hours"
        }
        let isSnow = (weather?.hourly.numbers("snowfall")[safe: first.id] ?? 0) ?? 0 > 0
        let kind = isSnow ? "Snow" : "Rain"
        if first.id == hourlyRows.first?.id { return "\(kind) is currently falling" }
        return "\(kind) expected around \(first.clock)"
    }

    var pressureDisplay: (value: String, trend: String) {
        guard let weather, let hpa = weather.current.number("surface_pressure") else { return ("—", "Steady") }
        let inHg = hpa * 0.02953
        let hourly = weather.hourly.numbers("surface_pressure")
        var trend = "Steady"
        if let idx = hourlyRows.first?.id, idx >= 3, let cur = hourly[safe: idx] ?? nil, let past = hourly[safe: idx - 3] ?? nil {
            let diff = cur - past
            if diff > 1 { trend = "Rising" }
            else if diff < -1 { trend = "Falling" }
        }
        return (String(format: "%.2f\"", inHg), trend)
    }

    var moon: (emoji: String, name: String, rise: String, set: String, illumination: String, nextFull: String, nextNew: String) {
        let logic = LogicEngine.shared
        let nowMs = Date().timeIntervalSince1970 * 1000
        let phase = logic.number("calculateMoonPhase", [nowMs]) ?? 0
        let info = JSONMap(logic.object("getMoonPhase", [phase]))
        let times = JSONMap(logic.object("moonTimesMs", [nowMs, coordinate.latitude, coordinate.longitude]))
        let offset = weather?.utcOffset ?? 0
        let rise = times.number("rise").flatMap { logic.string("formatInstantInLocation", [$0, offset]) } ?? "n/a"
        let set = times.number("set").flatMap { logic.string("formatInstantInLocation", [$0, offset]) } ?? "n/a"
        let illum = logic.number("getMoonIllumination", [nowMs]).map { "\(Int($0))%" } ?? "—"
        let full = JSONMap(logic.object("getNextFullMoon", [nowMs]))
        let neu = JSONMap(logic.object("getNextNewMoon", [nowMs]))
        let fullLabel = full.int("days").map { "in \($0)d" } ?? "—"
        let newLabel = neu.int("days").map { "in \($0)d" } ?? "—"
        return (info.string("emoji") ?? "🌑", info.string("name") ?? "Unknown", rise, set, illum, fullLabel, newLabel)
    }

    private func runSearch() async {
        guard searchQuery.count >= 2 else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await geocoding.search(query: searchQuery)) ?? []
    }

    private func startTicker() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run { self?.tickLastUpdated() }
            }
        }
    }

    private static func hourlyStartIndex(times: [String], utcOffset: Int) -> Int {
        let nowMs = Date().timeIntervalSince1970 * 1000
        if let idx = LogicEngine.shared.number("nearestTimeIndex", [times, nowMs]) {
            return Int(idx)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffset)
        let now = Date()
        for (i, stamp) in times.enumerated() {
            if let date = formatter.date(from: String(stamp.prefix(16))), date >= now.addingTimeInterval(-1800) {
                return i
            }
        }
        return min(2 * 24, max(0, times.count - 1))
    }

    private static func dayLabel(_ date: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = parser.date(from: date) else { return date }
        parser.dateFormat = "EEE MMM d"
        parser.locale = Locale(identifier: "en_US")
        return parser.string(from: parsed)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
