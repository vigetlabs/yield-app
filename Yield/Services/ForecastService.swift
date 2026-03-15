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

    func getProjects() async throws -> [ForecastProject] {
        let response: ForecastProjectsResponse = try await client.request("/projects")
        return response.projects
    }

    func getClients() async throws -> [ForecastClient] {
        let response: ForecastClientsResponse = try await client.request("/clients")
        return response.clients
    }
}
