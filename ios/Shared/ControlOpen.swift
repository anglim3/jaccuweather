import Foundation

/// `jaccuweather://now` opens the Now tab for the place already loaded.
enum NowLink {
    static let opened = Notification.Name("jaccuweather.openNow")
    private static let darwinName = "cloud.janglim.jaccuweather.open-now" as CFString
    private static var observing = false

    /// Reaches the app whether the intent runs there or in the widget extension.
    static func postOpen() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName),
            nil,
            nil,
            true
        )
        NotificationCenter.default.post(name: opened, object: nil)
    }

    static func startObserving() {
        guard !observing else { return }
        observing = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NowLink.opened, object: nil)
                }
            },
            darwinName,
            nil,
            .deliverImmediately
        )
    }

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
