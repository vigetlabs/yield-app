import Foundation

final class HarvestService {
    private let client: APIClient

    init(token: String, accountId: String) {
        self.client = APIClient(
            baseURL: "https://api.harvestapp.com/v2",
            token: token,
            accountHeader: "Harvest-Account-Id",
            accountId: accountId
        )
    }

    init(tokenProvider: @escaping () async throws -> String, accountId: String) {
        self.client = APIClient(
            baseURL: "https://api.harvestapp.com/v2",
            tokenProvider: tokenProvider,
            accountHeader: "Harvest-Account-Id",
            accountId: accountId
        )
    }

    func getCurrentUser() async throws -> HarvestUserResponse {
        try await client.request("/users/me")
    }

    func getTimeEntries(userId: Int, from: String, to: String) async throws -> [HarvestTimeEntry] {
        var allEntries: [HarvestTimeEntry] = []
        var page = 1

        while true {
            let response: HarvestTimeEntriesResponse = try await client.request(
                "/time_entries",
                queryItems: [
                    URLQueryItem(name: "user_id", value: String(userId)),
                    URLQueryItem(name: "from", value: from),
                    URLQueryItem(name: "to", value: to),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            allEntries.append(contentsOf: response.timeEntries)

            guard response.totalPages > 0, page < response.totalPages else { break }
            page += 1
        }

        return allEntries
    }

    func stopTimer(entryId: Int) async throws -> HarvestTimeEntry {
        try await client.request("/time_entries/\(entryId)/stop", method: "PATCH")
    }

    func restartTimer(entryId: Int) async throws -> HarvestTimeEntry {
        try await client.request("/time_entries/\(entryId)/restart", method: "PATCH")
    }

    func getMyProjectAssignments() async throws -> [HarvestProjectAssignment] {
        var allAssignments: [HarvestProjectAssignment] = []
        var page = 1

        while true {
            let response: HarvestProjectAssignmentsResponse = try await client.request(
                "/users/me/project_assignments",
                queryItems: [URLQueryItem(name: "page", value: String(page))]
            )
            allAssignments.append(contentsOf: response.projectAssignments)

            guard response.totalPages > 0, page < response.totalPages else { break }
            page += 1
        }

        return allAssignments
    }

    func deleteTimeEntry(entryId: Int) async throws {
        try await client.requestVoid(
            "/time_entries/\(entryId)",
            method: "DELETE"
        )
    }

    func updateTimeEntry(entryId: Int, hours: Double? = nil, taskId: Int? = nil, notes: String?) async throws -> HarvestTimeEntry {
        var body: [String: Any] = [:]
        if let hours { body["hours"] = hours }
        if let taskId { body["task_id"] = taskId }
        // Always send notes — empty string clears them, nil omits the field
        if let notes { body["notes"] = notes }
        return try await client.request(
            "/time_entries/\(entryId)",
            method: "PATCH",
            body: body
        )
    }

    func createTimeEntry(projectId: Int, taskId: Int, hours: Double? = nil, notes: String? = nil, spentDate: String? = nil) async throws -> HarvestTimeEntry {
        let dateString = spentDate ?? DateHelpers.dateFormatter.string(from: Date())
        var body: [String: Any] = [
            "project_id": projectId,
            "task_id": taskId,
            "spent_date": dateString,
        ]
        if let hours {
            body["hours"] = hours
        }
        if let notes, !notes.isEmpty {
            body["notes"] = notes
        }
        return try await client.request(
            "/time_entries",
            method: "POST",
            body: body
        )
    }
}
