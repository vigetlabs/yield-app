import Foundation

struct HarvestUserResponse: Codable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let email: String?
}

struct HarvestTimeEntriesResponse: Codable {
    let timeEntries: [HarvestTimeEntry]
    let perPage: Int
    let totalPages: Int
    let totalEntries: Int
    let page: Int
    let links: HarvestLinks
}

struct HarvestLinks: Codable {
    let first: String?
    let next: String?
    let previous: String?
    let last: String?
}

struct HarvestTimeEntry: Codable, Identifiable {
    let id: Int
    let hours: Double
    let spentDate: String
    let isRunning: Bool
    let updatedAt: String
    let notes: String?
    /// Optional so older API responses (and our test fixtures) decode
    /// without complaint. Treat nil as unlocked at the use site.
    /// Note: `is_locked` is a *functional* lock — it's true when the
    /// entry can't be edited for any reason (submitted, approved,
    /// invoiced, project closed). For the "you've submitted this
    /// week" semantic the lock icon represents, prefer
    /// `approvalStatus` instead.
    let isLocked: Bool?
    /// Submission/approval workflow state. One of `"unsubmitted"`,
    /// `"submitted"`, or `"approved"`. Optional for the same reason
    /// as `isLocked` (older fixtures, defensive decoding).
    /// Replaces the deprecated `is_closed` field.
    let approvalStatus: String?
    /// ISO-8601 timestamp of when the currently-running timer was last
    /// started by the user. Non-nil iff `isRunning` is true.
    let timerStartedAt: String?
    let project: HarvestProjectRef
    let client: HarvestClientRef?
    let task: HarvestTaskRef?
    let taskAssignment: HarvestTaskAssignmentRef?
}

struct HarvestProjectRef: Codable {
    let id: Int
    let name: String
    /// Project code (e.g. "02", "ACME-042"). Harvest's
    /// `project_assignments` endpoint returns this; the embedded
    /// project ref on time entries does not — so callers see nil
    /// when reading from time-entry data and a populated value
    /// when reading from project assignments.
    let code: String?
}

struct HarvestClientRef: Codable {
    let id: Int
    let name: String
}

struct HarvestTaskAssignmentRef: Codable {
    let id: Int
    let task: HarvestTaskRef?
}

struct HarvestTaskRef: Codable, Hashable {
    let id: Int
    let name: String
}

struct HarvestProjectTaskAssignment: Codable, Identifiable, Hashable {
    let id: Int
    let isActive: Bool
    let task: HarvestTaskRef
}

// MARK: - Project Assignments (user-scoped)

struct HarvestProjectAssignmentsResponse: Codable {
    let projectAssignments: [HarvestProjectAssignment]
    let perPage: Int
    let totalPages: Int
    let totalEntries: Int
    let page: Int
}

struct HarvestProjectAssignment: Codable, Identifiable {
    let id: Int
    let isActive: Bool
    let project: HarvestProjectRef
    let client: HarvestClientRef?
    let taskAssignments: [HarvestProjectTaskAssignment]
}
