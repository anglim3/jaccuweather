import Foundation

/// One Open-Meteo forecast for the Watch glance and the complication.
/// Current conditions plus the next place-local hours.
enum WatchForecastClient {
    struct Reading {
        var snapshot: WidgetConditionsSnapshot
        var hours: [WatchHourSlot]
        var days: [WatchDaySlot]
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
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "8"),
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
        let days = daySlots(payload.daily, offset: offset, now: now)
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
        return Reading(snapshot: snapshot, hours: hours, days: days)
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

    private static func daySlots(_ daily: Daily?, offset: Int, now: Date) -> [WatchDaySlot] {
        guard let daily else { return [] }
        var samples: [WatchDaySample] = []
        samples.reserveCapacity(daily.time.count)
        for (index, stamp) in daily.time.enumerated() {
            let code = value(daily.weatherCode, index).map { Int($0.rounded()) }
            samples.append(WatchDaySample(
                date: stamp,
                highF: value(daily.temperature2mMax, index),
                lowF: value(daily.temperature2mMin, index),
                weatherCode: code
            ))
        }
        return WatchDailyPlan.slots(samples: samples, utcOffsetSeconds: offset, now: now)
    }

    private static func value(_ series: [Double?]?, _ index: Int) -> Double? {
        guard let series, series.indices.contains(index) else { return nil }
        return series[index]
    }
}

enum WatchHourCache {
    private static let key = "jaccuweather.watch.hours"

    struct Hit {
        var hours: [WatchHourSlot]
        var days: [WatchDaySlot]
    }

    static func load(matching snapshot: WidgetConditionsSnapshot) -> Hit? {
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
        return Hit(hours: cache.hours, days: cache.days)
    }

    static func save(hours: [WatchHourSlot], days: [WatchDaySlot], snapshot: WidgetConditionsSnapshot) {
        let cache = Cache(
            locationId: snapshot.locationId,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            fetchedAt: Date(),
            hours: hours,
            days: days
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
        var days: [WatchDaySlot]

        enum CodingKeys: String, CodingKey {
            case locationId, latitude, longitude, fetchedAt, hours, days
        }

        init(locationId: String, latitude: Double, longitude: Double, fetchedAt: Date, hours: [WatchHourSlot], days: [WatchDaySlot]) {
            self.locationId = locationId
            self.latitude = latitude
            self.longitude = longitude
            self.fetchedAt = fetchedAt
            self.hours = hours
            self.days = days
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            locationId = try container.decode(String.self, forKey: .locationId)
            latitude = try container.decode(Double.self, forKey: .latitude)
            longitude = try container.decode(Double.self, forKey: .longitude)
            fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
            hours = try container.decodeIfPresent([WatchHourSlot].self, forKey: .hours) ?? []
            days = try container.decodeIfPresent([WatchDaySlot].self, forKey: .days) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(locationId, forKey: .locationId)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
            try container.encode(fetchedAt, forKey: .fetchedAt)
            try container.encode(hours, forKey: .hours)
            try container.encode(days, forKey: .days)
        }
    }
}

private struct Payload: Decodable {
    let utcOffsetSeconds: Int?
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case current
        case hourly
        case daily
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

private struct Daily: Decodable {
    let time: [String]
    let weatherCode: [Double?]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
        weatherCode = try container.decodeIfPresent([Double?].self, forKey: .weatherCode) ?? []
        temperature2mMax = try container.decodeIfPresent([Double?].self, forKey: .temperature2mMax) ?? []
        temperature2mMin = try container.decodeIfPresent([Double?].self, forKey: .temperature2mMin) ?? []
    }
}
