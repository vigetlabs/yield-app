import Foundation
import Observation

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
@Observable
@MainActor
final class MeetingHistoryStore {
    static let shared = MeetingHistoryStore()

    /// One memory: which (project, task) the user last paired with a
    /// given normalized title, plus when. `lastUsedAt` is bumped on
    /// every save and drives LRU eviction when the cap is hit.
    struct Memory: Codable, Hashable {
        /// Lowercased + whitespace-trimmed event title / notes text.
        /// Stored normalized so lookup is case- and whitespace-
        /// insensitive without re-normalizing on every read.
        let normalizedTitle: String
        let projectId: Int
        let taskId: Int
        var lastUsedAt: Date

        // Identity is the title only — `record(notes:)` should
        // overwrite an existing memory for the same title rather
        // than accumulating duplicates.
        static func == (lhs: Memory, rhs: Memory) -> Bool {
            lhs.normalizedTitle == rhs.normalizedTitle
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(normalizedTitle)
        }
    }

    /// Hard cap on stored memories. ~200 covers years of distinct
    /// meeting titles for a typical user; well under any UserDefaults
    /// payload concern.
    static let maxEntries = 200

    /// Internal-settable so tests can seed and reset state.
    /// Production callers should mutate through `record(...)`.
    var memories: Set<Memory> = []

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
        guard !key.isEmpty else { return nil }
        let probe = Memory(normalizedTitle: key, projectId: 0, taskId: 0, lastUsedAt: .distantPast)
        guard let memory = memories.first(where: { $0 == probe }) else { return nil }
        return (memory.projectId, memory.taskId)
    }

    /// Record that the user just submitted a time entry with the
    /// given notes against a (project, task) pair. Overwrites any
    /// previous memory for the same title and bumps `lastUsedAt`.
    /// No-op for empty/whitespace-only titles.
    func record(notes: String, projectId: Int, taskId: Int) {
        let key = Self.normalize(notes)
        guard !key.isEmpty else { return }

        let probe = Memory(normalizedTitle: key, projectId: 0, taskId: 0, lastUsedAt: .distantPast)
        memories.remove(probe)  // no-op if absent
        memories.insert(Memory(
            normalizedTitle: key,
            projectId: projectId,
            taskId: taskId,
            lastUsedAt: Date()
        ))

        // LRU eviction. Sorted by lastUsedAt ascending → drop the
        // oldest until we're under the cap.
        if memories.count > Self.maxEntries {
            let sorted = memories.sorted { $0.lastUsedAt < $1.lastUsedAt }
            let toDrop = sorted.prefix(memories.count - Self.maxEntries)
            for old in toDrop { memories.remove(old) }
        }

        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Memory].self, from: data)
        else { return }
        memories = Set(decoded)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(memories)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
