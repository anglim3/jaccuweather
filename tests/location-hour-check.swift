import Foundation

@main
struct LocationHourCheck {
    static func main() {
        run()
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}

func hourStamps() -> [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var parts = DateComponents()
    parts.calendar = calendar
    parts.timeZone = TimeZone(secondsFromGMT: 0)
    parts.year = 2026
    parts.month = 10
    parts.day = 1
    let start = calendar.date(from: parts)!
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return (0..<72).map { offset in
        formatter.string(from: calendar.date(byAdding: .hour, value: offset, to: start)!)
    }
}

/// What `new Date("yyyy-MM-ddTHH:mm")` does: read the stamp in the phone zone.
func phoneLocalIndex(times: [String], timeZone: TimeZone, now: Date) -> Int {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    let nowSeconds = now.timeIntervalSince1970
    var best = 0
    var bestDelta = Double.greatestFiniteMagnitude
    for (index, stamp) in times.enumerated() {
        guard let date = formatter.date(from: String(stamp.prefix(16))) else { continue }
        let delta = abs(date.timeIntervalSince1970 - nowSeconds)
        if delta < bestDelta {
            bestDelta = delta
            best = index
        }
    }
    return best
}

func run() {
    let times = hourStamps()
    var nowParts = DateComponents()
    nowParts.calendar = Calendar(identifier: .gregorian)
    nowParts.timeZone = TimeZone(secondsFromGMT: 0)
    nowParts.year = 2026
    nowParts.month = 10
    nowParts.day = 2
    nowParts.hour = 7
    nowParts.minute = 8
    let now = nowParts.date!
    let tokyo = 9 * 3600
    let newYork = -4 * 3600
    let tokyoIndex = times.firstIndex(of: "2026-10-02T16:00")!
    let newYorkIndex = times.firstIndex(of: "2026-10-02T03:00")!

    check(LocationHour.nearestIndex(times: [], utcOffsetSeconds: tokyo, now: now) == 0, "empty series stays at the first hour")
    check(LocationHour.nearestIndex(times: times, utcOffsetSeconds: tokyo, now: now) == tokyoIndex, "Tokyo offset selects 16:00 local, not the phone hour")
    check(LocationHour.nearestIndex(times: times, utcOffsetSeconds: newYork, now: now) == newYorkIndex, "New York offset selects 03:00 local")

    let phoneZone = TimeZone(secondsFromGMT: newYork)!
    let phoneIndex = phoneLocalIndex(times: times, timeZone: phoneZone, now: now)
    check(phoneIndex == newYorkIndex, "parsing naive stamps in the phone zone picks 03:00")
    check(phoneIndex != LocationHour.nearestIndex(times: times, utcOffsetSeconds: tokyo, now: now), "phone-zone parsing disagrees with the Tokyo hour")

    let india = 19800
    let indiaIndex = times.firstIndex(of: "2026-10-02T13:00")!
    check(LocationHour.nearestIndex(times: times, utcOffsetSeconds: india, now: now) == indiaIndex, "half-hour offset rounds to the nearer stamp")

    var zonedParts = DateComponents()
    zonedParts.calendar = Calendar(identifier: .gregorian)
    zonedParts.timeZone = TimeZone(secondsFromGMT: 0)
    zonedParts.year = 2026
    zonedParts.month = 10
    zonedParts.day = 2
    zonedParts.hour = 7
    let zoned = LocationHour.absoluteSeconds(localISO: "2026-10-02T07:00:00Z", utcOffsetSeconds: tokyo)
    check(zoned == zonedParts.date?.timeIntervalSince1970, "a zoned stamp stays an absolute instant")

    var temps = Array(repeating: 10.0, count: times.count)
    temps[newYorkIndex] = 41
    temps[tokyoIndex] = 72
    let codes = times.indices.map { $0 == tokyoIndex ? 1 : 0 }
    let root: [String: Any] = [
        "utc_offset_seconds": tokyo,
        "hourly": [
            "time": times,
            "temperature_2m": temps,
            "weather_code": codes
        ],
        "current": [
            "time": times[newYorkIndex],
            "temperature_2m": 41.0,
            "weather_code": 0
        ]
    ]
    let aligned = WeatherBundle(root: JSONMap(root)).alignedToLocationHour(now: now)
    check(aligned.current.string("time") == times[tokyoIndex], "current time follows the location hour, got \(aligned.current.string("time") ?? "nil")")
    check(aligned.current.number("temperature_2m") == 72, "current temperature follows the location hour, got \(aligned.current.number("temperature_2m") ?? -1)")
    check(aligned.current.int("weather_code") == 1, "current weather code follows the location hour")

    let untouched = WeatherBundle(root: JSONMap(["utc_offset_seconds": tokyo])).alignedToLocationHour(now: now)
    check(untouched.current.raw.isEmpty, "missing hourly times leave current alone")

    print("ok")
}
