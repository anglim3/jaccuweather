import Foundation

@main
struct WatchSpokenCheck {
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
    check(WatchSpoken.degrees(62) == "62 degrees", "a temperature is spoken in degrees")
    check(WatchSpoken.degrees(-3.2) == "-3 degrees", "a negative temperature keeps the sign")
    check(WatchSpoken.degrees(nil) == "unavailable", "a missing temperature is unavailable")
    check(WatchSpoken.degrees(fromDisplay: "62°") == "62 degrees", "a degree sign becomes the word")
    check(WatchSpoken.degrees(fromDisplay: "—") == "Temperature unavailable", "a dash is a missing temperature")

    let rainy = WatchHourSlot(
        time: "2026-10-02T15:00",
        label: "3p",
        temperatureF: 62,
        precipProbability: 20,
        cue: .rain
    )
    check(
        WatchSpoken.hourlyCell(rainy) == "3 PM, 62 degrees, 20 percent chance of rain",
        "an hourly cell is one sentence"
    )
    check(!WatchSpoken.hourlyCell(rainy).contains("°"), "an hourly cell has no degree sign")
    check(!WatchSpoken.hourlyCell(rainy).contains("3p"), "an hourly cell expands the clock")

    let snowHour = WatchHourSlot(
        time: "2026-10-02T21:00",
        label: "9p",
        temperatureF: 31,
        precipProbability: nil,
        cue: .snow
    )
    check(WatchSpoken.hourlyCell(snowHour) == "9 PM, 31 degrees, snow", "snow without a chance still names snow")

    let dry = WatchHourSlot(
        time: "2026-10-02T16:00",
        label: "4p",
        temperatureF: 70,
        precipProbability: nil,
        cue: .none
    )
    check(WatchSpoken.hourlyCell(dry) == "4 PM, 70 degrees", "a dry hour is time and temperature")

    let chanceOnly = WatchHourSlot(
        time: "2026-10-02T18:00",
        label: "6p",
        temperatureF: 58,
        precipProbability: 15,
        cue: .none
    )
    check(
        WatchSpoken.hourlyCell(chanceOnly) == "6 PM, 58 degrees, 15 percent chance of precipitation",
        "a chance without a cue names precipitation"
    )

    let day = WatchDaySlot(
        date: "2026-10-02",
        label: "Fri",
        highF: 62,
        lowF: 48,
        symbolName: "cloud.sun.fill",
        conditionText: "Partly cloudy",
        precipProbability: 20,
        rainInches: 0.2,
        snowInches: 0
    )
    check(
        WatchSpoken.dailyCell(day) == "Friday, Partly cloudy, high 62 degrees, low 48 degrees, 20 percent chance of rain",
        "a daily cell names the condition, high, low, and chance"
    )
    check(WatchSpoken.conditionName(text: nil, symbolName: "cloud.sun.fill") == "Partly cloudy", "a sun and cloud symbol is partly cloudy")
    check(WatchSpoken.weekdayName(date: "", label: "Fri") == "Friday", "a short weekday expands when the date is missing")

    let hour = WatchHourSlot(
        time: "2026-10-02T15:00",
        label: "3p",
        temperatureF: 47,
        precipProbability: 72,
        cue: .rain,
        symbolName: "cloud.rain.fill",
        conditionText: "Light rain",
        rainInches: 0.42,
        snowInches: 0,
        feelsLikeF: 44,
        windMph: 13,
        humidity: 81,
        uvIndex: 1.2
    )
    let sheet = WatchSpoken.hourSheet(hour)
    check(sheet.contains("3 PM"), "the hour sheet uses 12-hour time")
    check(sheet.contains("Light rain"), "the hour sheet names the condition")
    check(sheet.contains("47 degrees"), "the hour sheet says degrees")
    check(sheet.contains("72 percent chance of rain"), "the hour sheet says chance of rain")
    check(sheet.contains("0.42 inches of rain"), "the hour sheet says inches of rain")
    check(sheet.contains("Feels like 44 degrees"), "feels-like is spoken in degrees")
    check(sheet.contains("Wind 13 miles per hour"), "wind is spoken in miles per hour")
    check(sheet.contains("Humidity 81 percent"), "humidity is spoken as percent")
    check(sheet.contains("Ultraviolet index 1, Low"), "UV is spoken as ultraviolet index")
    check(!sheet.contains("°") && !sheet.contains("mph") && !sheet.contains("UV "), "the hour sheet avoids the short forms")

    check(WatchSpoken.airQuality(value: 42, category: "Good") == "Air quality index 42, Good", "AQI is spoken as air quality index")
    check(WatchSpoken.ultraviolet(index: 6.2) == "Ultraviolet index 6, High", "a high UV index names the band")

    let glance = WatchSpoken.glance(
        place: "Juneau",
        temperatureText: "44°",
        condition: "Light rain",
        feelsSpoken: "Feels like 39 degrees",
        dewSpoken: "Dew point 37 degrees",
        aqiSpoken: "Air quality index 22, Good",
        atmosphere: ["Wind 5 miles per hour", "Humidity 76 percent"],
        sunSpoken: "Sunrise 7:31 AM, sunset 5:54 PM",
        alertSpoken: "2 alerts, Moderate, Wind Advisory"
    )
    check(glance.hasPrefix("Juneau, 44 degrees"), "the glance starts with the place and temperature")
    check(glance.contains("Light rain"), "the glance names the condition")
    check(glance.contains("Dew point 37 degrees"), "the glance includes the dew point")
    check(glance.contains("Air quality index 22, Good"), "the glance includes air quality")
    check(glance.contains("miles per hour"), "the glance speaks wind in miles per hour")
    check(!glance.contains("°"), "the glance summary has no degree sign")

    print("ok")
}
