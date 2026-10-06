import Foundation

@main
struct WatchDewPointCheck {
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
    let warm = WatchDewPoint.chip(fahrenheit: 52.4)
    check(warm?.text == "Dew 52°", "52.4 rounds down like the other watch temperatures")
    check(warm?.spoken == "Dew point 52 degrees", "voiceover names the dew point in degrees")
    check(warm?.fahrenheit == 52, "the chip keeps the rounded degrees")

    let up = WatchDewPoint.chip(fahrenheit: 52.5)
    check(up?.text == "Dew 53°", "52.5 rounds away from zero")
    check(up?.spoken == "Dew point 53 degrees", "voiceover uses the rounded degrees")

    let freezing = WatchDewPoint.chip(fahrenheit: -3.2)
    check(freezing?.text == "Dew -3°", "a negative dew point stays signed")
    check(freezing?.spoken == "Dew point -3 degrees", "voiceover keeps the minus")

    let zero = WatchDewPoint.chip(fahrenheit: 0)
    check(zero?.text == "Dew 0°", "zero dew point is shown")
    check(zero?.spoken == "Dew point 0 degrees", "voiceover speaks zero")

    check(WatchDewPoint.chip(fahrenheit: nil) == nil, "a missing dew point stays hidden")
    check(WatchDewPoint.chip(fahrenheit: .nan) == nil, "a non-numeric dew point stays hidden")
    check(WatchDewPoint.chip(fahrenheit: .infinity) == nil, "an infinite dew point stays hidden")
    check(WatchDewPoint.chip(fahrenheit: -.infinity) == nil, "a negative infinite dew point stays hidden")
    check(WatchDewPoint.usable(nil) == nil, "usable rejects a missing value")

    check(WatchDewPoint.preferringExisting(52, fill: 40) == 52, "a phone dew point wins over the forecast fill")
    check(WatchDewPoint.preferringExisting(nil, fill: 45.4) == 45.4, "a missing phone value takes the forecast fill")
    check(WatchDewPoint.preferringExisting(.nan, fill: 45) == 45, "an unusable phone value takes the forecast fill")
    check(WatchDewPoint.preferringExisting(nil, fill: nil) == nil, "two missing values stay hidden")

    print("ok")
}
