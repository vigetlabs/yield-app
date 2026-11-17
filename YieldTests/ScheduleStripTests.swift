import XCTest
@testable import Yield

/// The main view's strip of today's meetings: the hours it covers,
/// where each meeting sits, and which lane overlapping ones take.
final class ScheduleStripTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    private var midnight: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 17))!
    }

    private func at(_ hour: Double) -> Date {
        midnight.addingTimeInterval(hour * 3600)
    }

    private func event(_ title: String, _ start: Double, _ end: Double) -> CalendarEvent {
        CalendarEvent(id: title, summary: title, start: at(start), end: at(end))
    }

    private func strip(_ events: [CalendarEvent]?, now hour: Double = 10) -> ScheduleStrip {
        ScheduleStrip(events: events, day: midnight, now: at(hour), calendar: calendar)
    }

    // MARK: - Hours

    func test_anEmptyDay_isStillTheWorkingDay() {
        let s = strip([])
        XCTAssertTrue(s.blocks.isEmpty)
        XCTAssertEqual(s.hourMarks.count, 8)
        XCTAssertTrue(s.isLoaded)
    }

    func test_eventsNotYetFetched_isNotAnEmptyDay() {
        XCTAssertFalse(strip(nil).isLoaded)
    }

    func test_coversTheWorkingDay_whenMeetingsFallInsideIt() {
        let s = strip([event("Review", 11, 12)])
        XCTAssertEqual(s.hourMarks.map(\.label), ["9am", "10", "11", "12pm", "1", "2", "3", "4"])
    }

    func test_anEarlyMeeting_stretchesTheStart_toItsHour() {
        let s = strip([event("Focus time", 7.5, 8.83)])
        XCTAssertEqual(s.hourMarks.first?.label, "7am")
        XCTAssertEqual(s.hourMarks.count, 10)
    }

    func test_aLateMeeting_stretchesTheEnd_upToTheHour() {
        let s = strip([event("Talk", 18, 19.5)])
        XCTAssertEqual(s.hourMarks.last?.label, "7")
    }

    func test_anotherDaysEvents_areLeftOut() {
        XCTAssertTrue(strip([event("Yesterday", -3, -2)]).blocks.isEmpty)
    }

    // MARK: - Placement

    func test_aMeeting_sitsWhereTheClockPutsIt() throws {
        // 11:00–12:00 on a 9–5 strip: an eighth wide, a quarter in.
        let block = try XCTUnwrap(strip([event("Review", 11, 12)]).blocks.first)
        XCTAssertEqual(block.start, 0.25, accuracy: 0.0001)
        XCTAssertEqual(block.width, 0.125, accuracy: 0.0001)
        XCTAssertEqual(block.lane, 0)
    }

    func test_now_isPlacedOnTheStrip_andLeftOffOutsideItsHours() {
        XCTAssertEqual(strip([event("Review", 11, 12)], now: 13).nowFraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertNil(strip([event("Review", 11, 12)], now: 7).nowFraction)
        XCTAssertNil(strip([event("Review", 11, 12)], now: 20).nowFraction)
    }

    func test_phases_followTheClock() {
        let s = strip([event("Done", 9, 9.5), event("On", 9.75, 10.5), event("Later", 14, 15)], now: 10)
        XCTAssertEqual(s.blocks.map(\.phase), [.past, .current, .upcoming])
    }

    // MARK: - Another day

    func test_anotherDay_hasNoNowLine_andOneStrength() {
        // Wednesday's meetings, seen from the Tuesday before at 10am.
        let wednesday = midnight.addingTimeInterval(24 * 3600)
        let events = [9.0, 14.0].map { hour in
            CalendarEvent(id: "\(hour)", summary: "Meeting",
                          start: wednesday.addingTimeInterval(hour * 3600),
                          end: wednesday.addingTimeInterval((hour + 1) * 3600))
        }
        let s = ScheduleStrip(events: events, day: wednesday, now: at(10), calendar: calendar)
        XCTAssertNil(s.nowFraction)
        XCTAssertFalse(s.showsToday)
        XCTAssertEqual(s.blocks.map(\.phase), [.upcoming, .upcoming])
        XCTAssertEqual(s.blocks.first?.start ?? -1, 0, accuracy: 0.0001)
    }

    func test_aPastDay_isDrawnAtTheSameStrength() {
        let monday = midnight.addingTimeInterval(-24 * 3600)
        let events = [CalendarEvent(id: "m", summary: "Meeting",
                                    start: monday.addingTimeInterval(9 * 3600),
                                    end: monday.addingTimeInterval(10 * 3600))]
        let s = ScheduleStrip(events: events, day: monday, now: at(10), calendar: calendar)
        XCTAssertEqual(s.blocks.map(\.phase), [.upcoming])
    }

    // MARK: - Overlap

    func test_separateMeetings_shareOneLane() {
        let s = strip([event("A", 9, 9.5), event("B", 9.5, 10), event("C", 13, 14)])
        XCTAssertEqual(s.laneCount, 1)
        XCTAssertEqual(s.blocks.map(\.lane), [0, 0, 0])
    }

    func test_aMeetingInsideALongerOne_takesTheSecondLane() {
        let s = strip([event("Focus time", 9, 12), event("Standup", 10, 10.25)])
        XCTAssertEqual(s.laneCount, 2)
        XCTAssertEqual(s.blocks.first { $0.event.summary == "Focus time" }?.lane, 0)
        XCTAssertEqual(s.blocks.first { $0.event.summary == "Standup" }?.lane, 1)
    }

    func test_partialOverlap_takesTheSecondLane_andALaterMeetingReturnsToTheFirst() {
        let s = strip([event("A", 12, 12.5), event("B", 12, 13), event("C", 14, 15)])
        XCTAssertEqual(s.laneCount, 2)
        XCTAssertEqual(s.blocks.first { $0.event.summary == "C" }?.lane, 0)
    }
}

