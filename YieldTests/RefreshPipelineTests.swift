import XCTest
@testable import Yield

/// Covers `TimeComparisonViewModel.applyRefreshedData(...)` — the pure
/// merge step that turns Harvest entries + Forecast bookings into the
/// `projectStatuses` array the UI binds to.
///
/// `applyRefreshedData` is the heart of every refresh path (hard, soft,
/// background tick). Driving it directly with fixtures lets us assert
/// the merge contract without touching the network: which projects show
/// up, in what order, with what totals, and with the tracking flags
/// pointing at the right places.
@MainActor
final class RefreshPipelineTests: XCTestCase {

    // MARK: - Fixture helpers

    /// Today's date as Harvest formats it. Tests that exercise
    /// "today" need the spent_date to match what the view model
    /// reads from `Date()` so the today-by-project aggregation
    /// kicks in.
    private var todayString: String {
        DateHelpers.dateFormatter.string(from: Date())
    }

    /// Build a Harvest time entry with sane defaults — tests override
    /// only the fields they exercise.
    private func entry(
        id: Int,
        projectId: Int,
        projectName: String = "Project",
        clientName: String? = nil,
        hours: Double,
        spentDate: String? = nil,
        isRunning: Bool = false,
        taskId: Int = 100,
        taskName: String = "Task"
    ) -> HarvestTimeEntry {
        HarvestTimeEntry(
            id: id,
            hours: hours,
            spentDate: spentDate ?? todayString,
            isRunning: isRunning,
            updatedAt: "2026-05-06T00:00:00Z",
            notes: nil,
            isLocked: nil,
            approvalStatus: nil,
            timerStartedAt: nil,
            project: HarvestProjectRef(id: projectId, name: projectName, code: nil),
            client: clientName.map { HarvestClientRef(id: 1, name: $0) },
            task: nil,
            taskAssignment: HarvestTaskAssignmentRef(
                id: 999,
                task: HarvestTaskRef(id: taskId, name: taskName)
            )
        )
    }

    private func forecastProject(
        id: Int,
        name: String,
        harvestId: Int?,
        clientId: Int? = nil
    ) -> ForecastProject {
        ForecastProject(
            id: id,
            name: name,
            code: nil,
            clientId: clientId,
            harvestId: harvestId,
            archived: false
        )
    }

    /// Build a fresh view model. Each test gets its own so internal
    /// caches don't bleed between cases.
    private func makeVM() -> TimeComparisonViewModel {
        TimeComparisonViewModel()
    }

    // MARK: - Empty-input baseline

