import Foundation

/// URL builders that replace Worker `/api/*` proxies. Native code calls upstreams directly.
enum APIEndpoints {
    static let ensembleHost = "https://ensemble-api.open-meteo.com/v1/ensemble"
    static let geocodingHost = "https://geocoding-api.open-meteo.com/v1/search"
    static let reverseHost = "https://api.bigdatacloud.net/data/reverse-geocode-client"
    static let airQualityHost = "https://air-quality-api.open-meteo.com/v1/air-quality"
    static let googlePollenHost = "https://pollen.googleapis.com/v1/forecast:lookup"
    static let tomorrowForecastHost = "https://api.tomorrow.io/v4/weather/forecast"
    static let nwsHost = "https://api.weather.gov"
    static let noaaStations = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions"
    static let noaaDatagetter = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
    static let rainViewerMaps = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    static let rainViewerCredit = URL(string: "https://www.rainviewer.com/")!
    static let noaaRadarCredit = URL(string: "https://www.weather.gov/disclaimer")!

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

    static let pollenCurrent = "us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
    static let pollenHourly = "alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"

    /// Exact ensemble request used by public/app.js fetchWeather().
    static func ensemble(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: ensembleHost)!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "models", value: "icon_seamless,gfs_seamless,ecmwf_ifs025"),
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

}
