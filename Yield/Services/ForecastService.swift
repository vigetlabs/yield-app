import Foundation

final class ForecastService {
    private let client: APIClient

    init(token: String, accountId: String) {
        self.client = APIClient(
            baseURL: "https://api.forecastapp.com",
            token: token,
            accountHeader: "Forecast-Account-Id",
            accountId: accountId
        )
    }

    init(tokenProvider: @escaping () async throws -> String, accountId: String) {
        self.client = APIClient(
            baseURL: "https://api.forecastapp.com",
            tokenProvider: tokenProvider,
            accountHeader: "Forecast-Account-Id",
            accountId: accountId
        )
    }

    func getCurrentPerson() async throws -> ForecastCurrentUser {
        let response: ForecastWhoAmIResponse = try await client.request("/whoami")
        return response.currentUser
    }

    func getAssignments(personId: Int, startDate: String, endDate: String) async throws -> [ForecastAssignment] {
        let response: ForecastAssignmentsResponse = try await client.request(
            "/assignments",
            queryItems: [
                URLQueryItem(name: "person_id", value: String(personId)),
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate),
                URLQueryItem(name: "state", value: "active"),
            ]
        )
        return response.assignments
    }

    /// Fetch company-wide "Everyone" assignments for a week — rows with
    /// both `person_id` and `placeholder_id` null. Forecast uses that
    /// shape exclusively for org-level time off (company holidays,
    /// office closures). Rows with `person_id == null` but a non-null
    /// `placeholder_id` are unassigned placeholder bookings — those
    /// aren't relevant to the current user and are excluded here.
    ///
    /// Pass `restrictToProjectId` (the Time Off project ID) to scope the
    /// query server-side. This keeps the response bounded — a 1000-person
    /// org's weekly time-off count is a handful of rows, whereas the
    /// unfiltered query returns every assignment for every person. If
    /// nil, we fall back to an unfiltered query and filter client-side
    /// (used on first refresh before the Time Off project ID is known).
    func getEveryoneAssignments(startDate: String, endDate: String, restrictToProjectId: Int? = nil) async throws -> [ForecastAssignment] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate),
            URLQueryItem(name: "state", value: "active"),
        ]
        if let pid = restrictToProjectId {
            items.append(URLQueryItem(name: "project_id", value: String(pid)))
        }
        let response: ForecastAssignmentsResponse = try await client.request(
            "/assignments",
            queryItems: items
        )
        return response.assignments.filter { $0.personId == nil && $0.placeholderId == nil }
    }

    func getProjects() async throws -> [ForecastProject] {
        let response: ForecastProjectsResponse = try await client.request("/projects")
        return response.projects
    }

    func getClients() async throws -> [ForecastClient] {
        let response: ForecastClientsResponse = try await client.request("/clients")
        return response.clients
    }
}