/// Which day's meetings the view model hands the strip.
@MainActor
final class ScheduleStripSelectionTests: XCTestCase {

    private func event(_ title: String, on day: Date, hour: Double) -> CalendarEvent {
        let start = Calendar.current.startOfDay(for: day).addingTimeInterval(hour * 3600)
        return CalendarEvent(id: title, summary: title, start: start, end: start.addingTimeInterval(1800))
    }

    private func id(_ day: Date) -> String { DateHelpers.dateFormatter.string(from: day) }

    func test_noDaySelected_noStrip() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(cachedCalendarEvents: [event("Standup", on: Date(), hour: 9)])
        XCTAssertNil(vm.scheduleStrip)
    }

    func test_calendarNotConnected_noStrip() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(dayFilter: id(Date()))
        XCTAssertNil(vm.scheduleStrip)
    }

    func test_todaySelected_drawsTodaysEvents() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(cachedCalendarEvents: [event("Standup", on: Date(), hour: 9)], dayFilter: id(Date()))
        XCTAssertEqual(vm.scheduleStrip?.blocks.map(\.event.summary), ["Standup"])
        XCTAssertEqual(vm.scheduleStrip?.showsToday, true)
    }

    func test_anotherDaySelected_drawsThatDaysEvents_notTodays() {
        let tomorrow = Date().addingTimeInterval(24 * 3600)
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            cachedCalendarEvents: [event("Standup", on: Date(), hour: 9)], dayFilter: id(tomorrow),
            otherDayCalendarEvents: [id(tomorrow): [event("Planning", on: tomorrow, hour: 13)]]
        )
        XCTAssertEqual(vm.scheduleStrip?.blocks.map(\.event.summary), ["Planning"])
        XCTAssertEqual(vm.scheduleStrip?.showsToday, false)
    }

    func test_anotherDaySelected_beforeItsEventsArrive_isNotYetLoaded() {
        let tomorrow = Date().addingTimeInterval(24 * 3600)
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(cachedCalendarEvents: [], dayFilter: id(tomorrow))
        XCTAssertEqual(vm.scheduleStrip?.isLoaded, false)
    }
}
