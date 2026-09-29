import AppIntents
import Foundation

/// Last successful forecast readings, keyed by rounded coordinates, in the app
/// sandbox. Shortcuts read this without an App Group.
enum IntentForecastStore {
    private static let defaultsKey = "jaccuweather.intentForecast.v1"
    private static let lock = NSLock()
    private static let readingLimit = 8

    private struct Cache: Codable {
        var currentKey: String?
        var readings: [String: IntentForecastReading]
    }

    static func current() -> IntentForecastReading? {
        lock.lock()
        defer { lock.unlock() }
        let cache = loadUnlocked()
        guard let key = cache.currentKey else { return nil }
        return cache.readings[key]
    }

    static func reading(latitude: Double, longitude: Double) -> IntentForecastReading? {
        lock.lock()
        defer { lock.unlock() }
        let key = IntentForecastCopy.placeKey(latitude: latitude, longitude: longitude)
        return loadUnlocked().readings[key]
    }

    static func save(_ reading: IntentForecastReading, makeCurrent: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var cache = loadUnlocked()
        let key = IntentForecastCopy.placeKey(latitude: reading.latitude, longitude: reading.longitude)
        cache.readings[key] = reading
        if makeCurrent {
            cache.currentKey = key
        }
        trim(&cache)
        guard let data = try? encoder.encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func loadUnlocked() -> Cache {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let cache = try? decoder.decode(Cache.self, from: data) else {
            return Cache(currentKey: nil, readings: [:])
        }
        return cache
    }

    private static func trim(_ cache: inout Cache) {
        guard cache.readings.count > readingLimit else { return }
        let ranked = cache.readings.sorted { $0.value.fetchedAt > $1.value.fetchedAt }
        var keep = Set(ranked.prefix(readingLimit).map(\.key))
        if let current = cache.currentKey {
            keep.insert(current)
        }
        cache.readings = cache.readings.filter { keep.contains($0.key) }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum IntentOpenRequest {
    static let notification = Notification.Name("jaccuweather.intentOpen")
    private static let key = "jaccuweather.intentOpen.v1"

    struct Payload: Codable {
        var token: String
        var name: String?
        var latitude: Double?
        var longitude: Double?
    }

    static func post(place: FavoritePlace?) {
        let payload = Payload(
            token: UUID().uuidString,
            name: place?.name,
            latitude: place?.latitude,
            longitude: place?.longitude
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func take() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}

struct FavoritePlace: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Favorite")
    static var defaultQuery = FavoritePlaceQuery()

    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(place: GeoResult) {
        id = place.id
        name = place.displayName
        latitude = place.latitude
        longitude = place.longitude
    }
}

struct FavoritePlaceQuery: EntityQuery {
    func entities(for identifiers: [FavoritePlace.ID]) async throws -> [FavoritePlace] {
        let places = Self.load()
        return identifiers.compactMap { id in places.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [FavoritePlace] {
        Self.load()
    }

    fileprivate static func load() -> [FavoritePlace] {
        guard let data = UserDefaults.standard.data(forKey: "weatherFavorites"),
              let places = try? JSONDecoder().decode([GeoResult].self, from: data) else {
            return []
        }
        return places.map(FavoritePlace.init(place:))
    }
}

extension FavoritePlaceQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [FavoritePlace] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let places = Self.load()
        guard !needle.isEmpty else { return places }
        return places.filter { $0.name.lowercased().contains(needle) }
    }
}

enum CurrentWeatherDonation {
    static func donate() {
        Task {
            try? await GetCurrentWeather().donate()
        }
    }
}

private enum CurrentWeatherIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noPlace
    case unavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noPlace:
            return "Open Jaccuweather once so it can save a place."
        case .unavailable:
            return "Current weather is unavailable right now."
        }
    }
}

private enum CurrentWeatherLoader {
    static func load(favorite: FavoritePlace?) async throws -> (IntentForecastReading, Bool) {
        let targetName: String
        let latitude: Double
        let longitude: Double
        let makeCurrent: Bool
        if let favorite {
            targetName = favorite.name
            latitude = favorite.latitude
            longitude = favorite.longitude
            makeCurrent = false
        } else if let current = IntentForecastStore.current() {
            targetName = current.placeName
            latitude = current.latitude
            longitude = current.longitude
            makeCurrent = true
        } else if let saved = SavedPlace.current() {
            targetName = saved.displayName
            latitude = saved.latitude
            longitude = saved.longitude
            makeCurrent = true
        } else {
            throw CurrentWeatherIntentError.noPlace
        }

        if var cached = IntentForecastStore.reading(latitude: latitude, longitude: longitude),
           IntentForecastCopy.isFresh(fetchedAt: cached.fetchedAt, now: Date()) {
            cached.placeName = targetName
            return (cached, false)
        }

        if let fetched = await IntentForecastFetch.load(name: targetName, latitude: latitude, longitude: longitude) {
            IntentForecastStore.save(fetched, makeCurrent: makeCurrent)
            return (fetched, false)
        }

        if var cached = IntentForecastStore.reading(latitude: latitude, longitude: longitude) {
            cached.placeName = targetName
            return (cached, true)
        }
        throw CurrentWeatherIntentError.unavailable
    }
}

private enum IntentForecastFetch {
    static func load(name: String, latitude: Double, longitude: Double) async -> IntentForecastReading? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard let current = payload.current, let temperature = current.temperature2m else { return nil }
            let isDay = (current.isDay ?? 1) != 0
            return IntentForecastReading(
                placeName: name,
                latitude: latitude,
                longitude: longitude,
                temperatureF: temperature,
                feelsLikeF: current.apparentTemperature,
                conditionText: IntentForecastCopy.conditionText(weatherCode: current.weatherCode),
                symbolName: WidgetWeatherCode.symbol(code: current.weatherCode, isDay: isDay),
                fetchedAt: Date()
            )
        } catch {
            return nil
        }
    }

    private struct Payload: Decodable {
        let current: Current?
    }

    private struct Current: Decodable {
        let temperature2m: Double?
        let apparentTemperature: Double?
        let weatherCode: Int?
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }
}

