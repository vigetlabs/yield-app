import Foundation

/// A `UserDefaults` suite for tests to write to instead of
/// `UserDefaults.standard`.
///
/// The test bundle is hosted inside Yield.app, so `.standard` in a test
/// is the user's real `com.yield` preferences. Stores that persist
/// take a `UserDefaults` in their initializer; tests pass
/// `scratch.defaults` so fixtures can never overwrite real data.
///
/// One fixed suite name, emptied before and after each use — not a
/// fresh name per test. A unique name per test looked tidier but left
/// a file behind every time: cfprefsd writes an emptied domain back to
/// disk some seconds after the test process has gone, so deleting the
/// plist (even after `synchronize()`) only had it reappear, and
/// `~/Library/Preferences` gained a couple of dozen empty files per
/// run. A fixed name leaves exactly one small, empty plist, ever.
/// Tests run serially in one process, so sharing the name is safe.
final class ScratchDefaults {
    static let suiteName = "com.yield.tests.scratch"

    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)!
        // Start clean even if an earlier run crashed mid-test.
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    /// Empty the suite. Idempotent; call from `tearDown`.
    func discard() {
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    deinit { discard() }
}
