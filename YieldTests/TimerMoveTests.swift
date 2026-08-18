import XCTest
@testable import Yield

/// Covers the pure half of the timer-move flow (banner right-click →
/// "Move Time…"): capturing the source into `PendingTimerMove` and the
/// live available-hours ceiling. The commit choreography talks to the
/// Harvest API and sits outside the unit-test boundary, same as the
/// idle-move commits.
@MainActor
final class TimerMoveTests: XCTestCase {

    // MARK: - Fixtures

    private func entry(
        id: Int,
        projectId: Int = 500,
        taskId: Int = 100,
        hours: Double,
        isRunning: Bool
    ) -> TimeEntryInfo {
        TimeEntryInfo(
            id: id,
            harvestProjectId: projectId,
            taskId: taskId,
            taskName: "Task \(taskId)",
            hours: hours,
            date: DateHelpers.dateFormatter.string(from: Date()),
            isRunning: isRunning,
            notes: nil,
            timerStartedAt: nil
        )
    }

    private func project(
        id: String,
        harvestId: Int = 500,
        isTracking: Bool,
        entries: [TimeEntryInfo]
    ) -> ProjectStatus {
        ProjectStatus(
            id: id,
            clientName: "Client",
            projectName: "Project",
            projectCode: nil,
            bookedHours: 8.0,
            loggedHours: entries.reduce(0) { $0 + $1.hours },
            todayHours: 0,
            isTracking: isTracking,
            harvestProjectId: harvestId,
            todayEntryId: entries.first?.id,
            lastTaskId: nil,
            timeEntries: entries,
            forecastNotes: nil
        )
    }

    // MARK: - Capture

    func test_startTimerMove_capturesRunningSource() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p", harvestId: 500, isTracking: true,
                    entries: [entry(id: 1, taskId: 100, hours: 1.5, isRunning: true)]),
        ])

        vm.startTimerMove()

        XCTAssertEqual(vm.pendingTimerMove?.sourceEntryId, 1)
        XCTAssertEqual(vm.pendingTimerMove?.sourceProjectId, 500)
        XCTAssertEqual(vm.pendingTimerMove?.sourceTaskId, 100)
        XCTAssertEqual(vm.pendingTimerMove?.sourceWasRunning, true)
    }

    func test_startTimerMove_capturesPausedSource() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [
                project(id: "p", harvestId: 500, isTracking: false,
                        entries: [entry(id: 7, taskId: 100, hours: 2.0, isRunning: false)]),
            ],
            pausedState: TimeComparisonViewModel.PausedTimerState(
                clientName: "Client",
                projectName: "Project",
                projectCode: nil,
                taskName: "Task 100",
                entryId: 7,
                frozenHours: 2.0
            )
        )

        vm.startTimerMove()

        XCTAssertEqual(vm.pendingTimerMove?.sourceEntryId, 7)
        XCTAssertEqual(vm.pendingTimerMove?.sourceProjectId, 500)
        XCTAssertEqual(vm.pendingTimerMove?.sourceTaskId, 100)
        XCTAssertEqual(vm.pendingTimerMove?.sourceWasRunning, false)
    }

    func test_startTimerMove_withNoTimer_capturesNothing() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p", isTracking: false,
                    entries: [entry(id: 1, hours: 1.0, isRunning: false)]),
        ])

        vm.startTimerMove()

        XCTAssertNil(vm.pendingTimerMove)
    }

    func test_timerMoveCancel_clearsPendingMove() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p", isTracking: true,
                    entries: [entry(id: 1, hours: 1.0, isRunning: true)]),
        ])
        vm.startTimerMove()
        XCTAssertNotNil(vm.pendingTimerMove)

        vm.timerMoveCancel()

        XCTAssertNil(vm.pendingTimerMove)
    }

    // MARK: - Available hours (the move ceiling)

    func test_availableHours_runningSource_includesElapsedOffset() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [
                project(id: "p", isTracking: true,
                        entries: [entry(id: 1, hours: 1.0, isRunning: true)]),
            ],
            elapsedOffset: 0.25
        )
        vm.startTimerMove()
        guard let move = vm.pendingTimerMove else { return XCTFail("no pending move") }

        XCTAssertEqual(vm.timerMoveAvailableHours(move), 1.25, accuracy: 0.001)
    }

    func test_availableHours_stoppedSource_excludesElapsedOffset() {
        // A paused source isn't ticking — the local elapsed offset
        // (which belongs to whatever ran last) must not inflate it.
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [
                project(id: "p", isTracking: false,
                        entries: [entry(id: 7, hours: 2.0, isRunning: false)]),
            ],
            elapsedOffset: 0.5,
            pausedState: TimeComparisonViewModel.PausedTimerState(
                clientName: nil,
                projectName: "Project",
                projectCode: nil,
                taskName: "Task",
                entryId: 7,
                frozenHours: 2.0
            )
        )
        vm.startTimerMove()
        guard let move = vm.pendingTimerMove else { return XCTFail("no pending move") }

        XCTAssertEqual(vm.timerMoveAvailableHours(move), 2.0, accuracy: 0.001)
    }

    func test_availableHours_fallsBackToFrozenHours_whenEntryMissing() {
        // Paused entry no longer present in projectStatuses (e.g. a
        // refresh raced the pause) — the frozen banner total is the
        // number the user is looking at, so it's the ceiling.
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [],
            pausedState: TimeComparisonViewModel.PausedTimerState(
                clientName: nil,
                projectName: "Project",
                projectCode: nil,
                taskName: "Task",
                entryId: 7,
                frozenHours: 1.75
            )
        )
        vm.startTimerMove()
        guard let move = vm.pendingTimerMove else { return XCTFail("no pending move") }

        XCTAssertEqual(vm.timerMoveAvailableHours(move), 1.75, accuracy: 0.001)
    }
}
