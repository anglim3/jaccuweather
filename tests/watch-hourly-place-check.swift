import Foundation

@main
struct WatchHourlyPlaceCheck {
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

func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func run() {
    let offset = 9 * 3600
    let stamp = "2026-10-02T11:00"
    let absolute = WatchHourlyPlan.absoluteSeconds(localISO: stamp, utcOffsetSeconds: offset)
    let expected = utcDate(year: 2026, month: 10, day: 2, hour: 2, minute: 0).timeIntervalSince1970
    check(absolute != nil && abs(absolute! - expected) < 1, "utc+9 11:00 is 02:00 UTC")

    var samples: [WatchHourSample] = []
    for hour in 8...20 {
        let code = hour == 15 ? 73 : (hour == 16 ? 61 : 0)
        samples.append(WatchHourSample(
            time: String(format: "2026-10-02T%02d:00", hour),
            temperatureF: Double(50 + hour),
            precipProbability: hour == 16 ? 40 : 0,
            weatherCode: code,
            precipitation: hour == 16 ? 0.4 : 0,
            snowfall: hour == 14 ? 0.2 : 0
        ))
    }
    let now = utcDate(year: 2026, month: 10, day: 2, hour: 2, minute: 20)
    let slots = WatchHourlyPlan.slots(samples: samples, utcOffsetSeconds: offset, now: now, count: 8)
    check(slots.count == 8, "eight upcoming hours")
    check(slots.first?.label == "11a", "starts at the place-local hour, not the device zone")
    check(slots.last?.label == "6p", "eighth hour is 6p")
    check(slots.contains { $0.label == "3p" && $0.cue == .snow }, "15:00 snow code is a snow cue")
    check(slots.contains { $0.label == "2p" && $0.cue == .snow }, "snowfall amount is a snow cue")
    check(slots.contains { $0.label == "4p" && $0.cue == .rain && $0.precipProbability == 40 }, "rain code keeps the chance")
    check(slots.first { $0.label == "12p" }?.cue == WatchPrecipCue.none, "a dry hour has no precip cue")
    check(WatchHourlyPlan.label(for: "2026-10-02T00:00") == "12a", "midnight label")
    check(WatchHourlyPlan.label(for: "2026-10-02T12:00") == "12p", "noon label")

    let chicago = WatchPlaceChoice(
        locationId: "41.8781,-87.6298",
        locationName: "Chicago",
        latitude: 41.8781,
        longitude: -87.6298,
        hasReading: false
    )
    let seattleReading = WatchPlaceChoice(
        locationId: WatchPlacePlan.seattle.locationId,
        locationName: "Seattle",
        latitude: WatchPlacePlan.defaultLatitude,
        longitude: WatchPlacePlan.defaultLongitude,
        hasReading: true
    )
    let chosen = WatchPlacePlan.choose(pinned: nil, phone: nil, saved: seattleReading, shared: chicago)
    check(chosen.locationName == "Chicago", "shared place replaces the complication's Seattle reading")
    let sameCity = WatchPlacePlan.choose(
        pinned: nil,
        phone: nil,
        saved: WatchPlaceChoice(
            locationId: chicago.locationId,
            locationName: "Chicago",
            latitude: chicago.latitude,
            longitude: chicago.longitude,
            hasReading: true
        ),
        shared: chicago
    )
    check(sameCity.hasReading, "matching saved reading is kept")
    let pinned = WatchPlacePlan.choose(
        pinned: WatchPlaceChoice(
            locationId: "40.7128,-74.0060",
            locationName: "New York",
            latitude: 40.7128,
            longitude: -74.0060,
            hasReading: false
        ),
        phone: seattleReading,
        saved: seattleReading,
        shared: chicago
    )
    check(pinned.locationName == "New York", "pinned place wins over the phone and the shared place")
    check(
        WatchPlacePlan.choose(pinned: nil, phone: nil, saved: nil, shared: nil).locationName == "Seattle",
        "no place yet stays on the sample city"
    )

    let place = WatchPlace(
        locationId: "41.8781,-87.6298",
        locationName: "Chicago",
        latitude: 41.8781,
        longitude: -87.6298
    )
    let url = WatchPlaceLink.url(for: place)
    check(url != nil, "complication url")
    let roundTrip = url.flatMap(WatchPlaceLink.place(from:))
    check(roundTrip == place, "complication url round trip")
    check(WatchPlaceLink.place(from: URL(string: "https://example.com")!) == nil, "other urls are ignored")

    print("ok")
}
