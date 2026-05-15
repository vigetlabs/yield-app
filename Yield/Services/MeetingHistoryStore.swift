import Foundation

/// Remembers which (project, task) pair the user last picked when
/// logging a time entry against a given notes string. Powers the
/// pre-fill behavior in the calendar-event picker: when the user
/// pulls in a meeting whose title they've tracked time against
/// before, the form's project + task are auto-selected to whatever
/// they used last.
///
/// This is distinct from `FavoritesStore`:
/// - Favorites are explicit (the user stars a (project, task) combo)
///   and global.
/// - Meeting history is implicit (every save is recorded) and keyed
///   by the notes/title text. It's a "you usually log this kind of
///   work against this project" memory rather than a single default.
///
/// Capped at `maxEntries` with LRU eviction so a year of distinct
/// meeting titles can't grow UserDefaults unbounded.
///
/// Not `@Observable` — no view binds to the store directly. The
/// pre-fill consumer (`NewTimerFormView.applyCalendarEvent`) reads
/// imperatively at the moment of selection.
@MainActor
final class MeetingHistoryStore {
    static let shared = MeetingHistoryStore()

    /// One memory: which (project, task) the user last paired with a
    /// given title, plus when. Stored in `memories` keyed by the
    /// normalized title — so the title isn't carried on the value.
    /// `lastUsedAt` is bumped on every save and drives LRU eviction
    /// when the cap is hit.
    struct Memory: Codable {
        let projectId: Int
        let taskId: Int
        var lastUsedAt: Date
    }

    /// Hard cap on stored memories. ~200 covers years of distinct
    /// meeting titles for a typical user; well under any UserDefaults
    /// payload concern.
    static let maxEntries = 200

    /// Internal-settable so tests can seed and reset state.
    /// Production callers should mutate through `record(...)`.
    /// Keyed by the normalized title — O(1) lookup, no fragile
    /// custom-equality dance on the value.
    var memories: [String: Memory] = [:]

    private let storageKey = DefaultsKey.meetingHistory

    /// `loadFromDefaults: false` produces a fresh store with no
    /// UserDefaults round-trip — used by tests to start from a known
    /// empty state without touching the user's real history.
    init(loadFromDefaults: Bool = true) {
        if loadFromDefaults { load() }
    }

    /// Lowercase + trim a raw title for storage and lookup. Skipping
    /// punctuation/diacritics intentionally — too aggressive a
    /// normalization makes wrong matches more likely (e.g.
    /// "Standup" vs "Stand-up" probably *should* be different
    /// memories until proven otherwise).
    static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Look up the (projectId, taskId) the user last paired with a
    /// given title. Returns nil for empty titles or unseen ones.
    func lookup(title: String) -> (projectId: Int, taskId: Int)? {
        let key = Self.normalize(title)
        guard !key.isEmpty, let memory = memories[key] else { return nil }
        return (memory.projectId, memory.taskId)
    }

    /// Record that the user just submitted a time entry with the
    /// given notes against a (project, task) pair. Overwrites any
    /// previous memory for the same title and bumps `lastUsedAt`.
    /// No-op for empty/whitespace-only titles.
    func record(notes: String, projectId: Int, taskId: Int) {
        let key = Self.normalize(notes)
        guard !key.isEmpty else { return }

        memories[key] = Memory(
            projectId: projectId,
            taskId: taskId,
            lastUsedAt: Date()
        )

        // LRU eviction. Sort the (key, value) pairs by lastUsedAt
        // ascending and drop the oldest until we're under the cap.
        // Only runs when over cap so the sort cost is rare.
        if memories.count > Self.maxEntries {
            let sortedKeys = memories
                .sorted { $0.value.lastUsedAt < $1.value.lastUsedAt }
                .map(\.key)
            let dropCount = memories.count - Self.maxEntries
            for key in sortedKeys.prefix(dropCount) {
                memories.removeValue(forKey: key)
            }
        }

        save()
    }

    // MARK: - Persistence

    /// Persisted shape — paired with a title so we can encode/decode
    /// the dictionary as a flat array. Kept separate from the in-
    /// memory `Memory` so the runtime type stays minimal.
    private struct PersistedMemory: Codable {
        let normalizedTitle: String
        let projectId: Int
        let taskId: Int
        var lastUsedAt: Date
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()

        // Try the current persisted shape first.
        if let decoded = try? decoder.decode([PersistedMemory].self, from: data) {
            memories = Dictionary(
                uniqueKeysWithValues: decoded.map { entry in
                    (entry.normalizedTitle, Memory(
                        projectId: entry.projectId,
                        taskId: entry.taskId,
                        lastUsedAt: entry.lastUsedAt
                    ))
                }
            )
            return
        }

        // Old shape (pre-dictionary refactor) had `Memory` carry the
        // title field directly. Decode it tolerantly so existing
        // installs don't lose their history on upgrade.
        struct LegacyMemory: Codable {
            let normalizedTitle: String
            let projectId: Int
            let taskId: Int
            var lastUsedAt: Date
        }
        if let legacy = try? decoder.decode([LegacyMemory].self, from: data) {
            memories = Dictionary(
                uniqueKeysWithValues: legacy.map { entry in
                    (entry.normalizedTitle, Memory(
                        projectId: entry.projectId,
                        taskId: entry.taskId,
                        lastUsedAt: entry.lastUsedAt
                    ))
                }
            )
            // Re-save in the new shape so subsequent loads take the fast path.
            save()
        }
    }

    private func save() {
        let persisted = memories.map { key, value in
            PersistedMemory(
                normalizedTitle: key,
                projectId: value.projectId,
                taskId: value.taskId,
                lastUsedAt: value.lastUsedAt
            )
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
