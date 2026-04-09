import CoreGraphics
import Foundation
import SwiftUI
import UserNotifications

@Observable
final class TimeComparisonViewModel {
    deinit {
        refreshTimer?.invalidate()
        activeRefreshTask?.cancel()
        elapsedTimer?.invalidate()
    }

    var projectStatuses: [ProjectStatus] = []
    var totalLogged: Double = 0
    var totalBooked: Double = 0
    var totalUnbookedLogged: Double = 0
    var totalTodayLogged: Double = 0
    var dailyHours: [DayHours] = []

    struct DayHours: Identifiable {
        let id: String          // date string YYYY-MM-DD
        let dayLabel: String    // "Mon", "Tue", etc.
        let hours: Double
        let isToday: Bool
    }
    var weekLabel: String = ""
    var lastUpdated: Date? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var serviceErrors: [ServiceError] = []

    #if DEBUG
    /// Set to simulate API failures for UI testing.
    /// Options: .harvest, .forecast, or both.
    var simulateServiceFailures: Set<ServiceName> = []
    #endif

    struct ServiceError: Identifiable {
        let id = UUID()
        let service: ServiceName
        let message: String
    }

    enum ServiceName: String {
        case harvest = "Harvest"
        case forecast = "Forecast"
    }

    /// Whether Harvest API is currently unreachable (timer controls should be disabled)
    var isHarvestDown: Bool {
        serviceErrors.contains { $0.service == .harvest }
    }
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

    struct IdleAlertState {
        let idleStartDate: Date       // when idle was first detected
        let entryId: Int
        let projectName: String
        let hoursAtIdleStart: Double   // entry hours of real work (before idle began)

        /// Current idle duration in minutes, updating live
        var currentIdleMinutes: Int {
            max(1, Int(Date().timeIntervalSince(idleStartDate) / 60))
        }

        /// Hours to set the entry to if removing idle time
        var adjustedHours: Double {
            max(0, hoursAtIdleStart)
        }
    }

