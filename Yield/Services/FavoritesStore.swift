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

    /// A favorited project + task pair. `lastUsedAt` is bumped whenever
    /// the user toggles the favorite on or commits a timer with this
    /// pair, so `mostRecentlyUsedFavorite(forProjectId:)` can pick the
    /// best default when a project has multiple favorites. Identity is
    /// the (projectId, taskId) pair only — `lastUsedAt` is excluded
    /// from `Hashable` so updating the timestamp doesn't create a
    /// duplicate Set entry.
    struct Favorite: Codable, Hashable {
        let projectId: Int
        let taskId: Int
        var lastUsedAt: Date

        static func == (lhs: Favorite, rhs: Favorite) -> Bool {
            lhs.projectId == rhs.projectId && lhs.taskId == rhs.taskId
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(projectId)
            hasher.combine(taskId)
        }

        // Custom decoder so favorites stored before `lastUsedAt`
        // existed still load — they default to "now", which treats
        // them as most-recent until something newer is used.
        private enum CodingKeys: String, CodingKey {
            case projectId, taskId, lastUsedAt
        }

        init(projectId: Int, taskId: Int, lastUsedAt: Date) {
            self.projectId = projectId
            self.taskId = taskId
            self.lastUsedAt = lastUsedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.projectId = try container.decode(Int.self, forKey: .projectId)
            self.taskId = try container.decode(Int.self, forKey: .taskId)
            self.lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()
        }
    }

    private(set) var favorites: Set<Favorite> = []

    private let storageKey = "favorites"

    init() {
        load()
    }

    func isFavorite(projectId: Int, taskId: Int) -> Bool {
        favorites.contains(Favorite(projectId: projectId, taskId: taskId, lastUsedAt: .distantPast))
    }

    /// Add the pair to favorites if absent (with `lastUsedAt = now`),
    /// remove it if present. Toggling on counts as a use.
    func toggle(projectId: Int, taskId: Int) {
        let probe = Favorite(projectId: projectId, taskId: taskId, lastUsedAt: .distantPast)
        if favorites.contains(probe) {
            favorites.remove(probe)
        } else {
            favorites.insert(Favorite(projectId: projectId, taskId: taskId, lastUsedAt: Date()))
        }
        save()
    }

    /// Remove a favorite without considering its current state. Called
    /// from the Settings list's per-row remove button.
    func remove(projectId: Int, taskId: Int) {
        favorites.remove(Favorite(projectId: projectId, taskId: taskId, lastUsedAt: .distantPast))
        save()
    }

    /// Bump `lastUsedAt` to now for the matching favorite (if one
    /// exists). No-op when the pair isn't a favorite. Called when the
    /// user commits a timer with this combo so the auto-select picks
    /// the right one next time.
    func markUsed(projectId: Int, taskId: Int) {
        let probe = Favorite(projectId: projectId, taskId: taskId, lastUsedAt: .distantPast)
        guard favorites.contains(probe) else { return }
        favorites.remove(probe)
        favorites.insert(Favorite(projectId: projectId, taskId: taskId, lastUsedAt: Date()))
        save()
    }

    /// Most-recently-used favorite for a given project, or nil if the
    /// project has no favorites. Powers the auto-select behavior when
    /// the user picks a project in the new-timer form.
    func mostRecentlyUsedFavorite(forProjectId projectId: Int) -> Favorite? {
        favorites
            .filter { $0.projectId == projectId }
            .max(by: { $0.lastUsedAt < $1.lastUsedAt })
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
