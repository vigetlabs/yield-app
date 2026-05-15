import XCTest
@testable import Yield

/// Covers `GoogleCalendarService`'s pure post-decode helpers — the
/// filtering and sorting that turn the wire-format response into the
/// `[CalendarEvent]` the picker shows. The HTTP layer isn't tested
/// here (would need URLProtocol stubbing); these tests pin the
/// contract that callers care about: which events make it through.
final class GoogleCalendarServiceTests: XCTestCase {

    // MARK: - Helpers

    /// A calendar pinned to UTC so fixture date strings line up with
    /// `isDate(_:inSameDayAs:)` checks regardless of where the test
    /// machine actually is.
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Decode a JSON string into the wire response so each test
    /// reads like a fixture rather than a constructor party.
    private func response(from json: String) throws -> GCalEventsResponse {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(GCalEventsResponse.self, from: data)
    }

    // MARK: - Filter tests

    func test_events_dropsCancelledStatus() throws {
        let json = """
        { "items": [
          { "id": "a", "summary": "Confirmed",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00Z" },
            "status": "confirmed" },
          { "id": "b", "summary": "Cancelled meeting",
            "start": { "dateTime": "2026-05-15T10:00:00Z" },
            "end":   { "dateTime": "2026-05-15T10:30:00Z" },
            "status": "cancelled" }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func test_events_dropsAllDayEvents() throws {
        // All-day events use `date`, not `dateTime` — there's no
        // duration to populate the form's time field with.
        let json = """
        { "items": [
          { "id": "timed",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T10:00:00Z" } },
          { "id": "allday",
            "start": { "date": "2026-05-15" },
            "end":   { "date": "2026-05-16" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.map(\.id), ["timed"])
    }

    func test_events_dropsMultiDaySpans() throws {
        // Travel blocks etc. — duration would be misleading on a
        // single-day time entry.
        let json = """
        { "items": [
          { "id": "single",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00Z" } },
          { "id": "twoDay",
            "start": { "dateTime": "2026-05-15T22:00:00Z" },
            "end":   { "dateTime": "2026-05-16T02:00:00Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.map(\.id), ["single"])
    }

    func test_events_dropsDeclinedBySelf() throws {
        // Declined invites shouldn't show up — the user clearly
        // didn't sit through them.
        let json = """
        { "items": [
          { "id": "accepted",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00Z" },
            "attendees": [
              { "email": "me@example.com", "self": true, "responseStatus": "accepted" }
            ] },
          { "id": "declined",
            "start": { "dateTime": "2026-05-15T10:00:00Z" },
            "end":   { "dateTime": "2026-05-15T10:30:00Z" },
            "attendees": [
              { "email": "me@example.com", "self": true, "responseStatus": "declined" }
            ] },
          { "id": "needsAction",
            "start": { "dateTime": "2026-05-15T11:00:00Z" },
            "end":   { "dateTime": "2026-05-15T11:30:00Z" },
            "attendees": [
              { "email": "me@example.com", "self": true, "responseStatus": "needsAction" }
            ] }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.map(\.id), ["accepted", "needsAction"])
    }

    func test_events_keepsSoloEventsWithoutAttendees() throws {
        // Personal blocks (focus time, no other invitees) have no
        // attendees array — must not be filtered out.
        let json = """
        { "items": [
          { "id": "focus", "summary": "Heads-down work",
            "start": { "dateTime": "2026-05-15T13:00:00Z" },
            "end":   { "dateTime": "2026-05-15T15:00:00Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.summary, "Heads-down work")
    }

    func test_events_keepsEventWithEmptySummary() throws {
        // Untitled blocks should still appear; `summary` ends up
        // empty and the picker substitutes a placeholder for display.
        let json = """
        { "items": [
          { "id": "untitled",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.summary, "")
    }

    // MARK: - Sort + duration

    func test_events_sortedByStartAscending() throws {
        // Input intentionally jumbled to confirm sort, not just
        // pass-through ordering.
        let json = """
        { "items": [
          { "id": "noon",
            "start": { "dateTime": "2026-05-15T12:00:00Z" },
            "end":   { "dateTime": "2026-05-15T12:30:00Z" } },
          { "id": "morning",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00Z" } },
          { "id": "evening",
            "start": { "dateTime": "2026-05-15T17:00:00Z" },
            "end":   { "dateTime": "2026-05-15T17:30:00Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.map(\.id), ["morning", "noon", "evening"])
    }

    func test_calendarEvent_durationHours_30Min_isHalf() throws {
        let json = """
        { "items": [
          { "id": "thirty",
            "start": { "dateTime": "2026-05-15T09:00:00Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.first?.durationHours ?? 0, 0.5, accuracy: 0.0001)
    }

    func test_calendarEvent_durationHours_1h45m() throws {
        let json = """
        { "items": [
          { "id": "x",
            "start": { "dateTime": "2026-05-15T13:15:00Z" },
            "end":   { "dateTime": "2026-05-15T15:00:00Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.first?.durationHours ?? 0, 1.75, accuracy: 0.0001)
    }

    // MARK: - Rounding contract (regression fence on Double.roundedHM)

    func test_durationHours_roundsToFormFields_30Min() {
        let (h, m) = (0.5).roundedHM
        XCTAssertEqual(h, 0)
        XCTAssertEqual(m, 30)
    }

    func test_durationHours_roundsToFormFields_1h45m() {
        let (h, m) = (1.75).roundedHM
        XCTAssertEqual(h, 1)
        XCTAssertEqual(m, 45)
    }

    // MARK: - RFC3339 parsing

    func test_events_parsesFractionalSecondsTimestamps() throws {
        // Google sometimes returns dateTime values with millisecond
        // precision — make sure those decode just like the integer-
        // second variant.
        let json = """
        { "items": [
          { "id": "ms",
            "start": { "dateTime": "2026-05-15T09:00:00.123Z" },
            "end":   { "dateTime": "2026-05-15T09:30:00.456Z" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.durationHours ?? 0, 0.5, accuracy: 0.001)
    }

    func test_events_parsesTimestampsWithOffset() throws {
        // Non-UTC offset (Pacific Daylight). Same wall-clock 30
        // minutes — duration should still round to 0.5h.
        let json = """
        { "items": [
          { "id": "pdt",
            "start": { "dateTime": "2026-05-15T09:00:00-07:00" },
            "end":   { "dateTime": "2026-05-15T09:30:00-07:00" } }
        ] }
        """
        let result = GoogleCalendarService.events(from: try response(from: json), calendar: utc)
        XCTAssertEqual(result.first?.durationHours ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - URL-encoded body builder (used by the auth service)

    func test_formURLEncoded_escapesSpecialCharacters() {
        // Refresh tokens commonly contain `+`, `=`, `/` — all of
        // which carry meaning in form-urlencoded bodies and must be
        // percent-escaped, not passed through.
        let body = GoogleAuthService.formURLEncoded([
            "grant_type": "refresh_token",
            "refresh_token": "1//abc+def=ghi/jkl"
        ])
        // Sorted output (deterministic): grant_type comes first.
        XCTAssertTrue(body.hasPrefix("grant_type=refresh_token&refresh_token="), "got: \(body)")
        // Each special char encoded:
        XCTAssertTrue(body.contains("%2B"), "Expected `+` → %2B in: \(body)")
        XCTAssertTrue(body.contains("%3D"), "Expected `=` → %3D in: \(body)")
        XCTAssertTrue(body.contains("%2F"), "Expected `/` → %2F in: \(body)")
    }
}
