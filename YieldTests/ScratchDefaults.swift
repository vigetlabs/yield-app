import Foundation

/// A throwaway `UserDefaults` suite for tests that exercise a
/// persisted store. The test bundle is hosted inside Yield.app, so
/// `UserDefaults.standard` in a test *is* the user's real preferences;
/// a store under test must be pointed somewhere else or every fixture
/// it saves replaces the user's data.
///
/// One per test instance, empty on creation. Call `discard()` from
/// `tearDown` — XCTest keeps test instances alive until the whole run
/// ends, so relying on `deinit` leaves the suite's plist behind in
/// ~/Library/Preferences.
final class ScratchDefaults {
    let name: String
    let defaults: UserDefaults

    init() {
        name = "com.yield.tests.scratch.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
    }

    /// Wipe the suite from memory and disk. Idempotent.
    func discard() {
        defaults.removePersistentDomain(forName: name)
        // `removePersistentDomain` empties the domain but can leave a
        // zero-entry plist on disk; remove that too.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    deinit { discard() }
}
