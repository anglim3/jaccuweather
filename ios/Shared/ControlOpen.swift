import Foundation

/// `jaccuweather://now` opens the Now tab for the place already loaded.
enum NowLink {
    static let scheme = "jaccuweather"

    static var url: URL {
        URL(string: "\(scheme)://now")!
    }

    static func opensNow(_ url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return false }
        if url.host?.caseInsensitiveCompare("now") == .orderedSame { return true }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.caseInsensitiveCompare("now") == .orderedSame
    }
}

/// Control Center label. A missing temperature (no App Group snapshot) stays "Open".
enum OpenNowControlCopy {
    struct Face: Equatable {
        var title: String
        var symbolName: String
        var status: String?
    }

    static func face(temperatureF: Double?, symbolName: String?, placeName: String?) -> Face {
        guard let temperatureF, temperatureF.isFinite else {
            return Face(title: "Open", symbolName: "sun.max.fill", status: nil)
        }
        let trimmedSymbol = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let symbol = trimmedSymbol.isEmpty ? "cloud.fill" : trimmedSymbol
        let place = placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Face(
            title: "\(Int(temperatureF.rounded()))°",
            symbolName: symbol,
            status: place.isEmpty ? nil : place
        )
    }
}
