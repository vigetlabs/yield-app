import XCTest
@testable import Yield

/// Covers `MeetingHistoryStore`'s in-memory contract: record/lookup,
/// title normalization, overwrite-on-rerecord, LRU eviction. Storage
/// (UserDefaults round-trip) isn't tested here — load/save are
/// trivial pass-throughs and would require a stubbed defaults suite.
@MainActor
final class MeetingHistoryStoreTests: XCTestCase {

    private var store: MeetingHistoryStore!

    override func setUp() async throws {
        try await super.setUp()
        // `loadFromDefaults: false` skips reading the user's real
        // history, so each test starts from a known empty state
        // without leaking across runs.
        store = MeetingHistoryStore(loadFromDefaults: false)
    }

    // MARK: - Normalization

    func test_normalize_trimsAndLowercases() {
        XCTAssertEqual(MeetingHistoryStore.normalize("  Standup  "), "standup")
        XCTAssertEqual(MeetingHistoryStore.normalize("STANDUP"), "standup")
        XCTAssertEqual(MeetingHistoryStore.normalize("Sprint Planning"), "sprint planning")
    }

    func test_normalize_doesNotStripPunctuation() {
        // Conservative on purpose — "Stand-up" and "Standup" are
        // probably *meant* to be different memories until proven
        // otherwise.
        XCTAssertNotEqual(
            MeetingHistoryStore.normalize("Stand-up"),
            MeetingHistoryStore.normalize("Standup")
        )
    }

    // MARK: - Record + lookup

    func test_lookup_returnsNilForUnseenTitle() {
        XCTAssertNil(store.lookup(title: "Never seen this"))
    }

    func test_lookup_returnsRecordedPair() {
        store.record(notes: "Standup", projectId: 100, taskId: 7)
        let result = store.lookup(title: "Standup")
        XCTAssertEqual(result?.projectId, 100)
        XCTAssertEqual(result?.taskId, 7)
    }

    func test_lookup_isCaseAndWhitespaceInsensitive() {
        store.record(notes: "Sprint Planning", projectId: 42, taskId: 9)
        XCTAssertEqual(store.lookup(title: "sprint planning")?.projectId, 42)
        XCTAssertEqual(store.lookup(title: "  SPRINT PLANNING  ")?.projectId, 42)
    }

    func test_record_emptyOrWhitespaceTitle_isNoOp() {
        store.record(notes: "", projectId: 1, taskId: 1)
        store.record(notes: "   \n  ", projectId: 1, taskId: 1)
        XCTAssertTrue(store.memories.isEmpty)
    }

    func test_lookup_emptyTitle_returnsNil() {
        store.record(notes: "Standup", projectId: 1, taskId: 1)
        XCTAssertNil(store.lookup(title: ""))
        XCTAssertNil(store.lookup(title: "   "))
    }

    // MARK: - Overwrite contract

    func test_record_sameTitle_overwritesPair() {
        store.record(notes: "Standup", projectId: 100, taskId: 7)
        store.record(notes: "Standup", projectId: 200, taskId: 8)

        XCTAssertEqual(store.memories.count, 1, "Re-recording same title should overwrite, not duplicate")
        let result = store.lookup(title: "Standup")
        XCTAssertEqual(result?.projectId, 200)
        XCTAssertEqual(result?.taskId, 8)
    }

    func test_record_differentTitles_keptSeparately() {
        store.record(notes: "Standup", projectId: 100, taskId: 7)
        store.record(notes: "1:1 with Pat", projectId: 200, taskId: 8)

        XCTAssertEqual(store.memories.count, 2)
        XCTAssertEqual(store.lookup(title: "Standup")?.projectId, 100)
        XCTAssertEqual(store.lookup(title: "1:1 with Pat")?.projectId, 200)
    }

    // MARK: - LRU eviction

    func test_record_evictsOldestWhenOverCap() {
        // Fill to the cap with monotonically increasing timestamps so
        // we know which is "oldest." The store doesn't expose a way
        // to inject lastUsedAt, so simulate by recording in order
        // (each record sets lastUsedAt = now and has a real wall-
        // clock gap).
        //
        // Use a much smaller cap surrogate by recording cap+1 entries
        // with a synthetic gap — actual cap is 200, so touch the real
        // boundary.
        let cap = MeetingHistoryStore.maxEntries
        for i in 0..<(cap + 5) {
            // Inject memories directly (bypassing `record(...)`) so
            // we can pin lastUsedAt to a known ascending sequence —
            // production code uses Date() and the test needs
            // deterministic ordering for the eviction assertions.
            store.memories["title-\(i)"] = MeetingHistoryStore.Memory(
                projectId: i,
                taskId: i,
                lastUsedAt: Date(timeIntervalSince1970: TimeInterval(i))
            )
        }
        // Now trigger an actual record to engage the eviction path.
        store.record(notes: "trigger eviction", projectId: 999, taskId: 999)

        XCTAssertLessThanOrEqual(store.memories.count, cap)
        // The oldest synthetic entries should be gone.
        XCTAssertNil(store.lookup(title: "title-0"))
        // The most recently recorded entry must have survived.
        XCTAssertNotNil(store.lookup(title: "trigger eviction"))
    }
}
