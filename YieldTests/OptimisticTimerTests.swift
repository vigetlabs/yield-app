import XCTest
@testable import Yield

/// Covers the optimistic timer mutations on `TimeComparisonViewModel`:
///
/// - `optimisticallyStartEntry(_:)` — flip the named entry to running,
///    flip every other entry off, mark the owning project tracking.
/// - `optimisticallyStopEntry(_:)` — flip a single entry off and
///    recompute the project's `isTracking` from its remaining entries.
///
/// These helpers run in front of the Harvest API round-trip so the UI
/// flips immediately. The next refresh reconciles the truth.
@MainActor
final class OptimisticTimerTests: XCTestCase {

    // MARK: - Fixtures

    private func entry(id: Int, isRunning: Bool, taskId: Int = 100) -> TimeEntryInfo {
        TimeEntryInfo(
            id: id,
            harvestProjectId: 500,
            taskId: taskId,
            taskName: "Task",
            hours: 1.0,
            date: "2026-05-06",
            isRunning: isRunning,
            notes: nil
        )
    }

    private func project(
        id: String,
        name: String = "Project",
        isTracking: Bool,
        entries: [TimeEntryInfo]
    ) -> ProjectStatus {
        ProjectStatus(
            id: id,
            clientName: nil,
            projectName: name,
            bookedHours: 8.0,
            loggedHours: 4.0,
            todayHours: 4.0,
            isTracking: isTracking,
            harvestProjectId: 500,
            todayEntryId: nil,
            lastTaskId: nil,
            timeEntries: entries,
            forecastNotes: nil
        )
    }

    private func makeVM() -> TimeComparisonViewModel { TimeComparisonViewModel() }

    // MARK: - Stop

    func test_stop_flagsEntryNotRunningAndClearsTracking_whenLastRunning() {
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: true, entries: [entry(id: 1, isRunning: true)]),
        ])

        vm.optimisticallyStopEntry(1)

        XCTAssertFalse(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertFalse(vm.projectStatuses[0].isTracking)
        XCTAssertNil(vm.trackingProject)
    }

    func test_stop_keepsTracking_whenAnotherEntryStillRunning() {
        // Edge case: two entries running on the same project (shouldn't
        // happen on Harvest's side but the helper must not collapse the
        // project's tracking flag while one is still alive).
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: true, entries: [
                entry(id: 1, isRunning: true),
                entry(id: 2, isRunning: true),
            ]),
        ])

        vm.optimisticallyStopEntry(1)

        XCTAssertFalse(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertTrue(vm.projectStatuses[0].timeEntries[1].isRunning)
        XCTAssertTrue(vm.projectStatuses[0].isTracking)
    }

    func test_stop_unknownEntryId_isNoOp() {
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: true, entries: [entry(id: 1, isRunning: true)]),
        ])

        vm.optimisticallyStopEntry(99)

        XCTAssertTrue(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertTrue(vm.projectStatuses[0].isTracking)
    }

    // MARK: - Start

    func test_start_flipsTargetEntryRunningAndMarksProjectTracking() {
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: false, entries: [entry(id: 1, isRunning: false)]),
        ])

        vm.optimisticallyStartEntry(1)

        XCTAssertTrue(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertTrue(vm.projectStatuses[0].isTracking)
        XCTAssertEqual(vm.trackingEntry?.id, 1)
    }

    func test_start_stopsAnyOtherRunningEntryOnSameProject() {
        // Starting a different entry on a project should atomically stop
        // whatever was previously running there — Harvest only allows
        // one running timer at a time.
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: true, entries: [
                entry(id: 1, isRunning: true),
                entry(id: 2, isRunning: false),
            ]),
        ])

        vm.optimisticallyStartEntry(2)

        XCTAssertFalse(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertTrue(vm.projectStatuses[0].timeEntries[1].isRunning)
        XCTAssertTrue(vm.projectStatuses[0].isTracking)
    }

    func test_start_stopsRunningEntryOnDifferentProject() {
        // Starting a timer on Project B must stop any running timer on
        // Project A — same single-timer invariant, across projects.
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", name: "A", isTracking: true, entries: [entry(id: 1, isRunning: true)]),
            project(id: "p2", name: "B", isTracking: false, entries: [entry(id: 2, isRunning: false)]),
        ])

        vm.optimisticallyStartEntry(2)

        XCTAssertFalse(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertFalse(vm.projectStatuses[0].isTracking)
        XCTAssertTrue(vm.projectStatuses[1].timeEntries[0].isRunning)
        XCTAssertTrue(vm.projectStatuses[1].isTracking)
    }

    func test_start_unknownEntryId_stopsAllEntries() {
        // Documenting actual behavior: starting an unknown ID flips
        // every entry off (because none match the "shouldRun" comparison)
        // — calling code is expected to use a known ID. The intent of
        // this test is to lock in the behavior so a future refactor
        // can't silently change it.
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: true, entries: [entry(id: 1, isRunning: true)]),
        ])

        vm.optimisticallyStartEntry(99)

        XCTAssertFalse(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertFalse(vm.projectStatuses[0].isTracking)
    }

    // MARK: - Round-trip start → stop

    func test_startThenStop_returnsProjectToIdleState() {
        let vm = makeVM()
        vm._setStateForTesting(projectStatuses: [
            project(id: "p1", isTracking: false, entries: [entry(id: 1, isRunning: false)]),
        ])

        vm.optimisticallyStartEntry(1)
        XCTAssertTrue(vm.projectStatuses[0].isTracking)

        vm.optimisticallyStopEntry(1)
        XCTAssertFalse(vm.projectStatuses[0].timeEntries[0].isRunning)
        XCTAssertFalse(vm.projectStatuses[0].isTracking)
    }
}
