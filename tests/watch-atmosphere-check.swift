import Foundation

@main
struct WatchAtmosphereCheck {
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
    check(WatchAtmosphere.category(uvIndex: 0) == "Low", "uv 0 is low")
    check(WatchAtmosphere.category(uvIndex: 2.9) == "Low", "uv 2.9 is low")
    check(WatchAtmosphere.category(uvIndex: 3) == "Moderate", "uv 3 is moderate")
    check(WatchAtmosphere.category(uvIndex: 5.9) == "Moderate", "uv 5.9 is moderate")
    check(WatchAtmosphere.category(uvIndex: 6) == "High", "uv 6 is high")
    check(WatchAtmosphere.category(uvIndex: 7.9) == "High", "uv 7.9 is high")
    check(WatchAtmosphere.category(uvIndex: 8) == "Very high", "uv 8 is very high")
    check(WatchAtmosphere.category(uvIndex: 10.9) == "Very high", "uv 10.9 is very high")
    check(WatchAtmosphere.category(uvIndex: 11) == "Extreme", "uv 11 is extreme")
    check(WatchAtmosphere.category(uvIndex: 14) == "Extreme", "uv 14 is extreme")

    let lowEdge = WatchAtmosphere.metrics(uvIndex: 2.9, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil)
    let lowChip = WatchAtmosphere.uvChip(lowEdge)
    check(lowChip?.text == "UV 3", "displayed uv rounds like the now tab")
    check(lowChip?.spoken == "UV index 3, Low", "category stays on the raw index")

    let high = WatchAtmosphere.metrics(uvIndex: 6.2, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil)
    check(WatchAtmosphere.uvChip(high)?.text == "UV 6", "uv 6.2 displays as 6")
    check(WatchAtmosphere.uvChip(high)?.spoken == "UV index 6, High", "uv 6.2 is high")
    check(WatchAtmosphere.uvChip(WatchAtmosphere.Metrics.empty) == nil, "missing uv stays hidden")
    check(WatchAtmosphere.uvChip(WatchAtmosphere.metrics(uvIndex: .infinity, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil)) == nil, "non-finite uv stays hidden")
    check(WatchAtmosphere.uvChip(WatchAtmosphere.metrics(uvIndex: 0, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil))?.text == "UV 0", "nighttime uv 0 still shows")

    check(WatchAtmosphere.compass(0) == "N", "0 is north")
    check(WatchAtmosphere.compass(360) == "N", "360 is north")
    check(WatchAtmosphere.compass(11.24) == "N", "just below the north boundary stays north")
    check(WatchAtmosphere.compass(11.25) == "NNE", "the north boundary rounds to nne")
    check(WatchAtmosphere.compass(22.5) == "NNE", "nne center")
    check(WatchAtmosphere.compass(180) == "S", "180 is south")
    check(WatchAtmosphere.compass(225) == "SW", "225 is southwest")
    check(WatchAtmosphere.compass(315) == "NW", "315 is northwest")
    check(WatchAtmosphere.compass(-10) == "N", "negative degrees wrap")
    check(WatchAtmosphere.compass(348.74) == "NNW", "just below north from the west stays nnw")
    check(WatchAtmosphere.arrowDegrees(315) == 495, "the arrow points where the wind is going")

    let full = WatchAtmosphere.metrics(uvIndex: 4, windSpeedMph: 12.4, windDirectionDegrees: 315, windGustMph: 20.2)
    let wind = WatchAtmosphere.windChip(full)
    check(wind?.text == "12 mph NW · G20", "speed, direction, and gust")
    check(wind?.spoken == "Wind 12 miles per hour, from NW, gust 20", "wind is spoken with direction and gust")
    check(wind?.arrowDegrees == 495, "wind chip carries the arrow")
    let glance = WatchAtmosphere.glanceLine(full)
    check(glance?.text == "12 mph NW", "glance wind omits the gust")
    check(glance?.spoken == "Wind 12 miles per hour, from NW, gust 20", "glance still speaks the gust")
    check(glance?.identifier == "watch-wind", "glance wind identifier")
    check(WatchAtmosphere.detailLine(full) == "UV 4 · 12 mph NW · G20", "complication line joins uv and wind")
    check(WatchAtmosphere.circularToken(full) == "12 mph", "circular prefers the wind speed")

    let speedOnly = WatchAtmosphere.metrics(uvIndex: nil, windSpeedMph: 8, windDirectionDegrees: nil, windGustMph: nil)
    check(WatchAtmosphere.windChip(speedOnly)?.text == "8 mph", "speed without direction")
    check(WatchAtmosphere.windChip(speedOnly)?.arrowDegrees == nil, "no arrow without a direction")
    check(WatchAtmosphere.glanceLine(speedOnly)?.text == "8 mph", "glance speed without direction")
    check(WatchAtmosphere.circularToken(speedOnly) == "8 mph", "circular uses the speed")

