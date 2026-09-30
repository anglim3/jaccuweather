import Foundation

@main
struct PrecipNotificationCheck {
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

func hour(_ time: String, chance: Int? = nil, precip: Double? = nil, snow: Double? = nil, clock: String = "") -> PrecipHourSample {
    PrecipHourSample(time: time, clock: clock, precipChance: chance, precip: precip, snow: snow)
}

func run() {
    let place = "42.36_-71.06"
    let dry = (0..<8).map { offset in
        hour(String(format: "2026-09-30T%02d:00", 12 + offset), chance: 10, precip: 0, snow: 0, clock: "\(12 + offset):00")
    }

    check(PrecipNotificationCopy.upcoming(hours: dry, placeKey: place) == nil, "dry hours stay quiet")

    var rainAtThree = dry
    rainAtThree[3] = hour("2026-09-30T15:00", chance: 50, precip: 0.02, snow: 0, clock: "3:00 PM")
    let rain = PrecipNotificationCopy.upcoming(hours: rainAtThree, placeKey: " \(place) ")
    check(rain?.kind == .rain, "fifty percent with liquid precip is rain")
    check(rain?.dedupeKey == "\(place)|2026-09-30T15", "dedupe key is place plus hour, got \(rain?.dedupeKey ?? "nil")")
    check(rain?.identifier == "precip.\(place).20260930T15", "identifier, got \(rain?.identifier ?? "nil")")
    check(
        PrecipNotificationCopy.title(kind: rain?.kind ?? .precipitation) == "Rain starting soon",
        "rain title"
    )
    check(
        PrecipNotificationCopy.body(placeName: "Boston", time: rain?.startTime ?? "", clock: rain?.clock ?? "") == "Boston. 3:00 PM–4:00 PM.",
        "body names the place and the hour window, got \(PrecipNotificationCopy.body(placeName: "Boston", time: rain?.startTime ?? "", clock: rain?.clock ?? ""))"
    )

    var already = dry
    already[0] = hour("2026-09-30T12:00", chance: 10, precip: 0.04, snow: 0)
    already[2] = hour("2026-09-30T14:00", chance: 90, precip: 0.2, snow: 0)
    check(PrecipNotificationCopy.upcoming(hours: already, placeKey: place) == nil, "current precip blocks a later start")

    var laterOnly = dry
    laterOnly[6] = hour("2026-09-30T18:00", chance: 90, precip: 0.2, snow: 0, clock: "6:00 PM")
    check(PrecipNotificationCopy.upcoming(hours: laterOnly, placeKey: place) == nil, "hour seven is outside the window")

    var snowStart = dry
    snowStart[1] = hour("2026-09-30T13:00", chance: 80, precip: 0.1, snow: 0.2, clock: "1:00 PM")
    let snow = PrecipNotificationCopy.upcoming(hours: snowStart, placeKey: place)
    check(snow?.kind == .snow, "snow amount wins")
    check(PrecipNotificationCopy.title(kind: .snow) == "Snow starting soon", "snow title")

    var chanceOnly = dry
    chanceOnly[2] = hour("2026-09-30T14:00", chance: 62, precip: 0, snow: 0, clock: "")
    let generic = PrecipNotificationCopy.upcoming(hours: chanceOnly, placeKey: place)
    check(generic?.kind == .precipitation, "probability without an amount stays generic")
    check(PrecipNotificationCopy.title(kind: .precipitation) == "Precipitation starting soon", "generic title")
    check(generic?.clock == "2:00 PM", "blank clock is filled from the hour, got \(generic?.clock ?? "nil")")
    check(
        PrecipNotificationCopy.body(placeName: " ", time: generic?.startTime ?? "", clock: generic?.clock ?? "") == "2:00 PM–3:00 PM.",
        "blank place still states the window"
    )

    var amountOnly = dry
    amountOnly[4] = hour("2026-09-30T16:00", chance: nil, precip: 0.05, snow: 0, clock: "4:00 PM")
    let fallback = PrecipNotificationCopy.upcoming(hours: amountOnly, placeKey: place)
    check(fallback?.kind == .rain, "missing probability uses a positive amount")
    check(fallback?.startTime.hasPrefix("2026-09-30T16") == true, "amount fallback hour")

    var lowChanceWithAmount = dry
    lowChanceWithAmount[1] = hour("2026-09-30T13:00", chance: 49, precip: 0.4, snow: 0)
    check(PrecipNotificationCopy.upcoming(hours: lowChanceWithAmount, placeKey: place) == nil, "probability below 50 wins over amount")

    check(PrecipNotificationCopy.upcoming(hours: rainAtThree, placeKey: " ") == nil, "blank place key stays quiet")
    check(PrecipNotificationCopy.placeKey(latitude: 42.3601, longitude: -71.0589) == place, "place key rounds to two decimals")
    check(PrecipNotificationCopy.placeKey(latitude: .nan, longitude: 1) == "", "non-finite coordinate is blank")

    check(PrecipNotificationCopy.sampleBody(placeName: "Boston") == "Sample for Boston. Around 3:00 PM. This is not a live forecast.", "sample body")
    check(PrecipNotificationCopy.sampleBody(placeName: " ") == "Sample. Around 3:00 PM. This is not a live forecast.", "sample body without a place")
    check(PrecipNotificationCopy.isForecastRoute(PrecipNotificationCopy.userInfo(startTime: "2026-09-30T15:00")), "user info opens forecast")
    check(!PrecipNotificationCopy.isForecastRoute(["nwsAlertID": "abc"]), "alert info is not a forecast route")

    let active = rain!
    let other = PrecipPostedRecord(identifier: "precip.40.71_-74.01.20260930T18", placeKey: "40.71_-74.01", startTime: "2026-09-30T18:00")
    let stale = PrecipPostedRecord(identifier: "precip.\(place).20260930T09", placeKey: place, startTime: "2026-09-30T09:00")
    let previous = PrecipPostedRecord(identifier: "precip.\(place).20260930T13", placeKey: place, startTime: "2026-09-30T13:00")
    let kept = PrecipPostedRecord(identifier: active.identifier, placeKey: place, startTime: active.startTime)
    let cancel = PrecipNotificationCopy.identifiersToCancel(
        posted: [kept, previous, stale, other, previous],
        activeIdentifier: active.identifier,
        placeKey: place,
        currentTime: "2026-09-30T12:00"
    )
    check(cancel == [previous.identifier, stale.identifier], "cancels a replaced start and a passed hour, got \(cancel)")

    let cleared = PrecipNotificationCopy.identifiersToCancel(
        posted: [kept, other],
        activeIdentifier: nil,
        placeKey: place,
        currentTime: "2026-09-30T12:00"
    )
    check(cleared == [kept.identifier], "a forecast with no start removes this place only, got \(cleared)")

    let longPlace = String(repeating: "Boston ", count: 40)
    check(PrecipNotificationCopy.body(placeName: longPlace, time: "2026-09-30T15:00", clock: "3:00 PM").count == 178, "long body is clipped")

    print("ok")
}
