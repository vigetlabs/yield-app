import XCTest
@testable import Yield

/// The menu bar's meeting countdown: which meeting it talks about, how
/// it words the time, and what it leaves out.
final class MeetingCountdownTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    private func event(
        _ title: String,
        startsIn minutes: Double,
        lasting duration: Double = 30
    ) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEvent(
            id: title, summary: title, start: start,
            end: start.addingTimeInterval(duration * 60)
        )
    }

    private func status(
        _ events: [CalendarEvent],
        mode: MeetingCountdownMode = .titleAndTime,
        overrunSince: Date? = nil
    ) -> MenuBarMeetingStatus? {
        MeetingCountdown.status(
            events: events, now: now, mode: mode,
            overrunSince: overrunSince, overrunTitle: "1:1 Sam"
        )
    }

    // MARK: - Upcoming

    func test_upcoming_titleAndTime() {
        let s = status([event("AMC kickoff", startsIn: 82)])
        XCTAssertEqual(s, MenuBarMeetingStatus(text: "AMC kickoff in 1h 22m", tone: .plain))
    }

    func test_upcoming_timeOnly_leavesTheTitleOut() {
        XCTAssertEqual(status([event("AMC kickoff", startsIn: 82)], mode: .timeOnly)?.text, "in 1h 22m")
    }

    func test_upcoming_picksTheSoonest() {
        let s = status([event("Later", startsIn: 200), event("Sooner", startsIn: 45)])
        XCTAssertEqual(s?.text, "Sooner in 45m")
    }

    func test_upcoming_turnsImminentInsideTwoMinutes() {
        XCTAssertEqual(status([event("Standup", startsIn: 2)])?.tone, .imminent)
        XCTAssertEqual(status([event("Standup", startsIn: 3)])?.tone, .plain)
    }

    func test_upcoming_secondsAway_isOneMinute_notZero() {
        XCTAssertEqual(status([event("Standup", startsIn: 0.4)])?.text, "Standup in 1m")
    }

    func test_longTitles_areCut_toTheDefaultLength() {
        let s = status([event("Viget <> AFSP/JED Meet & Greet Q&A", startsIn: 10)])
        XCTAssertEqual(s?.text, "Viget <> AFSP/JED M… in 10m")
    }

    func test_titleLength_isTheUsersCall() {
        let events = [event("Viget <> AFSP/JED Meet & Greet Q&A", startsIn: 10)]
        func text(_ length: Int) -> String? {
            MeetingCountdown.status(events: events, now: now, mode: .titleAndTime, titleLength: length)?.text
        }
        XCTAssertEqual(text(10), "Viget <>… in 10m")
        XCTAssertEqual(text(35), "Viget <> AFSP/JED Meet & Greet Q&A in 10m", "fits: nothing cut")
    }

    func test_titleLength_isKeptInRange() {
        XCTAssertEqual(MeetingCountdown.clampedTitleLength(0), 5)
        XCTAssertEqual(MeetingCountdown.clampedTitleLength(500), 60)
        XCTAssertEqual(MeetingCountdown.shortTitle("Design review", limit: 1), "Desi…")
    }

    func test_untitledEvent_showsTheTimeAlone() {
        XCTAssertEqual(status([event("", startsIn: 10)])?.text, "in 10m")
    }

    // MARK: - In a meeting

    func test_inAMeeting_namesIt_andShowsTimeLeft() {
        let s = status([event("1:1 Sam", startsIn: -18, lasting: 30)])
        XCTAssertEqual(s, MenuBarMeetingStatus(text: "1:1 Sam 12m left", tone: .plain))
    }

    func test_inAMeeting_timeOnly_leavesTheTitleOut() {
        let s = status([event("1:1 Sam", startsIn: -18, lasting: 30)], mode: .timeOnly)
        XCTAssertEqual(s?.text, "12m left")
    }

    func test_inAMeeting_mentionsANextOneThatFollowsClosely() {
        let s = status([
            event("1:1 Sam", startsIn: -18, lasting: 30),
            event("1:1 Alex", startsIn: 20),
        ])
        XCTAssertEqual(s?.text, "1:1 Sam 12m left · next 20m")
    }

    func test_inAMeeting_doesNotMentionADistantNextOne() {
        let s = status([
            event("1:1 Sam", startsIn: -18, lasting: 30),
            event("Review", startsIn: 120),
        ])
        XCTAssertEqual(s?.text, "1:1 Sam 12m left")
    }

    // MARK: - Overrun

    func test_overrun_whenAMeetingsTimerOutlivesIt() {
        let s = status([], overrunSince: now.addingTimeInterval(-12 * 60))
        XCTAssertEqual(s, MenuBarMeetingStatus(text: "1:1 Sam ended 12m ago", tone: .overrun))
    }

    func test_overrun_timeOnly_leavesTheTitleOut() {
        let s = status([], mode: .timeOnly, overrunSince: now.addingTimeInterval(-12 * 60))
        XCTAssertEqual(s?.text, "ended 12m ago")
    }

    func test_overrun_outranksAMeetingThatIsMerelyLater() {
        let s = status([event("Review", startsIn: 90)], overrunSince: now.addingTimeInterval(-12 * 60))
        XCTAssertEqual(s?.tone, .overrun)
    }

    func test_overrun_yieldsToAMeetingAboutToStart() {
        let s = status([event("Review", startsIn: 1)], overrunSince: now.addingTimeInterval(-12 * 60))
        XCTAssertEqual(s, MenuBarMeetingStatus(text: "Review in 1m", tone: .imminent))
    }

    func test_overrun_yieldsToAMeetingInProgress() {
        let s = status([event("Review", startsIn: -5)], overrunSince: now.addingTimeInterval(-12 * 60))
        XCTAssertEqual(s?.text, "Review 25m left")
    }

    // MARK: - What it leaves out

    func test_off_saysNothing() {
        XCTAssertNil(status([event("Standup", startsIn: 5)], mode: .off))
    }

    func test_nothingLeftToday_saysNothing() {
        XCTAssertNil(status([event("Earlier", startsIn: -120)]))
    }

    func test_everyKindOfEventCounts_focusTimeIncluded() {
        // A focus block is as much "what's next" as a meeting.
        let s = status([event("Focus time", startsIn: 10), event("Review", startsIn: 60)])
        XCTAssertEqual(s?.text, "Focus time in 10m")
    }

    func test_duringAFocusBlock_itsEndAndTheNextMeetingShow() {
        let s = status([event("Focus time", startsIn: -30, lasting: 50), event("Review", startsIn: 25)])
        XCTAssertEqual(s?.text, "Focus time 20m left · next 25m")
    }

    // MARK: - Drawing

    func test_segment_widensTheImage_andKeepsATemplateATemplate() {
        let status = MenuBarMeetingStatus(text: "in 12m")

        let templateBase = NSImage(size: NSSize(width: 40, height: 18), flipped: false) { _ in true }
        templateBase.isTemplate = true
        let template = MenuBarMeetingSegment.append(status, to: templateBase, day: 16, isDark: false)
        XCTAssertGreaterThan(template.size.width, 40)
        XCTAssertEqual(template.size.height, 18)
        XCTAssertTrue(template.isTemplate)

        let coloredBase = NSImage(size: NSSize(width: 40, height: 18), flipped: false) { _ in true }
        let colored = MenuBarMeetingSegment.append(status, to: coloredBase, day: 16, isDark: true)
        XCTAssertFalse(colored.isTemplate)
    }

    /// Not an assertion — a sheet of the countdown beside each style on
    /// a light and a dark bar, for looking at. Opt in with
    /// `TEST_RUNNER_YIELD_MENUBAR_PREVIEW_DIR=/some/dir`.
    func test_writePreviewSheet() throws {
        var running = MenuBarGraphicState()
        running.timer = .running; running.tone = .onPace; running.progress = 0.33
        running.weekFractions = [1, 0.94, 1, 0.55, 0]; running.todayIndex = 3
        var due = running
        due.meetingDue = true
        var inMeeting = running
        inMeeting.meetingTimerRunning = true
        let rows: [(name: String, state: MenuBarGraphicState, status: MenuBarMeetingStatus)] = [
            ("Later", running, .init(text: "[bizdev] AMC: Pitch Con… in 1h 22m")),
            ("Starting", due, .init(text: "AMC kickoff in 2m", tone: .imminent)),
            ("In a meeting", inMeeting, .init(text: "[bizdev] AMC: Pitch Con… 14m left · next 24m")),
            ("Overrun", inMeeting, .init(text: "1:1 Sam ended 12m ago", tone: .overrun)),
            ("Time only", running, .init(text: "in 1h 22m")),
        ]
        try MenuBarPreviewSheet.write(
            named: "menubar-meetings.png",
            rowNames: rows.map(\.name),
            styles: [.capsule, .ring],
            labelWidth: 96,
            cellWidth: 400
        ) { row, style, dark in
            let base = MenuBarGraphicRenderer.render(
                style: style, label: "5:12 / 16:00", state: rows[row].state, labelMode: .projectTime, isDark: dark
            )
            return MenuBarMeetingSegment.append(rows[row].status, to: base, day: 16, isDark: dark)
        }
    }

    // MARK: - On the view model

    /// The view model derives the status from what it holds; nothing
    /// has to tell it to recompute.
    @MainActor
    func test_viewModel_derivesTheStatus_fromItsEventsAndSetting() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            cachedCalendarEvents: [event("Standup", startsIn: 10)],
            meetingCountdownMode: .titleAndTime
        )
        XCTAssertEqual(vm.menuBarMeetingStatus(now: now)?.text, "Standup in 10m")

        vm._setStateForTesting(meetingCountdownMode: .off)
        XCTAssertNil(vm.menuBarMeetingStatus(now: now))
    }
}
