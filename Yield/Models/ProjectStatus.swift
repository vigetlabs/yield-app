import Foundation

struct TimeEntryInfo: Identifiable {
    let id: Int
    let harvestProjectId: Int
    let taskId: Int
    let taskName: String
    let hours: Double
    let date: String
    let isRunning: Bool
    let notes: String?
}

struct ProjectStatus: Identifiable {
    let id: String
    let clientName: String?
    let projectName: String
    let bookedHours: Double
    let loggedHours: Double
    let todayHours: Double
    let isTracking: Bool
    let harvestProjectId: Int?
    let todayEntryId: Int?      // today's time entry (restart this if it exists)
    let lastTaskId: Int?        // task ID from most recent entry (for creating new entries)
    let timeEntries: [TimeEntryInfo]
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
        let abs = Swift.abs(remainingHours)
        let h = Int(abs)
        let m = Int((abs - Double(h)) * 60)
        let suffix = isOver ? "over this week" : "remaining this week"
        return "\(h)h \(String(format: "%02d", m))m \(suffix)"
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
