import AppKit
import CryptoKit
import Foundation
import Network

/// OAuth client for Google Calendar (read-only events scope). Mirrors
/// `OAuthService` (the Harvest one) line-for-line in shape: a local
/// `NWListener` catches the loopback redirect, the browser handles
/// the account picker + consent, the code is exchanged for tokens
/// server-to-server, and refresh is coalesced via a single `Task`.
///
/// Differences from Harvest:
/// - Token endpoint expects `application/x-www-form-urlencoded`, not
///   JSON — Google rejects JSON bodies on `oauth2/token`.
/// - `prompt=consent` + `access_type=offline` on the auth URL are
///   required for Google to issue a refresh token; without them
///   re-auth would silently downgrade to access-token-only and our
///   long-lived sign-in would break after the first hour.
/// - The refresh response may omit `refresh_token`; preserve the
///   existing keychain entry when that happens.
/// - No `viewModel.refresh()` call on success — Google Calendar isn't
///   part of the comparison view; the picker fetches on demand.
@Observable
@MainActor
final class GoogleAuthService {
    private let clientId: String = Bundle.main.object(forInfoDictionaryKey: "GoogleClientId") as? String ?? ""
    private let clientSecret: String = Bundle.main.object(forInfoDictionaryKey: "GoogleClientSecret") as? String ?? ""
    private let redirectURI = "http://localhost:14739/google/callback"
    private let callbackPort: UInt16 = 14739
    private let scope = "https://www.googleapis.com/auth/calendar.events.readonly"

    var isAuthenticating = false
    var authError: String?

    /// Per-flow PKCE verifier (RFC 7636). Generated at the start of
    /// each OAuth flow, sent (as its SHA256-derived challenge) to the
    /// authorization endpoint, then sent in plaintext to the token
    /// endpoint to prove the same client that requested the code is
    /// exchanging it. Adds defense-in-depth: even if the embedded
    /// `client_secret` is extracted from the app bundle, an attacker
    /// who intercepts an authorization code still can't exchange it
    /// without the verifier.
    private var pkceVerifier: String?

    var isAuthenticated: Bool {
        KeychainHelper.load(key: "googleAccessToken") != nil
    }

    var userEmail: String? {
        UserDefaults.standard.string(forKey: DefaultsKey.GoogleCalendar.userEmail)
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() {
        isAuthenticating = true
        authError = nil
        // Fresh verifier per flow — never reuse, never persist. Held
        // in instance state because the round-trip through the
        // browser separates challenge-send from verifier-send.
        let verifier = Self.generateCodeVerifier()
        pkceVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)
        startLocalServer { [weak self] in
            guard let self else { return }
            guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else { return }
            components.queryItems = [
                URLQueryItem(name: "client_id", value: self.clientId),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: self.redirectURI),
                URLQueryItem(name: "scope", value: self.scope),
                // `access_type=offline` + `prompt=consent` together
                // guarantee Google issues a refresh token. Without
                // `prompt=consent`, a user re-authorizing won't get a
                // new refresh token and our refresh path silently
                // breaks once the access token expires.
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
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
            guard let port = NWEndpoint.Port(rawValue: callbackPort) else {
                authError = "Invalid OAuth callback port"
                isAuthenticating = false
                return
            }
            listener = try NWListener(using: params, on: port)
        } catch {
            // Most likely cause: a Harvest auth flow is already
            // listening on the same port. Surface a hint rather than
            // the raw "address in use" error.
            authError = "Sign-in server is busy. If you started another sign-in, finish it first."
            isAuthenticating = false
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.handleConnection(connection)
            }
        }

