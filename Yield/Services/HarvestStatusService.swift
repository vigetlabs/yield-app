import Foundation

/// Pulls live state from harveststatus.com (Statuspage.io) so we can
/// enrich API outage messages with confirmed-incident context. The
/// status page covers both Harvest and Forecast as separate components,
/// so we can distinguish their incidents and tell the user when the API
/// errors they're seeing *aren't* reported by Harvest as a known issue —
/// pointing them at their connection / auth rather than just waiting.
///
/// All endpoints are public (no auth, no account scoping) so this just
/// uses URLSession directly with a tight 5s timeout — we don't want a
/// slow status page itself to hold up our error UI.
actor HarvestStatusService {
    struct Snapshot {
        let incidents: [Incident]
        let components: [Component]

        /// First active incident touching the named service. Matches by
        /// substring on the component name so "Harvest API" / "Forecast
        /// Web App" / "Forecast Schedule" all resolve cleanly. Case-
        /// insensitive.
        func incident(affecting service: String) -> Incident? {
            incidents.first { incident in
                incident.components.contains {
                    $0.name.localizedCaseInsensitiveContains(service)
                }
            }
        }
    }

    struct Incident: Decodable, Identifiable {
        let id: String
        let name: String
        /// `investigating` | `identified` | `monitoring`
        let status: String
        /// `none` | `minor` | `major` | `critical` | `maintenance`
        let impact: String
        let shortlink: String?
        let createdAt: Date
        let components: [Component]

        var url: URL? { shortlink.flatMap(URL.init(string:)) }

        /// Title-cased, human-friendly status: "Investigating" etc.
        var statusLabel: String {
            status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    struct Component: Decodable {
        let name: String
        /// `operational` | `degraded_performance` | `partial_outage` |
        /// `major_outage` | `under_maintenance`
        let status: String?
    }

    private struct ComponentsResponse: Decodable { let components: [Component] }
    private struct IncidentsResponse: Decodable { let incidents: [Incident] }

    private static let baseURL = "https://www.harveststatus.com"
    private static let cacheLifetime: TimeInterval = 60

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Statuspage.io serializes timestamps with fractional seconds
    /// ("2025-04-28T15:42:11.123Z"), which `.iso8601` rejects. Try with
    /// fractional seconds first, fall back to plain. Formatters are
    /// instantiated inside the closure so we don't capture non-Sendable
    /// state — cost is negligible at the call frequency here (one
    /// status fetch per minute at most).
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: raw) { return date }

            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date: \(raw)"
            )
        }
        return d
    }()

    private var cached: (snapshot: Snapshot, expiresAt: Date)?
    private var inFlight: Task<Snapshot, Error>?

    /// Returns a fresh-ish (≤60s) snapshot. Concurrent calls coalesce
    /// onto the same in-flight task so a burst of error events doesn't
    /// fan out into multiple status-page hits.
    func fetch() async throws -> Snapshot {
        if let cached, Date() < cached.expiresAt {
            return cached.snapshot
        }
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task<Snapshot, Error> {
            async let incidents = Self.fetchIncidents()
            async let components = Self.fetchComponents()
            return Snapshot(
                incidents: try await incidents,
                components: try await components
            )
        }
        inFlight = task
        defer { inFlight = nil }

        let snapshot = try await task.value
        cached = (snapshot, Date().addingTimeInterval(Self.cacheLifetime))
        return snapshot
    }

    private static func fetchIncidents() async throws -> [Incident] {
        let url = URL(string: "\(baseURL)/api/v2/incidents/unresolved.json")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(IncidentsResponse.self, from: data).incidents
    }

    private static func fetchComponents() async throws -> [Component] {
        let url = URL(string: "\(baseURL)/api/v2/components.json")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(ComponentsResponse.self, from: data).components
    }
}
