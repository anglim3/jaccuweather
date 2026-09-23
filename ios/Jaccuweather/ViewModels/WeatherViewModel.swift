import Foundation
import CoreLocation
import Observation

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
        if let coordinate = locations.last?.coordinate {
            onUpdate?(coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFail?(error)
    }
}

@Observable
@MainActor
final class WeatherViewModel {
    var locationName = "Seattle, Washington"
    var coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    var forecast: ForecastResponse?
    var pollen: PollenSnapshot?
    var alerts: [NWSAlertFeature] = []
    var isLoading = false
    var errorMessage: String?
    var searchQuery = ""
    var searchResults: [GeoResult] = []
    var isSearching = false

    let favorites = FavoritesStore()

    private let weather = WeatherService()
    private let geocoding = GeocodingService()
    private let pollenService = PollenService()
    private let alertsService = AlertsService()
    private let locator = LocationProvider()
    private var searchTask: Task<Void, Never>?

    var currentPlace: GeoResult {
        GeoResult(
            name: locationName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            admin1: nil,
            country: nil
        )
    }

    var hourlyPoints: [HourlyPoint] {
        guard let hourly = forecast?.hourly else { return [] }
        let now = Date()
        return zip(hourly.time.indices, hourly.time).compactMap { index, stamp in
            guard let date = parseLocal(stamp), date >= now.addingTimeInterval(-3600) else { return nil }
            return HourlyPoint(
                id: stamp,
                time: stamp,
                temperature: hourly.temperature2m[safe: index] ?? nil,
                weatherCode: hourly.weatherCode[safe: index] ?? nil,
                precipChance: hourly.precipitationProbability[safe: index] ?? nil
            )
        }
        .prefix(48)
        .map { $0 }
    }

    var dailyPoints: [DailyPoint] {
        guard let daily = forecast?.daily else { return [] }
        let start = daily.todayIndex
        return daily.time.enumerated().compactMap { index, date in
            guard index >= start else { return nil }
            return DailyPoint(
                id: date,
                date: date,
                weatherCode: daily.weatherCode[safe: index] ?? nil,
                high: daily.temperature2mMax[safe: index] ?? nil,
                low: daily.temperature2mMin[safe: index] ?? nil,
                precip: daily.precipitationSum[safe: index] ?? nil
            )
        }
    }

    var sinus: HealthScores.Risk? {
        guard let daily = forecast?.daily, let hourly = forecast?.hourly else { return nil }
        let today = daily.todayIndex
        let high = daily.temperature2mMax[safe: today] ?? nil
        let low = daily.temperature2mMin[safe: today] ?? nil
        let swing = (high ?? 0) - (low ?? 0)
        let humidity = Double(forecast?.current?.relativeHumidity2m ?? 0)
        let precip = forecast?.current?.precipitation ?? 0
        var pressureChange = 0.0
        if let pressures = hourly.surfacePressure, pressures.count > 24 {
            let recent = pressures.compactMap { $0 }.suffix(24)
            let previous = pressures.compactMap { $0 }.dropLast(24).suffix(24)
            if let r = recent.last, let p = previous.last {
                // Open-Meteo surface_pressure is hPa; website uses inHg for the sinus helper.
                pressureChange = (r - p) / 33.8639
            }
        }
        return HealthScores.sinusRisk(
            pressureChangeInHg: pressureChange,
            humidity: humidity,
            precipitationInches: precip,
            tempSwingF: swing
        )
    }

    var allergy: HealthScores.Risk {
        HealthScores.allergyRisk(pollen: pollen)
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
                guard let self else { return }
                if self.forecast == nil {
                    self.errorMessage = "Location unavailable. Showing Seattle. \(error.localizedDescription)"
                }
            }
        }
    }

    func bootstrap() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let forecastTask = weather.forecast(latitude: coordinate.latitude, longitude: coordinate.longitude)
            async let pollenTask = pollenService.load(latitude: coordinate.latitude, longitude: coordinate.longitude)
            async let alertsTask = alertsService.alerts(latitude: coordinate.latitude, longitude: coordinate.longitude)
            forecast = try await forecastTask
            pollen = await pollenTask
            alerts = await alertsTask
            if locationName.contains(",") == false || locationName == "Current location" {
                locationName = (try? await geocoding.reverse(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? locationName
            }
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

    func requestDeviceLocation() {
        locator.request()
    }

    func updateSearch(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        let q = searchQuery
        guard q.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await geocoding.search(query: q)) ?? []
    }

    private func parseLocal(_ stamp: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let date = iso.date(from: stamp) { return date }
        iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let date = iso.date(from: stamp) { return date }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: stamp)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
