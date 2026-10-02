import Foundation

/// One upcoming hour on the Watch glance.
struct WatchHourSlot: Codable, Equatable, Identifiable {
    var time: String
    var label: String
    var temperatureF: Double?
    var precipProbability: Int?
    var cue: WatchPrecipCue

    var id: String { time }
}

enum WatchPrecipCue: String, Codable {
    case none
    case rain
    case snow
}

/// One Open-Meteo hourly row before it is clipped to the glance.
struct WatchHourSample {
    var time: String
    var temperatureF: Double?
    var precipProbability: Double?
    var weatherCode: Int?
    var precipitation: Double?
    var snowfall: Double?
}

/// Place-local hours for the Watch strip.
///
/// Open-Meteo `timezone=auto` stamps are wall clocks with no offset. The
/// absolute instant uses `utc_offset_seconds`, the same way the iPhone Now
/// and Forecast tabs pick the current hour. Labels come from that stamp, so
/// a watch set to another zone still shows the place's hour.
enum WatchHourlyPlan {
    static let defaultCount = 8
    private static let snowCodes: Set<Int> = [71, 73, 75, 77, 85, 86]
    private static let rainCodes: Set<Int> = [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]

    static func slots(
        samples: [WatchHourSample],
        utcOffsetSeconds: Int,
        now: Date = Date(),
        count: Int = defaultCount
    ) -> [WatchHourSlot] {
        let start = startIndex(samples: samples, utcOffsetSeconds: utcOffsetSeconds, now: now)
        guard samples.indices.contains(start) else { return [] }
        let limit = max(1, count)
        return samples[start..<min(samples.count, start + limit)].map { sample in
            WatchHourSlot(
                time: sample.time,
                label: label(for: sample.time),
                temperatureF: sample.temperatureF,
                precipProbability: sample.precipProbability.map { Int($0.rounded()) },
                cue: cue(code: sample.weatherCode, precipitation: sample.precipitation, snowfall: sample.snowfall)
            )
        }
    }

    /// The place-local hour that contains `now`, then the hours after it.
    static func startIndex(samples: [WatchHourSample], utcOffsetSeconds: Int, now: Date) -> Int {
        guard !samples.isEmpty else { return 0 }
        let nowSeconds = now.timeIntervalSince1970
        var containing: Int?
        for (index, sample) in samples.enumerated() {
            guard let seconds = absoluteSeconds(localISO: sample.time, utcOffsetSeconds: utcOffsetSeconds) else { continue }
            if seconds <= nowSeconds {
                containing = index
            } else if containing == nil {
                return index
            } else {
                break
            }
        }
        return containing ?? 0
    }

    /// `9a`, `12p`, `3p` from a `yyyy-MM-dd'T'HH:mm` stamp.
    static func label(for stamp: String) -> String {
        guard let hour = hour(from: stamp) else { return "" }
        let suffix = hour < 12 ? "a" : "p"
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve)\(suffix)"
    }

    static func cue(code: Int?, precipitation: Double?, snowfall: Double?) -> WatchPrecipCue {
        if let snowfall, snowfall > 0 { return .snow }
        if let code, snowCodes.contains(code) { return .snow }
        if let precipitation, precipitation > 0 { return .rain }
        if let code, rainCodes.contains(code) { return .rain }
        return .none
    }

    /// Absolute instant for a location-local `yyyy-MM-dd'T'HH:mm` stamp.
    static func absoluteSeconds(localISO: String, utcOffsetSeconds: Int) -> TimeInterval? {
        guard let match = stampPattern.firstMatch(in: localISO, range: NSRange(localISO.startIndex..., in: localISO)),
              let year = integer(localISO, match, 1),
              let month = integer(localISO, match, 2),
              let day = integer(localISO, match, 3),
              let hour = integer(localISO, match, 4),
              let minute = integer(localISO, match, 5) else { return nil }
        var parts = DateComponents()
        parts.calendar = utcCalendar
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        guard let utc = utcCalendar.date(from: parts) else { return nil }
        return utc.timeIntervalSince1970 - TimeInterval(utcOffsetSeconds)
    }

    static func hour(from stamp: String) -> Int? {
        guard let match = stampPattern.firstMatch(in: stamp, range: NSRange(stamp.startIndex..., in: stamp)) else { return nil }
        return integer(stamp, match, 4)
    }

    private static func integer(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static let utcCalendar = Calendar(identifier: .gregorian)
    private static let stampPattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})"#
    )
}
