import XCTest
@testable import Yield

/// The weekly chart's series plan: which project takes which colour
/// slot, and which fold into "Other".
final class ChartSeriesPlanTests: XCTestCase {

    private func point(_ projectId: Int, _ name: String, _ day: String, _ hours: Double) -> TimeComparisonViewModel.ChartPoint {
        .init(id: "\(projectId)-\(day)", projectId: projectId, projectName: name,
              date: "2026-11-\(day)", dayLabel: day, hours: hours)
    }

    func test_projects_areOrderedByTheWeeksHours_mostFirst() {
        let plan = ChartSeriesPlan(points: [
            point(1, "Acme", "16", 2), point(1, "Acme", "17", 1),
            point(2, "Northwind", "16", 6), point(2, "Northwind", "17", 5),
            point(3, "Bluebird", "16", 4),
        ], slotCount: 10)
        XCTAssertEqual(plan.projects.map(\.name), ["Northwind", "Bluebird", "Acme"])
        XCTAssertTrue(plan.folded.isEmpty)
    }

    func test_alphabeticalFirst_noLongerTakesTheFirstSlot_byDefault() {
        // The complaint: the project that sorts first was always slot 1.
        let plan = ChartSeriesPlan(points: [
            point(1, "Aardvark Co", "16", 1),
            point(2, "Zephyr", "16", 30),
        ], slotCount: 10)
        XCTAssertEqual(plan.projects.first?.name, "Zephyr")
    }

    func test_ties_goByName_thenId() {
        let plan = ChartSeriesPlan(points: [
            point(3, "Beta", "16", 2), point(1, "alpha", "16", 2), point(2, "Alpha", "16", 2),
        ], slotCount: 10)
        XCTAssertEqual(plan.projects.map(\.id), [1, 2, 3])
    }

    func test_pastTheLastSlot_projectsFoldIntoOther() {
        let points = (1...4).map { point($0, "P\($0)", "16", Double(10 - $0)) }
        let plan = ChartSeriesPlan(points: points, slotCount: 2)
        XCTAssertEqual(plan.projects.map(\.id), [1, 2, ChartSeriesPlan.otherId])
        XCTAssertEqual(plan.projects.last?.name, "Other")
        XCTAssertEqual(plan.folded, [3, 4])
    }

    func test_exactlyAsManyProjectsAsSlots_hasNoOther() {
        let points = (1...3).map { point($0, "P\($0)", "16", 1) }
        let plan = ChartSeriesPlan(points: points, slotCount: 3)
        XCTAssertEqual(plan.projects.count, 3)
        XCTAssertFalse(plan.projects.contains { $0.id == ChartSeriesPlan.otherId })
    }

    func test_foldedPoints_moveOntoOther_andKeepTheirHours() {
        let points = [point(1, "Big", "16", 8), point(2, "Small", "16", 1), point(2, "Small", "17", 2)]
        let plan = ChartSeriesPlan(points: points, slotCount: 1)
        let drawn = plan.points(points)
        XCTAssertEqual(drawn.filter { $0.projectId == ChartSeriesPlan.otherId }.map(\.hours), [1, 2])
        XCTAssertEqual(drawn.filter { $0.projectId == ChartSeriesPlan.otherId }.map(\.projectName), ["Other", "Other"])
        XCTAssertEqual(drawn.first { $0.projectId == 1 }?.hours, 8)
    }

    func test_points_comeBackInSlotOrder_soTheStackFollowsTheSlots() {
        // Alphabetical input; the stack must follow the hours order.
        let points = [
            point(1, "Acme", "16", 1), point(1, "Acme", "17", 1),
            point(2, "Bluebird", "16", 9), point(2, "Bluebird", "17", 9),
            point(3, "Cobalt", "16", 4), point(3, "Cobalt", "17", 4),
        ]
        let plan = ChartSeriesPlan(points: points, slotCount: 10)
        XCTAssertEqual(plan.points(points).map(\.id), ["2-16", "2-17", "3-16", "3-17", "1-16", "1-17"])
    }

    func test_otherIsStackedLast() {
        let points = [point(1, "Tiny", "16", 1), point(2, "Big", "16", 9), point(3, "Mid", "16", 5)]
        let plan = ChartSeriesPlan(points: points, slotCount: 1)
        XCTAssertEqual(plan.points(points).map(\.projectId), [2, ChartSeriesPlan.otherId, ChartSeriesPlan.otherId])
    }

    func test_projects_carryTheirLabelClientAndWeeklyHours() {
        var a = point(1, "[ACME-1] Website", "16", 2); a.projectLabel = "Website"; a.clientName = "Acme"
        var b = point(1, "[ACME-1] Website", "17", 1.5); b.projectLabel = "Website"; b.clientName = "Acme"
        let plan = ChartSeriesPlan(points: [a, b], slotCount: 10)
        XCTAssertEqual(plan.projects.first?.label, "Website")
        XCTAssertEqual(plan.projects.first?.client, "Acme")
        XCTAssertEqual(plan.projects.first?.hours, 3.5)
    }

    func test_aProjectWithoutALabel_isCalledByItsName() {
        let plan = ChartSeriesPlan(points: [point(1, "Website", "16", 1)], slotCount: 10)
        XCTAssertEqual(plan.projects.first?.label, "Website")
        XCTAssertNil(plan.projects.first?.client)
    }

    func test_other_saysHowManyProjects_andTotalsTheirHours() {
        let points = [point(1, "Big", "16", 8), point(2, "Small", "16", 1), point(3, "Smaller", "16", 0.5)]
        let plan = ChartSeriesPlan(points: points, slotCount: 1)
        XCTAssertEqual(plan.projects.last?.client, "2 projects")
        XCTAssertEqual(plan.projects.last?.hours, 1.5)
    }

    func test_edges_runUpTheStack_dayByDay() {
        let points = [
            point(1, "Big", "16", 4), point(1, "Big", "17", 2),
            point(2, "Mid", "16", 3), point(2, "Mid", "17", 0),
            point(3, "Small", "16", 1), point(3, "Small", "17", 1),
        ]
        let edges = ChartSeriesPlan.edges(points)
        XCTAssertEqual(edges.filter { $0.dayLabel == "16" }.map(\.top), [4, 7, 8])
        // A band with no hours that day sits on the one beneath it.
        XCTAssertEqual(edges.filter { $0.dayLabel == "17" }.map(\.top), [2, 2, 3])
    }

    func test_noPoints_noProjects() {
        let plan = ChartSeriesPlan(points: [], slotCount: 10)
        XCTAssertTrue(plan.projects.isEmpty)
    }

    func test_bothPalettes_haveEightSlots() {
        XCTAssertEqual(YieldChartColors.editorial.count, 8)
        XCTAssertEqual(YieldChartColors.system.count, 8)
    }
}

