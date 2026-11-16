import Foundation

/// What the menu bar says about the calendar, beside the timer graphic:
/// the next meeting and how long until it starts, how long the current
/// one has left, or — when a meeting's timer has outlived the meeting —
/// how long ago it ended. Persisted via `DefaultsKey.meetingCountdownMode`.
enum MeetingCountdownMode: String, CaseIterable {
    /// Nothing is drawn. The default: the countdown widens the menu bar
    /// item, which nobody should get from an update without asking.
    case off
    /// "in 1h 22m" — no titles, for screen sharing.
    case timeOnly
    /// "Design review in 1h 22m".
    case titleAndTime

    static let `default`: MeetingCountdownMode = .off

    var label: String {
        switch self {
        case .off:          return "Off"
        case .timeOnly:     return "Time only"
        case .titleAndTime: return "Title and time"
        }
    }
}

/// The countdown as the menu bar draws it: a line of text and how
/// urgently to draw it. Plain values, built by `MeetingCountdown.status`
/// so the wording is testable without rendering.
struct MenuBarMeetingStatus: Equatable {
    enum Tone: Equatable {
        /// Ordinary menu bar ink.
        case plain
        /// The next meeting is starting: the meeting blue, the same as
        /// the capsule's "meeting waiting" state.
        case imminent
        /// The meeting is over and its timer is still running.
        case overrun
    }

    var text: String
    var tone: Tone = .plain
}

enum MeetingCountdown {
    /// How close a start has to be to draw in the meeting blue. Matches
    /// the moment the start prompt opens.
    static let imminentWindow: TimeInterval = 2 * 60
    /// While in a meeting, the next one is mentioned only when it
    /// follows this closely — back-to-back, or near enough.
    static let nextMentionWindow: TimeInterval = 30 * 60
    /// Titles are cut to a set number of characters; the menu bar is
    /// narrow and the time is the part that has to survive. How many
    /// is the user's call ("Shorten titles to"), within these bounds
    /// and stepped by `titleLengthStep` from the settings row.
    static let defaultTitleLength = 20
    static let titleLengthRange = 5...60
    static let titleLengthStep = 5

    static func clampedTitleLength(_ value: Int) -> Int {
        min(max(value, titleLengthRange.lowerBound), titleLengthRange.upperBound)
    }

    /// The status for `now`, or nil when there is nothing to say: the
    /// mode is off, or no meeting is on, overrunning or still to come
    /// today.
    ///
    /// - Parameters:
    ///   - events: today's events (any order).
    ///   - overrunSince: the end of the meeting whose timer is still
    ///     running, if there is one — and `overrunTitle`, its name.
    ///   - titleLength: characters of the title to keep.
    ///
    /// Every event counts, whatever kind it is — a focus block is as
    /// much "what's next" as a 1:1. Muted titles count too: muting
    /// turns off the *start prompt* for a meeting, which is a separate
    /// question from whether it exists and is coming up.
    static func status(
        events: [CalendarEvent],
        now: Date,
        mode: MeetingCountdownMode,
        overrunSince: Date? = nil,
        overrunTitle: String = "",
        titleLength: Int = defaultTitleLength
    ) -> MenuBarMeetingStatus? {
        guard mode != .off else { return nil }
        let current = events
            .filter { $0.start <= now && now < $0.end }
            .max(by: { $0.start < $1.start })
        let next = events
            .filter { $0.start > now }
            .min(by: { $0.start < $1.start })

        /// "Design review " ahead of the time, when titles are shown.
        func titled(_ name: String, _ time: String) -> String {
            let title = shortTitle(name, limit: titleLength)
            return (mode == .titleAndTime && !title.isEmpty) ? "\(title) \(time)" : time
        }

        if let current {
            // Named, like an upcoming one: "50m left" on its own doesn't
            // say what is ending. Kept terse — this is the longest line
            // the menu bar shows, and the two numbers are what get read.
            var text = titled(current.summary, "\(until(current.end, from: now)) left")
            if let next, next.start.timeIntervalSince(now) <= nextMentionWindow {
                text += " · next \(until(next.start, from: now))"
            }
            return MenuBarMeetingStatus(text: text)
        }

        let nextIsImminent = next.map { $0.start.timeIntervalSince(now) <= imminentWindow } ?? false

        // A meeting's timer still running after it ended is the one
        // thing here that wants doing something about — it outranks a
        // meeting that is merely later, but not one about to begin.
        if let overrunSince, now >= overrunSince, !nextIsImminent {
            let minutes = max(1, Int(now.timeIntervalSince(overrunSince) / 60))
            return MenuBarMeetingStatus(
                text: titled(overrunTitle, "ended \(span(minutes: minutes)) ago"),
                tone: .overrun
            )
        }

        guard let next else { return nil }
        return MenuBarMeetingStatus(
            text: titled(next.summary, "in \(until(next.start, from: now))"),
            tone: nextIsImminent ? .imminent : .plain
        )
    }

    /// "1h 22m", "45m", "2h". Rounded up, so a meeting 30 seconds away
    /// is "1m" rather than "0m" — it hasn't started yet.
    static func until(_ date: Date, from now: Date) -> String {
        span(minutes: max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up))))
    }

    static func span(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    /// `title` cut to `limit` characters, the last of them an ellipsis
    /// when anything was dropped.
    static func shortTitle(_ title: String, limit: Int = defaultTitleLength) -> String {
        let limit = clampedTitleLength(limit)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return trimmed.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
