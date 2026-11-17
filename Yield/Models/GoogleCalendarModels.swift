import Foundation

/// Domain-level representation of a single Google Calendar event,
/// flattened from the v3 API's wire types into the shape the rest of
/// the app cares about. Created by `GoogleCalendarService` after
/// filtering out anything we can't (or shouldn't) populate the
/// timer form from — all-day blocks, multi-day spans, declined
/// invites, cancelled events.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    /// Event title. May be empty (Google omits the field for events
    /// created without a title); the picker view substitutes a
    /// placeholder for display, but `applyEvent` won't clobber the
    /// form's notes field with an empty string.
    let summary: String
    let start: Date
    let end: Date

    /// Event duration in decimal hours (e.g. 9:00 → 10:30 = 1.5).
    /// Fed to `Double.roundedHM` to populate the form's H:MM inputs.
    var durationHours: Double {
        end.timeIntervalSince(start) / 3600
    }
}

extension CalendarEvent {
    /// "9:30am".
    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    var displayTitle: String {
        summary.isEmpty ? "(No title)" : summary
    }

    /// "Design review — 9:00am – 9:30am (30m)": the hover text
    /// wherever an event is drawn too small to say all of that.
    var tooltip: String {
        let (h, m) = durationHours.roundedHM
        let duration = MeetingCountdown.span(minutes: h * 60 + m)
        let range = "\(Self.clockFormatter.string(from: start)) \u{2013} \(Self.clockFormatter.string(from: end))"
        return "\(displayTitle) \u{2014} \(range) (\(duration))"
    }
}

// MARK: - Google Calendar v3 wire types
//
// These mirror the subset of fields requested via the `fields=` query
// parameter on the events.list call. Keep them `private` to the
// service via `internal` access so tests can decode fixture JSON, but
// don't expose them to the rest of the app — `CalendarEvent` is the
// shared currency.

struct GCalEventsResponse: Decodable {
    let items: [GCalEvent]
}

struct GCalEvent: Decodable {
    let id: String
    let summary: String?
    let start: GCalEventTime
    let end: GCalEventTime
    /// "confirmed" | "tentative" | "cancelled" — we filter out
    /// cancelled before promoting to `CalendarEvent`.
    let status: String?
    let attendees: [GCalAttendee]?
}

/// Either `dateTime` (timed event, RFC3339 string) or `date`
/// (all-day, YYYY-MM-DD string) is populated, never both. We use
/// `dateTime != nil` as the "this is a timed event" signal — all-day
/// events have no duration meaningful to a time entry.
struct GCalEventTime: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

struct GCalAttendee: Decodable {
    let email: String?
    /// True on the row representing the signed-in user. Used to find
    /// our own response status without comparing email strings.
    let `self`: Bool?
    /// "needsAction" | "declined" | "tentative" | "accepted"
    let responseStatus: String?
}
