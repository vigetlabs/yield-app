import Foundation
import SwiftUI
import UserNotifications

@Observable
final class TimeComparisonViewModel {
    var projectStatuses: [ProjectStatus] = []
    var totalLogged: Double = 0
    var totalBooked: Double = 0
    var totalUnbookedLogged: Double = 0
    var totalTodayLogged: Double = 0
    var weekLabel: String = ""
    var lastUpdated: Date? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var elapsedOffset: Double = 0  // hours elapsed locally since last API refresh
    var selectedTab: ProjectTab = .recent
    var pausedState: PausedTimerState? = nil

    enum ProjectTab: String, CaseIterable {
        case recent, forecasted
    }

    struct PausedTimerState {
        let projectName: String
        let taskName: String
        let entryId: Int
        let frozenHours: Double
    }

    var filteredStatuses: [ProjectStatus] {
        switch selectedTab {
        case .recent:
            return projectStatuses
        case .forecasted:
            return projectStatuses.filter { $0.bookedHours > 0 }
        }
    }

    /// The currently tracking project, if any
    var trackingProject: ProjectStatus? {
        projectStatuses.first(where: { $0.isTracking })
    }

    /// The running time entry from the tracking project
    var trackingEntry: TimeEntryInfo? {
        trackingProject?.timeEntries.first(where: { $0.isRunning })
    }

    /// Whether the timer banner should be visible
    var isTimerBannerVisible: Bool {
        trackingProject != nil || pausedState != nil
    }

    /// Whether the timer is currently paused (stopped but banner still showing)
    var isTimerPaused: Bool {
        pausedState != nil && trackingProject == nil
    }

    private var refreshTimer: Timer?
    private var elapsedTimer: Timer?
    private var notifiedProjectIds: Set<Int> = []

    enum AuthMode {
        case oauth, pat, none
    }

    var authMode: AuthMode {
        // OAuth takes priority
        if KeychainHelper.load(key: "accessToken") != nil,
           let hId = UserDefaults.standard.string(forKey: "oauthHarvestAccountId"), !hId.isEmpty,
           let fId = UserDefaults.standard.string(forKey: "oauthForecastAccountId"), !fId.isEmpty {
            return .oauth
        }
        // Fall back to PAT
        let token = UserDefaults.standard.string(forKey: "harvestToken") ?? ""
        let harvestId = UserDefaults.standard.string(forKey: "harvestAccountId") ?? ""
        let forecastId = UserDefaults.standard.string(forKey: "forecastAccountId") ?? ""
        if !token.isEmpty && !harvestId.isEmpty && !forecastId.isEmpty {
            return .pat
        }
        return .none
    }

    var isConfigured: Bool {
        authMode != .none
    }

    var menuBarLabel: String {
        guard lastUpdated != nil else { return "" }
        guard let tracking = projectStatuses.first(where: { $0.isTracking }) else {
            let remaining = totalBooked - totalLogged
            return formatRemaining(remaining)
        }
        let effectiveLogged = tracking.loggedHours + elapsedOffset
        let remaining = tracking.bookedHours - effectiveLogged
        return formatRemaining(remaining)
    }

    func effectiveLoggedHours(for project: ProjectStatus) -> Double {
        project.loggedHours + (project.isTracking ? elapsedOffset : 0)
    }

    private func formatRemaining(_ hours: Double) -> String {
        let abs = Swift.abs(hours)
        let h = Int(abs)
        let m = Int((abs - Double(h)) * 60)
        if hours < 0 {
            return String(format: "%d:%02d over", h, m)
        }
        return String(format: "%d:%02d left", h, m)
    }

