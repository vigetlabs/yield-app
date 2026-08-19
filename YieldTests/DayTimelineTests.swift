import XCTest
@testable import Yield

/// Covers the day-timeline layout math behind the calendar event
/// picker: hour-span bounds, y positioning, and the overlap-column
/// assignment that splits concurrent meetings side by side.
final class DayTimelineTests: XCTestCase {

    /// Fixed base: some day at 00:00 local. Events are built at
    /// hour/minute offsets from it.
    private let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_755_000_000))

    private func event(
        id: String,
        startHour: Double,
        endHour: Double
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            summary: "Event \(id)",
            start: midnight.addingTimeInterval(startHour * 3600),
            end: midnight.addingTimeInterval(endHour * 3600)
        )
    }

    private func block(_ timeline: DayTimeline, _ id: String) -> DayTimeline.Block? {
        timeline.blocks.first { $0.id == id }
    }

    // MARK: - Bounds

    func test_bounds_floorAndCeilToHours() {
        let t = DayTimeline(events: [event(id: "a", startHour: 9.25, endHour: 10.75)])
        XCTAssertEqual(t.timelineStart, midnight.addingTimeInterval(9 * 3600))
        XCTAssertEqual(t.timelineEnd, midnight.addingTimeInterval(11 * 3600))
    }

    func test_bounds_exactHoursDontOverextend() {
        let t = DayTimeline(events: [event(id: "a", startHour: 9, endHour: 10)])
        XCTAssertEqual(t.timelineStart, midnight.addingTimeInterval(9 * 3600))
        XCTAssertEqual(t.timelineEnd, midnight.addingTimeInterval(10 * 3600))
    }

    func test_y_scalesByPointsPerHour() {
        let t = DayTimeline(events: [event(id: "a", startHour: 9, endHour: 10)])
        XCTAssertEqual(t.y(for: midnight.addingTimeInterval(9 * 3600)), 0)
        XCTAssertEqual(
            t.y(for: midnight.addingTimeInterval(9.5 * 3600)),
            DayTimeline.pointsPerHour / 2
        )
    }

    func test_hourMarks_coverSpanInclusive() {
        let t = DayTimeline(events: [event(id: "a", startHour: 9.25, endHour: 11.5)])
        // 9, 10, 11, 12
        XCTAssertEqual(t.hourMarks.count, 4)
    }

    // MARK: - Overlap columns

    func test_nonOverlapping_allFullWidth() {
        let t = DayTimeline(events: [
            event(id: "a", startHour: 9, endHour: 10),
            event(id: "b", startHour: 10, endHour: 11),
        ])
        XCTAssertEqual(block(t, "a")?.columnCount, 1)
        XCTAssertEqual(block(t, "b")?.columnCount, 1)
        XCTAssertEqual(block(t, "b")?.column, 0)
    }

    func test_overlapping_splitIntoColumns() {
        let t = DayTimeline(events: [
            event(id: "a", startHour: 9, endHour: 10),
            event(id: "b", startHour: 9.5, endHour: 10.5),
        ])
        XCTAssertEqual(block(t, "a")?.column, 0)
        XCTAssertEqual(block(t, "b")?.column, 1)
        XCTAssertEqual(block(t, "a")?.columnCount, 2)
        XCTAssertEqual(block(t, "b")?.columnCount, 2)
    }

    func test_columnReuse_afterEventEnds() {
        // a(9-10) and b(9-11) overlap; c(10-11) starts after a ends —
        // it reuses whichever column a occupied (the sort places the
        // longer 9am event first, so the index itself isn't fixed),
        // keeping the cluster at 2 columns instead of growing to 3.
        let t = DayTimeline(events: [
            event(id: "a", startHour: 9, endHour: 10),
            event(id: "b", startHour: 9, endHour: 11),
            event(id: "c", startHour: 10, endHour: 11),
        ])
        XCTAssertEqual(block(t, "c")?.column, block(t, "a")?.column)
        XCTAssertNotEqual(block(t, "c")?.column, block(t, "b")?.column)
        XCTAssertEqual(block(t, "c")?.columnCount, 2)
    }

    func test_clusters_dontNarrowLaterLoneEvents() {
        // Two overlapping morning meetings must not squeeze a lone
        // afternoon one into half width.
        let t = DayTimeline(events: [
            event(id: "a", startHour: 9, endHour: 10),
            event(id: "b", startHour: 9.5, endHour: 10.5),
            event(id: "c", startHour: 15, endHour: 16),
        ])
        XCTAssertEqual(block(t, "a")?.columnCount, 2)
        XCTAssertEqual(block(t, "c")?.columnCount, 1)
        XCTAssertEqual(block(t, "c")?.column, 0)
    }

    func test_tripleOverlap_threeColumns() {
        let t = DayTimeline(events: [
            event(id: "a", startHour: 9, endHour: 11),
            event(id: "b", startHour: 9.5, endHour: 10.5),
            event(id: "c", startHour: 10, endHour: 11),
        ])
        XCTAssertEqual(Set(t.blocks.map(\.column)).count, 3)
        XCTAssertTrue(t.blocks.allSatisfy { $0.columnCount == 3 })
    }
}