    func test_apply_emptyInputs_clearsAllAggregates() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 0)
        XCTAssertEqual(vm.totalLogged, 0, accuracy: 0.001)
        XCTAssertEqual(vm.totalBooked, 0, accuracy: 0.001)
        XCTAssertEqual(vm.totalUnbookedLogged, 0, accuracy: 0.001)
        XCTAssertEqual(vm.totalTodayLogged, 0, accuracy: 0.001)
        // Daily-hours array is always 7 entries (Mon–Sun) regardless
        // of input — it's the chart's X-axis backbone.
        XCTAssertEqual(vm.dailyHours.count, 7)
        XCTAssertNotNil(vm.lastUpdated)
        XCTAssertNotEqual(vm.weekLabel, "")
    }

    // MARK: - Booked + logged merge

    func test_apply_forecastedProjectGetsLoggedFromHarvest() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [
                entry(id: 1, projectId: 500, hours: 3.0),
                entry(id: 2, projectId: 500, hours: 1.5),
            ],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme Site", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 1)
        let project = vm.projectStatuses[0]
        XCTAssertEqual(project.id, "forecast-10")
        XCTAssertEqual(project.bookedHours, 8.0, accuracy: 0.001)
        XCTAssertEqual(project.loggedHours, 4.5, accuracy: 0.001)
        XCTAssertEqual(project.harvestProjectId, 500)
        XCTAssertEqual(vm.totalLogged, 4.5, accuracy: 0.001)
        XCTAssertEqual(vm.totalBooked, 8.0, accuracy: 0.001)
    }

    func test_apply_harvestOnlyProject_appearsAsUnbooked() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 700, projectName: "Internal", hours: 2.0)],
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 1)
        let project = vm.projectStatuses[0]
        XCTAssertEqual(project.id, "harvest-700")
        XCTAssertEqual(project.bookedHours, 0)
        XCTAssertEqual(project.loggedHours, 2.0, accuracy: 0.001)
        XCTAssertEqual(vm.totalUnbookedLogged, 2.0, accuracy: 0.001)
        XCTAssertEqual(vm.totalLogged, 0, accuracy: 0.001) // booked-only sum
    }

    func test_apply_unmatchedForecast_stillAppearsWithZeroLogged() {
        // A forecasted project with no Harvest link (proposal stage) —
        // shows the booking but can't accumulate logged time.
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [42: 5.0],
            projectMap: [42: forecastProject(id: 42, name: "Pitch", harvestId: nil)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 1)
        XCTAssertEqual(vm.projectStatuses[0].bookedHours, 5.0, accuracy: 0.001)
        XCTAssertEqual(vm.projectStatuses[0].loggedHours, 0)
        XCTAssertNil(vm.projectStatuses[0].harvestProjectId)
    }

    // MARK: - Tracking flag

    func test_apply_runningEntry_marksOwningProjectTracking() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [
                entry(id: 1, projectId: 500, hours: 1.0),
                entry(id: 2, projectId: 500, hours: 0.5, isRunning: true),
            ],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 1)
        XCTAssertTrue(vm.projectStatuses[0].isTracking)
        XCTAssertNotNil(vm.trackingProject)
        XCTAssertEqual(vm.trackingEntry?.id, 2)
    }

    func test_apply_noRunningEntries_noTrackingProject() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 500, hours: 1.0)],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertNil(vm.trackingProject)
        XCTAssertNil(vm.trackingEntry)
        XCTAssertFalse(vm.projectStatuses[0].isTracking)
    }

    // MARK: - Today aggregation

    func test_apply_todayHours_onlyCountsTodaysEntries() {
        let vm = makeVM()
        let today = todayString
        vm.applyRefreshedData(
            entries: [
                entry(id: 1, projectId: 500, hours: 4.0, spentDate: today),
                entry(id: 2, projectId: 500, hours: 2.0, spentDate: "2025-01-01"),
            ],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses[0].todayHours, 4.0, accuracy: 0.001)
        XCTAssertEqual(vm.projectStatuses[0].loggedHours, 6.0, accuracy: 0.001)
        XCTAssertEqual(vm.totalTodayLogged, 4.0, accuracy: 0.001)
    }

    // MARK: - Sort order

    func test_apply_sortsAlphabeticallyByProjectName_whenNoClient() {
        // The merge step does a stable alphabetical sort by client then
        // project name (booked vs. unbooked doesn't influence sort —
        // that's a row-rendering concern, not a list-order one). Lock
        // the contract so a future refactor can't silently shuffle
        // ordering between refreshes.
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [
                entry(id: 1, projectId: 700, projectName: "Charlie", hours: 1.0),
                entry(id: 2, projectId: 800, projectName: "Alpha", hours: 1.0),
            ],
            bookedByForecastProject: [10: 5.0],
            projectMap: [10: forecastProject(id: 10, name: "Bravo", harvestId: 999)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 3)
        XCTAssertEqual(vm.projectStatuses.map(\.projectName), ["Alpha", "Bravo", "Charlie"])
    }

    func test_apply_sortsByClientThenProject() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [
                entry(id: 1, projectId: 700, projectName: "Beta", clientName: "Acme", hours: 1.0),
                entry(id: 2, projectId: 800, projectName: "Alpha", clientName: "Zenith", hours: 1.0),
                entry(id: 3, projectId: 900, projectName: "Alpha", clientName: "Acme", hours: 1.0),
            ],
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses.count, 3)
        // Acme/Alpha → Acme/Beta → Zenith/Alpha
        XCTAssertEqual(vm.projectStatuses[0].clientName, "Acme")
        XCTAssertEqual(vm.projectStatuses[0].projectName, "Alpha")
        XCTAssertEqual(vm.projectStatuses[1].clientName, "Acme")
        XCTAssertEqual(vm.projectStatuses[1].projectName, "Beta")
        XCTAssertEqual(vm.projectStatuses[2].clientName, "Zenith")
    }

    // MARK: - Daily breakdown

    func test_apply_dailyHours_sumsEntriesByDate() {
        let vm = makeVM()
        let weekStart = DateHelpers.currentWeekBounds().start
        let calendar = Calendar.current
        let monday = DateHelpers.dateFormatter.string(from: weekStart)
        let tuesday = DateHelpers.dateFormatter.string(
            from: calendar.date(byAdding: .day, value: 1, to: weekStart)!
        )

        vm.applyRefreshedData(
            entries: [
                entry(id: 1, projectId: 500, hours: 3.0, spentDate: monday),
                entry(id: 2, projectId: 500, hours: 2.0, spentDate: monday),
                entry(id: 3, projectId: 500, hours: 1.5, spentDate: tuesday),
            ],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.dailyHours.count, 7)
        XCTAssertEqual(vm.dailyHours[0].dayLabel, "Mon")
        XCTAssertEqual(vm.dailyHours[0].hours, 5.0, accuracy: 0.001)
        XCTAssertEqual(vm.dailyHours[1].dayLabel, "Tue")
        XCTAssertEqual(vm.dailyHours[1].hours, 1.5, accuracy: 0.001)
        XCTAssertEqual(vm.dailyHours[2].hours, 0)
    }

    // MARK: - Forecast notes pass-through

    func test_apply_forecastNotes_attachedToMatchingProject() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [10: 5.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [10: "Watch scope creep"]
        )

        XCTAssertEqual(vm.projectStatuses[0].forecastNotes, "Watch scope creep")
    }

    // MARK: - Client name resolution

    func test_apply_clientName_resolvedFromForecastClientMap() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 500, hours: 1.0)],
            bookedByForecastProject: [10: 5.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme Site", harvestId: 500, clientId: 77)],
            clientMap: [77: ForecastClient(id: 77, name: "Acme Inc")],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses[0].clientName, "Acme Inc")
        XCTAssertEqual(vm.projectStatuses[0].qualifiedName, "Acme Inc — Acme Site")
    }

    func test_apply_harvestOnlyProject_clientNameFromHarvestEntry() {
        // Logged-only projects have no Forecast project to read the
        // client from, so the merge must fall back to the client name
        // on the Harvest entry itself.
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 700, projectName: "Internal", clientName: "Acme", hours: 2.0)],
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.projectStatuses[0].clientName, "Acme")
    }

    // MARK: - Time Off pass-through

    func test_apply_timeOffBlock_storedOnViewModel() {
        let vm = makeVM()
        let block = TimeComparisonViewModel.TimeOffBlock(
            totalHours: 8.0,
            dayLabels: ["Wed"],
            fullDayLabels: ["Wed"]
        )
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: block,
            notesByForecastProject: [:]
        )

        XCTAssertEqual(vm.timeOffBlock?.totalHours, 8.0)
        XCTAssertEqual(vm.timeOffBlock?.dayLabels, ["Wed"])
    }

    // MARK: - Status thresholds (integration with ProjectStatus.status)

    func test_apply_projectOverBudget_hasOverStatus() {
        let vm = makeVM()
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 500, hours: 12.0)],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(vm.projectStatuses[0].status, .over)
    }

    // MARK: - Harvest link state (booked-but-unassigned detection)

    /// Look up a forecast-derived status by its Forecast project id.
    private func forecastStatus(_ vm: TimeComparisonViewModel, _ forecastId: Int) -> ProjectStatus? {
        vm.projectStatuses.first { $0.id == "forecast-\(forecastId)" }
    }

    func test_linkState_prospective_whenNoHarvestId() {
        let vm = makeVM()
        vm.assignedHarvestProjectIds = [500]
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Proposal", harvestId: nil)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(forecastStatus(vm, 10)?.harvestLinkState, .prospective)
    }

    func test_linkState_linked_whenUserIsAssigned() {
        let vm = makeVM()
        vm.assignedHarvestProjectIds = [500]
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [10: 8.0],
            projectMap: [10: forecastProject(id: 10, name: "Acme", harvestId: 500)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(forecastStatus(vm, 10)?.harvestLinkState, .linked)
    }

    func test_linkState_unassigned_whenLinkedButNotAMember() {
        // Booked on harvest project 600, but the user is only on 500.
        let vm = makeVM()
        vm.assignedHarvestProjectIds = [500]
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [11: 4.0],
            projectMap: [11: forecastProject(id: 11, name: "NotAMember", harvestId: 600)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(forecastStatus(vm, 11)?.harvestLinkState, .unassigned)
    }

    func test_linkState_failsSafeToLinked_whenMembershipUnknown() {
        // No assignment set fetched yet → never false-flag.
        let vm = makeVM()
        vm.assignedHarvestProjectIds = nil
        vm.applyRefreshedData(
            entries: [],
            bookedByForecastProject: [11: 4.0],
            projectMap: [11: forecastProject(id: 11, name: "Unknown", harvestId: 600)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(forecastStatus(vm, 11)?.harvestLinkState, .linked)
    }

    func test_linkState_loggedTimeProvesMembership_evenIfNotInSet() {
        // The assignment fetch can lag, but logged time is proof the
        // user can track against the project — don't flag it.
        let vm = makeVM()
        vm.assignedHarvestProjectIds = [500]
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 600, hours: 2.0)],
            bookedByForecastProject: [11: 4.0],
            projectMap: [11: forecastProject(id: 11, name: "HasLoggedTime", harvestId: 600)],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(forecastStatus(vm, 11)?.harvestLinkState, .linked)
    }

    func test_linkState_harvestOnlyProject_isLinked() {
        // Logged-but-not-booked projects are always linked — you logged
        // time, so you're a member.
        let vm = makeVM()
        vm.assignedHarvestProjectIds = []
        vm.applyRefreshedData(
            entries: [entry(id: 1, projectId: 700, hours: 3.0)],
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        XCTAssertEqual(vm.projectStatuses.first { $0.id == "harvest-700" }?.harvestLinkState, .linked)
    }
}
