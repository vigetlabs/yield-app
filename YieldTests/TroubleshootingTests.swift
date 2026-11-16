import XCTest
@testable import Yield

/// Settings → Troubleshooting: what the two resets remove and, more
/// to the point, what they leave alone.
@MainActor
final class TroubleshootingTests: XCTestCase {

    private let scratch = ScratchDefaults()

    override func tearDown() async throws {
        scratch.discard()
        try await super.tearDown()
    }

    func test_resetPreferences_removesEverySetting() {
        let d = scratch.defaults
        for key in PreferencesReset.keys { d.set("changed", forKey: key) }
        PreferencesReset.reset(in: d)
        // Removed from the store itself. Reading a key back through
        // `object(forKey:)` would find the app's registered default —
        // which is the point of removing rather than overwriting.
        let stored = d.persistentDomain(forName: ScratchDefaults.suiteName) ?? [:]
        for key in PreferencesReset.keys {
            XCTAssertNil(stored[key], "\(key) should no longer be stored")
        }
    }

    func test_resetPreferences_keepsSignInsAndWhatTheUserBuiltUp() {
        let d = scratch.defaults
        let kept = [
            DefaultsKey.favorites,
            DefaultsKey.meetingHistory,
            DefaultsKey.projectTaskHistory,
            DefaultsKey.mutedMeetingTitles,
            DefaultsKey.meetingTimerLink,
            DefaultsKey.forecastTimeOffProjectId,
            DefaultsKey.OAuth.tokenExpiresAt,
            DefaultsKey.OAuth.harvestAccountId,
            DefaultsKey.OAuth.forecastAccountId,
            DefaultsKey.OAuth.userName,
            DefaultsKey.GoogleCalendar.tokenExpiresAt,
            DefaultsKey.GoogleCalendar.userEmail,
            DefaultsKey.Legacy.harvestAccountId,
            DefaultsKey.Legacy.forecastAccountId,
        ]
        for key in kept { d.set("mine", forKey: key) }
        PreferencesReset.reset(in: d)
        for key in kept {
            XCTAssertEqual(d.string(forKey: key), "mine", "\(key) must survive a reset")
        }
        XCTAssertTrue(Set(kept).isDisjoint(with: PreferencesReset.keys))
    }

    func test_forgetAll_clearsMeetingMemories_andPersistsThat() {
        let store = MeetingHistoryStore(defaults: scratch.defaults)
        store.record(notes: "1:1 Sam", projectId: 1, taskId: 2)
        store.record(notes: "Standup", projectId: 3, taskId: 4)
        XCTAssertNotNil(store.lookup(title: "1:1 Sam"))

        store.forgetAll()
        XCTAssertNil(store.lookup(title: "1:1 Sam"))
        XCTAssertTrue(MeetingHistoryStore(defaults: scratch.defaults).memories.isEmpty)
    }

    func test_lastSyncedText() {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        XCTAssertEqual(TroubleshootingCard.lastSyncedText(nil, now: now), "never")
        XCTAssertEqual(TroubleshootingCard.lastSyncedText(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(TroubleshootingCard.lastSyncedText(now.addingTimeInterval(-125), now: now), "2 min ago")
        XCTAssertEqual(TroubleshootingCard.lastSyncedText(now.addingTimeInterval(-3 * 3600), now: now), "3 hr ago")
    }
}
