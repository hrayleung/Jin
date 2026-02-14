import Foundation
import SwiftUI

struct FavoriteModelKey: Codable, Hashable {
    let providerID: String
    let modelID: String
}

@MainActor
final class FavoriteModelsStore: ObservableObject {
    static let shared = FavoriteModelsStore()

    @Published private(set) var favorites: Set<FavoriteModelKey> = []

    private let storageKey = "favoriteModels.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isFavorite(providerID: String, modelID: String) -> Bool {
        favorites.contains(FavoriteModelKey(providerID: providerID, modelID: modelID))
    }

    func toggle(providerID: String, modelID: String) {
        let key = FavoriteModelKey(providerID: providerID, modelID: modelID)
        if favorites.contains(key) {
            favorites.remove(key)
        } else {
            favorites.insert(key)
        }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([FavoriteModelKey].self, from: data) else { return }
        favorites = Set(decoded)
    }

    private func persist() {
        // Store as an array for stable Codable encoding.
        let sorted = favorites.sorted { lhs, rhs in
            if lhs.providerID != rhs.providerID { return lhs.providerID < rhs.providerID }
            return lhs.modelID < rhs.modelID
        }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
