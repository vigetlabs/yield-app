import Foundation

/// Read-only Google Calendar v3 client. Inlines its own URLSession
/// call rather than reusing `APIClient` because APIClient is shaped
/// around Harvest's `<header>: <accountId>` auth model — bending it
/// to make the account header optional would risk regressions in the
/// Harvest paths. The single endpoint here is small enough that the
/// duplication isn't a maintenance burden.
final class GoogleCalendarService {
    private let tokenProvider: () async throws -> String

    /// Tightened-timeout session matching `APIClient` — 20s request /
    /// 60s resource — so a stalled fetch fails fast rather than
    /// leaving the picker spinning indefinitely.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
    }

    /// Fetch today's events on the primary calendar, post-filtered to
    /// the subset usable as a time entry. Sorted by start ascending.
    ///
    /// Throws `APIError.unauthorized` on 401 (signal to the picker to
    /// show "Reconnect Google Calendar in Settings"); other status
    /// codes throw `APIError.serverError`.
    func fetchTodayEvents(now: Date = Date(), calendar: Calendar = .current) async throws -> [CalendarEvent] {
        let token = try await tokenProvider()

        let (timeMin, timeMax) = Self.todayBounds(now: now, calendar: calendar)

        guard var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events") else {
            throw APIError.noData
        }
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            // Required so recurring events are returned as concrete
            // instances with real start/end timestamps. Without this,
            // recurring events come back as a single template entry
            // with no usable times.
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
            // Trim the response to just the fields we use — keeps
            // payload small and decoding quick.
            URLQueryItem(name: "fields", value: "items(id,summary,start,end,status,attendees(self,responseStatus))"),
        ]

        guard let url = components.url else {
            throw APIError.noData
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Yield (menubar)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await Self.session.data(for: request)

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

        let decoded: GCalEventsResponse
        do {
            decoded = try JSONDecoder().decode(GCalEventsResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }

        return Self.events(from: decoded, calendar: calendar)
    }

    // MARK: - Pure helpers (internal so tests can drive them)

    /// RFC3339 timestamps bounding the start and end of `now`'s
    /// calendar day. We compute these in the user's local time zone
    /// (not UTC) so the boundary matches what the user thinks of as
    /// "today" — Google honors the offset on `timeMin`/`timeMax`.
    static func todayBounds(now: Date, calendar: Calendar) -> (timeMin: String, timeMax: String) {
        let startOfDay = calendar.startOfDay(for: now)
        // Use date arithmetic, not 86400 seconds, to handle DST.
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return (formatter.string(from: startOfDay), formatter.string(from: endOfDay))
    }

    /// Promote a decoded API response to filtered, sorted
    /// `CalendarEvent` values. Pure — passes through `calendar` for
    /// same-day comparisons so tests can pin a fixed time zone.
    static func events(from response: GCalEventsResponse, calendar: Calendar) -> [CalendarEvent] {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parserNoFractional = ISO8601DateFormatter()
        parserNoFractional.formatOptions = [.withInternetDateTime]

        let parsed: [CalendarEvent] = response.items.compactMap { item -> CalendarEvent? in
            // Cancelled — Google may still include these in the
            // response window even with the default filter.
            if item.status == "cancelled" { return nil }

            // All-day events have `date`, not `dateTime`. We can't
            // map a 24h block to a meaningful time entry duration,
            // so skip.
            guard let startStr = item.start.dateTime,
                  let endStr = item.end.dateTime else { return nil }

            // Try fractional-seconds first (Google sometimes includes
            // them, sometimes doesn't), fall back to plain RFC3339.
            guard let start = parser.date(from: startStr) ?? parserNoFractional.date(from: startStr),
                  let end = parser.date(from: endStr) ?? parserNoFractional.date(from: endStr) else { return nil }

            // Multi-day spans (rare for normal meetings, common for
            // travel blocks) — skip; the form's date is a single day
            // and the duration would be misleading.
            guard calendar.isDate(start, inSameDayAs: end) else { return nil }

            // Skip events the signed-in user declined. Use the
            // attendee row marked `self == true` to find ourselves
            // without comparing email strings.
            if let attendees = item.attendees,
               let selfRow = attendees.first(where: { $0.`self` == true }),
               selfRow.responseStatus == "declined" {
                return nil
            }

            return CalendarEvent(
                id: item.id,
                summary: item.summary ?? "",
                start: start,
                end: end
            )
        }

        return parsed.sorted { $0.start < $1.start }
    }
}