        var didCallReady = false
        listener?.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
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
        }
        listener?.start(queue: .main)

        // Timeout after 2 minutes — same shape as the Harvest flow.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(120))
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

            // Parse the GET request line for the URL path and query.
            // Google's redirect target is `/google/callback`; ignore
            // any other path (e.g. a Harvest callback that somehow
            // raced its way into our listener — shouldn't happen, but
            // defensive).
            guard let firstLine = requestString.components(separatedBy: "\r\n").first,
                  let urlString = firstLine.components(separatedBy: " ").dropFirst().first,
                  let url = URL(string: "http://localhost\(urlString)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                self.sendResponse(connection: connection, body: "Invalid request.")
                return
            }

            // Surface user-cancelled flows ("error=access_denied") cleanly.
            if let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
                self.sendResponse(connection: connection, body: "Sign-in cancelled. You can close this tab.")
                self.stopLocalServer()
                Task { @MainActor in
                    self.authError = errorParam == "access_denied"
                        ? "Sign-in was cancelled."
                        : "Sign-in failed: \(errorParam)"
                    self.isAuthenticating = false
                }
                return
            }

            let code = components.queryItems?.first(where: { $0.name == "code" })?.value

            guard let code else {
                self.sendResponse(connection: connection, body: "No authorization code received. You can close this tab.")
                return
            }

            // Send success response immediately
            self.sendResponse(connection: connection, body: "Connected Google Calendar to Yield! You can close this tab.")
            self.stopLocalServer()

            Task { @MainActor in
                do {
                    try await self.exchangeCodeForToken(code: code)
                    await self.fetchUserEmail()
                } catch {
                    self.authError = "Failed to exchange authorization code: \(error.localizedDescription)"
                }
                self.isAuthenticating = false
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
        guard let token = KeychainHelper.load(key: "googleAccessToken") else {
            throw APIError.notConfigured
        }

        // Refresh when within 5 minutes of expiry — same lookahead
        // window the Harvest service uses.
        let expiresAt = UserDefaults.standard.double(forKey: DefaultsKey.GoogleCalendar.tokenExpiresAt)
        if expiresAt > 0 && Date().timeIntervalSince1970 > expiresAt - 300 {
            return try await refreshToken()
        }

        return token
    }

    func signOut() {
        KeychainHelper.delete(key: "googleAccessToken")
        KeychainHelper.delete(key: "googleRefreshToken")
        UserDefaults.standard.removeObject(forKey: DefaultsKey.GoogleCalendar.tokenExpiresAt)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.GoogleCalendar.userEmail)
        authError = nil
    }

    // MARK: - Private

    private var refreshTask: Task<String, Error>?

    private func refreshToken() async throws -> String {
        // Coalesce concurrent refresh requests — same pattern as
        // OAuthService. Without this, two simultaneous calendar
        // fetches that both trigger refresh would burn two refresh
        // tokens (Google rotates on use in some configurations) or
        // race for the keychain.
        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }

            guard let refreshToken = KeychainHelper.load(key: "googleRefreshToken") else {
                throw APIError.unauthorized
            }

            let body: [String: String] = [
                "client_id": clientId,
                "client_secret": clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ]

            let tokenResponse = try await postTokenRequest(body: body)
            try storeTokens(tokenResponse, fallbackRefreshToken: refreshToken)
            return tokenResponse.accessToken
        }

        refreshTask = task
        return try await task.value
    }

    private func exchangeCodeForToken(code: String) async throws {
        // The PKCE verifier proves this is the same client that
        // started the flow. If `startOAuthFlow` wasn't called (or
        // the verifier was already consumed/cleared) Google returns
        // `invalid_grant` — clearer to fail early with our own
        // error than to pass that through opaquely.
        guard let verifier = pkceVerifier else {
            throw APIError.notConfigured
        }
        // One-shot: clear regardless of outcome so a retry must
        // start a new flow (and generate a new verifier).
        pkceVerifier = nil

        let body: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]

        let tokenResponse = try await postTokenRequest(body: body)
        try storeTokens(tokenResponse, fallbackRefreshToken: nil)
    }

    private func postTokenRequest(body: [String: String]) async throws -> GoogleTokenResponse {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw APIError.noData
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        // Google's token endpoint requires form-urlencoded — JSON
        // bodies come back as 400 invalid_request.
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Self.formURLEncoded(body).data(using: .utf8)

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

        // No `keyDecodingStrategy` — `GoogleTokenResponse` uses
        // explicit `CodingKeys` with snake_case rawValues, and the
        // strategy would convert JSON keys to camelCase first,
        // leaving the lookup with no match and a misleading
        // "data couldn't be read" decode error.
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    /// Encode a flat string→string dictionary as form-urlencoded body,
    /// percent-escaping each key/value. Internal so tests can verify
    /// special-character handling (`+`, `=`, `/`). `nonisolated` so
    /// tests can call it without hopping to the main actor — the
    /// helper is pure (no instance/UI state).
    ///
    /// Uses the WHATWG `application/x-www-form-urlencoded` whitelist
    /// (alphanumerics + `*-._`) rather than `CharacterSet.urlQueryAllowed`,
    /// because the latter leaves `/` unescaped — which is fine in a URL
    /// query string but breaks strict form-urlencoded parsers and is
    /// exactly the kind of thing that's hard to debug when it goes wrong.
    /// Generate a PKCE `code_verifier` per RFC 7636: 32 random bytes,
    /// base64url-encoded without padding → 43 ASCII characters drawn
    /// from the unreserved set `[A-Za-z0-9-._~]`. `nonisolated` so the
    /// test target can call it without a MainActor hop.
    nonisolated static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // `SecRandomCopyBytes` is the platform CSPRNG. `errSecSuccess`
        // failures are theoretical (would mean the system RNG is
        // unavailable, which would brick most of the OS); fall back to
        // `Data.random` shape via `UUID` just so we never return an
        // empty verifier in an unreachable error path.
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Self.base64URLEncode(Data(bytes))
    }

    /// PKCE `code_challenge` for S256 method: BASE64URL(SHA256(verifier)).
    nonisolated static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Self.base64URLEncode(Data(hashed))
    }

    /// Base64URL encoding (RFC 4648 §5) without padding. Standard
    /// `Data.base64EncodedString()` uses `+` `/` `=` which are not
    /// safe in URL contexts and which RFC 7636 explicitly forbids.
    nonisolated static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func formURLEncoded(_ params: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "*-._"))
        return params
            .sorted { $0.key < $1.key }  // deterministic output for tests
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    private func storeTokens(_ response: GoogleTokenResponse, fallbackRefreshToken: String?) throws {
        try KeychainHelper.save(key: "googleAccessToken", value: response.accessToken)

        // Google's refresh-grant response often omits `refresh_token`
        // — the caller (a refresh) should keep the existing one.
        // The initial code-for-token exchange always includes it.
        if let newRefresh = response.refreshToken {
            try KeychainHelper.save(key: "googleRefreshToken", value: newRefresh)
        } else if let fallback = fallbackRefreshToken {
            try KeychainHelper.save(key: "googleRefreshToken", value: fallback)
        }

        let expiresAt = Date().timeIntervalSince1970 + Double(response.expiresIn)
        UserDefaults.standard.set(expiresAt, forKey: DefaultsKey.GoogleCalendar.tokenExpiresAt)
    }

    private func fetchUserEmail() async {
        guard let token = try? await getAccessToken() else { return }
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return
        }

        let decoder = JSONDecoder()
        if let info = try? decoder.decode(GoogleUserInfo.self, from: data),
           let email = info.email, !email.isEmpty {
            UserDefaults.standard.set(email, forKey: DefaultsKey.GoogleCalendar.userEmail)
        }
    }
}

// MARK: - Response Models

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    /// Optional — refresh-grant responses omit this; preserve the
    /// existing keychain entry in that case.
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct GoogleUserInfo: Decodable {
    let email: String?
}
