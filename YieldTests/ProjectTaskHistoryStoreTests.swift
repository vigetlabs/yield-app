import XCTest
@testable import Yield

/// Covers `ProjectTaskHistoryStore`'s inference contract: recording,
/// best-task lookup, the recency-weighted-frequency scoring (a settled
/// habit resists a single outlier but yields to sustained change), and
/// cap eviction. Dates are injected via the `now:` parameters so the
/// decay math is deterministic. Storage round-trips aren't tested (the
/// load/save are trivial pass-throughs).
@MainActor
final class ProjectTaskHistoryStoreTests: XCTestCase {

    private var store: ProjectTaskHistoryStore!

    /// A fixed reference instant; tests offset from it so decay is
    /// deterministic regardless of wall-clock.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUp() async throws {
        try await super.setUp()
        store = ProjectTaskHistoryStore(loadFromDefaults: false)
    }

    // MARK: - Basic record / lookup

    func test_bestTask_nilWhenNoHistory() {
        XCTAssertNil(store.bestTask(forProjectId: 1, now: t0))
    }

    func test_bestTask_returnsOnlyRecordedTask() {
        store.record(projectId: 1, taskId: 10, now: t0)
        XCTAssertEqual(store.bestTask(forProjectId: 1, now: t0), 10)
    }

    func test_history_isScopedPerProject() {
        store.record(projectId: 1, taskId: 10, now: t0)
        store.record(projectId: 2, taskId: 20, now: t0)
        XCTAssertEqual(store.bestTask(forProjectId: 1, now: t0), 10)
        XCTAssertEqual(store.bestTask(forProjectId: 2, now: t0), 20)
        XCTAssertNil(store.bestTask(forProjectId: 3, now: t0))
    }

    // MARK: - Recency-weighted frequency

    func test_frequentTask_beatsSingleOutlier() {
        // Design logged many times, then one stray Admin entry — all on
        // the same day, so this is the pure-frequency case.
        for _ in 0..<20 {
            store.record(projectId: 1, taskId: /*Design*/ 10, now: t0)
        }
        store.record(projectId: 1, taskId: /*Admin*/ 99, now: t0)
        XCTAssertEqual(
            store.bestTask(forProjectId: 1, now: t0), 10,
            "A single outlier must not dethrone a well-established habit"
        )
    }

    func test_default_migratesAfterSustainedChange() {
        // Three weeks of Design (the store's half-life), then a fresh
        // burst of Dev. The decayed Design score should fall behind the
        // recent Dev accumulation.
        for d in 0..<10 {
            store.record(projectId: 1, taskId: /*Design*/ 10, now: t0.addingTimeInterval(Double(d) * day))
        }
        // ~6 weeks later, a run of Dev entries.
        let later = t0.addingTimeInterval(42 * day)
        for d in 0..<8 {
            store.record(projectId: 1, taskId: /*Dev*/ 20, now: later.addingTimeInterval(Double(d) * day))
        }
        let now = later.addingTimeInterval(8 * day)
        XCTAssertEqual(
            store.bestTask(forProjectId: 1, now: now), 20,
            "Once work genuinely shifts, the inferred default should follow"
        )
    }

    func test_recentSingleUse_beatsStaleHeavyUse_pastManyHalfLives() {
        // One Design entry a year ago vs. one Dev entry today: the ancient
        // score has decayed to near-zero, so today's wins despite equal
        // raw counts.
        store.record(projectId: 1, taskId: 10, now: t0)
        let now = t0.addingTimeInterval(365 * day)
        store.record(projectId: 1, taskId: 20, now: now)
        XCTAssertEqual(store.bestTask(forProjectId: 1, now: now), 20)
    }

    // MARK: - Cap eviction

    func test_enforcesCap_evictingLowestScoredRows() {
        // Fill past the cap; the most-recently/heavily used rows survive.
        // Record a clearly-dominant row first, then flood with one-offs.
        for _ in 0..<5 {
            store.record(projectId: 0, taskId: 0, now: t0)  // dominant
        }
        for i in 1...(ProjectTaskHistoryStore.maxEntries + 50) {
            store.record(projectId: i, taskId: i, now: t0)
        }
        let total = store.stats.reduce(0) { $0 + $1.value.count }
        XCTAssertLessThanOrEqual(total, ProjectTaskHistoryStore.maxEntries)
        // The dominant row (score 5) must outlast the score-1 one-offs.
        XCTAssertEqual(store.bestTask(forProjectId: 0, now: t0), 0)
    }
}
