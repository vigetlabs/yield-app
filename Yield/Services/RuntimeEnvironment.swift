import Foundation

/// Facts about how the process was launched.
enum RuntimeEnvironment {
    /// True inside an XCTest run. The test bundle is hosted in
    /// Yield.app, so the app's own code runs there with the user's
    /// real preferences and notification centre: the few places that
    /// must not touch those under test check this. Read once — the
    /// lookup copies the whole environment.
    static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
