import XCTest
@testable import Yield

/// `startTimerMove(from:)` — the drawer's Move Time entry point. It
/// must build the same `PendingTimerMove` the banner builds, from any
/// of today's entries, running or not.
@MainActor
final class EntryMoveTests: XCTestCase {

    private func entry(id: Int, projectId: Int, hours: Double, isRunning: Bool, task: String) -> HarvestTimeEntry {
        HarvestTimeEntry(
            id: id, hours: hours, spentDate: DateHelpers.dateFormatter.string(from: Date()), isRunning: isRunning,
            updatedAt: "2026-11-03T00:00:00Z", notes: nil, isLocked: nil, approvalStatus: nil,
            timerStartedAt: isRunning ? "2026-11-03T00:00:00Z" : nil,
            project: HarvestProjectRef(id: projectId, name: "BOATUS.com Redesign", code: nil),
            client: HarvestClientRef(id: 1, name: "GEICO"),
            task: nil,
            taskAssignment: HarvestTaskAssignmentRef(id: 900 + id, task: HarvestTaskRef(id: 100 + id, name: task))
        )
    }

    private func makeVM() -> TimeComparisonViewModel {
        let vm = TimeComparisonViewModel()
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 7, hours: 1.5, isRunning: true, task: "FED"),
                      entry(id: 2, projectId: 7, hours: 0.75, isRunning: false, task: "Design")],
            bookedByForecastProject: [:], projectMap: [:], clientMap: [:], timeOffBlock: nil, notesByForecastProject: [:]
        )
        return vm
    }

    func test_fromStoppedEntry_buildsNonRunningMove() {
        let vm = makeVM()
        let stopped = vm.projectStatuses.flatMap(\.timeEntries).first { $0.id == 2 }!
        vm.startTimerMove(from: stopped)

        let move = vm.pendingTimerMove
        XCTAssertEqual(move?.sourceEntryId, 2)
        XCTAssertEqual(move?.sourceProjectId, 7)
        XCTAssertEqual(move?.sourceTaskId, 102)
        XCTAssertEqual(move?.sourceTaskName, "Design")
        XCTAssertEqual(move?.sourceProjectName, "BOATUS.com Redesign")
        XCTAssertEqual(move?.sourceWasRunning, false)
    }

    func test_fromRunningEntry_matchesBannerMove() {
        let vm = makeVM()
        let running = vm.projectStatuses.flatMap(\.timeEntries).first { $0.id == 1 }!
        vm.startTimerMove(from: running)
        let fromEntry = vm.pendingTimerMove

        vm.timerMoveCancel()
        vm.startTimerMove()  // the banner's path
        let fromBanner = vm.pendingTimerMove

        XCTAssertEqual(fromEntry?.sourceEntryId, fromBanner?.sourceEntryId)
        XCTAssertEqual(fromEntry?.sourceTaskId, fromBanner?.sourceTaskId)
        XCTAssertEqual(fromEntry?.sourceProjectName, fromBanner?.sourceProjectName)
        XCTAssertEqual(fromEntry?.sourceWasRunning, true)
    }

    /// The ceiling on a move from a stopped entry is that entry's hours
    /// — no live offset, since nothing is ticking.
    func test_availableHours_forStoppedEntry_isItsHours() {
        let vm = makeVM()
        let stopped = vm.projectStatuses.flatMap(\.timeEntries).first { $0.id == 2 }!
        vm.startTimerMove(from: stopped)
        XCTAssertEqual(vm.timerMoveAvailableHours(vm.pendingTimerMove!), 0.75, accuracy: 0.0001)
    }
}
