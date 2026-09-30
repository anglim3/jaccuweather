import Foundation

@main
struct ControlOpenCheck {
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
    let open = OpenNowControlCopy.face(temperatureF: nil, symbolName: nil, placeName: "Seattle")
    check(open.title == "Open", "missing temperature stays Open")
    check(open.symbolName == "sun.max.fill", "open symbol")
    check(open.status == nil, "open control has no place status")

    let nan = OpenNowControlCopy.face(temperatureF: .nan, symbolName: "sun.max.fill", placeName: "Seattle")
    check(nan.title == "Open", "non-finite temperature stays Open")

    let warm = OpenNowControlCopy.face(temperatureF: 61.6, symbolName: " cloud.sun.fill ", placeName: " Seattle ")
    check(warm.title == "62°", "rounds temperature, got \(warm.title)")
    check(warm.symbolName == "cloud.sun.fill", "trims symbol")
    check(warm.status == "Seattle", "trims place")

    let blankSymbol = OpenNowControlCopy.face(temperatureF: -0.4, symbolName: " ", placeName: " ")
    check(blankSymbol.title == "0°", "negative rounds toward zero")
    check(blankSymbol.symbolName == "cloud.fill", "blank symbol falls back")
    check(blankSymbol.status == nil, "blank place is omitted")

    check(NowLink.opensNow(NowLink.url), "canonical now url")
    check(NowLink.opensNow(URL(string: "JACCUWEATHER://Now")!), "scheme and host are case-insensitive")
    check(NowLink.opensNow(URL(string: "jaccuweather:///now")!), "path form")
    check(!NowLink.opensNow(URL(string: "jaccuweather://forecast")!), "other host stays closed")
    check(!NowLink.opensNow(URL(string: "https://weather.janglim.cloud/now")!), "other scheme stays closed")
    check(NowLink.opensForecast(URL(string: "jaccuweather://forecast")!), "forecast host")
    check(NowLink.opensForecast(URL(string: "jaccuweather:///forecast")!), "forecast path")
    check(NowLink.opensForecast(URL(string: "JACCUWEATHER://Forecast")!), "forecast scheme is case-insensitive")
    check(!NowLink.opensForecast(NowLink.url), "now is not forecast")
    check(!NowLink.opensForecast(URL(string: "https://example.com/forecast")!), "other scheme is not forecast")

    print("ok")
}
