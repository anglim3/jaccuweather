import Foundation

@main
struct WindGustNotificationCheck {
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

func hour(_ time: String, speed: Double? = nil, gust: Double? = nil, clock: String = "") -> WindHourSample {
    WindHourSample(time: time, clock: clock, speed: speed, gust: gust)
}

func run() {
    check(WindGustNotificationCopy.reading(speed: 30, gust: 48) == WindReading(mph: 48, usesGust: true), "gust wins when it is stronger")
    check(WindGustNotificationCopy.reading(speed: 52, gust: 44) == WindReading(mph: 52, usesGust: false), "speed wins when it is stronger")
    check(WindGustNotificationCopy.reading(speed: 41, gust: 41) == WindReading(mph: 41, usesGust: true), "a tie prefers the gust")
    check(WindGustNotificationCopy.reading(speed: 46, gust: nil) == WindReading(mph: 46, usesGust: false), "speed alone is used")
    check(WindGustNotificationCopy.reading(speed: nil, gust: 47) == WindReading(mph: 47, usesGust: true), "gust alone is used")
    check(WindGustNotificationCopy.reading(speed: nil, gust: nil) == nil, "missing wind stays quiet")
    check(WindGustNotificationCopy.reading(speed: .nan, gust: 12) == WindReading(mph: 12, usesGust: true), "non-finite speed is ignored")
    check(WindGustNotificationCopy.reading(speed: .infinity, gust: .nan) == nil, "non-finite values stay quiet")

    check(WindGustNotificationCopy.title(usesGust: true) == "Damaging gusts expected", "gust title")
    check(WindGustNotificationCopy.title(usesGust: false) == "High winds expected", "sustained wind title")
    check(
        WindGustNotificationCopy.body(mph: 48.4, usesGust: true, placeName: "Boston", startClock: "3:00 PM", endClock: "4:00 PM")
            == "Boston. Gusts near 48 mph, 3:00 PM–4:00 PM.",
        "gust body names the place, speed, and window"
    )
    check(
        WindGustNotificationCopy.body(mph: 40.5, usesGust: false, placeName: "  Boston   MA ", startClock: "11:00 PM", endClock: "12:00 AM")
            == "Boston MA. Wind near 41 mph, 11:00 PM–12:00 AM.",
        "speed body collapses the place and crosses midnight"
    )
    check(
        WindGustNotificationCopy.body(mph: 44, usesGust: true, placeName: "  ", startClock: "", endClock: "")
            == "this place. Gusts near 44 mph, in the next 24 hours.",
        "blank place and clock fallback"
    )

    let placeKey = WindGustNotificationCopy.dedupeKey(placeName: "  Boston   MA ", hourKey: "2026-09-30T15")
    check(placeKey == "boston ma|2026-09-30T15", "dedupe key is place plus start hour, got \(placeKey)")
    check(WindGustNotificationCopy.dedupeKey(placeName: "Boston MA", hourKey: "2026-09-30T15") == placeKey, "place casing shares a key")
    check(WindGustNotificationCopy.shouldPost(key: placeKey, alreadyPosted: []), "new window can post")
    check(!WindGustNotificationCopy.shouldPost(key: placeKey, alreadyPosted: [placeKey]), "same place and hour stays quiet")
    check(
        WindGustNotificationCopy.shouldPost(key: WindGustNotificationCopy.dedupeKey(placeName: "Boston MA", hourKey: "2026-09-30T18"), alreadyPosted: [placeKey]),
        "a later hour can post"
    )
    check(
        WindGustNotificationCopy.shouldPost(key: WindGustNotificationCopy.dedupeKey(placeName: "Chicago", hourKey: "2026-09-30T15"), alreadyPosted: [placeKey]),
        "another place can post"
    )
    check(!WindGustNotificationCopy.shouldPost(key: "", alreadyPosted: []), "blank key stays quiet")
    check(
        WindGustNotificationCopy.notificationIdentifier(for: placeKey) == "jaccuweather.wind.boston-ma-2026-09-30t15",
        "notification id is stable"
    )

    let offset = -4 * 3600
    let now = localDate(year: 2026, month: 9, day: 30, hour: 14, minute: 30, offset: offset)
    let hours = [
        hour("2026-09-30T13:00", speed: 55, gust: 60),
        hour("2026-09-30T14:00", speed: 22, gust: 30),
        hour("2026-09-30T15:00", speed: 28, gust: 39.9),
        hour("2026-09-30T16:00", speed: 33, gust: 40),
        hour("2026-09-30T17:00", gust: 70),
        hour("2026-10-01T14:00", speed: 50),
        hour("2026-10-01T15:00", gust: 80)
    ]
    let notice = WindGustNotificationCopy.upcoming(hours: hours, placeName: "Boston", now: now, utcOffsetSeconds: offset)
    check(notice?.hourKey == "2026-09-30T16", "first hour at 40 mph is selected, got \(String(describing: notice?.hourKey))")
    check(notice?.usesGust == true, "40 mph gust uses the gust title")
    check(notice?.mph == 40, "selected reading is the gust")
    check(notice?.startClock == "4:00 PM" && notice?.endClock == "5:00 PM", "window is the place-local hour, got \(notice?.startClock ?? "")–\(notice?.endClock ?? "")")
    check(notice?.dedupeKey == "boston|2026-09-30T16", "selected key is place plus hour")

    let speedOnly = WindGustNotificationCopy.upcoming(
        hours: [hour("2026-09-30T16:00", speed: 44, gust: 20)],
        placeName: "Boston",
        now: now,
        utcOffsetSeconds: offset
    )
    check(speedOnly?.usesGust == false && speedOnly?.mph == 44, "stronger sustained wind is the reading")
    check(WindGustNotificationCopy.title(usesGust: speedOnly?.usesGust ?? true) == "High winds expected", "sustained wind title from the selection")

    let current = WindGustNotificationCopy.upcoming(
        hours: [hour("2026-09-30T14:00", gust: 51, clock: "2:00 PM")],
        placeName: "Boston",
        now: now,
        utcOffsetSeconds: offset
    )
    check(current?.hourKey == "2026-09-30T14", "the hour still in progress counts")
    check(current?.startClock == "2:00 PM" && current?.endClock == "3:00 PM", "supplied clock is kept and the end hour follows the stamp")

    check(
        WindGustNotificationCopy.upcoming(hours: [hour("2026-09-30T13:00", gust: 90)], placeName: "Boston", now: now, utcOffsetSeconds: offset) == nil,
        "an hour that already ended is skipped"
    )
    check(
        WindGustNotificationCopy.upcoming(hours: [hour("2026-10-01T15:00", gust: 90)], placeName: "Boston", now: now, utcOffsetSeconds: offset) == nil,
        "an hour that starts 24 hours later is outside the window"
    )
    check(
        WindGustNotificationCopy.upcoming(hours: [hour("2026-10-01T14:00", speed: 42)], placeName: "Boston", now: now, utcOffsetSeconds: offset)?.hourKey == "2026-10-01T14",
        "an hour that starts inside 24 hours still counts"
    )
    check(
        WindGustNotificationCopy.upcoming(hours: [hour("not-a-time", gust: 80), hour("2026-09-30T18:00", speed: 41)], placeName: "Boston", now: now, utcOffsetSeconds: offset)?.hourKey == "2026-09-30T18",
        "a stamp that is not a local hour is skipped"
    )
    check(
        WindGustNotificationCopy.upcoming(hours: [], placeName: "Boston", now: now, utcOffsetSeconds: offset) == nil,
        "no hours stays quiet"
    )

    let laterFirst = [
        hour("2026-09-30T18:00", gust: 60),
        hour("2026-09-30T16:00", speed: 45)
    ]
    check(
        WindGustNotificationCopy.upcoming(hours: laterFirst, placeName: "Boston", now: now, utcOffsetSeconds: offset)?.hourKey == "2026-09-30T16",
        "the earlier qualifying hour wins even when it is listed second"
    )

    check(!WindGustNotificationCopy.hourHasPassed("2026-09-30T14", now: now, utcOffsetSeconds: offset), "14:30 is still inside the 14:00 hour")
    check(WindGustNotificationCopy.hourHasPassed("2026-09-30T13", now: now, utcOffsetSeconds: offset), "13:00 has ended by 14:30")
    check(
        !WindGustNotificationCopy.shouldRemoveNotice(noticeHour: "2026-09-30T16", now: now, utcOffsetSeconds: offset, activeHour: "2026-09-30T16"),
        "the active hour stays"
    )
    check(
        WindGustNotificationCopy.shouldRemoveNotice(noticeHour: "2026-09-30T16", now: now, utcOffsetSeconds: offset, activeHour: nil),
        "a forecast that no longer meets the threshold removes the notice"
    )
    check(
        WindGustNotificationCopy.shouldRemoveNotice(noticeHour: "2026-09-30T16", now: now, utcOffsetSeconds: offset, activeHour: "2026-09-30T18"),
        "a different hour replaces the previous window"
    )
    check(
        WindGustNotificationCopy.shouldRemoveNotice(noticeHour: "2026-09-30T13", now: now, utcOffsetSeconds: offset, activeHour: "2026-09-30T13"),
        "a passed hour is removed"
    )
    check(
        WindGustNotificationCopy.shouldRemoveNotice(noticeHour: "", now: now, utcOffsetSeconds: offset, activeHour: "2026-09-30T16"),
        "a notice without an hour is removed"
    )

    let forecastURL = URL(string: "jaccuweather://forecast")!
    check(WindGustNotificationCopy.opensForecast(forecastURL), "forecast URL opens Forecast")
    check(WindGustNotificationCopy.opensForecast(URL(string: "jaccuweather://forecast/")!), "forecast path opens Forecast")
    check(!WindGustNotificationCopy.opensForecast(URL(string: "jaccuweather://now")!), "now URL is not the wind route")
    check(
        WindGustNotificationCopy.isForecastRoute(WindGustNotificationCopy.userInfo(hourKey: "2026-09-30T16", dedupeKey: placeKey)),
        "posted info opens Forecast"
    )
    check(WindGustNotificationCopy.isSample([WindGustNotificationCopy.sampleKey: "1"]), "sample flag")
    check(!WindGustNotificationCopy.isSample([:]), "live notice is not a sample")

    let suite = "wind-gust-notification-check"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    check(!WindGustNotificationStore.isOn(in: defaults), "missing preference stays off")
    WindGustNotificationStore.setOn(true, in: defaults)
    check(WindGustNotificationStore.isOn(in: defaults), "turning the control on is stored")
    WindGustNotificationStore.setOn(false, in: defaults)
    check(!WindGustNotificationStore.isOn(in: defaults), "turning the control off is stored")
    WindGustNotificationStore.remember(placeKey, in: defaults)
    WindGustNotificationStore.remember(placeKey, in: defaults)
    check(WindGustNotificationStore.postedKeys(in: defaults) == [placeKey], "a window is remembered once")
    defaults.removePersistentDomain(forName: suite)

    print("ok")
}
