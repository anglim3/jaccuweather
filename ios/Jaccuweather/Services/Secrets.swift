import Foundation

enum Secrets {
    /// Empty string means Open-Meteo pollen/AQI only.
    static var googlePollenAPIKey: String { string(for: "GOOGLE_POLLEN_API_KEY") }
    static var tomorrowAPIKey: String { string(for: "TOMORROW_API_KEY") }

    /// NWS requires an identifying User-Agent. Edit NWS_USER_AGENT in Secrets.xcconfig.
    static var nwsUserAgent: String {
        let value = string(for: "NWS_USER_AGENT")
        return value.isEmpty
            ? "JaccuweatherPersonal/1.0 (personal iOS; edit NWS_USER_AGENT in Secrets.xcconfig; https://github.com/anglim3/jaccuweather)"
            : value
    }

    static var hasPaidPollenKeys: Bool {
        !googlePollenAPIKey.isEmpty || !tomorrowAPIKey.isEmpty
    }

    private static func string(for key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
