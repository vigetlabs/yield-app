import XCTest
@testable import Yield

/// Covers the meeting-start prompt's suppression gauntlet
/// (`meetingPromptEligible`) and the mute store. The notification and
/// commit paths sit outside the unit boundary like the other
/// API-touching flows; eligibility is where the fatigue-prevention
/// rules live, so it gets the coverage.
@MainActor
final class MeetingPromptTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    private func event(
        id: String = "evt-1",
        title: String = "Design Review",
        startOffsetMinutes: Double,
        durationMinutes: Double = 30
    ) -> CalendarEvent {
        let start = now.addingTimeInterval(startOffsetMinutes * 60)
        return CalendarEvent(
            id: id,
            summary: title,
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60)
        )
    }

    private func entry(
        id: Int,
        projectId: Int = 500,
        taskId: Int = 100,
        notes: String? = nil,
        isRunning: Bool
    ) -> TimeEntryInfo {
        TimeEntryInfo(
            id: id,
            harvestProjectId: projectId,
            taskId: taskId,
            taskName: "Task",
            hours: 1.0,
            date: DateHelpers.dateFormatter.string(from: now),
            isRunning: isRunning,
            notes: notes,
            timerStartedAt: nil
        )
    }

    /// A view model whose prompt engine reads fresh, non-persisted
    /// stores — tests must never write into the user's real
    /// UserDefaults-backed history or mute list.
    private func makeVM() -> TimeComparisonViewModel {
        let vm = TimeComparisonViewModel()
        vm.meetingHistoryStore = MeetingHistoryStore(loadFromDefaults: false)
        vm.mutedMeetingsStore = MutedMeetingsStore(loadFromDefaults: false)
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

    // MARK: - Window

    func test_eligible_insideWindow_afterStart() {
        let vm = makeVM()
        XCTAssertTrue(vm.meetingPromptEligible(event(startOffsetMinutes: -6), now: now))
    }

    func test_eligible_shortlyBeforeStart() {
        let vm = makeVM()
        XCTAssertTrue(vm.meetingPromptEligible(event(startOffsetMinutes: 1.5), now: now))
    }

    func test_ineligible_tooFarBeforeStart() {
        let vm = makeVM()
        XCTAssertFalse(vm.meetingPromptEligible(event(startOffsetMinutes: 10), now: now))
    }

    func test_ineligible_pastPromptWindow() {
        // Started 35 min ago (window is 30) even though the event is
        // still in progress (60-min duration).
        let vm = makeVM()
        XCTAssertFalse(vm.meetingPromptEligible(
            event(startOffsetMinutes: -35, durationMinutes: 60), now: now))
    }

    func test_ineligible_afterEventEnd() {
        // Short meeting: ended 5 min ago, still inside the 30-min
        // after-start window — the end wins.
        let vm = makeVM()
        XCTAssertFalse(vm.meetingPromptEligible(
            event(startOffsetMinutes: -20, durationMinutes: 15), now: now))
    }

    // MARK: - Identity suppressions

    func test_ineligible_untitledEvent() {
        let vm = makeVM()
        XCTAssertFalse(vm.meetingPromptEligible(
            event(title: "", startOffsetMinutes: -5), now: now))
    }

    func test_ineligible_mutedTitle_caseInsensitive() {
        let vm = makeVM()
        vm.mutedMeetingsStore.mute(title: "design review")
        XCTAssertFalse(vm.meetingPromptEligible(
            event(title: "Design Review", startOffsetMinutes: -5), now: now))
    }

    // MARK: - Already-timing suppressions

    func test_ineligible_whenTimingRememberedPair() {
        let vm = trackingVM(entry: entry(id: 1, projectId: 500, taskId: 100, isRunning: true))
        vm.meetingHistoryStore.record(notes: "Design Review", projectId: 500, taskId: 100)
        XCTAssertFalse(vm.meetingPromptEligible(event(startOffsetMinutes: -5), now: now))
    }

    func test_eligible_whenTimingDifferentPair() {
        let vm = trackingVM(entry: entry(id: 1, projectId: 500, taskId: 100, isRunning: true))
        vm.meetingHistoryStore.record(notes: "Design Review", projectId: 999, taskId: 42)
        XCTAssertTrue(vm.meetingPromptEligible(event(startOffsetMinutes: -5), now: now))
    }

    func test_ineligible_whenRunningNotesMatchTitle() {
        // First-encounter meetings have no memory, but a timer started
        // via the form carries the title as notes — that's proof it's
        // already being timed.
        let vm = trackingVM(entry: entry(id: 1, notes: "  design review ", isRunning: true))
        XCTAssertTrue(vm.meetingHistoryStore.memories.isEmpty)
        XCTAssertFalse(vm.meetingPromptEligible(event(startOffsetMinutes: -5), now: now))
    }

    func test_eligible_whenNoTimerRunning() {
        // The forgot-to-track-at-all case still prompts.
        let vm = makeVM()
        XCTAssertTrue(vm.meetingPromptEligible(event(startOffsetMinutes: -5), now: now))
    }

    // MARK: - Elapsed amount

    func test_elapsedHours_afterStart() {
        let vm = makeVM()
        vm._setStateForTesting(activeMeetingPrompt: event(startOffsetMinutes: -6))
        XCTAssertEqual(vm.meetingPromptElapsedHours(now: now), 0.1, accuracy: 0.001)
    }

    func test_elapsedHours_zeroBeforeStart() {
        let vm = makeVM()
        vm._setStateForTesting(activeMeetingPrompt: event(startOffsetMinutes: 1.5))
        XCTAssertEqual(vm.meetingPromptElapsedHours(now: now), 0, accuracy: 0.001)
    }

    // MARK: - Dismiss / mute actions

    func test_finalizeAction_suppressesEventAndClearsPrompt() {
        // Form commits finalize deferred — same end state as the ×.
        let vm = makeVM()
        let evt = event(startOffsetMinutes: -5)
        vm._setStateForTesting(activeMeetingPrompt: evt)
        vm.finalizeMeetingPromptAction(for: evt)
        XCTAssertNil(vm.activeMeetingPrompt)
        XCTAssertFalse(vm.meetingPromptEligible(evt, now: now))
    }

    func test_finalizeAction_forOtherEvent_keepsActivePrompt() {
        // Committing a picker-sourced timer for event B must not tear
        // down event A's live prompt.
        let vm = makeVM()
        let active = event(id: "evt-a", startOffsetMinutes: -5)
        vm._setStateForTesting(activeMeetingPrompt: active)
        vm.finalizeMeetingPromptAction(for: event(id: "evt-b", startOffsetMinutes: -3))
        XCTAssertEqual(vm.activeMeetingPrompt?.id, "evt-a")
        XCTAssertTrue(vm.meetingPromptEligible(active, now: now))
    }

    func test_dismiss_suppressesThatEventOnly() {
        let vm = makeVM()
        let evt = event(startOffsetMinutes: -5)
        vm._setStateForTesting(activeMeetingPrompt: evt)
        vm.dismissMeetingPrompt()
        XCTAssertNil(vm.activeMeetingPrompt)
        XCTAssertFalse(vm.meetingPromptEligible(evt, now: now))
        // A different event with the same title still prompts.
        XCTAssertTrue(vm.meetingPromptEligible(
            event(id: "evt-2", startOffsetMinutes: -5), now: now))
    }

    func test_mute_suppressesByTitleAcrossEvents() {
        let vm = makeVM()
        vm._setStateForTesting(activeMeetingPrompt: event(startOffsetMinutes: -5))
        vm.muteMeetingPrompt()
        XCTAssertNil(vm.activeMeetingPrompt)
        XCTAssertTrue(vm.mutedMeetingsStore.isMuted(title: "Design Review"))
        XCTAssertFalse(vm.meetingPromptEligible(
            event(id: "evt-2", startOffsetMinutes: -5), now: now))
    }
}

/// The mute store's own contract.
@MainActor
final class MutedMeetingsStoreTests: XCTestCase {

    func test_muteAndUnmute_roundTrip() {
        let store = MutedMeetingsStore(loadFromDefaults: false)
        store.mute(title: "  Weekly Standup ")
        XCTAssertTrue(store.isMuted(title: "weekly standup"))
        XCTAssertEqual(store.sortedMuted.first?.title, "Weekly Standup")

        store.unmute(normalizedTitle: "weekly standup")
        XCTAssertFalse(store.isMuted(title: "Weekly Standup"))
        XCTAssertTrue(store.sortedMuted.isEmpty)
    }

    func test_emptyTitle_neverMutes() {
        let store = MutedMeetingsStore(loadFromDefaults: false)
        store.mute(title: "   ")
        XCTAssertTrue(store.titles.isEmpty)
        XCTAssertFalse(store.isMuted(title: ""))
    }

    func test_sortedMuted_alphabetical() {
        let store = MutedMeetingsStore(loadFromDefaults: false)
        store.mute(title: "Retro")
        store.mute(title: "All Hands")
        XCTAssertEqual(store.sortedMuted.map(\.title), ["All Hands", "Retro"])
    }
}
