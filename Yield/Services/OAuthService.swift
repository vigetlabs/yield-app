import AppKit
import Foundation
import Network

@Observable
final class OAuthService {
    // TODO: Replace with your registered OAuth app credentials
    private let clientId = "seJMYEa5PwYL2G6f1UJGmsOq"
    private let clientSecret = "vrTLvN4QyEtc_7E0sddKeZI4BrxNxfNmiFwS4OoIxljTeuEL-I8yOwl-BVR87OkOGyBmjvQItrI3-izxZp_Tmw"
    private let redirectURI = "http://localhost:14739/oauth/callback"
    private let callbackPort: UInt16 = 14739

    var isAuthenticating = false
    var authError: String?

    var isAuthenticated: Bool {
        KeychainHelper.load(key: "accessToken") != nil
    }

    var harvestAccountId: String? {
        UserDefaults.standard.string(forKey: "oauthHarvestAccountId")
    }

    var forecastAccountId: String? {
        UserDefaults.standard.string(forKey: "oauthForecastAccountId")
    }

    var userName: String? {
        UserDefaults.standard.string(forKey: "oauthUserName")
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() {
        isAuthenticating = true
        authError = nil
        startLocalServer { [weak self] in
            guard let self else { return }
            var components = URLComponents(string: "https://id.getharvest.com/oauth2/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: self.clientId),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: self.redirectURI),
            ]
            if let url = components.url {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Local HTTP Server for OAuth Callback

    private var listener: NWListener?

    private func startLocalServer(onReady: @escaping () -> Void) {
        stopLocalServer()

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: callbackPort)!)
        } catch {
            authError = "Failed to start local OAuth server: \(error.localizedDescription)"
            isAuthenticating = false
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        var didCallReady = false
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if !didCallReady {
                    didCallReady = true
                    onReady()
                }
            case .failed(let error):
                self?.authError = "OAuth server failed: \(error.localizedDescription)"
                self?.isAuthenticating = false
                self?.stopLocalServer()
            default:
                break
            }
        }
        listener?.start(queue: .main)

        // Timeout after 2 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.isAuthenticating else { return }
            self.stopLocalServer()
            self.authError = "Sign-in timed out. Please try again."
            self.isAuthenticating = false
        }
    }

    private func stopLocalServer() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the GET request line for the URL path and query
            guard let firstLine = requestString.components(separatedBy: "\r\n").first,
                  let urlString = firstLine.components(separatedBy: " ").dropFirst().first,
                  let url = URL(string: "http://localhost\(urlString)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                self.sendResponse(connection: connection, body: "Invalid request.")
                return
            }

            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            let scope = components.queryItems?.first(where: { $0.name == "scope" })?.value ?? ""

            guard let code else {
                self.sendResponse(connection: connection, body: "No authorization code received. You can close this tab.")
                return
            }

            // Send success response immediately
            self.sendResponse(connection: connection, body: "Signed in to Yield! You can close this tab.")
            self.stopLocalServer()

            // Parse scope for account IDs (may or may not be present)
            self.parseAndStoreAccountIds(from: scope)
            Task { @MainActor in
                do {
                    try await self.exchangeCodeForToken(code: code)

                    // If scope didn't include account IDs, fetch them from the API
                    if self.harvestAccountId == nil || self.forecastAccountId == nil {
                        try await self.fetchAccountIds()
                    }

                    await self.fetchUserName()
                } catch {
                    self.authError = "Failed to exchange authorization code: \(error.localizedDescription)"
                }
                self.isAuthenticating = false
                await AppState.shared.viewModel.refresh()
            }
        }
    }

    private func sendResponse(connection: NWConnection, body: String) {
        let html = """
        <html><body style="font-family: -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0;">
        <p style="font-size: 18px; color: #333;">\(body)</p>
        </body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r\n\
        Content-Type: text/html\r\n\
        Content-Length: \(html.utf8.count)\r\n\
        Connection: close\r\n\
        \r\n\
        \(html)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token Management

    func getAccessToken() async throws -> String {
        guard let token = KeychainHelper.load(key: "accessToken") else {
            throw APIError.notConfigured
        }

        // Check if token needs refresh
        let expiresAt = UserDefaults.standard.double(forKey: "oauthTokenExpiresAt")
        if expiresAt > 0 && Date().timeIntervalSince1970 > expiresAt - 300 {
            // Token expires within 5 minutes — refresh it
            return try await refreshToken()
        }

        return token
    }

    func signOut() {
        KeychainHelper.delete(key: "accessToken")
        KeychainHelper.delete(key: "refreshToken")
        UserDefaults.standard.removeObject(forKey: "oauthTokenExpiresAt")
        UserDefaults.standard.removeObject(forKey: "oauthHarvestAccountId")
        UserDefaults.standard.removeObject(forKey: "oauthForecastAccountId")
        UserDefaults.standard.removeObject(forKey: "oauthUserName")
        authError = nil
    }

    // MARK: - Private

    private var refreshTask: Task<String, Error>?

    private func refreshToken() async throws -> String {
        // Coalesce concurrent refresh requests
        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }

            guard let refreshToken = KeychainHelper.load(key: "refreshToken") else {
                throw APIError.unauthorized
            }

            let body: [String: String] = [
                "client_id": clientId,
                "client_secret": clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ]

            let tokenResponse = try await postTokenRequest(body: body)
            try storeTokens(tokenResponse)
            return tokenResponse.accessToken
        }

        refreshTask = task
        return try await task.value
    }

    private func exchangeCodeForToken(code: String) async throws {
        let body: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
        ]

        let tokenResponse = try await postTokenRequest(body: body)
        try storeTokens(tokenResponse)
    }

    private func postTokenRequest(body: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: "https://id.getharvest.com/api/v2/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OAuthTokenResponse.self, from: data)
    }

    private func storeTokens(_ response: OAuthTokenResponse) throws {
        try KeychainHelper.save(key: "accessToken", value: response.accessToken)
        try KeychainHelper.save(key: "refreshToken", value: response.refreshToken)
        let expiresAt = Date().timeIntervalSince1970 + Double(response.expiresIn)
        UserDefaults.standard.set(expiresAt, forKey: "oauthTokenExpiresAt")
    }

    private func parseAndStoreAccountIds(from scope: String) {
        // Scope format: "harvest:123456 forecast:789012"
        let parts = scope.components(separatedBy: " ")
        for part in parts {
            let segments = part.components(separatedBy: ":")
            guard segments.count == 2 else { continue }
            switch segments[0] {
            case "harvest":
                UserDefaults.standard.set(segments[1], forKey: "oauthHarvestAccountId")
            case "forecast":
                UserDefaults.standard.set(segments[1], forKey: "oauthForecastAccountId")
            default:
                break
            }
        }
    }

    private func fetchAccountIds() async throws {
        guard let token = KeychainHelper.load(key: "accessToken") else {
            throw APIError.notConfigured
        }

        var request = URLRequest(url: URL(string: "https://id.getharvest.com/api/v2/accounts")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let accountsResponse = try decoder.decode(HarvestAccountsResponse.self, from: data)

        let harvestAccount = accountsResponse.accounts.first(where: { $0.product == "harvest" })
        let forecastAccount = accountsResponse.accounts.first(where: { $0.product == "forecast" })

        if let harvest = harvestAccount {
            UserDefaults.standard.set(String(harvest.id), forKey: "oauthHarvestAccountId")
        }
        if let forecast = forecastAccount {
            UserDefaults.standard.set(String(forecast.id), forKey: "oauthForecastAccountId")
        } else if let harvest = harvestAccount {
            // Fallback if no separate Forecast account
            UserDefaults.standard.set(String(harvest.id), forKey: "oauthForecastAccountId")
        }
    }

    @MainActor
    private func fetchUserName() async {
        guard let token = KeychainHelper.load(key: "accessToken"),
              let accountId = harvestAccountId else { return }
        let service = HarvestService(token: token, accountId: accountId)
        if let user = try? await service.getCurrentUser() {
            UserDefaults.standard.set("\(user.firstName) \(user.lastName)", forKey: "oauthUserName")
        }
    }
}

// MARK: - Response Model

private struct OAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

private struct HarvestAccountsResponse: Codable {
    let accounts: [HarvestAccountEntry]
}

private struct HarvestAccountEntry: Codable {
    let id: Int
    let name: String
    let product: String?
}
