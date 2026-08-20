import XCTest
@testable import Yield

/// Covers `detectExternalTimerChange`'s bookkeeping rules — in
/// particular that an externally-made timer switch voids a pending
/// idle alert instead of leaving it stuck over a timer that's no
/// longer running (the Harvest-app-alongside-Yield report). The
/// notification itself is XCTest-suppressed like the other senders.
@MainActor
final class ExternalTimerChangeTests: XCTestCase {

    private func entry(id: Int, projectId: Int = 500, taskId: Int = 100, isRunning: Bool = true) -> TimeEntryInfo {
        TimeEntryInfo(
            id: id,
            harvestProjectId: projectId,
            taskId: taskId,
            taskName: "Task",
            hours: 1.0,
            date: DateHelpers.dateFormatter.string(from: Date(timeIntervalSince1970: 1_755_000_000)),
            isRunning: isRunning,
            notes: nil,
            timerStartedAt: nil
        )
    }

    private func project(entry: TimeEntryInfo, isTracking: Bool = true) -> ProjectStatus {
        ProjectStatus(
            id: "p\(entry.harvestProjectId)",
            clientName: nil,
            projectName: "Project",
            projectCode: nil,
            bookedHours: 8,
            loggedHours: 1,
            todayHours: 1,
            isTracking: isTracking,
            harvestProjectId: entry.harvestProjectId,
            todayEntryId: entry.id,
            lastTaskId: nil,
            timeEntries: [entry],
            forecastNotes: nil
        )
    }

    private func idleAlert(entryId: Int) -> TimeComparisonViewModel.IdleAlertState {
        .init(
            idleStartDate: Date().addingTimeInterval(-600),
            entryId: entryId,
            projectName: "Project",
            hoursAtIdleStart: 1.0
        )
    }

    // MARK: - Idle alert invalidation

    func test_externalSwitch_clearsPendingIdleAlert() {
        // Idle alert references entry 1; a refresh now sees entry 2
        // running (switched via the Harvest app).
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [project(entry: entry(id: 2))],
            hasSeenInitialTrackingState: true,
            lastTrackingEntryId: 1,
            idleAlertState: idleAlert(entryId: 1)
        )
        vm.detectExternalTimerChange()
        XCTAssertNil(vm.idleAlertState)
    }

    func test_externalStop_clearsPendingIdleAlert() {
        // Idle alert references entry 1; a refresh now sees nothing
        // running at all.
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [project(entry: entry(id: 1, isRunning: false), isTracking: false)],
            hasSeenInitialTrackingState: true,
            lastTrackingEntryId: 1,
            idleAlertState: idleAlert(entryId: 1)
        )
        vm.detectExternalTimerChange()
        XCTAssertNil(vm.idleAlertState)
    }

    func test_noChange_keepsIdleAlert() {
        // Same entry still running — the alert's premise holds.
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [project(entry: entry(id: 1))],
            hasSeenInitialTrackingState: true,
            lastTrackingEntryId: 1,
            idleAlertState: idleAlert(entryId: 1)
        )
        vm.detectExternalTimerChange()
        XCTAssertNotNil(vm.idleAlertState)
    }

    func test_userInitiatedChange_keepsIdleAlert() {
        // Suppressed diffs are the user's own mutations — those paths
        // manage the alert themselves, detection must not interfere.
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [project(entry: entry(id: 2))],
            hasSeenInitialTrackingState: true,
            lastTrackingEntryId: 1,
            suppressNextTimerChangeHUD: true,
            idleAlertState: idleAlert(entryId: 1)
        )
        vm.detectExternalTimerChange()
        XCTAssertNotNil(vm.idleAlertState)
    }

    func test_firstRefresh_keepsIdleAlert() {
        // Launch discovery isn't a change.
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [project(entry: entry(id: 2))],
            hasSeenInitialTrackingState: false,
            idleAlertState: idleAlert(entryId: 1)
        )
        vm.detectExternalTimerChange()
        XCTAssertNotNil(vm.idleAlertState)
    }

    // MARK: - Bookkeeping

    func test_detection_updatesLastTrackingEntryId() {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(
            projectStatuses: [project(entry: entry(id: 2))],
            hasSeenInitialTrackingState: true,
            lastTrackingEntryId: 1
        )
        vm.detectExternalTimerChange()

        // A second pass with unchanged state is a no-op (id now 2).
        vm._setStateForTesting(idleAlertState: idleAlert(entryId: 2))
        vm.detectExternalTimerChange()
        XCTAssertNotNil(vm.idleAlertState)
    }
}