struct GetCurrentWeather: AppIntent {
    static var title: LocalizedStringResource = "Get Current Weather"
    static var description = IntentDescription("Place, temperature, condition, and feels-like for the saved place, or a favorite.")
    static var openAppWhenRun = false

    @Parameter(title: "Favorite", description: "A saved favorite. Leave empty for the place last loaded in the app.")
    var place: FavoritePlace?

    static var parameterSummary: some ParameterSummary {
        Summary("Get the current weather") {
            \.$place
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let (reading, stale) = try await CurrentWeatherLoader.load(favorite: place)
        let spoken = IntentForecastCopy.spoken(
            placeName: reading.placeName,
            temperatureF: reading.temperatureF,
            conditionText: reading.conditionText,
            feelsLikeF: reading.feelsLikeF,
            stale: stale
        )
        let supporting = IntentForecastCopy.supportingLine(
            temperatureF: reading.temperatureF,
            conditionText: reading.conditionText,
            feelsLikeF: reading.feelsLikeF
        )
        let value = IntentForecastCopy.resultText(
            placeName: reading.placeName,
            temperatureF: reading.temperatureF,
            conditionText: reading.conditionText,
            feelsLikeF: reading.feelsLikeF
        )
        let full = LocalizedStringResource(stringLiteral: spoken)
        let support = LocalizedStringResource(stringLiteral: supporting)
        let dialog: IntentDialog
        if #available(iOS 17.2, *) {
            dialog = IntentDialog(full: full, supporting: support, systemImageName: reading.symbolName)
        } else {
            dialog = IntentDialog(full: full, supporting: support)
        }
        return .result(value: value, dialog: dialog)
    }
}

struct OpenJaccuweather: AppIntent {
    static var title: LocalizedStringResource = "Open Jaccuweather"
    static var description = IntentDescription("Opens the Now tab. Choose a favorite to switch places.")
    static var openAppWhenRun = true

    @Parameter(title: "Favorite", description: "A saved favorite. Leave empty to keep the current place.")
    var place: FavoritePlace?

    static var parameterSummary: some ParameterSummary {
        Summary("Open Jaccuweather") {
            \.$place
        }
    }

    func perform() async throws -> some IntentResult {
        IntentOpenRequest.post(place: place)
        return .result()
    }
}

struct JaccuweatherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCurrentWeather(),
            phrases: [
                "What's the weather in \(.applicationName)"
            ],
            shortTitle: "Current Weather",
            systemImageName: "cloud.sun.fill"
        )
        AppShortcut(
            intent: OpenJaccuweather(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open",
            systemImageName: "sun.max.fill"
        )
    }
}