    let gustOnly = WatchAtmosphere.metrics(uvIndex: nil, windSpeedMph: nil, windDirectionDegrees: 90, windGustMph: 18)
    check(WatchAtmosphere.windChip(gustOnly)?.text == "G18 E", "gust stands in when speed is missing")
    check(WatchAtmosphere.windChip(gustOnly)?.spoken == "Gust 18 miles per hour, from E", "gust is spoken as the wind")
    check(WatchAtmosphere.glanceLine(gustOnly)?.text == "G18 E", "glance gust when speed is missing")
    check(WatchAtmosphere.glanceLine(gustOnly)?.identifier == "watch-wind", "gust-only glance is still wind")
    check(WatchAtmosphere.circularToken(gustOnly) == "G18", "circular uses the gust when speed is missing")

    let directionOnly = WatchAtmosphere.metrics(uvIndex: nil, windSpeedMph: nil, windDirectionDegrees: 180, windGustMph: nil)
    check(WatchAtmosphere.windChip(directionOnly) == nil, "direction alone stays hidden")
    check(WatchAtmosphere.glanceLine(directionOnly) == nil, "glance hides direction alone")
    check(WatchAtmosphere.detailLine(directionOnly) == nil, "no complication line without uv or wind")

    let uvOnly = WatchAtmosphere.metrics(uvIndex: 9.2, windSpeedMph: nil, windDirectionDegrees: nil, windGustMph: nil)
    check(WatchAtmosphere.detailLine(uvOnly) == "UV 9", "uv alone is the complication line")
    check(WatchAtmosphere.glanceLine(uvOnly)?.text == "UV 9", "glance falls back to uv")
    check(WatchAtmosphere.glanceLine(uvOnly)?.identifier == "watch-uv", "glance uv identifier")
    check(WatchAtmosphere.glanceLine(WatchAtmosphere.Metrics.empty) == nil, "glance hides an empty reading")
    check(WatchAtmosphere.circularToken(uvOnly) == "UV 9", "circular falls back to uv")
    check(WatchAtmosphere.uvChip(uvOnly)?.spoken == "UV index 9, Very high", "uv 9.2 is very high")

    check(!WatchAtmosphere.isComplete(uvOnly), "uv without wind is incomplete")
    check(!WatchAtmosphere.isComplete(speedOnly), "wind without uv is incomplete")
    check(WatchAtmosphere.isComplete(WatchAtmosphere.metrics(uvIndex: 0, windSpeedMph: 0, windDirectionDegrees: nil, windGustMph: nil)), "zero uv and calm wind count as a reading")
    check(WatchAtmosphere.isComplete(WatchAtmosphere.metrics(uvIndex: 1, windSpeedMph: nil, windDirectionDegrees: 10, windGustMph: 5)), "a gust completes the wind side")

    let phone = WatchAtmosphere.metrics(uvIndex: 4, windSpeedMph: 10, windDirectionDegrees: nil, windGustMph: nil)
    let fetched = WatchAtmosphere.metrics(uvIndex: 5, windSpeedMph: 11, windDirectionDegrees: 200, windGustMph: 16)
    let merged = WatchAtmosphere.preferringExisting(phone, fill: fetched)
    check(merged.uvIndex == 4 && merged.windSpeedMph == 10, "a phone reading wins")
    check(merged.windDirectionDegrees == 200 && merged.windGustMph == 16, "open-meteo fills the fields the phone left empty")
    check(WatchAtmosphere.preferringExisting(.empty, fill: fetched) == fetched, "an empty phone reading takes the forecast")

    let json = """
    {"uv_index":6.2,"wind_speed_10m":12.4,"wind_direction_10m":315,"wind_gusts_10m":null}
    """.data(using: .utf8)!
    let object = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
    let parsed = WatchAtmosphere.metrics(fromCurrent: object)
    check(parsed.uvIndex == 6.2, "parses uv_index")
    check(parsed.windSpeedMph == 12.4, "parses wind_speed_10m")
    check(parsed.windDirectionDegrees == 315, "parses an integer wind direction")
    check(parsed.windGustMph == nil, "null gust stays empty")

    let partial = """
    {"wind_gusts_10m":9}
    """.data(using: .utf8)!
    let partialObject = try! JSONSerialization.jsonObject(with: partial) as! [String: Any]
    let gust = WatchAtmosphere.metrics(fromCurrent: partialObject)
    check(gust.uvIndex == nil && gust.windSpeedMph == nil && gust.windGustMph == 9, "a missing key stays empty")

    var noisy: [String: Any] = [
        "uv_index": Double.nan,
        "wind_speed_10m": "12",
        "wind_direction_10m": Double.infinity,
        "wind_gusts_10m": 4
    ]
    let cleaned = WatchAtmosphere.metrics(fromCurrent: noisy)
    check(cleaned.uvIndex == nil && cleaned.windSpeedMph == nil && cleaned.windDirectionDegrees == nil, "non-finite and non-numeric values drop")
    check(cleaned.windGustMph == 4, "a numeric gust remains")
    noisy["wind_speed_10m"] = 7
    check(WatchAtmosphere.metrics(fromCurrent: noisy).windSpeedMph == 7, "an int speed is accepted")

    print("ok")
}
