import Foundation
import SwiftUI

struct TimeEntryInfo: Identifiable {
    let id: Int
    let harvestProjectId: Int
    let taskId: Int
    let taskName: String
    let hours: Double
    let date: String
    /// Mutated by the view model's optimistic start/stop helpers so the
    /// UI flips before the Harvest API round-trip completes; the next
    /// refresh reconciles to the server's actual value.
    var isRunning: Bool
    let notes: String?
    /// When the current run of this timer started, parsed from
    /// Harvest's `timer_started_at`. Non-nil iff the entry is running.
    /// Drives the "Started at HH:MM" hover info on the banner.
    let timerStartedAt: Date?
}

struct ProjectStatus: Identifiable {
    let id: String
    let clientName: String?
    let projectName: String
    let bookedHours: Double
    let loggedHours: Double
    let todayHours: Double
    /// Mutated alongside `timeEntries[*].isRunning` by the view model's
    /// optimistic start/stop helpers — the next refresh reconciles.
    var isTracking: Bool
    let harvestProjectId: Int?
    let todayEntryId: Int?      // today's time entry (restart this if it exists)
    let lastTaskId: Int?        // task ID from most recent entry (for creating new entries)
    var timeEntries: [TimeEntryInfo]
    /// Concatenated non-empty notes from all of this week's Forecast
    /// assignments for this project (nil if none). Multiple assignments
    /// with notes are joined with a blank line between them.
    let forecastNotes: String?

    var delta: Double { loggedHours - bookedHours }

    enum Status {
        case onTrack
        case under
        case over
    }

    var status: Status {
        let threshold = max(bookedHours * 0.1, 0.5)
        if loggedHours < bookedHours - threshold { return .under }
        if loggedHours > bookedHours + threshold { return .over }
        return .onTrack
    }

    var remainingHours: Double {
        bookedHours - loggedHours
    }

    var isOver: Bool {
        remainingHours < 0
    }

    var remainingFormatted: String {
        let suffix = isOver ? "over this week" : "remaining this week"
        return "\(Swift.abs(remainingHours).formattedHoursMinutes) \(suffix)"
    }

    var isForecasted: Bool {
        bookedHours > 0
    }

    /// "Client — Project" when a client is known, just the project name
    /// otherwise. Used wherever we surface a project to the user as a
    /// single string — idle alerts, budget notifications, the timer
    /// banner's top label.
    var qualifiedName: String {
        Self.qualifiedName(client: clientName, project: projectName)
    }

    /// Free-standing version for callers that have client/project
    /// strings without a `ProjectStatus` in hand (e.g. the timer
    /// banner, which composes from either the live tracking project or
    /// the snapshot in `PausedTimerState`).
    static func qualifiedName(client: String?, project: String) -> String {
        [client, project].compactMap { $0 }.joined(separator: " — ")
    }
}

extension Double {
    /// Split decimal hours into `(h, m)` rounded to the nearest minute.
    /// Used everywhere we render an `H:MM` or `Hh MMm` display so the
    /// rounding contract is single-sourced — Harvest stores hours at
    /// 0.01h precision and displays the rounded minute, and we want to
    /// match across the row totals, the timer banner, the menu bar
    /// label, and the like. Naturally handles 60-rollover (3.999h → 4:00).
    var roundedHM: (h: Int, m: Int) {
        let total = Int((self * 60).rounded())
        return (total / 60, total % 60)
    }

    /// `"H:MM"` — colon form used by the menu bar label and tooltips.
    /// Handles negative values by applying a single leading minus and
    /// formatting the magnitude (so `-2.5` renders as `"-2:30"`, not
    /// `"-2:-30"`).
    var formattedColon: String {
        let totalMinutes = Int((self * 60).rounded())
        let isNegative = totalMinutes < 0
        let mag = abs(totalMinutes)
        let h = mag / 60
        let m = mag % 60
        return "\(isNegative ? "-" : "")\(h):\(String(format: "%02d", m))"
    }

    /// `"Hh MMm"` — long form used in row times, remaining-hours
    /// labels, and the duplicate banner.
    var formattedHoursMinutes: String {
        let (h, m) = roundedHM
        return "\(h)h \(String(format: "%02d", m))m"
    }
}

extension View {
    /// Disable the view and dim it to 40% opacity when Harvest is
    /// unreachable. The pair shows up on every Harvest-mutating control
    /// (timer toggle buttons, edit affordances) so they read as
    /// uniformly inert during an outage.
    func disabledWhenHarvestDown(_ down: Bool) -> some View {
        self.disabled(down).opacity(down ? 0.4 : 1.0)
    }
}
