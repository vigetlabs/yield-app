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
    let project: HarvestProjectRef
    let client: HarvestClientRef?
    let taskAssignment: HarvestTaskAssignmentRef?
}

struct HarvestProjectRef: Codable {
    let id: Int
    let name: String
}

struct HarvestClientRef: Codable {
    let id: Int
    let name: String
}

struct HarvestTaskAssignmentRef: Codable {
    let id: Int
    let task: HarvestTaskRef?
}

struct HarvestTaskRef: Codable {
    let id: Int
    let name: String
}

struct HarvestTaskAssignmentsResponse: Codable {
    let taskAssignments: [HarvestProjectTaskAssignment]
}

struct HarvestProjectTaskAssignment: Codable, Identifiable {
    let id: Int
    let isActive: Bool
    let task: HarvestTaskRef
}
