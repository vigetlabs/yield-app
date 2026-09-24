import XCTest
@testable import Yield

/// Covers `IdleAlertView.idleDurationLabel` — the duration phrasing in
/// the idle alert's header and in every action's subtitle ("Remove 25
/// minutes of idle time"), so it's the one string the user reads four
/// times while deciding what to do with the time.
@MainActor
final class IdleAlertTests: XCTestCase {

    private func label(_ minutes: Int) -> String {
        IdleAlertView.idleDurationLabel(minutes: minutes)
    }

    // MARK: - Under an hour

    func test_singularMinute() {
        XCTAssertEqual(label(1), "1 minute")
    }

    func test_pluralMinutes() {
        XCTAssertEqual(label(25), "25 minutes")
    }

    func test_justUnderAnHour() {
        XCTAssertEqual(label(59), "59 minutes")
    }

    // MARK: - An hour and over

    func test_exactlyOneHour() {
        XCTAssertEqual(label(60), "1h")
    }

    func test_hoursAndMinutes() {
        XCTAssertEqual(label(70), "1h 10m")
    }

    func test_wholeHoursDropTheMinutes() {
        XCTAssertEqual(label(180), "3h")
    }

    /// The case the hour/minute split exists for: an overnight idle
    /// should read as "12h", not "720 minutes".
    func test_overnightReadsAsHours() {
        XCTAssertEqual(label(720), "12h")
    }
}