    var idleAlertState: IdleAlertState? = nil

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
    private var activeRefreshTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var notifiedProjectIds: Set<String> = []
    private var idleNotificationSent: Bool = false

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
            guard let harvestId = UserDefaults.standard.string(forKey: "oauthHarvestAccountId"),
                  let forecastId = UserDefaults.standard.string(forKey: "oauthForecastAccountId") else {
                return nil
            }
            let tokenProvider: () async throws -> String = { try await oAuth.getAccessToken() }
            return (
                HarvestService(tokenProvider: tokenProvider, accountId: harvestId),
                ForecastService(tokenProvider: tokenProvider, accountId: forecastId)
            )
        case .pat:
            guard let token = UserDefaults.standard.string(forKey: "harvestToken"),
                  let harvestId = UserDefaults.standard.string(forKey: "harvestAccountId"),
                  let forecastId = UserDefaults.standard.string(forKey: "forecastAccountId") else {
                return nil
            }
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
        activeRefreshTask?.cancel()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.activeRefreshTask?.cancel()
            self.activeRefreshTask = Task { @MainActor in
                await self.refresh()
            }
        }
        activeRefreshTask = Task { @MainActor in
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
        idleNotificationSent = false
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedOffset += 1.0 / 60.0  // add 1 minute in hours
                self.checkBookedHoursReached()
                self.checkIdleTime()
            }
        }
    }

    private func checkIdleTime() {
        let enabled = UserDefaults.standard.bool(forKey: "idleDetectionEnabled")
        guard enabled else {
            idleNotificationSent = false
            return
        }

        // Only alert when a timer is actively running
        guard let project = trackingProject,
              let entry = trackingEntry else {
            idleNotificationSent = false
            return
        }

        // Don't check if we're already showing the idle alert
        guard idleAlertState == nil else { return }

        let idleMinutes = UserDefaults.standard.integer(forKey: "idleMinutes")
        let thresholdSeconds = Double(max(idleMinutes, 1)) * 60.0

        // Get system-wide idle time (seconds since last keyboard/mouse/trackpad event)
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0) ?? .mouseMoved
        )

        if idleSeconds >= thresholdSeconds {
            if !idleNotificationSent {
                idleNotificationSent = true

                // Use the actual idle seconds from CGEventSource (not the threshold)
                // since the check fires every 60s, actual idle could be beyond threshold
                let actualIdleHours = idleSeconds / 3600.0
                let hoursAtIdleStart = max(0, entry.hours - actualIdleHours)

                let name = [project.clientName, project.projectName]
                    .compactMap { $0 }
                    .joined(separator: " — ")

                idleAlertState = IdleAlertState(
                    idleStartDate: Date().addingTimeInterval(-idleSeconds),
                    entryId: entry.id,
                    projectName: name,
                    hoursAtIdleStart: hoursAtIdleStart
                )

                // Open the menu bar popup so the user sees the idle alert inline
                openMenuBarPanel()
            }
        } else {
            // User is active again — reset so we can notify next time
            if idleNotificationSent {
                idleNotificationSent = false
            }
        }
    }

    /// Programmatically open the MenuBarExtra panel by clicking its NSStatusItem button.
    private func openMenuBarPanel() {
        // Find our status item button — it's the one whose window belongs to this app
        guard let button = NSApp.windows
            .compactMap({ $0.value(forKey: "statusItem") as? NSStatusItem })
            .first?.button
        else { return }
        button.performClick(nil)
    }

    // MARK: - Idle Alert Actions

    /// Continue timing but subtract the idle time from the entry
    @MainActor
    func idleContinueAndRemoveTime() async {
        guard let alert = idleAlertState,
              let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.stopTimer(entryId: alert.entryId)
            do {
                _ = try await harvestService.updateTimeEntry(entryId: alert.entryId, hours: alert.adjustedHours, notes: nil)
            } catch {
                // Update failed — restart timer to avoid leaving it stopped
                _ = try? await harvestService.restartTimer(entryId: alert.entryId)
                throw error
            }
            _ = try await harvestService.restartTimer(entryId: alert.entryId)
            idleAlertState = nil
            idleNotificationSent = false
            await refresh()
        } catch {
            errorMessage = "Failed to adjust idle time: \(error.localizedDescription)"
        }
    }

    /// Stop the timer and subtract the idle time
    @MainActor
    func idleStopAndRemoveTime() async {
        guard let alert = idleAlertState,
              let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.stopTimer(entryId: alert.entryId)
            _ = try await harvestService.updateTimeEntry(entryId: alert.entryId, hours: alert.adjustedHours, notes: nil)
            idleAlertState = nil
            pausedState = nil
            idleNotificationSent = false
            await refresh()
        } catch {
            errorMessage = "Failed to adjust idle time: \(error.localizedDescription)"
        }
    }

    /// Keep all the time (including idle) and dismiss
    @MainActor
    func idleDismiss() {
        idleAlertState = nil
        idleNotificationSent = false
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
        entries.compactMap { entry in
            guard let taskId = entry.task?.id ?? entry.taskAssignment?.task?.id else { return nil }
            return TimeEntryInfo(
                id: entry.id,
                harvestProjectId: entry.project.id,
                taskId: taskId,
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

    /// Fetch task assignments for a Harvest project (used by NewTimerFormView)
    func fetchTaskAssignments(projectId: Int) async throws -> [HarvestProjectTaskAssignment] {
        guard let (harvestService, _) = makeServices() else { return [] }
        return try await harvestService.getTaskAssignments(projectId: projectId)
    }

    /// Fetch all active projects assigned to the current user (used by NewTimerFormView)
    func fetchAllProjects() async throws -> [TimerProjectOption] {
        guard let (harvestService, _) = makeServices() else { return [] }

        let assignments = try await harvestService.getMyProjectAssignments()

        return assignments
            .filter { $0.isActive }
            .map { assignment in
                TimerProjectOption(
                    harvestProjectId: assignment.project.id,
                    projectName: assignment.project.name,
                    clientName: assignment.client?.name
                )
            }
            .sorted { a, b in
                let aName = a.clientName ?? ""
                let bName = b.clientName ?? ""
                if aName != bName { return aName < bName }
                return a.projectName < b.projectName
            }
    }

    struct TimerProjectOption: Identifiable, Hashable {
        var id: Int { harvestProjectId }
        let harvestProjectId: Int
        let projectName: String
        let clientName: String?
    }

    /// Start a new timer for a specific project and task, stopping any running timer first
    @MainActor
    func startNewTimer(projectId: Int, taskId: Int, notes: String? = nil) async {
        guard let (harvestService, _) = makeServices() else { return }
        pausedState = nil

        do {
            // Stop any currently running timer
            if let running = projectStatuses.first(where: { $0.isTracking }),
               let runningEntryId = running.todayEntryId {
                _ = try await harvestService.stopTimer(entryId: runningEntryId)
            }

            // Create new entry (starts timer automatically)
            _ = try await harvestService.createTimeEntry(projectId: projectId, taskId: taskId, notes: notes)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Log a time entry with specific hours (no running timer)
    @MainActor
    func logTimeEntry(projectId: Int, taskId: Int, hours: Double, notes: String? = nil) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.createTimeEntry(projectId: projectId, taskId: taskId, hours: hours, notes: notes)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a time entry
    @MainActor
    func deleteTimeEntry(entryId: Int) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            try await harvestService.deleteTimeEntry(entryId: entryId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update an existing time entry's task, hours, and/or notes
    @MainActor
    func updateExistingEntry(entryId: Int, taskId: Int, hours: Double, notes: String) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.updateTimeEntry(
                entryId: entryId,
                hours: hours,
                taskId: taskId,
                notes: notes
            )
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
        serviceErrors = []

        guard let (harvestService, forecastService) = makeServices() else {
            errorMessage = "API credentials not configured."
            isLoading = false
            return
        }

        let weekDates = DateHelpers.weekDateStrings()
        let weekBounds = DateHelpers.currentWeekBounds()
        let todayString = DateHelpers.dateFormatter.string(from: Date())

        do {
            // Fetch Harvest data
            let user: HarvestUserResponse
            let entries: [HarvestTimeEntry]
            do {
                user = try await harvestService.getCurrentUser()

                // Backfill user name if missing (e.g. after cache clear)
                if AppState.shared.oAuthService.userName == nil {
                    let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
                    if !name.isEmpty {
                        UserDefaults.standard.set(name, forKey: "oauthUserName")
                    }
                }

                entries = try await harvestService.getTimeEntries(
                    userId: user.id,
                    from: weekDates.start,
                    to: weekDates.end
                )
            } catch {
                serviceErrors.append(ServiceError(service: .harvest, message: friendlyErrorMessage(error)))
                throw error
            }

            // Fetch Forecast data
            let person: ForecastCurrentUser
            let projects: [ForecastProject]
            let clients: [ForecastClient]
            let allAssignments: [ForecastAssignment]
            do {
                async let forecastPerson = forecastService.getCurrentPerson()
                async let forecastProjects = forecastService.getProjects()
                async let forecastClients = forecastService.getClients()

                person = try await forecastPerson
                projects = try await forecastProjects
                clients = try await forecastClients

                allAssignments = try await forecastService.getAssignments(
                    personId: person.id,
                    startDate: weekDates.start,
                    endDate: weekDates.end
                )
            } catch {
                serviceErrors.append(ServiceError(service: .forecast, message: friendlyErrorMessage(error)))
                throw error
            }

            // Build lookups
            let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            let clientMap = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })

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

            // Start with Forecast projects (booked), skip non-Harvest projects (e.g. Time Off)
            for (forecastProjectId, bookedHours) in bookedByForecastProject {
                let project = projectMap[forecastProjectId]
                // Skip Forecast-only projects with no Harvest link (Time Off, PTO, etc.)
                if project?.harvestId == nil { continue }
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
                    id: "forecast-\(forecastProjectId)",
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
                    id: "harvest-\(harvestProjectId)",
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

            // Build daily hours breakdown (Mon–Sun)
            var hoursByDate: [String: Double] = [:]
            for entry in entries {
                hoursByDate[entry.spentDate, default: 0] += entry.hours
            }
            let calendar = Calendar.current
            let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            var days: [DayHours] = []
            for i in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: i, to: weekBounds.start) else { continue }
                let dateStr = DateHelpers.dateFormatter.string(from: date)
                let isToday = calendar.isDateInToday(date)
                days.append(DayHours(
                    id: dateStr,
                    dayLabel: dayLabels[i],
                    hours: hoursByDate[dateStr] ?? 0,
                    isToday: isToday
                ))
            }
            dailyHours = days

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
            if serviceErrors.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = serviceErrors.map { "\($0.service.rawValue): \($0.message)" }.joined(separator: "\n")
            }
        }

        #if DEBUG
        // Inject simulated service failures after real data loads
        if !simulateServiceFailures.isEmpty {
            serviceErrors = []
            for service in simulateServiceFailures {
                serviceErrors.append(ServiceError(service: service, message: "Service unavailable (simulated)"))
            }
            errorMessage = serviceErrors.map { "\($0.service.rawValue): \($0.message)" }.joined(separator: "\n")
        }
        #endif

        isLoading = false
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let code) where (500...599).contains(code):
                return "Service unavailable (HTTP \(code))"
            case .networkError:
                return "Unable to connect"
            default:
                return apiError.localizedDescription
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection"
            case NSURLErrorTimedOut:
                return "Request timed out"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return "Unable to connect"
            default:
                return "Network error"
            }
        }
        return error.localizedDescription
    }
}