    private func makeServices() -> (HarvestService, ForecastService)? {
        switch authMode {
        case .oauth:
            let oAuth = AppState.shared.oAuthService
            let harvestId = UserDefaults.standard.string(forKey: "oauthHarvestAccountId")!
            let forecastId = UserDefaults.standard.string(forKey: "oauthForecastAccountId")!
            let tokenProvider: () async throws -> String = { try await oAuth.getAccessToken() }
            return (
                HarvestService(tokenProvider: tokenProvider, accountId: harvestId),
                ForecastService(tokenProvider: tokenProvider, accountId: forecastId)
            )
        case .pat:
            let token = UserDefaults.standard.string(forKey: "harvestToken")!
            let harvestId = UserDefaults.standard.string(forKey: "harvestAccountId")!
            let forecastId = UserDefaults.standard.string(forKey: "forecastAccountId")!
            return (
                HarvestService(token: token, accountId: harvestId),
                ForecastService(token: token, accountId: forecastId)
            )
        case .none:
            return nil
        }
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        Task { @MainActor in
            await refresh()
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopElapsedTimer()
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedOffset = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedOffset += 1.0 / 60.0  // add 1 minute in hours
                self.checkBookedHoursReached()
            }
        }
    }

    private func checkBookedHoursReached() {
        for project in projectStatuses where project.isTracking {
            let effective = effectiveLoggedHours(for: project)
            if project.bookedHours > 0,
               effective >= project.bookedHours,
               !notifiedProjectIds.contains(project.id) {
                notifiedProjectIds.insert(project.id)
                sendBookedHoursNotification(for: project)
            }
        }
    }

    private func sendBookedHoursNotification(for project: ProjectStatus) {
        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        let hours = project.bookedHours == project.bookedHours.rounded()
            ? String(format: "%.0f", project.bookedHours)
            : String(format: "%.1f", project.bookedHours)
        let name = [project.clientName, project.projectName].compactMap { $0 }.joined(separator: " — ")
        content.body = "\(name): You've reached your booked hours (\(hours)h)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "booked-hours-\(project.id)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func makeEntryInfos(from entries: [HarvestTimeEntry]) -> [TimeEntryInfo] {
        entries.map { entry in
            TimeEntryInfo(
                id: entry.id,
                taskName: entry.task?.name ?? entry.taskAssignment?.task?.name ?? "Unknown Task",
                hours: entry.hours,
                date: entry.spentDate,
                isRunning: entry.isRunning,
                notes: entry.notes
            )
        }.sorted { a, b in
            // Running first, then by date descending, then by hours descending
            if a.isRunning != b.isRunning { return a.isRunning }
            if a.date != b.date { return a.date > b.date }
            return a.hours > b.hours
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedOffset = 0
    }

    @MainActor
    func toggleTimer(for project: ProjectStatus) async {
        guard let (harvestService, _) = makeServices() else { return }
        let service = harvestService
        guard let harvestProjectId = project.harvestProjectId else { return }
        pausedState = nil

        do {
            // Stop any currently running timer first
            if let running = projectStatuses.first(where: { $0.isTracking }),
               let runningEntryId = running.todayEntryId {
                _ = try await service.stopTimer(entryId: runningEntryId)
            }

            if project.isTracking {
                // We just stopped it above — done
            } else if let todayEntryId = project.todayEntryId {
                // There's already an entry for today — restart it
                _ = try await service.restartTimer(entryId: todayEntryId)
            } else {
                // No entry for today — create a new one (timer starts automatically)
                // Use known task ID, or fetch the first active task for this project
                var taskId = project.lastTaskId
                if taskId == nil {
                    let tasks = try await service.getTaskAssignments(projectId: harvestProjectId)
                    taskId = tasks.first?.task.id
                }
                guard let resolvedTaskId = taskId else {
                    errorMessage = "No tasks assigned to this project in Harvest."
                    return
                }
                _ = try await service.createTimeEntry(projectId: harvestProjectId, taskId: resolvedTaskId)
            }

            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func pauseTimer() async {
        guard let project = trackingProject,
              let entry = trackingEntry,
              let (harvestService, _) = makeServices() else { return }

        // Save paused state before stopping
        let effectiveHours = effectiveLoggedHours(for: project)
        pausedState = PausedTimerState(
            projectName: project.projectName,
            taskName: entry.taskName,
            entryId: entry.id,
            frozenHours: effectiveHours
        )

        do {
            _ = try await harvestService.stopTimer(entryId: entry.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            pausedState = nil
        }
    }

    @MainActor
    func resumeTimer() async {
        guard let paused = pausedState,
              let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.restartTimer(entryId: paused.entryId)
            pausedState = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func stopBannerTimer() async {
        if let entry = trackingEntry,
           let (harvestService, _) = makeServices() {
            do {
                _ = try await harvestService.stopTimer(entryId: entry.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        pausedState = nil
        await refresh()
    }

    @MainActor
    func toggleEntryTimer(entryId: Int, isRunning: Bool) async {
        guard let (harvestService, _) = makeServices() else { return }
        if !isRunning { pausedState = nil }

        do {
            if isRunning {
                _ = try await harvestService.stopTimer(entryId: entryId)
            } else {
                // Stop any currently running timer first
                if let running = projectStatuses.first(where: { $0.isTracking }),
                   let runningEntryId = running.todayEntryId {
                    _ = try await harvestService.stopTimer(entryId: runningEntryId)
                }
                _ = try await harvestService.restartTimer(entryId: entryId)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func refresh() async {
        guard isConfigured else {
            errorMessage = "Open Settings to configure your API credentials."
            return
        }

        isLoading = true
        errorMessage = nil

        guard let (harvestService, forecastService) = makeServices() else {
            errorMessage = "API credentials not configured."
            isLoading = false
            return
        }

        let weekDates = DateHelpers.weekDateStrings()
        let weekBounds = DateHelpers.currentWeekBounds()
        let todayString = DateHelpers.dateFormatter.string(from: Date())

        do {
            // Fetch current user IDs in parallel
            async let harvestUser = harvestService.getCurrentUser()
            async let forecastPerson = forecastService.getCurrentPerson()
            async let forecastProjects = forecastService.getProjects()
            async let forecastClients = forecastService.getClients()

            let user = try await harvestUser
            let person = try await forecastPerson
            let projects = try await forecastProjects

            // Backfill user name if missing (e.g. after cache clear)
            if AppState.shared.oAuthService.userName == nil {
                let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
                if !name.isEmpty {
                    UserDefaults.standard.set(name, forKey: "oauthUserName")
                }
            }
            let clients = try await forecastClients

            // Build lookups
            let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            let clientMap = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
            // Fetch time data in parallel
            async let timeEntries = harvestService.getTimeEntries(
                userId: user.id,
                from: weekDates.start,
                to: weekDates.end
            )
            async let assignments = forecastService.getAssignments(
                personId: person.id,
                startDate: weekDates.start,
                endDate: weekDates.end
            )

            let entries = try await timeEntries
            let allAssignments = try await assignments

            // Aggregate logged hours by Harvest project ID and track timers
            var loggedByHarvestProject: [Int: Double] = [:]
            var todayByHarvestProject: [Int: Double] = [:]
            var harvestProjectNames: [Int: String] = [:]
            var harvestClientNames: [Int: String] = [:]
            var runningHarvestProjectIds: Set<Int> = []
            var todayEntryByProject: [Int: HarvestTimeEntry] = [:]  // today's entry per project
            var latestEntryByProject: [Int: HarvestTimeEntry] = [:]  // any entry (for task ID)
            var latestUpdatedAt: [Int: String] = [:]  // most recent updatedAt per project
            var entriesByHarvestProject: [Int: [HarvestTimeEntry]] = [:]

            for entry in entries {
                entriesByHarvestProject[entry.project.id, default: []].append(entry)
                loggedByHarvestProject[entry.project.id, default: 0] += entry.hours
                if entry.spentDate == todayString {
                    todayByHarvestProject[entry.project.id, default: 0] += entry.hours
                }
                harvestProjectNames[entry.project.id] = entry.project.name
                if let client = entry.client {
                    harvestClientNames[entry.project.id] = client.name
                }
                if entry.isRunning {
                    runningHarvestProjectIds.insert(entry.project.id)
                    todayEntryByProject[entry.project.id] = entry
                }
                // Track today's entry (prefer running, then most recent for today)
                if entry.spentDate == todayString && todayEntryByProject[entry.project.id] == nil {
                    todayEntryByProject[entry.project.id] = entry
                }
                // Track latest entry overall (for task ID when creating new entries)
                if latestEntryByProject[entry.project.id] == nil {
                    latestEntryByProject[entry.project.id] = entry
                }
                // Track most recent updatedAt per project
                if let existing = latestUpdatedAt[entry.project.id] {
                    if entry.updatedAt > existing {
                        latestUpdatedAt[entry.project.id] = entry.updatedAt
                    }
                } else {
                    latestUpdatedAt[entry.project.id] = entry.updatedAt
                }
            }

            // Aggregate booked hours by Forecast project ID
            var bookedByForecastProject: [Int: Double] = [:]
            for assignment in allAssignments {
                guard let projectId = assignment.projectId else { continue }
                let weekdays = DateHelpers.countOverlappingWeekdays(
                    assignmentStart: assignment.startDate,
                    assignmentEnd: assignment.endDate,
                    weekStart: weekBounds.start,
                    weekEnd: weekBounds.end
                )
                let hoursPerDay = Double(assignment.allocation ?? 0) / 3600.0
                bookedByForecastProject[projectId, default: 0] += hoursPerDay * Double(weekdays)
            }

            // Merge into ProjectStatus list
            var statuses: [ProjectStatus] = []
            var processedHarvestIds: Set<Int> = []

            // Start with Forecast projects (booked)
            for (forecastProjectId, bookedHours) in bookedByForecastProject {
                let project = projectMap[forecastProjectId]
                let projectName = project?.name ?? "Unknown Project"
                let clientName = project?.clientId.flatMap { clientMap[$0]?.name }
                var logged: Double = 0
                var tracking = false
                var harvestId: Int? = nil
                var todayEntry: HarvestTimeEntry? = nil
                var latestEntry: HarvestTimeEntry? = nil

                var today: Double = 0

                if let hId = project?.harvestId {
                    harvestId = hId
                    logged = loggedByHarvestProject[hId] ?? 0
                    today = todayByHarvestProject[hId] ?? 0
                    tracking = runningHarvestProjectIds.contains(hId)
                    todayEntry = todayEntryByProject[hId]
                    latestEntry = latestEntryByProject[hId]
                    processedHarvestIds.insert(hId)
                }

                statuses.append(ProjectStatus(
                    id: forecastProjectId,
                    clientName: clientName,
                    projectName: projectName,
                    bookedHours: bookedHours,
                    loggedHours: logged,
                    todayHours: today,
                    isTracking: tracking,
                    harvestProjectId: harvestId,
                    todayEntryId: todayEntry?.id,
                    lastTaskId: (latestEntry ?? todayEntry)?.taskAssignment?.task?.id,
                    lastTrackedAt: harvestId.flatMap { latestUpdatedAt[$0] },
                    timeEntries: Self.makeEntryInfos(from: harvestId.flatMap { entriesByHarvestProject[$0] } ?? [])
                ))
            }

            // Add Harvest-only projects (logged but not booked)
            for (harvestProjectId, loggedHours) in loggedByHarvestProject {
                if processedHarvestIds.contains(harvestProjectId) { continue }
                let projectName = harvestProjectNames[harvestProjectId] ?? "Unknown Project"
                let clientName = harvestClientNames[harvestProjectId]
                let todayEntry = todayEntryByProject[harvestProjectId]
                let latestEntry = latestEntryByProject[harvestProjectId]
                statuses.append(ProjectStatus(
                    id: harvestProjectId + 1_000_000,
                    clientName: clientName,
                    projectName: projectName,
                    bookedHours: 0,
                    loggedHours: loggedHours,
                    todayHours: todayByHarvestProject[harvestProjectId] ?? 0,
                    isTracking: runningHarvestProjectIds.contains(harvestProjectId),
                    harvestProjectId: harvestProjectId,
                    todayEntryId: todayEntry?.id,
                    lastTaskId: (latestEntry ?? todayEntry)?.taskAssignment?.task?.id,
                    lastTrackedAt: latestUpdatedAt[harvestProjectId],
                    timeEntries: Self.makeEntryInfos(from: entriesByHarvestProject[harvestProjectId] ?? [])
                ))
            }

            // Sort: currently tracking first, then by most recently tracked, then untracked by name
            statuses.sort { a, b in
                // Currently tracking always comes first
                if a.isTracking != b.isTracking {
                    return a.isTracking
                }
                // Both have been tracked — sort by most recent activity
                if let aTime = a.lastTrackedAt, let bTime = b.lastTrackedAt {
                    return aTime > bTime
                }
                // Tracked before untracked
                if (a.lastTrackedAt != nil) != (b.lastTrackedAt != nil) {
                    return a.lastTrackedAt != nil
                }
                // Neither tracked — sort by project name
                return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
            }

            projectStatuses = statuses
            let booked = statuses.filter { $0.bookedHours > 0 }
            let unbooked = statuses.filter { $0.bookedHours == 0 }
            totalLogged = booked.reduce(0) { $0 + $1.loggedHours }
            totalBooked = booked.reduce(0) { $0 + $1.bookedHours }
            totalUnbookedLogged = unbooked.reduce(0) { $0 + $1.loggedHours }
            totalTodayLogged = statuses.reduce(0) { $0 + $1.todayHours }
            weekLabel = DateHelpers.formattedWeekRange()
            lastUpdated = Date()

            // Reset elapsed counter — API data is fresh
            // Remove notifications only for projects no longer being tracked
            notifiedProjectIds = notifiedProjectIds.filter { id in
                statuses.contains { $0.id == id && $0.isTracking }
            }
            if statuses.contains(where: { $0.isTracking }) {
                startElapsedTimer()
                checkBookedHoursReached()
            } else {
                stopElapsedTimer()
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
