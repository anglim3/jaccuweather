import Foundation

/// One Open-Meteo forecast for the Watch glance and the complication.
/// Current conditions, the next place-local hours, and today's sunrise and sunset.
enum WatchForecastClient {
    struct Reading {
        var snapshot: WidgetConditionsSnapshot
        var hours: [WatchHourSlot]
        var days: [WatchDaySlot]
        var sun: WatchSunTimes
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
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation_probability,uv_index,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,weather_code,precipitation,rain,snowfall,wind_speed_10m,uv_index,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,rain_sum,snowfall_sum,uv_index_max,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "8"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "windspeed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
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
        let atmosphere = WatchAtmosphere.metrics(
            uvIndex: current.uvIndex,
            windSpeedMph: current.windSpeed10m,
            windDirectionDegrees: current.windDirection10m,
            windGustMph: current.windGusts10m
        )
        snapshot = snapshot.applyingAtmosphere(atmosphere)
        let hours = slots(payload.hourly, offset: offset, now: now)
        let days = daySlots(payload.daily, offset: offset, now: now)
        let sun = sunMatch(payload.daily, offset: offset, now: now)
        snapshot.sunriseISO = sun.sunriseISO
        snapshot.sunsetISO = sun.sunsetISO
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
        return Reading(snapshot: snapshot, hours: hours, days: days, sun: sun.times)
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
                snowfall: value(hourly.snowfall, index),
                rainInches: value(hourly.rain, index),
                feelsLikeF: value(hourly.apparentTemperature, index),
                windMph: value(hourly.windSpeed, index),
                humidity: value(hourly.relativeHumidity, index),
                uvIndex: value(hourly.uvIndex, index),
                isDay: flag(hourly.isDay, index)
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
                weatherCode: code,
                precipProbability: value(daily.precipitationProbabilityMax, index),
                rainInches: value(daily.rainSum, index),
                precipitationInches: value(daily.precipitationSum, index),
                snowInches: value(daily.snowfallSum, index),
                uvMax: value(daily.uvIndexMax, index)
            ))
        }
        return WatchDailyPlan.slots(samples: samples, utcOffsetSeconds: offset, now: now)
    }

    private static func sunMatch(_ daily: Daily?, offset: Int, now: Date) -> WatchSunPlan.Match {
        guard let daily else {
            return WatchSunPlan.Match(times: WatchSunTimes(sunriseLabel: nil, sunsetLabel: nil), sunriseISO: nil, sunsetISO: nil)
        }
        var samples: [WatchSunSample] = []
        samples.reserveCapacity(daily.time.count)
        for (index, stamp) in daily.time.enumerated() {
            samples.append(WatchSunSample(
                date: stamp,
                sunriseISO: text(daily.sunrise, index),
                sunsetISO: text(daily.sunset, index)
            ))
        }
        return WatchSunPlan.resolved(samples: samples, utcOffsetSeconds: offset, now: now)
    }

    private static func value(_ series: [Double?]?, _ index: Int) -> Double? {
        guard let series, series.indices.contains(index) else { return nil }
        return series[index]
    }

    private static func flag(_ series: [Double?]?, _ index: Int) -> Bool? {
        guard let value = value(series, index) else { return nil }
        return value != 0
    }

    private static func text(_ series: [String?]?, _ index: Int) -> String? {
        guard let series, series.indices.contains(index) else { return nil }
        let trimmed = series[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Current US AQI from the public Open-Meteo air-quality API.
/// The same host the iPhone uses for `us_aqi`. A missing or failed response stays nil.
enum WatchAirQualityClient {
    static func current(latitude: Double, longitude: Double) async -> Double? {
        guard let url = url(latitude: latitude, longitude: longitude) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.current?.usAqi
        } catch {
            return nil
        }
    }

    private static func url(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi")
        ]
        return components?.url
    }

    private struct Payload: Decodable {
        var current: Current?

        struct Current: Decodable {
            var usAqi: Double?

            enum CodingKeys: String, CodingKey {
                case usAqi = "us_aqi"
            }
        }
    }
}

enum WatchHourCache {
    private static let key = "jaccuweather.watch.hours"

    struct Hit {
        var hours: [WatchHourSlot]
        var days: [WatchDaySlot]
        /// Nil when this cache was written before sunrise and sunset were stored.
        var sun: WatchSunTimes?
        /// False when this cache was written before the day sheet's precip and UV fields.
        var includesDayDetail: Bool
        /// False when this cache was written before the hour sheet's condition and amounts.
        var includesHourDetail: Bool
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
        return Hit(
            hours: cache.hours,
            days: cache.days,
            sun: cache.sun,
            includesDayDetail: cache.includesDayDetail,
            includesHourDetail: cache.includesHourDetail
        )
    }

