import XCTest
@testable import Yield

/// Covers the post-meeting overage reminder: arming a calendar-sourced
/// timer, the due/not-due threshold, self-resolution when the timer
/// stops or switches, and dismissal finality. The notification and
/// move-commit paths sit outside the unit boundary like the other
/// API-touching flows.
@MainActor
final class PostMeetingReminderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    /// An event that *ended* `endedMinutesAgo` before `now`.
    private func endedEvent(
        id: String = "evt-1",
        title: String = "Design Review",
        endedMinutesAgo: Double,
        durationMinutes: Double = 30
    ) -> CalendarEvent {
        let end = now.addingTimeInterval(-endedMinutesAgo * 60)
        return CalendarEvent(
            id: id,
            summary: title,
            start: end.addingTimeInterval(-durationMinutes * 60),
            end: end
        )
    }

    private func entry(
        id: Int,
        projectId: Int = 500,
        taskId: Int = 100,
        isRunning: Bool = true
    ) -> TimeEntryInfo {
        TimeEntryInfo(
            id: id,
            harvestProjectId: projectId,
            taskId: taskId,
            taskName: "Task",
            hours: 1.0,
            date: DateHelpers.dateFormatter.string(from: now),
            isRunning: isRunning,
            notes: nil,
            timerStartedAt: nil
        )
    }

    /// A view model with a fixed 10-minute threshold and the feature
    /// force-enabled (never the user's real settings) and non-persisted
    /// stores.
    private func makeVM() -> TimeComparisonViewModel {
        let vm = TimeComparisonViewModel()
        vm.meetingHistoryStore = MeetingHistoryStore(loadFromDefaults: false)
        vm.mutedMeetingsStore = MutedMeetingsStore(loadFromDefaults: false)
        vm.postMeetingReminderMinutes = { 10 }
        vm.postMeetingRemindersEnabled = { true }
        return vm
    }

    private func trackingVM(entry: TimeEntryInfo) -> TimeComparisonViewModel {
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            ProjectStatus(
                id: "p",
                clientName: nil,
                projectName: "Project",
                projectCode: nil,
                bookedHours: 8,
                loggedHours: 1,
                todayHours: 1,
                isTracking: true,
                harvestProjectId: entry.harvestProjectId,
                todayEntryId: entry.id,
                lastTaskId: nil,
                timeEntries: [entry],
                forecastNotes: nil
            ),
        ])
        return vm
    }

    /// Arm the VM with a calendar-sourced timer whose event ended
    /// `endedMinutesAgo` before `now`.
    private func arm(_ vm: TimeComparisonViewModel, endedMinutesAgo: Double, eventId: String = "evt-1", projectId: Int = 500, taskId: Int = 100) {
        let end = now.addingTimeInterval(-endedMinutesAgo * 60)
        vm._setStateForTesting(calendarSourcedTimer: .init(
            eventId: eventId,
            eventTitle: "Design Review",
            eventStart: end.addingTimeInterval(-30 * 60),
            eventEnd: end,
            projectId: projectId,
            taskId: taskId
        ))
    }

    // MARK: - Arming (noteCalendarSourcedTimer)

    func test_note_recordsOngoingEvent() {
        let vm = makeVM()
        vm.noteCalendarSourcedTimer(
            event: endedEvent(endedMinutesAgo: -20),  // ends 20 min from now
            projectId: 500, taskId: 100, now: now
        )
        XCTAssertEqual(vm.calendarSourcedTimer?.eventId, "evt-1")
        XCTAssertEqual(vm.calendarSourcedTimer?.projectId, 500)
    }

    func test_note_ignoresAlreadyEndedEvent() {
        // Logging a timer against a meeting after the fact is
        // deliberate — no reminder should arm.
        let vm = makeVM()
        vm.noteCalendarSourcedTimer(
            event: endedEvent(endedMinutesAgo: 5),
            projectId: 500, taskId: 100, now: now
        )
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    func test_note_ignoresUntitledEvent() {
        let vm = makeVM()
        vm.noteCalendarSourcedTimer(
            event: endedEvent(title: "", endedMinutesAgo: -20),
            projectId: 500, taskId: 100, now: now
        )
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    // MARK: - Threshold

    func test_notDue_beforeThreshold() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 5)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)
        // Still armed — it becomes due later.
        XCTAssertNotNil(vm.calendarSourcedTimer)
    }

    func test_due_afterThreshold() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertEqual(vm.activePostMeetingReminder?.eventId, "evt-1")
        XCTAssertEqual(vm.postMeetingOverageHours(now: now), 0.2, accuracy: 0.001)
    }

    func test_due_exactlyAtThreshold() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 10)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNotNil(vm.activePostMeetingReminder)
    }

    // MARK: - Self-resolution

    func test_cleared_whenNoTimerRunning() {
        let vm = trackingVM(entry: entry(id: 1, isRunning: false))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    func test_cleared_whenTimerSwitchedToDifferentTask() {
        let vm = trackingVM(entry: entry(id: 1, taskId: 999))
        arm(vm, endedMinutesAgo: 12)  // armed for taskId 100
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    func test_activeReminder_clearsWhenTimerStops() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNotNil(vm.activePostMeetingReminder)

        vm._setStateForTesting(projectStatuses: [])
        vm.updatePostMeetingReminder(now: now.addingTimeInterval(60))
        XCTAssertNil(vm.activePostMeetingReminder)
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    // MARK: - Dismissal

    func test_dismiss_isFinalForTheEvent() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNotNil(vm.activePostMeetingReminder)

        vm.dismissPostMeetingReminder()
        XCTAssertNil(vm.activePostMeetingReminder)
        XCTAssertNil(vm.calendarSourcedTimer)

        // Re-arming the same event (e.g. state seeded again) stays quiet.
        arm(vm, endedMinutesAgo: 13)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)
    }

    func test_dismiss_beforeDue_dropsTheArmedRecord() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 5)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)

        // Dismissing with no visible bar (defensive path) still clears
        // the armed record so it can't fire later.
        vm.dismissPostMeetingReminder()
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    func test_overageHours_zeroWithoutActiveReminder() {
        let vm = makeVM()
        XCTAssertEqual(vm.postMeetingOverageHours(now: now), 0)
    }

    // MARK: - Settings toggle

    func test_disabled_suppressesReminderButKeepsRecord() {
        let vm = trackingVM(entry: entry(id: 1))
        vm.postMeetingRemindersEnabled = { false }
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)
        // The armed record survives — it still powers the banner's
        // calendar indicator, and re-enabling picks it back up.
        XCTAssertNotNil(vm.calendarSourcedTimer)
    }

    func test_disabled_stillClearsStaleRecordWhenTimerStops() {
        let vm = trackingVM(entry: entry(id: 1, isRunning: false))
        vm.postMeetingRemindersEnabled = { false }
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.calendarSourcedTimer)
    }

    // MARK: - Meeting-prompt precedence (one calendar bar at a time)

    func test_suppressed_whileMeetingPromptActive() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm._setStateForTesting(activeMeetingPrompt: endedEvent(id: "evt-2", endedMinutesAgo: -25))
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)
        // Deferred, not dropped — the armed record survives.
        XCTAssertNotNil(vm.calendarSourcedTimer)
    }

    func test_surfaces_afterPromptDismissed() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm._setStateForTesting(activeMeetingPrompt: endedEvent(id: "evt-2", endedMinutesAgo: -25))
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNil(vm.activePostMeetingReminder)

        vm.dismissMeetingPrompt()
        vm.updatePostMeetingReminder(now: now.addingTimeInterval(60))
        XCTAssertEqual(vm.activePostMeetingReminder?.eventId, "evt-1")
    }

    func test_promptTakesOver_whileReminderShowing() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNotNil(vm.activePostMeetingReminder)

        // A new event enters its prompt window — the prompt wins the
        // slot and the reminder yields.
        vm._setStateForTesting(activeMeetingPrompt: endedEvent(id: "evt-2", endedMinutesAgo: -25))
        vm.updatePostMeetingReminder(now: now.addingTimeInterval(60))
        XCTAssertNil(vm.activePostMeetingReminder)
        XCTAssertNotNil(vm.calendarSourcedTimer)
    }

    // MARK: - Commit-time settling (form flows)

    private func move(projectId: Int?, taskId: Int?) -> TimeComparisonViewModel.PendingTimerMove {
        .init(
            sourceEntryId: 1,
            sourceProjectId: projectId,
            sourceTaskId: taskId,
            sourceProjectName: "Project",
            sourceTaskName: "Task",
            sourceWasRunning: true
        )
    }

    func test_settleForMove_offMeetingTimer_dismissesReminderKeepsRecord() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)
        XCTAssertNotNil(vm.activePostMeetingReminder)

        vm.settlePostMeetingReminderForMove(move(projectId: 500, taskId: 100))
        XCTAssertNil(vm.activePostMeetingReminder)
        // Move & Keep leaves the meeting timer running — the armed
        // record (and the banner's indicator) survives, but the event
        // never re-reminds.
        XCTAssertNotNil(vm.calendarSourcedTimer)
        vm.updatePostMeetingReminder(now: now.addingTimeInterval(60))
        XCTAssertNil(vm.activePostMeetingReminder)
    }

    func test_settleForMove_offUnrelatedTimer_leavesReminder() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: 12)
        vm.updatePostMeetingReminder(now: now)

        vm.settlePostMeetingReminderForMove(move(projectId: 700, taskId: 300))
        XCTAssertNotNil(vm.activePostMeetingReminder)
    }

    // MARK: - Banner indicator source

    func test_calendarSourceForCurrentTimer_matchesRunningTimer() {
        let vm = trackingVM(entry: entry(id: 1))
        arm(vm, endedMinutesAgo: -20)  // meeting still in progress
        XCTAssertEqual(vm.calendarSourceForCurrentTimer?.eventId, "evt-1")
        XCTAssertEqual(vm.calendarSourceForCurrentTimer?.eventDurationHours ?? 0, 0.5, accuracy: 0.001)
    }

    func test_calendarSourceForCurrentTimer_nilWhenTimerSwitched() {
        let vm = trackingVM(entry: entry(id: 1, taskId: 999))
        arm(vm, endedMinutesAgo: -20)  // armed for taskId 100
        XCTAssertNil(vm.calendarSourceForCurrentTimer)
    }

    func test_calendarSourceForCurrentTimer_nilWhenNothingRunning() {
        let vm = trackingVM(entry: entry(id: 1, isRunning: false))
        arm(vm, endedMinutesAgo: -20)
        XCTAssertNil(vm.calendarSourceForCurrentTimer)
    }
}
