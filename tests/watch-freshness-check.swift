import Foundation

@main
struct WatchFreshnessCheck {
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
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    check(WatchFreshness.staleAfter == 60 * 60, "stale threshold is 60 minutes")

    let same = WatchFreshness.line(fetchedAt: now, now: now)
    check(same?.text == "Updated just now", "the fetch instant is just now")
    check(same?.isStale == false, "the fetch instant is current")
    check(same?.spoken == "Updated just now", "just now is spoken as written")

    let underMinute = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-59), now: now)
    check(underMinute?.text == "Updated just now", "59 seconds stays just now")
    check(underMinute?.isStale == false, "59 seconds is current")

    let oneMinute = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-60), now: now)
    check(oneMinute?.text == "Updated 1 min ago", "60 seconds is 1 min ago")
    check(oneMinute?.spoken == "Updated 1 minute ago", "one minute is spoken in full")
    check(oneMinute?.isStale == false, "one minute is current")

    let twelve = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-12 * 60), now: now)
    check(twelve?.text == "Updated 12 min ago", "twelve minutes uses min")
    check(twelve?.spoken == "Updated 12 minutes ago", "twelve minutes is spoken in full")
    check(twelve?.isStale == false, "twelve minutes is current")

    let fiftyNine = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-59 * 60), now: now)
    check(fiftyNine?.text == "Updated 59 min ago", "59 minutes stays in minutes")
    check(fiftyNine?.isStale == false, "59 minutes is still current")

    let hour = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-60 * 60), now: now)
    check(hour?.text == "Updated 1 hr ago", "exactly 60 minutes is 1 hr ago")
    check(hour?.spoken == "Updated 1 hour ago", "one hour is spoken in full")
    check(hour?.isStale == false, "exactly 60 minutes is still current")

    let justOver = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-60 * 60 - 1), now: now)
    check(justOver?.text == "Updated 1 hr ago", "one second past an hour still says 1 hr")
    check(justOver?.isStale == true, "over 60 minutes is stale")
    check(justOver?.spoken == "Updated 1 hour ago, stale", "stale is spoken with the age")

    let ninety = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-90 * 60), now: now)
    check(ninety?.text == "Updated 1 hr ago", "90 minutes is still 1 hr ago")
    check(ninety?.isStale == true, "90 minutes is stale")

    let almostTwo = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-119 * 60), now: now)
    check(almostTwo?.text == "Updated 1 hr ago", "119 minutes is still 1 hr ago")

    let three = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-3 * 60 * 60), now: now)
    check(three?.text == "Updated 3 hr ago", "three hours uses hr")
    check(three?.spoken == "Updated 3 hours ago, stale", "three hours is spoken in full")
    check(three?.isStale == true, "three hours is stale")

    let twoHours = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-2 * 60 * 60), now: now)
    check(twoHours?.spoken == "Updated 2 hours ago, stale", "plural hours")

    let oneDay = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-24 * 60 * 60), now: now)
    check(oneDay?.text == "Updated 1 day ago", "24 hours is 1 day ago")
    check(oneDay?.spoken == "Updated 1 day ago, stale", "one day is spoken in full")
    check(oneDay?.isStale == true, "one day is stale")

    let twoDays = WatchFreshness.line(fetchedAt: now.addingTimeInterval(-48 * 60 * 60), now: now)
    check(twoDays?.text == "Updated 2 days ago", "48 hours is 2 days ago")
    check(twoDays?.spoken == "Updated 2 days ago, stale", "plural days")

    let ahead = WatchFreshness.line(fetchedAt: now.addingTimeInterval(45), now: now)
    check(ahead?.text == "Updated just now", "a future stamp reads as just now")
    check(ahead?.isStale == false, "a future stamp is not stale")

    check(WatchFreshness.line(fetchedAt: .distantPast, now: now) == nil, "distantPast placeholder has no line")

    let ancient = WatchFreshness.line(fetchedAt: Date(timeIntervalSince1970: 0), now: now)
    check(ancient != nil, "an old real stamp still has a line")
    check(ancient?.isStale == true, "an old real stamp is stale")
    check(ancient?.text.hasPrefix("Updated ") == true, "an old real stamp still says Updated")

    print("ok")
}
