import Foundation

/// Dew point chip for the Watch glance temperature row.
///
/// Values are Fahrenheit, already converted by the phone (`dewpoint_2m`) or by
/// the watch forecast request (`temperature_unit=fahrenheit`). Rounding matches
/// the other Watch temperatures: nearest degree. A missing or non-finite
/// reading stays off the glance.
enum WatchDewPoint {
    struct Chip: Equatable {
        var fahrenheit: Int
        /// Visible chip, such as "Dew 52°".
        var text: String
        /// VoiceOver line.
        var spoken: String
    }

    static func chip(fahrenheit: Double?) -> Chip? {
        guard let value = usable(fahrenheit) else { return nil }
        let shown = Int(value.rounded())
        return Chip(
            fahrenheit: shown,
            text: "Dew \(shown)°",
            spoken: "Dew point \(shown) degrees"
        )
    }

    /// Finite Fahrenheit reading. Zero and negative dew points still count.
    static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Keep a phone reading. Open-Meteo fills the field only when that reading is unusable.
    static func preferringExisting(_ existing: Double?, fill: Double?) -> Double? {
        usable(existing) ?? usable(fill)
    }
}
