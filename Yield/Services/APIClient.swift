import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case rateLimited
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)
    case noData
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid credentials. Check your access token and account ID in Settings."
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .decodingError(let error):
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    return "Parse error: missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                case .typeMismatch(let type, let context):
                    return "Parse error: expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                case .valueNotFound(let type, let context):
                    return "Parse error: null value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                default:
                    return "Parse error: \(decodingError.localizedDescription)"
                }
            }
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noData:
            return "No data received from server."
        case .notConfigured:
            return "API credentials not configured. Open Settings to get started."
        }
    }
}

final class APIClient {
    let baseURL: String
    let accountHeader: String
    let accountId: String
    private let tokenProvider: () async throws -> String

    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(baseURL: String, token: String, accountHeader: String, accountId: String) {
        self.baseURL = baseURL
        self.accountHeader = accountHeader
        self.accountId = accountId
        self.tokenProvider = { token }
    }

    init(baseURL: String, tokenProvider: @escaping () async throws -> String, accountHeader: String, accountId: String) {
        self.baseURL = baseURL
        self.accountHeader = accountHeader
        self.accountId = accountId
        self.tokenProvider = tokenProvider
    }

    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: [String: Any]? = nil
    ) async throws -> T {
        let token = try await tokenProvider()
        return try await performRequest(endpoint, method: method, queryItems: queryItems, body: body, token: token)
    }

    /// Fire-and-forget request that discards the response body (e.g. DELETE)
    func requestVoid(
        _ endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: [String: Any]? = nil
    ) async throws {
        let token = try await tokenProvider()
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw APIError.noData
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.noData
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountId, forHTTPHeaderField: accountHeader)
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    private func performRequest<T: Decodable>(
        _ endpoint: String,
        method: String,
        queryItems: [URLQueryItem]?,
        body: [String: Any]?,
        token: String
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw APIError.noData
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.noData
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountId, forHTTPHeaderField: accountHeader)
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
