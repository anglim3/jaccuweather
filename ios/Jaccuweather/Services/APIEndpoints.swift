import Foundation

/// URL builders that replace Worker `/api/*` proxies. Native code calls upstreams directly.
enum APIEndpoints {
    static let forecastHost = "https://api.open-meteo.com/v1/forecast"
    static let geocodingHost = "https://geocoding-api.open-meteo.com/v1/search"
    static let reverseHost = "https://api.bigdatacloud.net/data/reverse-geocode-client"
    static let airQualityHost = "https://air-quality-api.open-meteo.com/v1/air-quality"
    static let googlePollenHost = "https://pollen.googleapis.com/v1/forecast:lookup"
    static let tomorrowForecastHost = "https://api.tomorrow.io/v4/weather/forecast"
    static let nwsHost = "https://api.weather.gov"
    static let ventuskyHost = "https://www.ventusky.com/"

    /// Same hourly/daily variables as `fetchWeather()` in public/app.js (minus ensemble models).
    static let hourlyVars = [
        "temperature_2m", "relative_humidity_2m", "weather_code", "wind_speed_10m",
        "wind_direction_10m", "wind_gusts_10m", "precipitation_probability", "precipitation",
        "snowfall", "surface_pressure", "cloud_cover", "cloud_cover_low", "cloud_cover_mid",
        "cloud_cover_high", "shortwave_radiation", "is_day", "apparent_temperature",
        "dew_point_2m", "uv_index"
    ].joined(separator: ",")

    static let dailyVars = [
        "weather_code", "temperature_2m_max", "temperature_2m_min", "apparent_temperature_max",
        "apparent_temperature_min", "precipitation_sum", "wind_speed_10m_max",
        "wind_direction_10m_dominant", "wind_gusts_10m_max", "precipitation_probability_max",
        "snowfall_sum", "uv_index_max", "sunrise", "sunset"
    ].joined(separator: ",")

    static let currentVars = [
        "temperature_2m", "relative_humidity_2m", "apparent_temperature", "is_day",
        "precipitation", "weather_code", "cloud_cover", "surface_pressure", "wind_speed_10m",
        "wind_direction_10m", "wind_gusts_10m", "uv_index", "dew_point_2m"
    ].joined(separator: ",")

    /// Matches `POLLEN_CURRENT_PARAMS` / `POLLEN_HOURLY_PARAMS` in build.js.
    static let pollenCurrent = "us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
    static let pollenHourly = "alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"

    static func forecast(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: forecastHost)!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: currentVars),
            URLQueryItem(name: "hourly", value: hourlyVars),
            URLQueryItem(name: "daily", value: dailyVars),
            URLQueryItem(name: "forecast_days", value: "14"),
            URLQueryItem(name: "past_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "windspeed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return c.url!
    }

    static func geocoding(name: String, count: Int = 8) -> URL {
        var c = URLComponents(string: geocodingHost)!
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        return c.url!
    }

    static func reverse(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: reverseHost)!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "localityLanguage", value: "en")
        ]
        return c.url!
    }

    static func openMeteoPollen(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: airQualityHost)!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: pollenCurrent),
            URLQueryItem(name: "hourly", value: pollenHourly),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return c.url!
    }

    static func googlePollen(latitude: Double, longitude: Double, apiKey: String) -> URL {
        var c = URLComponents(string: googlePollenHost)!
        c.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location.latitude", value: String(latitude)),
            URLQueryItem(name: "location.longitude", value: String(longitude)),
            URLQueryItem(name: "days", value: "5"),
            URLQueryItem(name: "plantsDescription", value: "false")
        ]
        return c.url!
    }

    static func tomorrowForecast(latitude: Double, longitude: Double, apiKey: String) -> URL {
        var c = URLComponents(string: tomorrowForecastHost)!
        c.queryItems = [
            URLQueryItem(name: "location", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "timesteps", value: "1d"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        return c.url!
    }

    static func nwsPoints(latitude: Double, longitude: Double) -> URL {
        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        return URL(string: "\(nwsHost)/points/\(lat),\(lon)")!
    }

    static func nwsAlerts(zoneId: String) -> URL {
        URL(string: "\(nwsHost)/alerts/active/zone/\(zoneId)")!
    }

    static func ventusky(latitude: Double, longitude: Double) -> URL {
        URL(string: "\(ventuskyHost)?p=\(latitude);\(longitude);7&l=rain")!
    }
}
