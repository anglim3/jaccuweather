import Foundation

@main
struct NotificationRouteIsolationCheck {
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

func run() {
    let wind = WindGustNotificationCopy.userInfo(hourKey: "2026-09-30T16", dedupeKey: "boston|2026-09-30T16")
    check(WindGustNotificationCopy.ownsNotice(wind), "high-wind payload is owned by wind")
    check(WindGustNotificationCopy.isForecastRoute(wind), "high-wind payload opens Forecast")
    check(!FreezeWarningCopy.ownsNotice(wind), "high-wind payload is not a freeze notice")
    check(!FreezeWarningCopy.isForecastRoute(wind), "high-wind payload is not a freeze route")

    let freeze: [String: String] = [
        FreezeWarningCopy.routeKey: FreezeWarningCopy.routeValue,
        "url": FreezeWarningCopy.forecastURL.absoluteString,
        FreezeWarningCopy.dayKey: "2026-01-15",
        FreezeWarningCopy.dedupeKeyName: "fairbanks ak|2026-01-15"
    ]
    check(FreezeWarningCopy.ownsNotice(freeze), "freeze payload is owned by freeze")
    check(FreezeWarningCopy.isForecastRoute(freeze), "freeze payload opens Forecast")
    check(!WindGustNotificationCopy.ownsNotice(freeze), "freeze payload is not a high-wind notice")
    check(!WindGustNotificationCopy.isForecastRoute(freeze), "freeze payload is not a wind route")

    let urlOnly = ["url": FreezeWarningCopy.forecastURL.absoluteString]
    check(!FreezeWarningCopy.ownsNotice(urlOnly), "url-only payload is not removed as a freeze notice")
    check(!WindGustNotificationCopy.ownsNotice(urlOnly), "url-only payload is not removed as a wind notice")
    check(FreezeWarningCopy.isForecastRoute(urlOnly), "url-only payload can still open Forecast")
    check(WindGustNotificationCopy.isForecastRoute(urlOnly), "url-only payload can still open Forecast from wind")

    let precip = ["openForecast": "forecast", "startTime": "2026-09-30T15:00"]
    check(!FreezeWarningCopy.ownsNotice(precip) && !FreezeWarningCopy.isForecastRoute(precip), "precip payload stays out of freeze")
    check(!WindGustNotificationCopy.ownsNotice(precip) && !WindGustNotificationCopy.isForecastRoute(precip), "precip payload stays out of wind")

    print("ok")
}
