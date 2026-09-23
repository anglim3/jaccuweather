import Foundation
import Observation

@Observable
final class FavoritesStore {
    private let key = "weatherFavorites"
    private(set) var items: [GeoResult] = []

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([GeoResult].self, from: data)
        else {
            items = []
            return
        }
        items = decoded
    }

    func contains(_ place: GeoResult) -> Bool {
        items.contains(place)
    }

    func toggle(_ place: GeoResult) {
        if let idx = items.firstIndex(of: place) {
            items.remove(at: idx)
        } else {
            items.insert(place, at: 0)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
