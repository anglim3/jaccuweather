import Foundation

/// Open-Meteo forecast payload (`api.open-meteo.com/v1/forecast`).
/// Scaffold uses the single-model forecast API. The website averages ensemble
/// members in `normalizeEnsembleWeatherData()` — port that later if parity is required.
struct ForecastResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let elevation: Double?
    let current: CurrentConditions?
    let hourly: HourlyForecast?
    let daily: DailyForecast?
}

struct CurrentConditions: Decodable {
    let time: String?
    let temperature2m: Double?
    let relativeHumidity2m: Int?
    let apparentTemperature: Double?
    let isDay: Int?
    let precipitation: Double?
    let weatherCode: Int?
    let cloudCover: Int?
    let surfacePressure: Double?
    let windSpeed10m: Double?
    let windDirection10m: Int?
    let windGusts10m: Double?
    let uvIndex: Double?
    let dewPoint2m: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case isDay = "is_day"
        case precipitation
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
        case surfacePressure = "surface_pressure"
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windGusts10m = "wind_gusts_10m"
        case uvIndex = "uv_index"
        case dewPoint2m = "dew_point_2m"
    }
}

struct HourlyForecast: Decodable {
    let time: [String]
    let temperature2m: [Double?]
    let relativeHumidity2m: [Int?]
    let weatherCode: [Int?]
    let windSpeed10m: [Double?]
    let precipitationProbability: [Int?]
    let precipitation: [Double?]
    let surfacePressure: [Double?]
    let cloudCover: [Double?]?
    let apparentTemperature: [Double?]?
    let uvIndex: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case weatherCode = "weather_code"
        case windSpeed10m = "wind_speed_10m"
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case surfacePressure = "surface_pressure"
        case cloudCover = "cloud_cover"
        case apparentTemperature = "apparent_temperature"
        case uvIndex = "uv_index"
    }
}

struct DailyForecast: Decodable {
    let time: [String]
    let weatherCode: [Int?]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]
    let precipitationSum: [Double?]
    let precipitationProbabilityMax: [Int?]?
    let uvIndexMax: [Double?]?
    let sunrise: [String]?
    let sunset: [String]?
    let windSpeed10mMax: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationSum = "precipitation_sum"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case uvIndexMax = "uv_index_max"
        case sunrise
        case sunset
        case windSpeed10mMax = "wind_speed_10m_max"
    }

    /// Website uses `past_days=2`, so "today" is index 2 when the array is aligned.
    var todayIndex: Int {
        let today = ISO8601DateFormatter.yearMonthDay.string(from: Date())
        if let idx = time.firstIndex(of: today) { return idx }
        return min(2, max(0, time.count - 1))
    }
}

struct HourlyPoint: Identifiable {
    let id: String
    let time: String
    let temperature: Double?
    let weatherCode: Int?
    let precipChance: Int?
}

struct DailyPoint: Identifiable {
    let id: String
    let date: String
    let weatherCode: Int?
    let high: Double?
    let low: Double?
    let precip: Double?
}

enum WeatherCode {
    static func description(_ code: Int?) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45: return "Foggy"
        case 48: return "Depositing rime fog"
        case 51: return "Light drizzle"
        case 53: return "Moderate drizzle"
        case 55: return "Dense drizzle"
        case 56: return "Light freezing drizzle"
        case 57: return "Dense freezing drizzle"
        case 61: return "Slight rain"
        case 63: return "Moderate rain"
        case 65: return "Heavy rain"
        case 66: return "Light freezing rain"
        case 67: return "Heavy freezing rain"
        case 71: return "Slight snow"
        case 73: return "Moderate snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80: return "Slight rain showers"
        case 81: return "Moderate rain showers"
        case 82: return "Violent rain showers"
        case 85: return "Slight snow showers"
        case 86: return "Heavy snow showers"
        case 95: return "Thunderstorm"
        case 96: return "Thunderstorm with slight hail"
        case 99: return "Thunderstorm with heavy hail"
        default: return "Unknown"
        }
    }

    static func symbol(code: Int?, isDay: Bool = true) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

extension ISO8601DateFormatter {
    static let yearMonthDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
