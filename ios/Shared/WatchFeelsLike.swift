import Foundation

/// Apparent temperature for the Watch glance.
///
/// Values are Fahrenheit, the same unit as the glance temperature. A fresh
/// phone snapshot's `feelsLikeF` wins when that place already has one.
/// Otherwise the number comes from the Watch Open-Meteo request:
/// `current.apparent_temperature`, then the nearest hour's
/// `apparent_temperature` when current omits it. The glance shows the line
/// only when the rounded feels-like and the rounded temperature differ by
/// at least 2°F.
enum WatchFeelsLike {
    /// Rounded degrees of difference required before the line is shown.
    static let minimumRoundedGap = 2

    struct Chip: Equatable {
        var fahrenheit: Int
        /// Visible line, such as "Feels like 64°".
        var text: String
        /// VoiceOver line. Spoken only while the chip is visible.
        var spoken: String
    }

    static func chip(temperatureF: Double?, feelsLikeF: Double?) -> Chip? {
        guard let temperature = usable(temperatureF), let feels = usable(feelsLikeF) else { return nil }
        let shownTemp = Int(temperature.rounded())
        let shownFeels = Int(feels.rounded())
        guard abs(shownFeels - shownTemp) >= minimumRoundedGap else { return nil }
        return Chip(
            fahrenheit: shownFeels,
            text: "Feels like \(shownFeels)°",
            spoken: "Feels like \(shownFeels) degrees"
        )
    }

    /// Finite Fahrenheit reading. Zero and negative values still count.
    static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Current apparent temperature, or the nearest hour when current has none.
    static func openMeteo(currentApparentF: Double?, nearestHourApparentF: Double?) -> Double? {
        usable(currentApparentF) ?? usable(nearestHourApparentF)
    }

    /// Phone (or another fresh reading) first when `preferExisting` is set.
    /// Open-Meteo replaces a value that is not preferred. A previous reading
    /// remains only when Open-Meteo has no apparent temperature at all.
    static func filled(existingFeelsLikeF: Double?, preferExisting: Bool, openMeteoFeelsLikeF: Double?) -> Double? {
        if preferExisting, let existing = usable(existingFeelsLikeF) { return existing }
        if let open = usable(openMeteoFeelsLikeF) { return open }
        return usable(existingFeelsLikeF)
    }

    /// Apparent temperature on the hourly stamp closest to `now`.
    /// Nil and non-finite samples are skipped. An exact tie keeps the earlier hour.
    static func nearestApparent(stamps: [TimeInterval], values: [Double?], now: Date) -> Double? {
        let nowSeconds = now.timeIntervalSince1970
        var bestDelta = Double.greatestFiniteMagnitude
        var best: Double?
        let count = min(stamps.count, values.count)
        for index in 0..<count {
            let stamp = stamps[index]
            guard stamp.isFinite, let value = usable(values[index]) else { continue }
            let delta = abs(stamp - nowSeconds)
            if delta < bestDelta {
                bestDelta = delta
                best = value
            }
        }
        return best
    }
}
