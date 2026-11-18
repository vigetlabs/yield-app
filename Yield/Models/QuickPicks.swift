import Foundation

/// The timer form's Favorites menu: this week's booked projects first,
/// then the favorites that aren't already one of those rows. Pure, so
/// the rules are testable without the form.
enum QuickPicks {
    /// One row of the menu: a project, and the task to select with it
    /// when Yield knows one. Nil leaves the task for the user to pick.
    struct Pick: Equatable {
        let projectId: Int
        let taskId: Int?
    }

    /// The task to select when `taskIds`' project is chosen, or nil
    /// when Yield has nothing to go on. In order: the favorite on that
    /// project used most recently (an explicit choice), then the task
    /// usually logged there lately, then the project's only task. Each
    /// is ignored if the project no longer has that task.
    static func preferredTask(
        taskIds: [Int],
        recentFavoriteTaskId: Int?,
        usualTaskId: Int?
    ) -> Int? {
        if let recentFavoriteTaskId, taskIds.contains(recentFavoriteTaskId) { return recentFavoriteTaskId }
        if let usualTaskId, taskIds.contains(usualTaskId) { return usualTaskId }
        return taskIds.count == 1 ? taskIds[0] : nil
    }

    /// `favorites` without the ones a booked row already offers: the
    /// same project with the same task. A favorite on a booked project
    /// but a different task stays, since the booked row won't pick it.
    static func favorites(_ favorites: [Pick], excluding booked: [Pick]) -> [Pick] {
        let offered = Set(booked.compactMap { pick in pick.taskId.map { PairKey(pick.projectId, $0) } })
        return favorites.filter { fav in
            guard let taskId = fav.taskId else { return true }
            return !offered.contains(PairKey(fav.projectId, taskId))
        }
    }

    private struct PairKey: Hashable {
        let projectId: Int
        let taskId: Int
        init(_ projectId: Int, _ taskId: Int) {
            self.projectId = projectId
            self.taskId = taskId
        }
    }
}
