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

            if page >= response.totalPages {
                break
            }
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

    func getTaskAssignments(projectId: Int) async throws -> [HarvestProjectTaskAssignment] {
        let response: HarvestTaskAssignmentsResponse = try await client.request(
            "/projects/\(projectId)/task_assignments",
            queryItems: [URLQueryItem(name: "is_active", value: "true")]
        )
        return response.taskAssignments
    }

    func createTimeEntry(projectId: Int, taskId: Int) async throws -> HarvestTimeEntry {
        let today = DateHelpers.dateFormatter.string(from: Date())
        return try await client.request(
            "/time_entries",
            method: "POST",
            body: [
                "project_id": projectId,
                "task_id": taskId,
                "spent_date": today,
            ]
        )
    }
}
