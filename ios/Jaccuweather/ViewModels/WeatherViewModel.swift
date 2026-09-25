import Foundation
import CoreLocation
import Observation
import SwiftUI
import UIKit

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocationCoordinate2D) -> Void)?
    var onDenied: (() -> Void)?
    var onFail: ((Error) -> Void)?
    private let manager = CLLocationManager()
    private var delegateReady = false

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    var isDenied: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted: return true
        default: return !CLLocationManager.locationServicesEnabled()
        }
    }

    func request() {
        if !delegateReady {
            delegateReady = true
            manager.delegate = self
        }
        guard CLLocationManager.locationServicesEnabled() else {
            onDenied?()
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            onDenied?()
        @unknown default:
            onDenied?()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            onDenied?()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        onUpdate?(coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFail?(error)
    }
}

struct HourRow: Identifiable, Equatable {
    let id: Int
    let time: String
    let clock: String
    let code: Int?
    let isDay: Bool
    let temp: Double?
    let feels: Double?
    let precip: Double?
    let snow: Double?
    let precipChance: Int?
    let wind: Double?
    let windDir: Double?
    let windGust: Double?
    let uv: Double?
    let uvLabel: String
    let cloudLow: Double?
    let cloudMid: Double?
    let cloudHigh: Double?
    let pressure: Double?
    let cloud: Double?
    let humidity: Double?
    let radiation: Double?
    let brightness: Double
    let niceScore: Double
    let moonPhase: Double
    let iconFile: String
}

struct DayRow: Identifiable, Equatable {
    let id: Int
    let date: String
    let label: String
    let fullLabel: String
    let summary: String
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
    let sunriseClock: String
    let sunsetClock: String
    let iconFile: String
    let snowSum: Double
    let gust: Double
    let humidityAvg: Double
    let cloudLowAvg: Double
    let cloudMidAvg: Double
    let cloudHighAvg: Double
    let brightness: Double
    let pressureInHg: Double
    let niceScore: Double
    let moonPhase: Double
}

struct SunSnapshot: Equatable {
    var high: Double?
    var low: Double?
    var sunriseLabel: String
    var sunsetLabel: String
    var sunriseMs: Double
    var sunsetMs: Double
}

struct MoonSnapshot: Equatable {
    var emoji: String = "🌑"
    var name: String = "—"
    var rise: String = "—"
    var set: String = "—"
    var illumination: String = "—"
    var nextFull: String = "—"
    var nextNew: String = "—"
}

private struct PlacePreference: Codable {
    var followsDeviceLocation: Bool
    var explicit: GeoResult?
    var lastKnown: GeoResult?
}

private enum PlaceStore {
    static let key = "jaccuweather.placePreference.v1"

    static func load() -> PlacePreference {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(PlacePreference.self, from: data) else {
            return PlacePreference(followsDeviceLocation: true, explicit: nil, lastKnown: nil)
        }
        return stored
    }

    static func save(_ preference: PlacePreference) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@Observable
@MainActor
final class WeatherViewModel {
    var locationName = ""
    var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var weather: WeatherBundle?
    var pollen: JSONMap?
    var alerts: [NWSAlertFeature] = []
    var alertIconFiles: [String: String] = [:]
    var tides: TideSnapshot?
    var health: CachedHealth?
    var isLoading = false
    var isLocating = false
    var showsPlacePrompt = false
    var hasResolvedPlace = false
    var errorMessage: String?
    var statusNote: String?
    var searchQuery = ""
    var searchResults: [GeoResult] = []
    var isSearching = false
    var lastFetchMs: Double = 0
    var lastUpdatedLabel = ""
    var hourlyMode = "conditions"
    var hourlyRows: [HourRow] = []
    var dailyRows: [DayRow] = []
    var sun: SunSnapshot?
    var precipTiming = ""
    var pressureText = "—"
    var pressureTrend = "Steady"
    var moon = MoonSnapshot()
    var conditionDescription = ""
    var conditionIcon = "clear-day.svg"
    var currentUVDetail = ""

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
    private var preference = PlacePreference(followsDeviceLocation: true, explicit: nil, lastKnown: nil)
    private var followsDeviceLocation = true
    private var sessionPinsLocation = false
    private var holdingLastKnown = false
    private var locationTries = 0
    private var lastFix: CLLocationCoordinate2D?
    private var refreshSerial = 0

    var currentPlace: GeoResult {
        GeoResult(name: locationName, latitude: coordinate.latitude, longitude: coordinate.longitude, admin1: nil, country: nil)
    }

    var pressureDisplay: (value: String, trend: String) { (pressureText, pressureTrend) }

    var blockingMessage: String? {
        guard weather == nil, !showsPlacePrompt else { return nil }
        if isLocating { return "Finding your location…" }
        if isLoading { return "Fetching ensemble forecast…" }
        return nil
    }

    init() {
        _ = LogicEngine.shared
        preference = PlaceStore.load()
        followsDeviceLocation = preference.followsDeviceLocation
        if let lat = LaunchArgs.latitude, let lon = LaunchArgs.longitude {
            sessionPinsLocation = true
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            locationName = LaunchArgs.placeName ?? "Pinned location"
            hasResolvedPlace = true
        } else if !preference.followsDeviceLocation, let place = preference.explicit {
            followsDeviceLocation = false
            coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            locationName = place.displayName
            hasResolvedPlace = true
            lastFix = coordinate
        } else {
            followsDeviceLocation = true
            if let last = preference.lastKnown {
                coordinate = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
                locationName = last.displayName
                hasResolvedPlace = true
                lastFix = coordinate
            } else {
                isLocating = true
                locationName = ""
                hasResolvedPlace = false
            }
        }
        locator.onUpdate = { [weak self] coordinate in
            Task { @MainActor in
                self?.handleLocation(coordinate)
            }
        }
        locator.onDenied = { [weak self] in
            Task { @MainActor in
                self?.applyLocationUnavailable()
            }
        }
        locator.onFail = { [weak self] error in
            Task { @MainActor in
                self?.noteLocationFailure(error)
            }
        }
        startTicker()
    }

    func bootstrap() async {
        if hasResolvedPlace {
            if followsDeviceLocation && !sessionPinsLocation {
                locator.request()
            }
            await refresh()
            return
        }
        locator.request()
    }

    func refresh() async {
        guard hasResolvedPlace else { return }
        refreshSerial += 1
        let serial = refreshSerial
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let geocode = shouldReverseGeocode
        if weather == nil { isLoading = true }
        errorMessage = nil
        defer {
            if serial == refreshSerial { isLoading = false }
        }

        let nameTask: Task<String?, Never>? = geocode ? Task { [geocoding] in
            try? await geocoding.reverse(latitude: lat, longitude: lon)
        } : nil
        let weatherTask = Task.detached(priority: .userInitiated) {
            try await ForecastWork.load(latitude: lat, longitude: lon)
        }
        let pollenTask = Task.detached(priority: .userInitiated) {
            await PollenService().load(latitude: lat, longitude: lon)
        }
        let alertsTask = Task.detached(priority: .userInitiated) {
            await AlertsService().alerts(latitude: lat, longitude: lon)
        }

        do {
            let (bundle, derived) = try await weatherTask.value
            guard serial == refreshSerial else { return }
            apply(derived, bundle: bundle)
            if followsDeviceLocation && !sessionPinsLocation {
                rememberDevicePlace()
            }
            isLoading = false

            let pollen = await pollenTask.value
            let alerts = await alertsTask.value
            let resolvedName = await nameTask?.value
            guard serial == refreshSerial else { return }

            self.pollen = pollen
            self.alerts = alerts
            var icons: [String: String] = [:]
            for alert in alerts {
                let key = alert.properties.event ?? ""
                if icons[key] == nil {
                    icons[key] = LogicEngine.shared.alertIconFile(alert.properties.event)
                }
            }
            alertIconFiles = icons
            if let resolvedName, !resolvedName.isEmpty {
                locationName = resolvedName
                if followsDeviceLocation && !sessionPinsLocation {
                    rememberDevicePlace()
                }
            }
            let scored = await Self.healthOffMain(weather: bundle, pollen: pollen)
            guard serial == refreshSerial else { return }
            health = scored
            let tides = await tideService.load(latitude: lat, longitude: lon, elevation: bundle.elevation)
            guard serial == refreshSerial else { return }
            self.tides = tides
            if holdingLastKnown {
                statusNote = "Location access is off. Showing the last place used on this phone."
            } else {
                statusNote = pollen == nil ? "Pollen request failed. Blank keys still use Open-Meteo when that call succeeds." : nil
            }
        } catch {
            guard serial == refreshSerial else { return }
            errorMessage = error.localizedDescription
        }
    }

    func select(_ place: GeoResult) async {
        followsDeviceLocation = false
        holdingLastKnown = false
        sessionPinsLocation = false
        showsPlacePrompt = false
        preference.followsDeviceLocation = false
        preference.explicit = place
        preference.lastKnown = place
        PlaceStore.save(preference)
        coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        locationName = place.displayName
        lastFix = coordinate
        hasResolvedPlace = true
        searchQuery = ""
        searchResults = []
        statusNote = nil
        await refresh()
    }

    func requestDeviceLocation() {
        sessionPinsLocation = false
        followsDeviceLocation = true
        holdingLastKnown = false
        preference.followsDeviceLocation = true
        preference.explicit = nil
        PlaceStore.save(preference)
        showsPlacePrompt = false
        locationTries = 0
        if locator.isDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            applyLocationUnavailable()
            return
        }
        if weather == nil { isLocating = true }
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

    func handleBecameActive() async {
        tickLastUpdated()
        if followsDeviceLocation && !sessionPinsLocation && showsPlacePrompt {
            locator.request()
            return
        }
        let now = Date().timeIntervalSince1970 * 1000
        let should = LogicEngine.shared.bool("shouldRefetchStaleForecast", [now, lastFetchMs, staleAfterMs])
        if should { await refresh() }
    }

    func tickLastUpdated() {
        let now = Date().timeIntervalSince1970 * 1000
        lastUpdatedLabel = LogicEngine.shared.string("formatLastUpdatedBetween", [now, lastFetchMs]) ?? ""
    }

    private var shouldReverseGeocode: Bool {
        if holdingLastKnown { return false }
        if sessionPinsLocation && LaunchArgs.placeName != nil { return false }
        if !followsDeviceLocation && !sessionPinsLocation { return false }
        return true
    }

    private func handleLocation(_ coordinate: CLLocationCoordinate2D) {
        guard followsDeviceLocation || isLocating else { return }
        if let applied = lastFix,
           Self.close(applied, coordinate),
           weather != nil || isLoading {
            isLocating = false
            return
        }
        lastFix = coordinate
        isLocating = false
        showsPlacePrompt = false
        holdingLastKnown = false
        hasResolvedPlace = true
        self.coordinate = coordinate
        if let last = preference.lastKnown, Self.near(last, coordinate) {
            locationName = last.displayName
        } else {
            locationName = "Current location"
        }
        statusNote = nil
        Task { await refresh() }
    }

    private func noteLocationFailure(_ error: Error) {
        if let code = (error as? CLError)?.code, code == .denied {
            applyLocationUnavailable()
            return
        }
        locationTries += 1
        if locationTries < 3, locator.isAuthorized {
            locator.request()
            return
        }
        applyLocationUnavailable()
    }

    private func applyLocationUnavailable() {
        isLocating = false
        isLoading = false
        if let last = preference.lastKnown {
            let already = hasResolvedPlace
                && Self.close(coordinate, CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))
                && weather != nil
            showsPlacePrompt = false
            holdingLastKnown = true
            statusNote = "Location access is off. Showing the last place used on this phone."
            if !already {
                hasResolvedPlace = true
                coordinate = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
                locationName = last.displayName
                lastFix = coordinate
                Task { await refresh() }
            }
            return
        }
        if weather == nil {
            showsPlacePrompt = true
            errorMessage = nil
        }
    }

    private func rememberDevicePlace() {
        let name = locationName.isEmpty ? "Current location" : locationName
        preference.followsDeviceLocation = true
        preference.lastKnown = GeoResult(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, admin1: nil, country: nil)
        PlaceStore.save(preference)
    }

    private func apply(_ derived: DerivedForecast, bundle: WeatherBundle) {
        weather = bundle
        hourlyRows = derived.hourly
        dailyRows = derived.daily
        sun = derived.sun
        precipTiming = derived.precipTiming
        pressureText = derived.pressureText
        pressureTrend = derived.pressureTrend
        moon = derived.moon
        conditionDescription = derived.conditionDescription
        conditionIcon = derived.conditionIcon
        currentUVDetail = derived.currentUVDetail
        lastFetchMs = Date().timeIntervalSince1970 * 1000
        tickLastUpdated()
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

    private static func healthOffMain(weather: WeatherBundle, pollen: JSONMap?) async -> CachedHealth {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: CachedHealth.make(weather: weather, pollen: pollen))
            }
        }
    }

    private static func close(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 0.0008 && abs(a.longitude - b.longitude) < 0.0008
    }

    private static func near(_ place: GeoResult, _ coordinate: CLLocationCoordinate2D) -> Bool {
        let dLat = (place.latitude - coordinate.latitude) * 111
        let dLon = (place.longitude - coordinate.longitude) * 111 * cos(place.latitude * .pi / 180)
        return (dLat * dLat + dLon * dLon) < 30 * 30
    }
}

