import Foundation

enum Secrets {
    /// Built-in NWS identifier. No contact email is stored in git; edit it in Settings.
    static let defaultNWSUserAgent = "Jaccuweather/1.0 (personal iOS; https://github.com/anglim3/jaccuweather)"

    /// Open-Meteo sees this on forecast and geocoding calls (same idea as the Worker User-Agent).
    static let openMeteoUserAgent = "Jaccuweather/1.0 (https://github.com/anglim3/jaccuweather)"

    /// Empty string means Open-Meteo pollen/AQI only.
    static var googlePollenAPIKey: String {
        KeychainStore.string(for: KeychainStore.googlePollenKey) ?? bundleString("GOOGLE_POLLEN_API_KEY")
    }

    static var tomorrowAPIKey: String {
        KeychainStore.string(for: KeychainStore.tomorrowKey) ?? bundleString("TOMORROW_API_KEY")
    }

    /// Keychain value wins, then a non-placeholder Info.plist value, then the built-in identifier.
    static var nwsUserAgent: String {
        if let stored = KeychainStore.string(for: KeychainStore.nwsUserAgentKey) {
            return stored
        }
        let bundled = bundleString("NWS_USER_AGENT")
        if bundled.isEmpty || bundled.contains("$(") || bundled.localizedCaseInsensitiveContains("edit-this-contact") {
            return defaultNWSUserAgent
        }
        return bundled
    }

    static var hasPaidPollenKeys: Bool {
        !googlePollenAPIKey.isEmpty || !tomorrowAPIKey.isEmpty
    }

    static var pollenSourceLabel: String {
        if !googlePollenAPIKey.isEmpty { return "Google, then Tomorrow, then Open-Meteo" }
        if !tomorrowAPIKey.isEmpty { return "Tomorrow, then Open-Meteo" }
        return "Open-Meteo (no pollen keys stored)"
    }

    private static func bundleString(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
