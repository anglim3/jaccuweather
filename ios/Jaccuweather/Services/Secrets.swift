import Foundation

enum Secrets {
    /// Values come from Info.plist, injected from Config/Secrets.xcconfig at build time.
    /// Empty string means "not configured" — Open-Meteo pollen fallback is used.
    static var googlePollenAPIKey: String {
        string(for: "GOOGLE_POLLEN_API_KEY")
    }

    static var tomorrowAPIKey: String {
        string(for: "TOMORROW_API_KEY")
    }

    static var hasPaidPollenKeys: Bool {
        !googlePollenAPIKey.isEmpty || !tomorrowAPIKey.isEmpty
    }

    private static func string(for key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