    static func save(hours: [WatchHourSlot], days: [WatchDaySlot], sun: WatchSunTimes, snapshot: WidgetConditionsSnapshot) {
        let cache = Cache(
            locationId: snapshot.locationId,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            fetchedAt: Date(),
            hours: hours,
            days: days,
            sun: sun,
            includesDayDetail: true,
            includesHourDetail: true
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
        var sun: WatchSunTimes?
        var includesDayDetail: Bool
        var includesHourDetail: Bool

        enum CodingKeys: String, CodingKey {
            case locationId, latitude, longitude, fetchedAt, hours, days, sun, includesDayDetail, includesHourDetail
        }

        init(locationId: String, latitude: Double, longitude: Double, fetchedAt: Date, hours: [WatchHourSlot], days: [WatchDaySlot], sun: WatchSunTimes?, includesDayDetail: Bool, includesHourDetail: Bool) {
            self.locationId = locationId
            self.latitude = latitude
            self.longitude = longitude
            self.fetchedAt = fetchedAt
            self.hours = hours
            self.days = days
            self.sun = sun
            self.includesDayDetail = includesDayDetail
            self.includesHourDetail = includesHourDetail
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            locationId = try container.decode(String.self, forKey: .locationId)
            latitude = try container.decode(Double.self, forKey: .latitude)
            longitude = try container.decode(Double.self, forKey: .longitude)
            fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
            hours = try container.decodeIfPresent([WatchHourSlot].self, forKey: .hours) ?? []
            days = try container.decodeIfPresent([WatchDaySlot].self, forKey: .days) ?? []
            sun = try container.decodeIfPresent(WatchSunTimes.self, forKey: .sun)
            includesDayDetail = try container.decodeIfPresent(Bool.self, forKey: .includesDayDetail) ?? false
            includesHourDetail = try container.decodeIfPresent(Bool.self, forKey: .includesHourDetail) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(locationId, forKey: .locationId)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
            try container.encode(fetchedAt, forKey: .fetchedAt)
            try container.encode(hours, forKey: .hours)
            try container.encode(days, forKey: .days)
            try container.encodeIfPresent(sun, forKey: .sun)
            try container.encode(includesDayDetail, forKey: .includesDayDetail)
            try container.encode(includesHourDetail, forKey: .includesHourDetail)
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
    let uvIndex: Double?
    let windSpeed10m: Double?
    let windDirection10m: Double?
    let windGusts10m: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case weatherCode = "weather_code"
        case isDay = "is_day"
        case precipitationProbability = "precipitation_probability"
        case uvIndex = "uv_index"
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windGusts10m = "wind_gusts_10m"
    }
}

extension WidgetConditionsSnapshot {
    var atmosphereMetrics: WatchAtmosphere.Metrics {
        WatchAtmosphere.metrics(
            uvIndex: uvIndex,
            windSpeedMph: windSpeedMph,
            windDirectionDegrees: windDirectionDegrees,
            windGustMph: windGustMph
        )
    }

    func applyingAtmosphere(_ metrics: WatchAtmosphere.Metrics) -> WidgetConditionsSnapshot {
        var copy = self
        copy.uvIndex = metrics.uvIndex
        copy.windSpeedMph = metrics.windSpeedMph
        copy.windDirectionDegrees = metrics.windDirectionDegrees
        copy.windGustMph = metrics.windGustMph
        return copy
    }
}

private struct Hourly: Decodable {
    let time: [String]
    let temperature2m: [Double?]
    let precipitationProbability: [Double?]
    let weatherCode: [Double?]
    let precipitation: [Double?]
    let rain: [Double?]
    let snowfall: [Double?]
    let apparentTemperature: [Double?]
    let relativeHumidity: [Double?]
    let windSpeed: [Double?]
    let uvIndex: [Double?]
    let isDay: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case precipitation
        case rain
        case snowfall
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity = "relative_humidity_2m"
        case windSpeed = "wind_speed_10m"
        case uvIndex = "uv_index"
        case isDay = "is_day"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
        temperature2m = try container.decodeIfPresent([Double?].self, forKey: .temperature2m) ?? []
        precipitationProbability = try container.decodeIfPresent([Double?].self, forKey: .precipitationProbability) ?? []
        weatherCode = try container.decodeIfPresent([Double?].self, forKey: .weatherCode) ?? []
        precipitation = try container.decodeIfPresent([Double?].self, forKey: .precipitation) ?? []
        rain = try container.decodeIfPresent([Double?].self, forKey: .rain) ?? []
        snowfall = try container.decodeIfPresent([Double?].self, forKey: .snowfall) ?? []
        apparentTemperature = try container.decodeIfPresent([Double?].self, forKey: .apparentTemperature) ?? []
        relativeHumidity = try container.decodeIfPresent([Double?].self, forKey: .relativeHumidity) ?? []
        windSpeed = try container.decodeIfPresent([Double?].self, forKey: .windSpeed) ?? []
        uvIndex = try container.decodeIfPresent([Double?].self, forKey: .uvIndex) ?? []
        isDay = try container.decodeIfPresent([Double?].self, forKey: .isDay) ?? []
    }
}

private struct Daily: Decodable {
    let time: [String]
    let weatherCode: [Double?]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]
    let precipitationProbabilityMax: [Double?]
    let precipitationSum: [Double?]
    let rainSum: [Double?]
    let snowfallSum: [Double?]
    let uvIndexMax: [Double?]
    let sunrise: [String?]
    let sunset: [String?]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
        case rainSum = "rain_sum"
        case snowfallSum = "snowfall_sum"
        case uvIndexMax = "uv_index_max"
        case sunrise
        case sunset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decodeIfPresent([String].self, forKey: .time) ?? []
        weatherCode = try container.decodeIfPresent([Double?].self, forKey: .weatherCode) ?? []
        temperature2mMax = try container.decodeIfPresent([Double?].self, forKey: .temperature2mMax) ?? []
        temperature2mMin = try container.decodeIfPresent([Double?].self, forKey: .temperature2mMin) ?? []
        precipitationProbabilityMax = try container.decodeIfPresent([Double?].self, forKey: .precipitationProbabilityMax) ?? []
        precipitationSum = try container.decodeIfPresent([Double?].self, forKey: .precipitationSum) ?? []
        rainSum = try container.decodeIfPresent([Double?].self, forKey: .rainSum) ?? []
        snowfallSum = try container.decodeIfPresent([Double?].self, forKey: .snowfallSum) ?? []
        uvIndexMax = try container.decodeIfPresent([Double?].self, forKey: .uvIndexMax) ?? []
        sunrise = try container.decodeIfPresent([String?].self, forKey: .sunrise) ?? []
        sunset = try container.decodeIfPresent([String?].self, forKey: .sunset) ?? []
    }
}
