import Foundation
import Observation

/// Persists user-favorited project/task combos to UserDefaults. Anywhere
/// that wants to query or toggle favorites reads through the shared
/// instance. The set is kept in memory and mirrored to UserDefaults on
/// every mutation so launches see the persisted state.
@Observable
@MainActor
final class FavoritesStore {
    static let shared = FavoritesStore()

    /// A favorited project + task pair. Same primary key shape Harvest
    /// uses for time entries — selecting a favorite is identical to
    /// picking the same project + task in the new-timer form.
    struct Favorite: Codable, Hashable {
        let projectId: Int
        let taskId: Int
    }

    private(set) var favorites: Set<Favorite> = []

    private let storageKey = "favorites"

    init() {
        load()
    }

    func isFavorite(projectId: Int, taskId: Int) -> Bool {
        favorites.contains(Favorite(projectId: projectId, taskId: taskId))
    }

    /// Add the pair to favorites if absent, remove it if present.
    func toggle(projectId: Int, taskId: Int) {
        let fav = Favorite(projectId: projectId, taskId: taskId)
        if favorites.contains(fav) {
            favorites.remove(fav)
        } else {
            favorites.insert(fav)
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Favorite].self, from: data)
        else { return }
        favorites = Set(decoded)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(favorites)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
