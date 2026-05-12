import XCTest
@testable import Yield

/// Covers `Double.roundedHM`, `Double.formattedColon`, and
/// `Double.formattedHoursMinutes` — the three formatters the entire
/// app relies on for hour/minute display.
final class DoubleFormattersTests: XCTestCase {

    // MARK: - roundedHM

    func test_roundedHM_zero() {
        let (h, m) = Double(0).roundedHM
        XCTAssertEqual(h, 0)
        XCTAssertEqual(m, 0)
    }

    func test_roundedHM_wholeHours() {
        XCTAssertEqual(Double(3).roundedHM.h, 3)
        XCTAssertEqual(Double(3).roundedHM.m, 0)
    }

    func test_roundedHM_halfHour() {
        XCTAssertEqual(Double(0.5).roundedHM.h, 0)
        XCTAssertEqual(Double(0.5).roundedHM.m, 30)
    }

    func test_roundedHM_thirtyOneMinutes() {
        // 0.5167h = 31 min — used to be off-by-one (truncation vs rounding).
        let (h, m) = (0.5167).roundedHM
        XCTAssertEqual(h, 0)
        XCTAssertEqual(m, 31)
    }

    func test_roundedHM_rollsOverToNextHour() {
        // 3.999h rounds to 4:00 with no carry bug.
        let (h, m) = (3.999).roundedHM
        XCTAssertEqual(h, 4)
        XCTAssertEqual(m, 0)
    }

    func test_roundedHM_floatPrecisionBoundary() {
        // 3.525 * 60 = 211.499999... in IEEE-754. Without `.rounded()`
        // this used to truncate to 211 → 3h 31m instead of 3h 32m.
        let (h, m) = (3.525).roundedHM
        XCTAssertEqual(h, 3)
        XCTAssertEqual(m, 32)
    }

    func test_roundedHM_largeValues() {
        let (h, m) = (88.5).roundedHM
        XCTAssertEqual(h, 88)
        XCTAssertEqual(m, 30)
    }

    func test_roundedHM_negativeValuesPreserveSign() {
        // Negative input — caller is expected to wrap with Swift.abs
        // when display should be unsigned; verify the math is correct
        // either way.
        let (h, m) = (-1.5).roundedHM
        XCTAssertEqual(h, -1)
        XCTAssertEqual(m, -30)
    }

    // MARK: - formattedColon

    func test_formattedColon_padsMinutes() {
        XCTAssertEqual(Double(1.0).formattedColon, "1:00")
        XCTAssertEqual(Double(1.0833).formattedColon, "1:05")  // 5 minutes
    }

    func test_formattedColon_doubleDigitMinutes() {
        XCTAssertEqual(Double(2.5).formattedColon, "2:30")
        XCTAssertEqual(Double(7.75).formattedColon, "7:45")
    }

    func test_formattedColon_zero() {
        XCTAssertEqual(Double(0).formattedColon, "0:00")
    }

    func test_formattedColon_largeValues() {
        XCTAssertEqual(Double(40).formattedColon, "40:00")
        XCTAssertEqual(Double(88.5).formattedColon, "88:30")
    }

    func test_formattedColon_negative() {
        // Negatives get a single leading minus, not a minus on each
        // component — required for the menu bar "current / remaining"
        // label to render an over-budget remaining cleanly.
        XCTAssertEqual(Double(-2.5).formattedColon, "-2:30")
        XCTAssertEqual(Double(-0.5).formattedColon, "-0:30")
        XCTAssertEqual(Double(-1).formattedColon, "-1:00")
    }

    // MARK: - formattedHoursMinutes

    func test_formattedHoursMinutes_basic() {
        XCTAssertEqual(Double(1.0).formattedHoursMinutes, "1h 00m")
        XCTAssertEqual(Double(2.5).formattedHoursMinutes, "2h 30m")
    }

    func test_formattedHoursMinutes_padsMinutes() {
        XCTAssertEqual(Double(1.0833).formattedHoursMinutes, "1h 05m")
    }

    func test_formattedHoursMinutes_zero() {
        XCTAssertEqual(Double(0).formattedHoursMinutes, "0h 00m")
    }

    func test_formattedHoursMinutes_rollover() {
        // 0.999h → "1h 00m" (rounds to next hour cleanly)
        XCTAssertEqual(Double(0.999).formattedHoursMinutes, "1h 00m")
    }
}
