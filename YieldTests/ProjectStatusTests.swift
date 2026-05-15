import XCTest
@testable import Yield

/// Covers the pure computed properties on `ProjectStatus`:
/// - `status` (under / onTrack / over) and its threshold logic
/// - `remainingHours` and `isOver`
/// - `remainingFormatted`
/// - `qualifiedName` (instance and static variants)
/// - `isForecasted`
final class ProjectStatusTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `ProjectStatus` with sane defaults; tests override only
    /// the fields they exercise.
    private func makeProject(
        booked: Double,
        logged: Double,
        client: String? = nil,
        project: String = "Project"
    ) -> ProjectStatus {
        ProjectStatus(
            id: "test-1",
            clientName: client,
            projectName: project,
            projectCode: nil,
            bookedHours: booked,
            loggedHours: logged,
            todayHours: 0,
            isTracking: false,
            harvestProjectId: nil,
            todayEntryId: nil,
            lastTaskId: nil,
            timeEntries: [],
            forecastNotes: nil
        )
    }

    // MARK: - status (threshold = max(booked * 0.1, 0.5))

    func test_status_underWhenWellBelowBooked() {
        // 8h booked, 4h logged → threshold is 0.8h, way under.
        XCTAssertEqual(makeProject(booked: 8, logged: 4).status, .under)
    }

    func test_status_onTrackWithinTenPercent() {
        // 8h booked, 7.5h logged → within 0.8h threshold.
        XCTAssertEqual(makeProject(booked: 8, logged: 7.5).status, .onTrack)
    }

    func test_status_onTrackAtExactBookedHours() {
        XCTAssertEqual(makeProject(booked: 8, logged: 8).status, .onTrack)
    }

    func test_status_overWhenWellAboveBooked() {
        XCTAssertEqual(makeProject(booked: 8, logged: 12).status, .over)
    }

    func test_status_overJustPastTenPercentThreshold() {
        // 8h booked → threshold 0.8h. 8.81h is just past.
        XCTAssertEqual(makeProject(booked: 8, logged: 8.81).status, .over)
    }

    func test_status_underJustBelowTenPercentThreshold() {
        // 8h booked → threshold 0.8h. 7.19h is just under.
        XCTAssertEqual(makeProject(booked: 8, logged: 7.19).status, .under)
    }

    func test_status_minimumThresholdAppliesWhenBookedIsSmall() {
        // 2h booked → 10% would be 0.2h, but the floor is 0.5h.
        // 1.6h logged is within 0.5h, so on-track.
        XCTAssertEqual(makeProject(booked: 2, logged: 1.6).status, .onTrack)
        // 1.4h logged is more than 0.5h under, so under.
        XCTAssertEqual(makeProject(booked: 2, logged: 1.4).status, .under)
    }

    func test_status_minimumThresholdAppliesAboveSmallBooking() {
        // 2h booked, 2.4h logged → within 0.5h, on-track (not over yet).
        XCTAssertEqual(makeProject(booked: 2, logged: 2.4).status, .onTrack)
        // 2.6h logged is past 0.5h → over.
        XCTAssertEqual(makeProject(booked: 2, logged: 2.6).status, .over)
    }

    // MARK: - remainingHours / isOver

    func test_remainingHours_positiveWhenUnder() {
        XCTAssertEqual(makeProject(booked: 8, logged: 3).remainingHours, 5)
    }

    func test_remainingHours_negativeWhenOver() {
        XCTAssertEqual(makeProject(booked: 8, logged: 10).remainingHours, -2)
    }

    func test_remainingHours_zeroWhenExactly() {
        XCTAssertEqual(makeProject(booked: 8, logged: 8).remainingHours, 0)
    }

    func test_isOver_followsRemainingSign() {
        XCTAssertFalse(makeProject(booked: 8, logged: 3).isOver)
        XCTAssertFalse(makeProject(booked: 8, logged: 8).isOver, "exactly at booked is not over")
        XCTAssertTrue(makeProject(booked: 8, logged: 9).isOver)
    }

    // MARK: - remainingFormatted

    func test_remainingFormatted_underReadsRemainingThisWeek() {
        let p = makeProject(booked: 8, logged: 5.5)  // 2.5h remaining
        XCTAssertEqual(p.remainingFormatted, "2h 30m remaining this week")
    }

    func test_remainingFormatted_overReadsOverThisWeek() {
        let p = makeProject(booked: 8, logged: 10.25)  // 2.25h over
        XCTAssertEqual(p.remainingFormatted, "2h 15m over this week")
    }

    func test_remainingFormatted_minutesPad() {
        let p = makeProject(booked: 8, logged: 7.9167)  // ~5 min remaining
        XCTAssertEqual(p.remainingFormatted, "0h 05m remaining this week")
    }

    // MARK: - qualifiedName

    func test_qualifiedName_withClient() {
        let p = makeProject(booked: 0, logged: 0, client: "Acme", project: "Website")
        XCTAssertEqual(p.qualifiedName, "Acme — Website")
    }

    func test_qualifiedName_withoutClient() {
        let p = makeProject(booked: 0, logged: 0, client: nil, project: "Website")
        XCTAssertEqual(p.qualifiedName, "Website")
    }

    func test_qualifiedName_static_matchesInstance() {
        XCTAssertEqual(
            ProjectStatus.qualifiedName(client: "Acme", project: "Website"),
            "Acme — Website"
        )
        XCTAssertEqual(
            ProjectStatus.qualifiedName(client: nil, project: "Website"),
            "Website"
        )
    }

    func test_qualifiedName_emptyClientStringStillJoins() {
        // Static helper takes Optional<String>, so an empty string is
        // treated as a present-but-empty client and joins with em-dash.
        // (Callers should pass nil for "no client".)
        XCTAssertEqual(
            ProjectStatus.qualifiedName(client: "", project: "Website"),
            " — Website"
        )
    }

    // MARK: - isForecasted

    func test_isForecasted_trueWhenBookedHoursPositive() {
        XCTAssertTrue(makeProject(booked: 8, logged: 0).isForecasted)
    }

    func test_isForecasted_falseWhenZeroBooked() {
        XCTAssertFalse(makeProject(booked: 0, logged: 5).isForecasted)
    }
}
