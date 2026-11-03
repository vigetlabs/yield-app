import XCTest
@testable import Yield

/// `ProjectGrouping.grouped` — the grouped layout's one piece of logic.
final class ProjectGroupingTests: XCTestCase {

    private func status(_ name: String, client: String?) -> ProjectStatus {
        ProjectStatus(
            id: "\(client ?? "-")/\(name)", clientName: client, projectName: name, projectCode: nil,
            bookedHours: 1, loggedHours: 0, todayHours: 0, isTracking: false,
            harvestProjectId: 1, todayEntryId: nil, lastTaskId: nil, timeEntries: [], forecastNotes: nil
        )
    }

    func test_groupsConsecutiveProjectsByClient() {
        let groups = ProjectGrouping.grouped([
            status("BOATUS", client: "GEICO"),
            status("Dev Extension", client: "GEICO"),
            status("Prof Dev", client: "Viget Labs"),
        ])
        XCTAssertEqual(groups.map(\.client), ["GEICO", "Viget Labs"])
        XCTAssertEqual(groups[0].projects.map(\.projectName), ["BOATUS", "Dev Extension"])
        XCTAssertEqual(groups[1].projects.map(\.projectName), ["Prof Dev"])
    }

    /// Grouping must not re-sort: the view model owns order. A group
    /// sits where its first project sat.
    func test_preservesInputOrder() {
        let groups = ProjectGrouping.grouped([
            status("Zed", client: "Zeta"),
            status("Alpha", client: "Acme"),
        ])
        XCTAssertEqual(groups.map(\.client), ["Zeta", "Acme"])
    }

    /// Non-adjacent projects for the same client still land in one
    /// group, at the position of the first.
    func test_mergesNonAdjacentProjectsForOneClient() {
        let groups = ProjectGrouping.grouped([
            status("A", client: "Acme"),
            status("B", client: "Beta"),
            status("C", client: "Acme"),
        ])
        XCTAssertEqual(groups.map(\.client), ["Acme", "Beta"])
        XCTAssertEqual(groups[0].projects.map(\.projectName), ["A", "C"])
    }

    func test_missingClientGetsTheFallbackLabel() {
        let groups = ProjectGrouping.grouped([status("Orphan", client: nil)])
        XCTAssertEqual(groups.map(\.client), [ProjectGrouping.noClientLabel])
    }

    func test_emptyInputGivesNoGroups() {
        XCTAssertTrue(ProjectGrouping.grouped([]).isEmpty)
    }
}
