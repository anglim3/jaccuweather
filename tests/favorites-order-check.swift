import Foundation

@main
struct FavoritesOrderCheck {
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

func place(_ name: String, _ latitude: Double, _ longitude: Double) -> GeoResult {
    GeoResult(name: name, latitude: latitude, longitude: longitude, admin1: nil, country: nil)
}

func names(_ items: [GeoResult]) -> [String] {
    items.map(\.name)
}

func run() {
    let suite = "jaccuweather.favorites-order-check"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fputs("FAIL defaults suite\n", stderr)
        exit(1)
    }
    defaults.removePersistentDomain(forName: suite)

    let seattle = place("Seattle", 47.6062, -122.3321)
    let portland = place("Portland", 45.5152, -122.6784)
    let denver = place("Denver", 39.7392, -104.9903)

    let store = FavoritesStore(defaults: defaults)
    check(store.items.isEmpty, "fresh store is empty")
    store.move(from: IndexSet(integer: 0), to: 0)
    check(store.items.isEmpty, "move on an empty list stays empty")

    store.toggle(seattle)
    check(names(store.items) == ["Seattle"], "first favorite is stored")
    store.move(from: IndexSet(integer: 0), to: 1)
    check(names(store.items) == ["Seattle"], "one favorite cannot be reordered")

    store.toggle(portland)
    store.toggle(denver)
    check(names(store.items) == ["Denver", "Portland", "Seattle"], "new favorites insert at the front")

    store.move(from: IndexSet(integer: 2), to: 0)
    check(names(store.items) == ["Seattle", "Denver", "Portland"], "last favorite moves to the front, got \(names(store.items))")

    store.move(from: IndexSet(integer: 0), to: 3)
    check(names(store.items) == ["Denver", "Portland", "Seattle"], "first favorite moves to the end, got \(names(store.items))")

    store.move(from: IndexSet(integer: 0), to: 2)
    check(names(store.items) == ["Portland", "Denver", "Seattle"], "dragging the first row down one place matches onMove, got \(names(store.items))")

    store.move(from: IndexSet(integer: 1), to: 1)
    check(names(store.items) == ["Portland", "Denver", "Seattle"], "move onto the same slot keeps the order")

    store.move(from: IndexSet(), to: 0)
    store.move(from: IndexSet(integer: 0), to: -1)
    store.move(from: IndexSet(integer: 9), to: 0)
    check(names(store.items) == ["Portland", "Denver", "Seattle"], "invalid moves leave the list alone")

    let reloaded = FavoritesStore(defaults: defaults)
    check(names(reloaded.items) == ["Portland", "Denver", "Seattle"], "reopen keeps the saved order, got \(names(reloaded.items))")

    reloaded.remove(portland)
    check(names(reloaded.items) == ["Denver", "Seattle"], "remove keeps the remaining order")
    let afterRemove = FavoritesStore(defaults: defaults)
    check(names(afterRemove.items) == ["Denver", "Seattle"], "removed favorite stays gone after reopen")

    afterRemove.toggle(portland)
    check(names(afterRemove.items) == ["Portland", "Denver", "Seattle"], "adding a favorite still inserts at the front")

    defaults.removePersistentDomain(forName: suite)
    print("ok")
}
