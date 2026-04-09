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
    let lastTrackedAt: String?  // ISO 8601 timestamp of most recent entry update
    let timeEntries: [TimeEntryInfo]

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
        max(bookedHours - loggedHours, 0)
    }

    var remainingFormatted: String {
        let h = Int(remainingHours)
        let m = Int((remainingHours - Double(h)) * 60)
        return "\(h)h \(String(format: "%02d", m))m remaining this week"
    }

    var isForecasted: Bool {
        bookedHours > 0
    }
}
