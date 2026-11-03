import Foundation

/// A client and its projects, for the grouped list layout.
struct ProjectGroup: Identifiable {
    /// Display label — the client name, or `ProjectGrouping.noClientLabel`
    /// for projects that have none.
    let client: String
    let projects: [ProjectStatus]

    var id: String { client }
}

/// Partitions an already-sorted project list into per-client groups.
///
/// Order is preserved, not re-derived: the view model's
/// `projectSortOrder` already sorts alphabetically by client and then
/// by project *name* (codes are display-only), and any tab or day
/// filter has been applied upstream. Each group appears where its
/// first project appeared, so grouping never reorders what the view
/// model decided.
enum ProjectGrouping {
    static let noClientLabel = "No client"

    static func grouped(_ statuses: [ProjectStatus]) -> [ProjectGroup] {
        var order: [String] = []
        var byClient: [String: [ProjectStatus]] = [:]
        for status in statuses {
            let key = status.clientName ?? noClientLabel
            if byClient[key] == nil { order.append(key) }
            byClient[key, default: []].append(status)
        }
        return order.map { ProjectGroup(client: $0, projects: byClient[$0] ?? []) }
    }
}
