import Foundation
import Observation

@Observable
final class FavoritesStore {
    private let key = "weatherFavorites"
    private let defaults: UserDefaults
    private(set) var items: [GeoResult] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([GeoResult].self, from: data)
        else {
            items = []
            return
        }
        let cleaned = Self.withoutDuplicatePlaces(decoded)
        items = cleaned
        if cleaned.count != decoded.count {
            persist()
        }
    }

    func contains(_ place: GeoResult) -> Bool {
        items.contains { $0.samePlace(as: place) }
    }

    func remove(_ place: GeoResult) {
        items.removeAll { $0.samePlace(as: place) }
        persist()
    }

    /// Saves the list order from a location-sheet drag.
    /// Offsets match SwiftUI `onMove`: `destination` is an index in the list before the removal.
    func move(from source: IndexSet, to destination: Int) {
        guard items.count > 1, source.isEmpty == false else { return }
        guard destination >= 0, destination <= items.count else { return }
        guard source.allSatisfy({ items.indices.contains($0) }) else { return }
        let original = items
        let moving = source.sorted().map { items[$0] }
        var insertion = destination
        for index in source.sorted(by: >) {
            if index < destination { insertion -= 1 }
            items.remove(at: index)
        }
        items.insert(contentsOf: moving, at: insertion)
        guard items != original else { return }
        persist()
    }

    func toggle(_ place: GeoResult) {
        if let idx = items.firstIndex(where: { $0.samePlace(as: place) }) {
            items.remove(at: idx)
        } else {
            items.insert(place, at: 0)
        }
        persist()
    }

    /// One row per coordinate. A reverse geocode can store the same fix under a new name.
    static func withoutDuplicatePlaces(_ places: [GeoResult]) -> [GeoResult] {
        var seen = Set<String>()
        return places.filter { seen.insert($0.id).inserted }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
