import Foundation

/// One Open-Meteo forecast for the Watch glance and the complication.
/// Current conditions plus the next place-local hours.
enum WatchForecastClient {
    struct Reading {
        var snapshot: WidgetConditionsSnapshot
        var hours: [WatchHourSlot]
    }

    static func fetch(_ place: WidgetConditionsSnapshot, now: Date = Date()) async -> Reading? {
        guard let url = forecastURL(for: place) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return merged(place, payload, now: now)
        } catch {
            return nil
        }
    }

    private static func forecastURL(for place: WidgetConditionsSnapshot) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,precipitation,snowfall"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components?.url
    }

    private static func merged(_ place: WidgetConditionsSnapshot, _ payload: Payload, now: Date) -> Reading? {
        guard let current = payload.current, current.temperature2m != nil else { return nil }
        let offset = payload.utcOffsetSeconds ?? 0
        let isDay = (current.isDay ?? (place.isDay ? 1 : 0)) != 0
        let code = current.weatherCode ?? place.weatherCode
        var snapshot = place
        snapshot.temperatureF = current.temperature2m
        snapshot.feelsLikeF = current.apparentTemperature ?? place.feelsLikeF
        snapshot.weatherCode = code
        snapshot.isDay = isDay
        snapshot.conditionText = WidgetWeatherCode.shortText(code)
        snapshot.symbolName = WidgetWeatherCode.symbol(code: code, isDay: isDay)
        if let chance = current.precipitationProbability {
            snapshot.precipChance = Int(chance.rounded())
        }
        let hours = slots(payload.hourly, offset: offset, now: now)
        if !hours.isEmpty {
            snapshot.nextHoursHint = hours.prefix(4).map { slot in
                let degrees = slot.temperatureF.map { "\(Int($0.rounded()))°" } ?? "—"
                if let chance = slot.precipProbability, chance >= 20 {
                    return "\(slot.label) \(degrees) \(chance)%"
                }
                return "\(slot.label) \(degrees)"
            }.joined(separator: " · ")
        }
        snapshot.fetchedAt = Date()
        return Reading(snapshot: snapshot, hours: hours)
    }

    private static func slots(_ hourly: Hourly?, offset: Int, now: Date) -> [WatchHourSlot] {
        guard let hourly else { return [] }
        var samples: [WatchHourSample] = []
        samples.reserveCapacity(hourly.time.count)
        for (index, stamp) in hourly.time.enumerated() {
            let code = value(hourly.weatherCode, index).map { Int($0.rounded()) }
            samples.append(WatchHourSample(
                time: stamp,
                temperatureF: value(hourly.temperature2m, index),
                precipProbability: value(hourly.precipitationProbability, index),
                weatherCode: code,
                precipitation: value(hourly.precipitation, index),
                snowfall: value(hourly.snowfall, index)
            ))
        }
        return WatchHourlyPlan.slots(samples: samples, utcOffsetSeconds: offset, now: now)
    }

    private static func value(_ series: [Double?]?, _ index: Int) -> Double? {
        guard let series, series.indices.contains(index) else { return nil }
        return series[index]
    }
}

enum WatchHourCache {
    private static let key = "jaccuweather.watch.hours"

    static func load(matching snapshot: WidgetConditionsSnapshot) -> [WatchHourSlot]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cache = try? decoder.decode(Cache.self, from: data) else { return nil }
        guard Date().timeIntervalSince(cache.fetchedAt) < WidgetConditionsSnapshot.refetchAfter else { return nil }
        let cached = WatchPlaceChoice(
            locationId: cache.locationId,
            locationName: snapshot.locationName,
            latitude: cache.latitude,
            longitude: cache.longitude,
            hasReading: true
        )
        let wanted = WatchPlaceChoice(
            locationId: snapshot.locationId,
            locationName: snapshot.locationName,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            hasReading: true
        )
        guard WatchPlacePlan.same(cached, wanted) else { return nil }
        return cache.hours
    }

    static func save(hours: [WatchHourSlot], snapshot: WidgetConditionsSnapshot) {
        let cache = Cache(
            locationId: snapshot.locationId,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            fetchedAt: Date(),
            hours: hours
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private struct Cache: Codable {
        var locationId: String
        var latitude: Double
        var longitude: Double
        var fetchedAt: Date
        var hours: [WatchHourSlot]
    }
}

private struct Payload: Decodable {
    let utcOffsetSeconds: Int?
    let current: Current?
    let hourly: Hourly?

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case current
        case hourly
    }
}

private struct Current: Decodable {
    let temperature2m: Double?
    let apparentTemperature: Double?
    let weatherCode: Int?
    let isDay: Int?
    let precipitationProbability: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case weatherCode = "weather_code"
        case isDay = "is_day"
        case precipitationProbability = "precipitation_probability"
    }
}

private struct Hourly: Decodable {
    let time: [String]
    let temperature2m: [Double?]
    let precipitationProbability: [Double?]
    let weatherCode: [Double?]
    let precipitation: [Double?]
    let snowfall: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case precipitation
        case snowfall
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
        temperature2m = try container.decodeIfPresent([Double?].self, forKey: .temperature2m) ?? []
        precipitationProbability = try container.decodeIfPresent([Double?].self, forKey: .precipitationProbability) ?? []
        weatherCode = try container.decodeIfPresent([Double?].self, forKey: .weatherCode) ?? []
        precipitation = try container.decodeIfPresent([Double?].self, forKey: .precipitation) ?? []
        snowfall = try container.decodeIfPresent([Double?].self, forKey: .snowfall) ?? []
    }
}
