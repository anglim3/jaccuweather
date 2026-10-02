import Foundation

@main
struct PlaceNameCheck {
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
    let blankCity = BigDataCloudReverse(
        city: "",
        locality: "McMurdo Sound",
        town: nil,
        village: nil,
        municipality: nil,
        county: nil,
        principalSubdivision: "",
        countryName: "Antarctica"
    )
    check(blankCity.placeName() == "McMurdo Sound, Antarctica", "a blank city uses the locality, got \(blankCity.placeName() ?? "nil")")

    let ocean = BigDataCloudReverse(
        city: "",
        locality: "Monumento Natural do Arquipelago de Sao Pedro e Sao Paulo",
        town: nil,
        village: nil,
        municipality: nil,
        county: nil,
        principalSubdivision: "",
        countryName: ""
    )
    check(
        ocean.placeName() == "Monumento Natural do Arquipelago de Sao Pedro e Sao Paulo",
        "a blank city and country keep the locality"
    )

    let seattle = BigDataCloudReverse(
        city: "Seattle",
        locality: "Seattle",
        town: nil,
        village: nil,
        municipality: nil,
        county: nil,
        principalSubdivision: "Washington",
        countryName: "United States of America"
    )
    check(seattle.placeName() == "Seattle, Washington", "US places keep the state")

    let amsterdam = BigDataCloudReverse(
        city: "Amsterdam",
        locality: "Centrum",
        town: nil,
        village: nil,
        municipality: nil,
        county: nil,
        principalSubdivision: "Noord-Holland",
        countryName: "Netherlands (the)"
    )
    check(amsterdam.placeName() == "Amsterdam, Netherlands", "a trailing (the) is not part of the country")

    let empty = BigDataCloudReverse(
        city: " ",
        locality: nil,
        town: nil,
        village: nil,
        municipality: nil,
        county: nil,
        principalSubdivision: "",
        countryName: nil
    )
    check(empty.placeName() == nil, "a payload with no locality does not invent a name")
    check(PlaceName.isUsable(", Antarctica") == false, "a comma-led label is not a usable place")
    check(PlaceName.isUsable("Current location"), "the generic stand-in can stay on screen")
    check(PlaceName.isUsable("McMurdo Sound, Antarctica"), "a locality plus country is usable")

    let paris = GeoResult(name: "Paris", latitude: 48.85341, longitude: 2.3488, admin1: "Île-de-France Region", country: "France")
    check(paris.displayName == "Paris, France", "a selected place outside the US uses the country")
    check(paris.subtitle == "Île-de-France Region, France", "the search subtitle does not repeat the city, got \(paris.subtitle)")

    let parisTexas = GeoResult(name: "Paris", latitude: 33.66094, longitude: -95.55551, admin1: "Texas", country: "United States")
    check(parisTexas.displayName == "Paris, Texas", "a US place keeps the state in the title")
    check(parisTexas.subtitle == "Texas, United States", "the search subtitle lists the state and country")

    let sameFix = GeoResult(name: "Current location", latitude: -77.8, longitude: 166.6, admin1: nil, country: nil)
    let renamed = GeoResult(name: "McMurdo Sound, Antarctica", latitude: -77.8, longitude: 166.6, admin1: nil, country: nil)
    check(sameFix.samePlace(as: renamed), "the same coordinates are one place after the name changes")
    check(sameFix != renamed, "different names are not the same value")

    check(CitySearch.shouldSearch(" a") == false, "spaces do not count toward the search minimum")
    check(CitySearch.shouldSearch("Se"), "two letters start a search")
    check(CitySearch.matchesRequest(generation: 2, currentGeneration: 3) == false, "an older response is dropped")
    check(CitySearch.matchesRequest(generation: 3, currentGeneration: 3), "the latest response is kept")

    let duplicated = CitySearch.uniquePlaces([paris, paris, parisTexas])
    check(duplicated.count == 2, "identical coordinates collapse to one result")

    let stale = CitySearch.Outcome.resolve(generation: 1, currentGeneration: 2, query: "Paris", results: [paris], failed: false)
    check(stale == .ignore, "a late response for an older query is ignored")
    let failed = CitySearch.Outcome.resolve(generation: 4, currentGeneration: 4, query: "Paris", results: nil, failed: true)
    check(failed == .failed, "a failed lookup is not an empty result list")
    let none = CitySearch.Outcome.resolve(generation: 4, currentGeneration: 4, query: "Paris", results: [], failed: false)
    check(none == .results([]), "a successful lookup with no rows is empty")
    let cleared = CitySearch.Outcome.resolve(generation: 5, currentGeneration: 5, query: " ", results: [paris], failed: false)
    check(cleared == .empty, "a cleared query drops whatever the request returned")

    print("ok")
}
