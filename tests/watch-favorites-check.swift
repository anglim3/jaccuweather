import Foundation

@main
struct WatchFavoritesCheck {
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

func input(_ name: String, _ latitude: Double, _ longitude: Double) -> WatchFavoritesPlan.Input {
    WatchFavoritesPlan.Input(name: name, latitude: latitude, longitude: longitude)
}

func place(_ name: String, _ latitude: Double, _ longitude: Double) -> WatchFavoritePlace {
    WatchFavoritePlace(name: name, latitude: latitude, longitude: longitude)
}

func choice(_ name: String, _ latitude: Double, _ longitude: Double, reading: Bool) -> WatchPlaceChoice {
    WatchPlaceChoice(
        locationId: String(format: "%.4f,%.4f", latitude, longitude),
        locationName: name,
        latitude: latitude,
        longitude: longitude,
        hasReading: reading
    )
}

func run() {
    let portland = GeoResult(name: "Portland", latitude: 45.5152, longitude: -122.6784, admin1: "Oregon", country: "United States")
    check(
        WatchFavoritesPlan.coordinateID(latitude: portland.latitude, longitude: portland.longitude) == portland.id,
        "favorite coordinates use the same id as the iPhone list"
    )

    let duplicated = WatchFavoritesPlan.compact([
        input("Current location", -77.8, 166.6),
        input("McMurdo Sound, Antarctica", -77.8, 166.6),
        input("Portland", 45.5152, -122.6784)
    ])
    check(duplicated.map(\.name) == ["Current location", "Portland"], "duplicate coordinates keep the first name, got \(duplicated.map(\.name))")

    let cleaned = WatchFavoritesPlan.compact([
        input("  ", 1, 2),
        input(", Antarctica", 10, 20),
        input("Denver", 91, -104),
        input("Denver", 39.7392, -181),
        input("Denver", .nan, -104),
        input("Denver", 39.7392, -104.9903)
    ])
    check(cleaned.map(\.name) == ["Denver"], "blank names and bad coordinates are left out, got \(cleaned.map(\.name))")

    let long = String(repeating: "A", count: 60)
    let clipped = WatchFavoritesPlan.compact([input(long, 40, -70)])
    check(clipped.first?.name.count == WatchFavoritesPlan.maxNameLength, "names stop at the length cap")

    var many: [WatchFavoritesPlan.Input] = []
    for index in 0..<14 {
        many.append(input("City \(index)", Double(index), Double(index) + 0.5))
    }
    many.insert(input("City 0", 0, 0.5), at: 3)
    let capped = WatchFavoritesPlan.compact(many)
    check(capped.count == WatchFavoritesPlan.cap, "the payload stops at \(WatchFavoritesPlan.cap) rows, got \(capped.count)")
    check(capped.first?.name == "City 0" && capped.last?.name == "City 11", "the cap keeps the earliest unique rows, got \(capped.map(\.name))")
    check(WatchFavoritesPlan.compact(many, limit: 0).isEmpty, "a zero cap sends nothing")

    let fields = WatchFavoritesPlan.fields(capped)
    check(fields.count == 1 && fields[WatchFavoritesPlan.contextKey] is String, "favorites is one JSON string")
    let roundTrip = WatchFavoritesPlan.places(from: fields)
    check(roundTrip == capped, "the JSON array round-trips name, latitude, and longitude")
    if let json = fields[WatchFavoritesPlan.contextKey] as? String,
       let data = json.data(using: .utf8),
       let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
       let first = raw.first {
        let keys = Set(first.keys)
        check(keys == ["name", "latitude", "longitude"], "each row is name, latitude, and longitude, got \(keys)")
    } else {
        check(false, "favorites JSON is an array of objects")
    }

    check(WatchFavoritesPlan.places(from: [:]).isEmpty, "a missing favorites field stays empty")
    check(WatchFavoritesPlan.places(from: [WatchFavoritesPlan.contextKey: "[]"]).isEmpty, "an empty array clears the list")
    check(WatchFavoritesPlan.places(from: [WatchFavoritesPlan.contextKey: "not-json"]).isEmpty, "malformed favorites stay empty")
    check(WatchFavoritesPlan.places(from: [WatchFavoritesPlan.contextKey: 3]).isEmpty, "a non-string favorites field stays empty")
    let hostile = WatchFavoritesPlan.places(from: [
        WatchFavoritesPlan.contextKey: #"[{"name":"","latitude":1,"longitude":2},{"name":"Paris","latitude":48.8,"longitude":2.3},{"name":"Paris again","latitude":48.8,"longitude":2.3}]"#
    ])
    check(hostile.map(\.name) == ["Paris"], "a decoded payload is deduped again, got \(hostile.map(\.name))")

    let rows = WatchFavoritesPlan.switcher(
        current: place("McMurdo Sound", -77.8, 166.6),
        favorites: [
            place("Current location", -77.8, 166.6),
            place("Portland", 45.5152, -122.6784),
            place("Denver", 39.7392, -104.9903)
        ]
    )
    check(rows.map(\.name) == ["McMurdo Sound", "Portland", "Denver"], "the current place leads and is not listed twice, got \(rows.map(\.name))")
    check(
        WatchFavoritesPlan.switcher(current: place("  ", 47.6, -122.3), favorites: []).first?.name == "Place",
        "a blank current name still has a row"
    )

    let phone = choice("Seattle", 47.6062, -122.3321, reading: true)
    let picked = choice("Portland", 45.5152, -122.6784, reading: false)
    let explicitChoice = WatchPlacePlan.choose(pinned: nil, phone: phone, saved: phone, shared: picked, sharedExplicit: true)
    check(explicitChoice.locationName == "Portland", "a saved selection stays ahead of the phone")
    let follow = WatchPlacePlan.choose(pinned: nil, phone: phone, saved: nil, shared: picked, sharedExplicit: false)
    check(follow.locationName == "Seattle", "without a selection the phone place still wins")
    check(
        WatchConditionsSource.pick(phoneMatchesAndFresh: true, savedMatchesAndFresh: true) == .phone,
        "a fresh phone reading for the chosen place wins"
    )
    check(
        WatchConditionsSource.pick(phoneMatchesAndFresh: false, savedMatchesAndFresh: true) == .saved,
        "a fresh saved reading is next"
    )
    check(
        WatchConditionsSource.pick(phoneMatchesAndFresh: false, savedMatchesAndFresh: false) == .fetch,
        "otherwise the watch fetches"
    )

    let old = #"{"locationId":"45.5152,-122.6784","locationName":"Portland","latitude":45.5152,"longitude":-122.6784}"#
    let decoded = try! JSONDecoder().decode(WatchPlace.self, from: Data(old.utf8))
    check(decoded.explicit == false, "an older place file still follows the phone")
    check(decoded.locationName == "Portland", "the older place name still decodes")
    var selected = decoded
    selected.explicit = true
    let encoded = try! JSONEncoder().encode(selected)
    let again = try! JSONDecoder().decode(WatchPlace.self, from: encoded)
    check(again == selected, "an explicit pick round-trips through watch-place.json")

    print("ok")
}
