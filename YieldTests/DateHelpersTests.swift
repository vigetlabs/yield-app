import XCTest
@testable import Yield

/// Covers the date helpers the app uses for week bounds, week labels,
/// and assignment overlap counting. Functions that read `Date()`
/// directly (`currentWeekBounds`, `weekBounds(offset:)`) can only be
/// asserted structurally — start is Monday, span is 6 days, etc.
/// Pure functions that take dates as arguments are tested with
/// constructed fixtures.
final class DateHelpersTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `Date` in the local calendar at midnight of the given
    /// year/month/day. Used by every test that needs a specific date
    /// without timezone surprises.
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return Calendar.current.date(from: components)!
    }

    // MARK: - currentWeekBounds (structural)

    func test_currentWeekBounds_startIsMonday() {
        let bounds = DateHelpers.currentWeekBounds()
        let weekday = Calendar.current.component(.weekday, from: bounds.start)
        // Sunday=1, Monday=2 in Calendar.weekday.
        XCTAssertEqual(weekday, 2, "Week should start on Monday")
    }

    func test_currentWeekBounds_endIsSunday() {
        let bounds = DateHelpers.currentWeekBounds()
        let weekday = Calendar.current.component(.weekday, from: bounds.end)
        XCTAssertEqual(weekday, 1, "Week should end on Sunday")
    }

    func test_currentWeekBounds_spansSixDays() {
        let bounds = DateHelpers.currentWeekBounds()
        let days = Calendar.current.dateComponents([.day], from: bounds.start, to: bounds.end).day
        XCTAssertEqual(days, 6, "Mon → Sun is a 6-day span")
    }

    func test_currentWeekBounds_includesToday() {
        let bounds = DateHelpers.currentWeekBounds()
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertGreaterThanOrEqual(today, bounds.start)
        XCTAssertLessThanOrEqual(today, Calendar.current.date(byAdding: .day, value: 1, to: bounds.end)!)
    }

    func test_currentWeekBounds_startIsAtMidnight() {
        let bounds = DateHelpers.currentWeekBounds()
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: bounds.start)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    // MARK: - weekBounds(offset:)

    func test_weekBounds_offsetZeroEqualsCurrentWeek() {
        let current = DateHelpers.currentWeekBounds()
        let offset = DateHelpers.weekBounds(offset: 0)
        XCTAssertEqual(current.start, offset.start)
        XCTAssertEqual(current.end, offset.end)
    }

    func test_weekBounds_offsetMinusOneIsSevenDaysEarlier() {
        let current = DateHelpers.currentWeekBounds()
        let lastWeek = DateHelpers.weekBounds(offset: -1)
        let daysBetween = Calendar.current.dateComponents([.day], from: lastWeek.start, to: current.start).day
        XCTAssertEqual(daysBetween, 7)
    }

    func test_weekBounds_offsetPlusOneIsSevenDaysLater() {
        let current = DateHelpers.currentWeekBounds()
        let nextWeek = DateHelpers.weekBounds(offset: 1)
        let daysBetween = Calendar.current.dateComponents([.day], from: current.start, to: nextWeek.start).day
        XCTAssertEqual(daysBetween, 7)
    }

    // MARK: - weekDays(starting:)

    func test_weekDays_returnsSevenDays() {
        let start = date(2026, 4, 27)  // Mon Apr 27, 2026
        let days = DateHelpers.weekDays(starting: start)
        XCTAssertEqual(days.count, 7)
    }

    func test_weekDays_firstDayIsTheStart() {
        let start = date(2026, 4, 27)
        let days = DateHelpers.weekDays(starting: start)
        XCTAssertEqual(days.first?.date, start)
    }

    func test_weekDays_dateStringsAreSequential() {
        let start = date(2026, 4, 27)  // Mon Apr 27
        let days = DateHelpers.weekDays(starting: start)
        XCTAssertEqual(days.map { $0.str }, [
            "2026-04-27", "2026-04-28", "2026-04-29", "2026-04-30",
            "2026-05-01", "2026-05-02", "2026-05-03",
        ])
    }

    // MARK: - formatWeekRange (deterministic)

    func test_formatWeekRange_sameMonth() {
        let bounds = (start: date(2026, 4, 20), end: date(2026, 4, 26))
        XCTAssertEqual(DateHelpers.formatWeekRange(bounds: bounds), "Apr 20 – 26, 2026")
    }

    func test_formatWeekRange_crossesMonths() {
        let bounds = (start: date(2026, 4, 27), end: date(2026, 5, 3))
        XCTAssertEqual(DateHelpers.formatWeekRange(bounds: bounds), "Apr 27 – May 3, 2026")
    }

    func test_formatWeekRange_crossesYear() {
        let bounds = (start: date(2025, 12, 29), end: date(2026, 1, 4))
        XCTAssertEqual(DateHelpers.formatWeekRange(bounds: bounds), "Dec 29, 2025 – Jan 4, 2026")
    }

    // MARK: - weekdayLabels

    func test_weekdayLabels_areMondayFirst() {
        XCTAssertEqual(DateHelpers.weekdayLabels, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    }

    // MARK: - countOverlappingWeekdays

    func test_countOverlappingWeekdays_assignmentSpansFullWorkweek() {
        // Mon Apr 27 → Sun May 3, 2026. Assignment Mon → Fri.
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "2026-04-27",
            assignmentEnd: "2026-05-01",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 5)
    }

    func test_countOverlappingWeekdays_assignmentEntirelyOnWeekend() {
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "2026-05-02",
            assignmentEnd: "2026-05-03",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 0, "Sat/Sun weekend days should not count")
    }

    func test_countOverlappingWeekdays_assignmentExtendsBeforeWeek() {
        // Assignment Apr 20 → Apr 30 overlaps Mon-Thu of Apr 27 week.
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "2026-04-20",
            assignmentEnd: "2026-04-30",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 4, "Mon, Tue, Wed, Thu of the week")
    }

    func test_countOverlappingWeekdays_assignmentExtendsAfterWeek() {
        // Assignment Apr 30 → May 8 overlaps Thu-Fri of Apr 27 week.
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "2026-04-30",
            assignmentEnd: "2026-05-08",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 2, "Thu, Fri of the week")
    }

    func test_countOverlappingWeekdays_assignmentNoOverlap() {
        // Assignment in a totally different week.
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "2026-04-13",
            assignmentEnd: "2026-04-17",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 0)
    }

    func test_countOverlappingWeekdays_singleDay() {
        // Wed Apr 29 only.
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "2026-04-29",
            assignmentEnd: "2026-04-29",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 1)
    }

    func test_countOverlappingWeekdays_invalidDateStringsReturnZero() {
        let count = DateHelpers.countOverlappingWeekdays(
            assignmentStart: "not-a-date",
            assignmentEnd: "2026-04-29",
            weekStart: date(2026, 4, 27),
            weekEnd: date(2026, 5, 3)
        )
        XCTAssertEqual(count, 0)
    }
}
