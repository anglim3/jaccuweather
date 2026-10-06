import Foundation

@main
struct WatchAQICheck {
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
    let good = WatchAQI.chip(usAqi: 42)
    check(good?.text == "AQI 42", "42 displays as AQI 42")
    check(good?.shortWord == "Good", "42 is Good")
    check(good?.category == "Good", "the full category is Good")
    check(good?.colorToken == "green", "Good uses the green token")
    check(good?.spoken == "Air Quality 42, Good", "voiceover matches the iphone air-quality card")
    check(good?.value == 42, "the chip keeps the rounded value")

    check(WatchAQI.chip(usAqi: 41.6)?.text == "AQI 42", "41.6 rounds like the iphone card")
    check(WatchAQI.chip(usAqi: 41.6)?.category == "Good", "the band uses the rounded integer")
    check(WatchAQI.chip(usAqi: 0)?.text == "AQI 0", "a zero reading still shows")
    check(WatchAQI.chip(usAqi: 0)?.shortWord == "Good", "zero is Good")
    check(WatchAQI.chip(usAqi: 50)?.category == "Good", "50 is Good")
    check(WatchAQI.chip(usAqi: 50.4)?.value == 50, "50.4 stays Good")
    check(WatchAQI.chip(usAqi: 50.5)?.value == 51, "50.5 rounds to 51")
    check(WatchAQI.chip(usAqi: 50.5)?.category == "Moderate", "51 is Moderate")
    check(WatchAQI.chip(usAqi: 50.5)?.colorToken == "yellow", "Moderate is yellow")
    check(WatchAQI.chip(usAqi: 100)?.category == "Moderate", "100 is Moderate")
    check(WatchAQI.chip(usAqi: 100.5)?.spoken == "Air Quality 101, Unhealthy for Sensitive Groups", "101 speaks the full sensitive-groups category")
    check(WatchAQI.chip(usAqi: 101)?.shortWord == "Sensitive", "the glance shortens the sensitive-groups band")
    check(WatchAQI.chip(usAqi: 101)?.colorToken == "orange", "sensitive groups is orange")
    check(WatchAQI.chip(usAqi: 150)?.shortWord == "Sensitive", "150 stays in the sensitive band")
    check(WatchAQI.chip(usAqi: 151)?.category == "Unhealthy", "151 is Unhealthy")
    check(WatchAQI.chip(usAqi: 151)?.colorToken == "red", "Unhealthy is red")
    check(WatchAQI.chip(usAqi: 200)?.category == "Unhealthy", "200 is Unhealthy")
    check(WatchAQI.chip(usAqi: 201)?.category == "Very Unhealthy", "201 is Very Unhealthy")
    check(WatchAQI.chip(usAqi: 201)?.colorToken == "purple", "Very Unhealthy is purple")
    check(WatchAQI.chip(usAqi: 300)?.category == "Very Unhealthy", "300 is Very Unhealthy")
    check(WatchAQI.chip(usAqi: 301)?.category == "Hazardous", "301 is Hazardous")
    check(WatchAQI.chip(usAqi: 301)?.shortWord == "Hazardous", "Hazardous stays the short word")
    check(WatchAQI.chip(usAqi: 301)?.colorToken == "maroon", "Hazardous is maroon")
    check(WatchAQI.chip(usAqi: 500)?.spoken == "Air Quality 500, Hazardous", "a high reading stays Hazardous")

    let supplied = WatchAQI.chip(usAqi: 42, category: "Good")
    check(supplied?.spoken == "Air Quality 42, Good", "a matching phone category stays on the chip")
    check(supplied?.shortWord == "Good", "a matching phone category keeps the short word")
    let lowercase = WatchAQI.chip(usAqi: 64, category: "moderate")
    check(lowercase?.category == "Moderate", "category spelling follows the band")
    check(lowercase?.colorToken == "yellow", "a matching category keeps the band color")
    let mismatch = WatchAQI.chip(usAqi: 42, category: "Hazardous")
    check(mismatch?.category == "Good", "a category for another band does not relabel the number")
    check(mismatch?.colorToken == "green", "the color follows the number")
    check(mismatch?.spoken == "Air Quality 42, Good", "voiceover follows the number when the category disagrees")

    check(WatchAQI.chip(usAqi: nil) == nil, "a missing reading stays hidden")
    check(WatchAQI.chip(usAqi: nil, category: "Good") == nil, "a category without a number stays hidden")
    check(WatchAQI.chip(usAqi: -1) == nil, "a negative reading stays hidden")
    check(WatchAQI.chip(usAqi: .nan) == nil, "nan stays hidden")
    check(WatchAQI.chip(usAqi: .infinity) == nil, "infinity stays hidden")
    check(WatchAQI.chip(usAqi: -.infinity, category: "Good") == nil, "a non-finite reading stays hidden")

    print("ok")
}
