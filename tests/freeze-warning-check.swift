import Foundation

@main
struct FreezeWarningCheck {
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

func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, offset: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: offset)!
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = hour
    parts.minute = minute
    return calendar.date(from: parts)!
}

func run() {
    check(FreezeWarningCopy.title(lowF: 32) == "Freeze warning tonight", "32 is a freeze warning")
    check(FreezeWarningCopy.title(lowF: 28.1) == "Freeze warning tonight", "just above 28 stays a freeze warning")
    check(FreezeWarningCopy.title(lowF: 28) == "Hard freeze tonight", "28 is a hard freeze")
    check(FreezeWarningCopy.title(lowF: 10) == "Hard freeze tonight", "colder than 28 is a hard freeze")
    check(FreezeWarningCopy.title(lowF: 32.1) == nil, "above 32 stays quiet")
    check(FreezeWarningCopy.title(lowF: .nan) == nil, "missing low stays quiet")
    check(FreezeWarningCopy.title(lowF: .infinity) == nil, "non-finite low stays quiet")

    check(FreezeWarningCopy.body(lowF: 29, placeName: "PlaceName") == "Low near 29° in PlaceName", "body names the low and place")
    check(FreezeWarningCopy.body(lowF: 28.6, placeName: "Duluth") == "Low near 29° in Duluth", "body rounds to the nearest degree")
    check(FreezeWarningCopy.body(lowF: -0.4, placeName: "Nome") == "Low near 0° in Nome", "body rounds a negative low")
    check(FreezeWarningCopy.body(lowF: 29, placeName: "  ") == "Low near 29° in this place", "blank place fallback")
    check(FreezeWarningCopy.body(lowF: 29, placeName: "  Fairbanks   AK ") == "Low near 29° in Fairbanks AK", "place whitespace collapses")

    let placeKey = FreezeWarningCopy.dedupeKey(placeName: "  Fairbanks   AK ", day: "2026-01-16")
    check(placeKey == "fairbanks ak|2026-01-16", "dedupe key is place plus day, got \(placeKey)")
    check(FreezeWarningCopy.dedupeKey(placeName: "Fairbanks AK", day: "2026-01-16") == placeKey, "place casing shares a key")
    check(FreezeWarningCopy.shouldPost(key: placeKey, alreadyPosted: []), "new night can post")
    check(!FreezeWarningCopy.shouldPost(key: placeKey, alreadyPosted: [placeKey]), "same place and day stays quiet")
    check(FreezeWarningCopy.shouldPost(key: FreezeWarningCopy.dedupeKey(placeName: "Nome", day: "2026-01-16"), alreadyPosted: [placeKey]), "another place can post")
    check(FreezeWarningCopy.shouldPost(key: FreezeWarningCopy.dedupeKey(placeName: "Fairbanks AK", day: "2026-01-17"), alreadyPosted: [placeKey]), "the next day can post")
    check(!FreezeWarningCopy.shouldPost(key: "", alreadyPosted: []), "blank key stays quiet")
    check(
        FreezeWarningCopy.notificationIdentifier(for: placeKey) == "jaccuweather.freeze.fairbanks-ak-2026-01-16",
        "notification id is stable"
    )

    let offset = -5 * 3600
    let days = ["2026-01-14", "2026-01-15", "2026-01-16", "2026-01-17"]
    let lows: [Double?] = [40, 31, nil, 22]
    let early = localDate(year: 2026, month: 1, day: 15, hour: 7, minute: 59, offset: offset)
    let cutoff = localDate(year: 2026, month: 1, day: 15, hour: 8, minute: 0, offset: offset)
    let evening = localDate(year: 2026, month: 1, day: 15, hour: 21, minute: 0, offset: offset)

    let tonight = FreezeWarningCopy.nextOvernight(days: days, lows: lows, now: early, utcOffsetSeconds: offset)
    check(tonight == FreezeNight(day: "2026-01-15", lowF: 31), "before 08:00 uses today's low, got \(String(describing: tonight))")
    let next = FreezeWarningCopy.nextOvernight(days: days, lows: lows, now: cutoff, utcOffsetSeconds: offset)
    check(next == FreezeNight(day: "2026-01-17", lowF: 22), "from 08:00 skips a missing low and uses the next overnight, got \(String(describing: next))")
    let later = FreezeWarningCopy.nextOvernight(days: days, lows: lows, now: evening, utcOffsetSeconds: offset)
    check(later?.day == "2026-01-17", "evening still uses the coming overnight")
    check(
        FreezeWarningCopy.nextOvernight(days: ["2026-01-14"], lows: [20], now: evening, utcOffsetSeconds: offset) == nil,
        "a finished overnight is not reused"
    )
    check(
        FreezeWarningCopy.nextOvernight(days: ["bad", "2026-01-16"], lows: [10, 20], now: evening, utcOffsetSeconds: offset)?.day == "2026-01-16",
        "skips a day token that is not a calendar day"
    )

    check(!FreezeWarningCopy.periodHasPassed(day: "2026-01-15", now: early, utcOffsetSeconds: offset), "07:59 is still the overnight")
    check(FreezeWarningCopy.periodHasPassed(day: "2026-01-15", now: cutoff, utcOffsetSeconds: offset), "08:00 ends that overnight")
    check(!FreezeWarningCopy.periodHasPassed(day: "2026-01-16", now: evening, utcOffsetSeconds: offset), "tomorrow morning has not passed")
    check(FreezeWarningCopy.periodHasPassed(day: "2026-01-14", now: early, utcOffsetSeconds: offset), "an earlier day has passed")

    check(
        !FreezeWarningCopy.shouldRemoveNotice(
            noticeDay: "2026-01-15",
            now: early,
            utcOffsetSeconds: offset,
            activeDay: "2026-01-15",
            activeLowF: 31
        ),
        "keeps a notice while the overnight is still freezing"
    )
    check(
        FreezeWarningCopy.shouldRemoveNotice(
            noticeDay: "2026-01-15",
            now: early,
            utcOffsetSeconds: offset,
            activeDay: "2026-01-15",
            activeLowF: 40
        ),
        "removes a notice when the low rises above 32"
    )
    check(
        FreezeWarningCopy.shouldRemoveNotice(
            noticeDay: "2026-01-15",
            now: cutoff,
            utcOffsetSeconds: offset,
            activeDay: "2026-01-17",
            activeLowF: 22
        ),
        "removes a notice after the overnight ends"
    )
    check(
        FreezeWarningCopy.shouldRemoveNotice(
            noticeDay: "2026-01-16",
            now: evening,
            utcOffsetSeconds: offset,
            activeDay: nil,
            activeLowF: nil
        ),
        "removes a notice when the forecast has no overnight"
    )
    check(
        !FreezeWarningCopy.shouldRemoveNotice(
            noticeDay: "2026-01-17",
            now: evening,
            utcOffsetSeconds: offset,
            activeDay: "2026-01-17",
            activeLowF: 28
        ),
        "keeps a hard-freeze notice for the active night"
    )

    check(FreezeWarningCopy.opensForecast(URL(string: "jaccuweather://forecast")!), "forecast host opens Forecast")
    check(FreezeWarningCopy.opensForecast(URL(string: "jaccuweather:///forecast")!), "forecast path opens Forecast")
    check(!FreezeWarningCopy.opensForecast(URL(string: "jaccuweather://now")!), "now stays on its own tab")
    check(!FreezeWarningCopy.opensForecast(URL(string: "https://example.com/forecast")!), "other schemes stay closed")
    check(FreezeWarningCopy.ownsNotice([FreezeWarningCopy.routeKey: "forecast"]), "route user info is a freeze notice")
    check(FreezeWarningCopy.ownsNotice([FreezeWarningCopy.routeKey: "Forecast"]), "route match ignores case")
    check(!FreezeWarningCopy.ownsNotice(["url": "jaccuweather://forecast"]), "a forecast URL alone is not a freeze notice")
    check(!FreezeWarningCopy.ownsNotice([:]), "empty user info is not a freeze notice")
    check(FreezeWarningCopy.isForecastRoute([FreezeWarningCopy.routeKey: "forecast"]), "route user info opens Forecast")
    check(FreezeWarningCopy.isForecastRoute(["url": "jaccuweather://forecast"]), "forecast url user info opens Forecast")
    let windNotice = [
        "windGustRoute": "forecast",
        "url": "jaccuweather://forecast",
        "windHour": "2026-01-15T16"
    ]
    check(!FreezeWarningCopy.ownsNotice(windNotice), "a high-wind notice is not owned by freeze")
    check(!FreezeWarningCopy.isForecastRoute(windNotice), "a high-wind notice is not a freeze route")
    check(!FreezeWarningCopy.isForecastRoute(["nwsAlertID": "abc"]), "alert user info is not a freeze route")
    check(FreezeWarningCopy.isSample([FreezeWarningCopy.sampleKey: "1"]), "sample flag")
    check(!FreezeWarningCopy.isSample([:]), "live notice is not a sample")

    let suite = "freeze-warning-check-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fputs("FAIL defaults suite\n", stderr)
        exit(1)
    }
    defaults.removePersistentDomain(forName: suite)
    check(!FreezeNotificationStore.isOn(in: defaults), "preference defaults off")
    FreezeNotificationStore.setOn(true, in: defaults)
    check(FreezeNotificationStore.isOn(in: defaults), "preference stores on")
    FreezeNotificationStore.setOn(false, in: defaults)
    check(!FreezeNotificationStore.isOn(in: defaults), "preference stores off")
    FreezeNotificationStore.remember(placeKey, in: defaults)
    FreezeNotificationStore.remember(placeKey, in: defaults)
    FreezeNotificationStore.remember("", in: defaults)
    check(FreezeNotificationStore.postedKeys(in: defaults) == [placeKey], "posted nights remember one place-day")
    check(
        !FreezeWarningCopy.shouldPost(key: placeKey, alreadyPosted: FreezeNotificationStore.postedKeys(in: defaults)),
        "stored place-day blocks a second post"
    )
    defaults.removePersistentDomain(forName: suite)

    let capSuite = "freeze-warning-cap-\(UUID().uuidString)"
    guard let capDefaults = UserDefaults(suiteName: capSuite) else {
        fputs("FAIL cap defaults suite\n", stderr)
        exit(1)
    }
    capDefaults.removePersistentDomain(forName: capSuite)
    for index in 0..<205 {
        FreezeNotificationStore.remember(String(format: "place|2026-01-%03d", index), in: capDefaults)
    }
    check(FreezeNotificationStore.postedKeys(in: capDefaults).count == 200, "posted nights stay capped")
    check(!FreezeNotificationStore.postedKeys(in: capDefaults).contains("place|2026-01-000"), "oldest nights drop first")
    capDefaults.removePersistentDomain(forName: capSuite)

    print("ok")
}
