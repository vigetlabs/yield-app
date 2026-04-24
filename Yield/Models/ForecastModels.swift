import Foundation

struct ForecastWhoAmIResponse: Codable {
    let currentUser: ForecastCurrentUser
}

struct ForecastCurrentUser: Codable {
    let id: Int
}

struct ForecastAssignment: Codable, Identifiable {
    let id: Int
    let projectId: Int?
    /// Nil for "Everyone" assignments (company-wide holidays) — those
    /// carry no person association because they apply to the whole org.
    /// Also nil for placeholder bookings (unassigned slots/roles) — use
    /// `placeholderId` to distinguish those from Everyone rows.
    let personId: Int?
    /// Non-nil for placeholder bookings — unassigned assignments on some
    /// role/slot that no human is tied to yet. Distinct from Everyone
    /// rows which have both `personId` and `placeholderId` nil.
    let placeholderId: Int?
    let startDate: String
    let endDate: String
    let allocation: Int? // seconds per day, null for placeholders/unallocated
    let activeOnDaysOff: Bool?
    let notes: String?
}

struct ForecastProject: Codable, Identifiable {
    let id: Int
    let name: String
    let code: String?
    let clientId: Int?
    let harvestId: Int?
    let archived: Bool?
}

struct ForecastProjectsResponse: Codable {
    let projects: [ForecastProject]
}

struct ForecastClient: Codable, Identifiable {
    let id: Int
    let name: String
}

struct ForecastClientsResponse: Codable {
    let clients: [ForecastClient]
}

struct ForecastAssignmentsResponse: Codable {
    let assignments: [ForecastAssignment]
}
