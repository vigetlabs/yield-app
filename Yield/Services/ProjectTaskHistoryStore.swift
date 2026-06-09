import Foundation

/// Infers a per-project "soft favorite" task — the one the user tends to
/// log against a given project lately — so the new-timer form can
/// pre-select it when no explicit (hard) favorite exists for the project.
///
/// Three task-memory systems now coexist, in precedence order:
///   1. `FavoritesStore` — explicit, user-starred (project, task) combos.
///      Hard favorites; always win.
///   2. `ProjectTaskHistoryStore` (this) — implicit, inferred from usage,
///      keyed by project. Soft favorites; fill the gap when no hard
///      favorite is set. Invisible: nothing binds to it; the form reads
///      it imperatively in `selectProject`.
///   3. `MeetingHistoryStore` — implicit, keyed by meeting title; used by
///      the calendar-event pre-fill, a different axis entirely.
///
/// Scoring is recency-weighted frequency via exponential decay: each use
/// adds 1.0 to the task's score, and every score decays with a fixed
/// half-life. This gives the "soft favorite" the right feel — a settled
/// habit (Design logged 20×) isn't dethroned by a single outlier (one
/// stray Admin entry), but the default still migrates when your work on a
/// project genuinely shifts (design wraps, dev begins).
///
/// Not `@Observable` — no view observes it; the form looks it up at the
/// moment a project is picked.
@MainActor
final class ProjectTaskHistoryStore {
    static let shared = ProjectTaskHistoryStore()

    /// Half-life of a single use's contribution. ~3 weeks: recent work
    /// dominates, but the inferred default doesn't whipsaw on one-offs.
    private static let halfLife: TimeInterval = 21 * 24 * 60 * 60

    /// Cap on stored (project, task) rows. Generous — users log to a
    /// bounded set of projects/tasks — but bounds UserDefaults growth.
    /// Lowest-scoring rows are evicted first when exceeded.
    static let maxEntries = 500

    /// A task's decaying usage score, valid as of `asOf`. To compare two
    /// tasks you must first decay both to a common instant (see `decayed`).
    struct Stat {
        var score: Double
        var asOf: Date
    }

    /// projectId → (taskId → score). Internal-settable so tests can seed
    /// and reset; production mutates through `record`.
    var stats: [Int: [Int: Stat]] = [:]

    private let storageKey = DefaultsKey.projectTaskHistory

    /// `loadFromDefaults: false` yields a fresh store with no UserDefaults
    /// round-trip — for tests that want a known-empty starting state.
    init(loadFromDefaults: Bool = true) {
        if loadFromDefaults { load() }
    }

    /// Decay a stored score forward to `now`. Scores only ever decay, so a
    /// past `asOf` shrinks the contribution; a future/equal `now` is a
    /// no-op guard against clock skew.
    private func decayed(_ stat: Stat, to now: Date) -> Double {
        let elapsed = now.timeIntervalSince(stat.asOf)
        guard elapsed > 0 else { return stat.score }
        return stat.score * pow(0.5, elapsed / Self.halfLife)
    }

    /// Record that the user just committed a time entry on (project, task).
    /// Decays the existing score to now, adds 1, and stamps `asOf = now`.
    /// `now` is injectable for deterministic tests.
    func record(projectId: Int, taskId: Int, now: Date = Date()) {
        var taskScores = stats[projectId] ?? [:]
        let current = taskScores[taskId].map { decayed($0, to: now) } ?? 0
        taskScores[taskId] = Stat(score: current + 1, asOf: now)
        stats[projectId] = taskScores
        enforceCap(now: now)
        save()
    }

    /// The soft-favorite task for a project: the highest decayed score, or
    /// nil if the project has no history. Decays every candidate to `now`
    /// first so tasks last used at different times compare fairly.
    func bestTask(forProjectId projectId: Int, now: Date = Date()) -> Int? {
        guard let taskScores = stats[projectId], !taskScores.isEmpty else { return nil }
        return taskScores.max { lhs, rhs in
            decayed(lhs.value, to: now) < decayed(rhs.value, to: now)
        }?.key
    }

    /// Evict the lowest-scoring rows once the total exceeds the cap. Runs
    /// only when over, so the flatten+sort cost is rare.
    private func enforceCap(now: Date) {
        let total = stats.reduce(0) { $0 + $1.value.count }
        guard total > Self.maxEntries else { return }

        var rows: [(projectId: Int, taskId: Int, score: Double)] = []
        for (projectId, tasks) in stats {
            for (taskId, stat) in tasks {
                rows.append((projectId, taskId, decayed(stat, to: now)))
            }
        }
        rows.sort { $0.score < $1.score }
        for row in rows.prefix(total - Self.maxEntries) {
            stats[row.projectId]?.removeValue(forKey: row.taskId)
            if stats[row.projectId]?.isEmpty == true {
                stats.removeValue(forKey: row.projectId)
            }
        }
    }

    // MARK: - Persistence

    /// Flat, Codable row — the nested dictionary is encoded as an array so
    /// the on-disk shape stays simple and migration-friendly.
    private struct PersistedStat: Codable {
        let projectId: Int
        let taskId: Int
        let score: Double
        let asOf: Date
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PersistedStat].self, from: data)
        else { return }

        var rebuilt: [Int: [Int: Stat]] = [:]
        for row in decoded {
            rebuilt[row.projectId, default: [:]][row.taskId] = Stat(score: row.score, asOf: row.asOf)
        }
        stats = rebuilt
    }

    private func save() {
        let persisted = stats.flatMap { projectId, tasks in
            tasks.map { taskId, stat in
                PersistedStat(projectId: projectId, taskId: taskId, score: stat.score, asOf: stat.asOf)
            }
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
