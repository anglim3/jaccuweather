import Foundation

/// One small Open-Meteo forecast call for a configured place, or to refresh a stale App Group snapshot.
/// Failures leave the caller on the last snapshot.
enum WidgetCurrentRefresh {
    static func fetch(name: String, latitude: Double, longitude: Double, locationId: String) async -> WidgetConditionsSnapshot? {
        await refresh(.shell(
            locationId: locationId,
            locationName: name,
            latitude: latitude,
            longitude: longitude
        ))
    }

    static func refresh(_ snapshot: WidgetConditionsSnapshot) async -> WidgetConditionsSnapshot? {
        guard let url = forecastURL(for: snapshot) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return merged(snapshot, payload)
        } catch {
            return nil
        }
    }

    private static func forecastURL(for snapshot: WidgetConditionsSnapshot) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(snapshot.latitude)),
            URLQueryItem(name: "longitude", value: String(snapshot.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components?.url
    }

    private static func merged(_ snapshot: WidgetConditionsSnapshot, _ payload: Payload) -> WidgetConditionsSnapshot? {
        guard let current = payload.current, current.temperature2m != nil else { return nil }
        let offset = payload.utcOffsetSeconds ?? 0
        let isDay = (current.isDay ?? (snapshot.isDay ? 1 : 0)) != 0
        let code = current.weatherCode ?? snapshot.weatherCode
        var next = snapshot
        next.temperatureF = current.temperature2m
        next.feelsLikeF = current.apparentTemperature ?? snapshot.feelsLikeF
        next.weatherCode = code
        next.isDay = isDay
        next.conditionText = WidgetWeatherCode.shortText(code)
        next.symbolName = WidgetWeatherCode.symbol(code: code, isDay: isDay)
        if let chance = current.precipitationProbability {
            next.precipChance = Int(chance.rounded())
        }
        if let daily = payload.daily {
            let today = todayString(offset: offset)
            let index = daily.time.firstIndex(of: today) ?? 0
            if daily.temperature2mMax.indices.contains(index) {
                next.highF = daily.temperature2mMax[index] ?? snapshot.highF
            }
            if daily.temperature2mMin.indices.contains(index) {
                next.lowF = daily.temperature2mMin[index] ?? snapshot.lowF
            }
        }
        if let hint = nextHours(payload.hourly, offset: offset), !hint.isEmpty {
            next.nextHoursHint = hint
        }
        next.fetchedAt = Date()
        return next
    }

    private static func todayString(offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func nextHours(_ hourly: Hourly?, offset: Int) -> String? {
        guard let hourly else { return nil }
        let zone = TimeZone(secondsFromGMT: offset) ?? .gmt
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = zone
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = zone
        clock.dateFormat = "h:mm a"
        let now = Date().addingTimeInterval(-30 * 60)
        var rows: [(label: String, temp: Double?, chance: Int?)] = []
        for (index, stamp) in hourly.time.enumerated() {
            guard let date = parser.date(from: String(stamp.prefix(16))), date >= now else { continue }
            let temp = hourly.temperature2m.indices.contains(index) ? hourly.temperature2m[index] : nil
            let chance = hourly.precipitationProbability.indices.contains(index)
                ? hourly.precipitationProbability[index].map { Int($0.rounded()) }
                : nil
            rows.append((clock.string(from: date), temp, chance))
            if rows.count == 5 { break }
        }
        if rows.count > 1 { rows.removeFirst() }
        let hint = WidgetClock.hint(times: rows)
        return hint.isEmpty ? nil : hint
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

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
    }
}

private struct Daily: Decodable {
    let time: [String]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
    }
}
