import SwiftUI
import XCTest
@testable import Yield

/// The System theme's row and formatting rules that don't need a
/// render to check. None of these touch `ThemeStore`, so they can't
/// flip the user's saved theme.
final class SystemThemeRefinementTests: XCTestCase {

    private func project(booked: Double, isTracking: Bool, harvestProjectId: Int? = 500) -> ProjectStatus {
        ProjectStatus(
            id: "p", clientName: nil, projectName: "Project", projectCode: nil,
            bookedHours: booked, loggedHours: 1, todayHours: 0,
            isTracking: isTracking, harvestProjectId: harvestProjectId, todayEntryId: nil,
            lastTaskId: nil, timeEntries: [], forecastNotes: nil
        )
    }

    // MARK: - Edge line

    func test_groupedEdgeLine_marksOnlyTheRunningProject() {
        XCTAssertEqual(GroupedRowLayout.statusLineColor(project(booked: 10, isTracking: false)), .clear,
                       "a booked project that isn't running gets no line")
        XCTAssertEqual(GroupedRowLayout.statusLineColor(project(booked: 0, isTracking: false)), .clear)
        XCTAssertNotEqual(GroupedRowLayout.statusLineColor(project(booked: 10, isTracking: true)), .clear)
        XCTAssertNotEqual(GroupedRowLayout.statusLineColor(project(booked: 0, isTracking: true)), .clear,
                          "running counts whether or not the project is booked")
    }

    func test_editorialEdgeLine_stillMarksEveryBookedProject() {
        XCTAssertNotEqual(EditorialRowLayout.statusLineColor(project(booked: 10, isTracking: false)), .clear)
        XCTAssertEqual(EditorialRowLayout.statusLineColor(project(booked: 0, isTracking: true)), .clear,
                       "Editorial's line means booked, not running — unchanged")
    }

    // MARK: - Durations

    func test_duration_perTheme() {
        XCTAssertEqual(YieldTheme.editorial.duration(6.5), "6h 30m")
        XCTAssertEqual(YieldTheme.system.duration(6.5), "6:30")
        XCTAssertEqual(YieldTheme.system.duration(0.05), "0:03")
    }

    func test_groupedRowFormats() {
        XCTAssertEqual(RowFormat.colon(7.5), "7:30", "a fractional booking keeps its minutes")
        XCTAssertEqual(RowFormat.colon(-1.5), "1:30", "magnitude only; the label says which way")
        XCTAssertEqual(RowFormat.remainingShort(3.5), "3:30 left")
        XCTAssertEqual(RowFormat.remainingShort(-1.5), "1:30 over")
        // Editorial's wording is untouched.
        XCTAssertEqual(RowFormat.remainingLabel(3.5), "3h 30m remaining this week")
    }
}
