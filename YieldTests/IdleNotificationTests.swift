import XCTest
@testable import Yield

/// Covers `TimeComparisonViewModel.formatIdleDuration` — the idle
/// nudge's duration phrasing. The notification is the only signal the
/// user gets while the panel is closed (macOS 27 broke the old
/// force-the-panel-open path), so the wording is worth pinning.
@MainActor
final class IdleNotificationTests: XCTestCase {

    private func format(_ seconds: TimeInterval) -> String {
        TimeComparisonViewModel.formatIdleDuration(seconds)
    }

    // MARK: - Under an hour

    func test_singularMinute() {
        XCTAssertEqual(format(60), "1 minute")
    }

    func test_pluralMinutes() {
        XCTAssertEqual(format(15 * 60), "15 minutes")
    }

    /// The check fires on a 60s tick, so idle time lands on arbitrary
    /// second offsets — round to the nearest minute rather than
    /// truncating (25m50s reads as 26, not 25).
    func test_roundsToNearestMinute() {
        XCTAssertEqual(format(25 * 60 + 50), "26 minutes")
        XCTAssertEqual(format(25 * 60 + 10), "25 minutes")
    }

    /// Sub-minute idle shouldn't render "0 minutes" — the floor of 1
    /// keeps the sentence sane if the threshold is ever set that low.
    func test_subMinuteFloorsToOne() {
        XCTAssertEqual(format(20), "1 minute")
        XCTAssertEqual(format(0), "1 minute")
    }

    // MARK: - An hour and over

    func test_exactlyOneHour() {
        XCTAssertEqual(format(3600), "1h")
    }

    func test_hoursAndMinutes() {
        XCTAssertEqual(format(3600 + 10 * 60), "1h 10m")
    }

    func test_wholeHoursDropTheMinutes() {
        XCTAssertEqual(format(3 * 3600), "3h")
    }

    /// 59.5 minutes rounds up to 60, which must read as "1h" rather
    /// than "60 minutes".
    func test_boundaryRoundsIntoHours() {
        XCTAssertEqual(format(59 * 60 + 40), "1h")
    }
}