private enum ForecastWork {
    static func load(latitude: Double, longitude: Double) async throws -> (WeatherBundle, DerivedForecast) {
        let bundle = try await WeatherService().ensemble(latitude: latitude, longitude: longitude)
        let derived = DerivedForecast.build(bundle, latitude: latitude, longitude: longitude)
        return (bundle, derived)
    }
}

struct DerivedForecast {
    var hourly: [HourRow]
    var daily: [DayRow]
    var sun: SunSnapshot?
    var precipTiming: String
    var pressureText: String
    var pressureTrend: String
    var moon: MoonSnapshot
    var conditionDescription: String
    var conditionIcon: String
    var currentUVDetail: String

    static func build(_ weather: WeatherBundle, latitude: Double, longitude: Double) -> DerivedForecast {
        let logic = LogicEngine.shared
        let hourlyMap = weather.hourly
        let dailyMap = weather.daily
        let times = hourlyMap.strings("time")
        let codes = hourlyMap.numbers("weather_code")
        let isDayValues = hourlyMap.numbers("is_day")
        let temps = hourlyMap.numbers("temperature_2m")
        let feels = hourlyMap.numbers("apparent_temperature")
        let precips = hourlyMap.numbers("precipitation")
        let snows = hourlyMap.numbers("snowfall")
        let chances = hourlyMap.numbers("precipitation_probability")
        let winds = hourlyMap.numbers("wind_speed_10m")
        let windDirs = hourlyMap.numbers("wind_direction_10m")
        let gusts = hourlyMap.numbers("wind_gusts_10m")
        let uvs = hourlyMap.numbers("uv_index")
        let cloudLows = hourlyMap.numbers("cloud_cover_low")
        let cloudMids = hourlyMap.numbers("cloud_cover_mid")
        let cloudHighs = hourlyMap.numbers("cloud_cover_high")
        let pressures = hourlyMap.numbers("surface_pressure")
        let clouds = hourlyMap.numbers("cloud_cover")
        let humidities = hourlyMap.numbers("relative_humidity_2m")
        let radiation = hourlyMap.numbers("shortwave_radiation")

        let dayTimes = dailyMap.strings("time")
        let dayCodes = dailyMap.numbers("weather_code")
        let dayHighs = dailyMap.numbers("temperature_2m_max")
        let dayLows = dailyMap.numbers("temperature_2m_min")
        let dayPrecips = dailyMap.numbers("precipitation_sum")
        let dayChances = dailyMap.numbers("precipitation_probability_max")
        let dayUVs = dailyMap.numbers("uv_index_max")
        let dayWinds = dailyMap.numbers("wind_speed_10m_max")
        let dayFeelsHigh = dailyMap.numbers("apparent_temperature_max")
        let dayFeelsLow = dailyMap.numbers("apparent_temperature_min")
        let daySunrise = dailyMap.strings("sunrise")
        let daySunset = dailyMap.strings("sunset")
        let daySnow = dailyMap.numbers("snowfall_sum")
        let dayGust = dailyMap.numbers("wind_gusts_10m_max")
        let startDay = weather.todayIndex

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let shortOut = DateFormatter()
        shortOut.locale = Locale(identifier: "en_US")
        shortOut.dateFormat = "EEE MMM d"
        let fullOut = DateFormatter()
        fullOut.locale = Locale(identifier: "en_US")
        fullOut.dateFormat = "EEEE MMM d"

        func clock(_ iso: String?) -> String {
            guard let iso, !iso.isEmpty else { return "" }
            return logic.string("formatIsoLocalClock", [iso]) ?? ""
        }
        func labels(_ date: String) -> (short: String, full: String) {
            guard let parsed = parser.date(from: date) else { return (date, date) }
            return (shortOut.string(from: parsed), fullOut.string(from: parsed))
        }
        func average(_ field: String, _ date: String) -> Double {
            logic.number("getAverageHourlyValueForDate", [hourlyMap.raw, field, date]) ?? 0
        }
        func noonPressure(_ date: String) -> Double {
            let noon = times.firstIndex { $0.hasPrefix(date) && $0.contains("T12:") } ?? times.firstIndex { $0.hasPrefix(date) }
            guard let noon, noon < pressures.count, let hpa = pressures[noon] else { return 0 }
            return hpa * 0.02953
        }
        func moonPhase(_ iso: String) -> Double {
            let ms = logic.number("parseLocationLocalIso", [iso, weather.utcOffset]) ?? 0
            return logic.number("calculateMoonPhase", [ms]) ?? 0
        }
        func niceScore(_ date: String, index: Int) -> Double {
            let avg = logic.object("calculateDailyAveragesForDateString", [hourlyMap.raw, date]) as Any
            let breakdown = logic.object("getNiceWeatherBreakdown", [weather.root.raw, avg, index])
            return JSONMap(breakdown).number("score") ?? 0
        }

        var radiationAvgs: [Double] = []
        var dailyDraft: [(index: Int, date: String, chance: Double?, radiation: Double)] = []
        for (index, date) in dayTimes.enumerated() where index >= startDay {
            let chance = dayChances.indices.contains(index) ? dayChances[index] : nil
            let rad = average("shortwave_radiation", date)
            radiationAvgs.append(rad)
            dailyDraft.append((index, date, chance, rad))
        }
        let maxDailyRad = max(radiationAvgs.max() ?? 0, 1)
        var niceByDate: [String: Double] = [:]
        let daily: [DayRow] = dailyDraft.map { draft in
            let index = draft.index
            let date = draft.date
            let text = labels(date)
            let code = dayCodes.indices.contains(index) ? dayCodes[index] : nil
            let chance = draft.chance
            let sunrise = daySunrise.indices.contains(index) ? daySunrise[index] : nil
            let sunset = daySunset.indices.contains(index) ? daySunset[index] : nil
            let score = niceScore(date, index: index)
            niceByDate[date] = score
            return DayRow(
                id: index,
                date: date,
                label: text.short,
                fullLabel: text.full,
                summary: logic.weatherDescription(code.map { Int($0) }),
                code: code.map { Int($0) },
                high: dayHighs.indices.contains(index) ? dayHighs[index] : nil,
                low: dayLows.indices.contains(index) ? dayLows[index] : nil,
                precip: dayPrecips.indices.contains(index) ? dayPrecips[index] : nil,
                precipChance: chance.map { Int($0) },
                uv: dayUVs.indices.contains(index) ? dayUVs[index] : nil,
                wind: dayWinds.indices.contains(index) ? dayWinds[index] : nil,
                feelsHigh: dayFeelsHigh.indices.contains(index) ? dayFeelsHigh[index] : nil,
                feelsLow: dayFeelsLow.indices.contains(index) ? dayFeelsLow[index] : nil,
                sunrise: sunrise,
                sunset: sunset,
                sunriseClock: clock(sunrise),
                sunsetClock: clock(sunset),
                iconFile: logic.weatherIconFile(code: code.map { Int($0) }, isDay: true, precipProbability: chance),
                snowSum: (daySnow.indices.contains(index) ? daySnow[index] : nil) ?? 0,
                gust: (dayGust.indices.contains(index) ? dayGust[index] : nil) ?? 0,
                humidityAvg: average("relative_humidity_2m", date),
                cloudLowAvg: average("cloud_cover_low", date),
                cloudMidAvg: average("cloud_cover_mid", date),
                cloudHighAvg: average("cloud_cover_high", date),
                brightness: draft.radiation / maxDailyRad * 100,
                pressureInHg: noonPressure(date),
                niceScore: score,
                moonPhase: moonPhase(date + "T12:00")
            )
        }

        let startHour = hourlyStartIndex(times: times, utcOffset: weather.utcOffset)
        var hourRadiation: [Double] = []
        for offset in 0..<48 {
            let index = startHour + offset
            guard index < times.count else { break }
            hourRadiation.append((radiation.indices.contains(index) ? radiation[index] : nil) ?? 0)
        }
        let maxHourRad = max(hourRadiation.max() ?? 0, 1)
        var hourly: [HourRow] = []
        hourly.reserveCapacity(hourRadiation.count)
        for offset in 0..<hourRadiation.count {
            let index = startHour + offset
            let code = codes.indices.contains(index) ? codes[index] : nil
            let isDay = ((isDayValues.indices.contains(index) ? isDayValues[index] : nil) ?? 1) != 0
            let chance = chances.indices.contains(index) ? chances[index] : nil
            let uv = uvs.indices.contains(index) ? uvs[index] : nil
            let stamp = times[index]
            let date = String(stamp.prefix(10))
            hourly.append(HourRow(
                id: index,
                time: stamp,
                clock: logic.string("formatIsoLocalClock", [stamp]) ?? stamp,
                code: code.map { Int($0) },
                isDay: isDay,
                temp: temps.indices.contains(index) ? temps[index] : nil,
                feels: feels.indices.contains(index) ? feels[index] : nil,
                precip: precips.indices.contains(index) ? precips[index] : nil,
                snow: snows.indices.contains(index) ? snows[index] : nil,
                precipChance: chance.map { Int($0) },
                wind: winds.indices.contains(index) ? winds[index] : nil,
                windDir: windDirs.indices.contains(index) ? windDirs[index] : nil,
                windGust: gusts.indices.contains(index) ? gusts[index] : nil,
                uv: uv,
                uvLabel: uv.map { logic.uvLabel($0) } ?? "",
                cloudLow: cloudLows.indices.contains(index) ? cloudLows[index] : nil,
                cloudMid: cloudMids.indices.contains(index) ? cloudMids[index] : nil,
                cloudHigh: cloudHighs.indices.contains(index) ? cloudHighs[index] : nil,
                pressure: pressures.indices.contains(index) ? pressures[index] : nil,
                cloud: clouds.indices.contains(index) ? clouds[index] : nil,
                humidity: humidities.indices.contains(index) ? humidities[index] : nil,
                radiation: radiation.indices.contains(index) ? radiation[index] : nil,
                brightness: hourRadiation[offset] / maxHourRad * 100,
                niceScore: niceByDate[date] ?? 0,
                moonPhase: moonPhase(stamp),
                iconFile: logic.weatherIconFile(code: code.map { Int($0) }, isDay: isDay)
            ))
        }

        let current = weather.current
        let isDay = current.int("is_day") != 0
        let description = logic.weatherDescription(current.int("weather_code"))
        let icon = logic.weatherIconFile(code: current.int("weather_code"), isDay: isDay)
        let uvDetail = current.number("uv_index").map { logic.uvLabel($0) } ?? ""
        let sun: SunSnapshot? = daily.first.map { today in
            let riseMs = logic.number("parseLocationLocalIso", [today.sunrise ?? "", weather.utcOffset]) ?? 0
            let setMs = logic.number("parseLocationLocalIso", [today.sunset ?? "", weather.utcOffset]) ?? 0
            return SunSnapshot(
                high: today.high,
                low: today.low,
                sunriseLabel: today.sunriseClock.isEmpty ? "—" : today.sunriseClock,
                sunsetLabel: today.sunsetClock.isEmpty ? "—" : today.sunsetClock,
                sunriseMs: riseMs,
                sunsetMs: setMs
            )
        }

        var precip = "No precipitation expected in the next 48 hours"
        if let first = hourly.first(where: { ($0.precip ?? 0) > 0 }) {
            let kind = (first.snow ?? 0) > 0 ? "Snow" : "Rain"
            if first.id == hourly.first?.id {
                precip = "\(kind) is currently falling"
            } else {
                precip = "\(kind) expected around \(first.clock)"
            }
        }

        var pressureText = "—"
        var pressureTrend = "Steady"
        if let hpa = current.number("surface_pressure") {
            pressureText = String(format: "%.2f\"", hpa * 0.02953)
            if let idx = hourly.first?.id, idx >= 3,
               pressures.indices.contains(idx), let cur = pressures[idx],
               pressures.indices.contains(idx - 3), let past = pressures[idx - 3] {
                let diff = cur - past
                if diff > 1 { pressureTrend = "Rising" }
                else if diff < -1 { pressureTrend = "Falling" }
            }
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let phase = logic.number("calculateMoonPhase", [nowMs]) ?? 0
        let info = JSONMap(logic.object("getMoonPhase", [phase]))
        let moonTimes = JSONMap(logic.object("moonTimesMs", [nowMs, latitude, longitude]))
        let offset = weather.utcOffset
        let moon = MoonSnapshot(
            emoji: info.string("emoji") ?? "🌑",
            name: info.string("name") ?? "Unknown",
            rise: moonTimes.number("rise").flatMap { logic.string("formatInstantInLocation", [$0, offset]) } ?? "n/a",
            set: moonTimes.number("set").flatMap { logic.string("formatInstantInLocation", [$0, offset]) } ?? "n/a",
            illumination: logic.number("getMoonIllumination", [nowMs]).map { "\(Int($0))%" } ?? "—",
            nextFull: JSONMap(logic.object("getNextFullMoon", [nowMs])).int("days").map { "in \($0)d" } ?? "—",
            nextNew: JSONMap(logic.object("getNextNewMoon", [nowMs])).int("days").map { "in \($0)d" } ?? "—"
        )

        return DerivedForecast(
            hourly: hourly,
            daily: daily,
            sun: sun,
            precipTiming: precip,
            pressureText: pressureText,
            pressureTrend: pressureTrend,
            moon: moon,
            conditionDescription: description,
            conditionIcon: icon,
            currentUVDetail: uvDetail
        )
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
}

enum WindCompass {
    private static let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    static func label(_ degrees: Double) -> String {
        let wrapped = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((wrapped / 22.5).rounded()) % 16
        return names[index]
    }

    /// Open-Meteo direction is meteorological (degrees the wind comes FROM).
    /// The arrow points the way the wind is going, opposite of FROM.
    static func arrowDegrees(_ fromDegrees: Double) -> Double { fromDegrees + 180 }
}
