import XCTest
@testable import Yield

/// The timer form's Favorites menu: which task a booked project
/// brings with it, and which favorites the second list leaves out.
final class QuickPicksTests: XCTestCase {

    private func pick(_ projectId: Int, _ taskId: Int?) -> QuickPicks.Pick {
        QuickPicks.Pick(projectId: projectId, taskId: taskId)
    }

    // MARK: - Preferred task

    func test_preferredTask_aFavoriteWins() {
        XCTAssertEqual(QuickPicks.preferredTask(taskIds: [1, 2, 3], recentFavoriteTaskId: 2, usualTaskId: 3), 2)
    }

    func test_preferredTask_thenTheUsualTask() {
        XCTAssertEqual(QuickPicks.preferredTask(taskIds: [1, 2, 3], recentFavoriteTaskId: nil, usualTaskId: 3), 3)
    }

    func test_preferredTask_thenTheOnlyTask() {
        XCTAssertEqual(QuickPicks.preferredTask(taskIds: [7], recentFavoriteTaskId: nil, usualTaskId: nil), 7)
    }

    func test_preferredTask_unknown_isNil() {
        XCTAssertNil(QuickPicks.preferredTask(taskIds: [1, 2], recentFavoriteTaskId: nil, usualTaskId: nil))
    }

    func test_preferredTask_ignoresTasksTheProjectNoLongerHas() {
        XCTAssertEqual(QuickPicks.preferredTask(taskIds: [1, 2], recentFavoriteTaskId: 9, usualTaskId: 2), 2)
        XCTAssertNil(QuickPicks.preferredTask(taskIds: [1, 2], recentFavoriteTaskId: 9, usualTaskId: 8))
    }

    // MARK: - Favorites below the bookings

    func test_aFavoriteThatIsABookedRow_isLeftOut() {
        let favorites = [pick(1, 10), pick(2, 20)]
        XCTAssertEqual(QuickPicks.favorites(favorites, excluding: [pick(1, 10)]), [pick(2, 20)])
    }

    func test_aFavoriteOnABookedProject_withAnotherTask_stays() {
        let favorites = [pick(1, 10), pick(1, 11)]
        XCTAssertEqual(QuickPicks.favorites(favorites, excluding: [pick(1, 10)]), [pick(1, 11)])
    }

    func test_aBookedRowWithNoTask_leavesThatProjectsFavoritesAlone() {
        // Can't happen through the form — a favorite on a project makes
        // it the booked row's task — but nothing matches a missing task.
        let favorites = [pick(1, 10)]
        XCTAssertEqual(QuickPicks.favorites(favorites, excluding: [pick(1, nil)]), favorites)
    }

    func test_noBookings_keepsEveryFavorite() {
        let favorites = [pick(1, 10), pick(2, 20)]
        XCTAssertEqual(QuickPicks.favorites(favorites, excluding: []), favorites)
    }
}
