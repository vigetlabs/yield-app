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
    var timeOffBlock: TimeOffBlock? = nil

    /// Week offset: 0 = current week (default), <0 = past, >0 = future.
    /// Current-week data stays in `projectStatuses` / `timeOffBlock` / etc.
    /// and keeps auto-refreshing in the background. Other weeks are fetched
    /// on demand and cached in `weekSnapshots`.
    var weekOffset: Int = 0

    /// Cached snapshots for non-current weeks, keyed by weekOffset.
    var weekSnapshots: [Int: WeekSnapshot] = [:]

    /// Loading + error state for non-current week fetches. Kept separate
    /// from `isLoading` / `errorMessage` so the current-week state isn't
    /// disturbed when a look-ahead/back fetch is in flight.
    var isLoadingOtherWeek: Bool = false
    var otherWeekError: String? = nil

    /// Snapshot of the previously-displayed week, captured just before each
    /// navigation. Used as a fallback for the project list / time off / day
    /// bar while the new week's data is loading — prevents the UI from
    /// blanking out during the fetch. The week label isn't held (it updates
    /// immediately so the user sees which week they're heading to).
    private struct TransitionSnapshot {
        var statuses: [ProjectStatus] = []
        var timeOff: TimeOffBlock? = nil
        var dailyHours: [DayHours] = []
    }
    private var transitionSnapshot: TransitionSnapshot = TransitionSnapshot()

    /// A read-only snapshot of a past or future week's project bookings +
    /// time off. Past weeks include logged hours; future weeks have only
    /// booked hours with zero logged.
    struct WeekSnapshot {
        let weekOffset: Int
        let weekLabel: String
        let weekStart: Date
        let statuses: [ProjectStatus]
        let timeOff: TimeOffBlock?
        let dailyHours: [DayHours]
    }

    struct DayHours: Identifiable {
        let id: String          // date string YYYY-MM-DD
        let dayLabel: String    // "Mon", "Tue", etc.
        let hours: Double
        let isToday: Bool
    }

    /// Summary of Forecast time-off bookings for the current week. Forecast
    /// treats all time off (vacation, sick, holiday, etc.) as a single
    /// undeletable "Time Off" project with no type discriminator, so we
    /// display it generically.
    struct TimeOffBlock {
        let totalHours: Double
        let dayLabels: [String]        // e.g. ["Mon", "Tue"] — all affected weekdays
        let fullDayLabels: Set<String> // subset that are full-day blocks (allocation == 0)
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
        case recent, forecasted, chart
    }

    /// Per-project, per-day hours for the current week — used by the chart tab.
    struct ChartPoint: Identifiable {
        let id: String  // "\(projectId)-\(date)"
        let projectId: Int
        let projectName: String
        let date: String       // YYYY-MM-DD
        let dayLabel: String   // "Mon", "Tue"…
        let hours: Double
    }

    /// Day labels on the chart's X-axis. Always Mon–Fri; Sat/Sun are only
    /// appended if someone logged time on those days.
    var chartDays: [String] {
        chartWeekDays().map(\.label)
    }

    /// Returns one point per (project, weekday) for every project that logged any
    /// hours this week. Weekend days are dropped unless time was logged on them,
    /// so the chart defaults to Mon–Fri.
    var chartSeries: [ChartPoint] {
        let weekDays = chartWeekDays()

        let projectsWithTime = projectStatuses.filter { $0.loggedHours > 0 && $0.harvestProjectId != nil }

        var points: [ChartPoint] = []
        for project in projectsWithTime {
            guard let pid = project.harvestProjectId else { continue }

            // Aggregate project's entries by date
            var hoursByDate: [String: Double] = [:]
            for entry in project.timeEntries {
                hoursByDate[entry.date, default: 0] += entry.hours
            }

            for day in weekDays {
                points.append(ChartPoint(
                    id: "\(pid)-\(day.date)",
                    projectId: pid,
                    projectName: project.projectName,
                    date: day.date,
                    dayLabel: day.label,
                    hours: hoursByDate[day.date] ?? 0
                ))
            }
        }
        return points
    }

    /// Days included on the chart. Mon–Fri always; Sat included if any hours
    /// were logged Sat or Sun (so we don't leave a gap); Sun included if Sun
    /// has any hours.
    private func chartWeekDays() -> [(date: String, label: String)] {
        let calendar = Calendar.current
        let weekStart = DateHelpers.currentWeekBounds().start
        let dayLabels = DateHelpers.weekdayLabels

        var allDays: [(date: String, label: String)] = []
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: i, to: weekStart) else { continue }
            allDays.append((DateHelpers.dateFormatter.string(from: date), dayLabels[i]))
        }

        // Sum every project's hours per day
        var hoursByDate: [String: Double] = [:]
        for project in projectStatuses {
            for entry in project.timeEntries {
                hoursByDate[entry.date, default: 0] += entry.hours
            }
        }

        let satHours = hoursByDate[allDays[5].date] ?? 0
        let sunHours = hoursByDate[allDays[6].date] ?? 0

        var days = Array(allDays.prefix(5))  // Mon–Fri
        if satHours > 0 || sunHours > 0 {
            days.append(allDays[5])  // Sat — include if weekend was worked at all
        }
        if sunHours > 0 {
            days.append(allDays[6])  // Sun
        }
        return days
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
        case .chart:
            return []  // chart tab renders its own view; list is hidden
        }
    }

    // MARK: - Week navigation

    var isViewingOtherWeek: Bool { weekOffset != 0 }

    /// Statuses to render for the currently displayed week. For offset 0
    /// this is the live current-week data; for other offsets it's the
    /// cached snapshot, or the previous week's data (held during the
    /// fetch) if the cache isn't populated yet.
    var displayedStatuses: [ProjectStatus] {
        if weekOffset == 0 { return projectStatuses }
        if let snap = weekSnapshots[weekOffset] { return snap.statuses }
        return transitionSnapshot.statuses
    }

    /// Display statuses filtered by tab / week context.
    /// - Current week: respects the Recent / Forecasted tab selection.
    /// - Future weeks: only booked projects (no logged time exists yet).
    /// - Past weeks: all projects, booked or logged-only.
    var displayedFilteredStatuses: [ProjectStatus] {
        guard weekOffset != 0 else { return filteredStatuses }
        return weekOffset > 0
            ? displayedStatuses.filter { $0.bookedHours > 0 }
            : displayedStatuses
    }

    var displayedTimeOff: TimeOffBlock? {
        if weekOffset == 0 { return timeOffBlock }
        if let snap = weekSnapshots[weekOffset] { return snap.timeOff }
        return transitionSnapshot.timeOff
    }

    /// Week label always reflects the current offset immediately, even
    /// while the new week is loading — so the user sees where they're
    /// navigating to.
    var displayedWeekLabel: String {
        if weekOffset == 0 { return weekLabel }
        return weekSnapshots[weekOffset]?.weekLabel
            ?? DateHelpers.formattedWeekRange(offset: weekOffset)
    }

    var displayedDailyHours: [DayHours] {
        if weekOffset == 0 { return dailyHours }
        if let snap = weekSnapshots[weekOffset] { return snap.dailyHours }
        return transitionSnapshot.dailyHours
    }

    /// Capture the currently-displayed data so it can be held on screen
    /// while the next week's fetch is in flight.
    private func captureTransitionSnapshot() {
        transitionSnapshot = TransitionSnapshot(
            statuses: displayedStatuses,
            timeOff: displayedTimeOff,
            dailyHours: displayedDailyHours
        )
    }

    @MainActor
    func advanceWeek() {
        captureTransitionSnapshot()
        weekOffset += 1
        otherWeekError = nil
        if weekSnapshots[weekOffset] == nil {
            Task { await fetchWeek(offset: weekOffset) }
        }
    }

    @MainActor
    func goBackWeek() {
        captureTransitionSnapshot()
        weekOffset -= 1
        otherWeekError = nil
        if weekSnapshots[weekOffset] == nil {
            Task { await fetchWeek(offset: weekOffset) }
        }
    }

    @MainActor
    func returnToCurrentWeek() {
        weekOffset = 0
        otherWeekError = nil
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
    /// Projects we've already notified (or explicitly suppressed) for the
    /// current week. Sticky across timer stop/start cycles — only cleared on
    /// week rollover (see `currentWeekStart`). Prevents duplicate "Time's up!"
    /// alerts when a user starts, stops, or restarts a timer on a project that
    /// is already over budget.
    private var notifiedProjectIds: Set<String> = []
    private var idleNotificationSent: Bool = false

    /// Week-start date (Monday) for both the soft-refresh cache and the
    /// notification suppression set. When the week rolls over we clear both
    /// so stale data doesn't leak across weeks.
    private var currentWeekStart: Date?

    // Cached state from last hard refresh — used by softRefresh() to avoid
    // re-fetching Forecast data and non-today Harvest entries every minute.
    private var cachedWeekEntries: [HarvestTimeEntry] = []
    private var cachedForecastBookings: [Int: Double] = [:]
    private var cachedProjectMap: [Int: ForecastProject] = [:]
    private var cachedClientMap: [Int: ForecastClient] = [:]
    private var cachedTimeOffBlock: TimeOffBlock?
    private var cachedHarvestUserId: Int?
    private var cachedForecastPersonId: Int?

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

    enum MenuBarIcon {
        case calendar                      // no timer running
        case gaugeUnder(progress: Double)  // booked timer, under budget (rotates)
        case gaugeOver                     // booked timer, over budget
        case timer                         // unbooked timer running
        case timeOff                       // full day of PTO today, no timer
        case error                         // API error
    }

    /// True when today is a full day of Forecast time off (allocation=0) and
    /// there's no active/paused timer. Used to swap the menu bar icon for a
    /// "you're off today" signal.
    var isFullDayOffToday: Bool {
        guard let block = timeOffBlock else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: Sun=1, Mon=2, ..., Sat=7
        let labels = [nil, "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard weekday >= 1, weekday <= 7, let label = labels[weekday] else { return false }
        return block.fullDayLabels.contains(label)
    }

    /// The project containing the paused entry, if any
    private var pausedProject: ProjectStatus? {
        guard let paused = pausedState else { return nil }
        return projectStatuses.first { project in
            project.timeEntries.contains(where: { $0.id == paused.entryId })
        }
    }

    /// Minimum weekly budget floor used when user has little or no forecast data
    private static let minimumWeeklyBudget: Double = 40

    var menuBarLabel: String {
        guard lastUpdated != nil else { return "" }

        // Active tracking timer
        if let tracking = projectStatuses.first(where: { $0.isTracking }) {
            if tracking.bookedHours == 0 {
                // Unbooked: current entry (live) / today's total (live)
                let entryHours = (trackingEntry?.hours ?? 0) + elapsedOffset
                let todayTotal = totalTodayLogged + elapsedOffset
                return formatPair(entryHours, todayTotal)
            }
            // Booked: project tracked / project booked
            let tracked = tracking.loggedHours + elapsedOffset
            return formatPair(tracked, tracking.bookedHours)
        }

        // Paused timer — same semantics as active, frozen values (no live offset)
        if let project = pausedProject {
            if project.bookedHours == 0 {
                // Unbooked paused: frozen entry hours / today's total
                let entryHours = pausedState?.frozenHours ?? 0
                return formatPair(entryHours, totalTodayLogged)
            }
            return formatPair(project.loggedHours, project.bookedHours)
        }

        // No timer: all tracked time / weekly booked (40h min)
        let allTracked = totalLogged + totalUnbookedLogged
        let budget = max(totalBooked, Self.minimumWeeklyBudget)
        return formatPair(allTracked, budget)
    }

    var menuBarIcon: MenuBarIcon {
        if !serviceErrors.isEmpty { return .error }
        guard lastUpdated != nil else { return .calendar }

        if let tracking = projectStatuses.first(where: { $0.isTracking }) {
            if tracking.bookedHours == 0 { return .timer }
            let effectiveLogged = tracking.loggedHours + elapsedOffset
            if effectiveLogged > tracking.bookedHours { return .gaugeOver }
            let progress = min(effectiveLogged / tracking.bookedHours, 1.0)
            return .gaugeUnder(progress: progress)
        }

        if let project = pausedProject {
            if project.bookedHours == 0 { return .timer }
            if project.loggedHours > project.bookedHours { return .gaugeOver }
            let progress = min(project.loggedHours / project.bookedHours, 1.0)
            return .gaugeUnder(progress: progress)
        }

        if isFullDayOffToday { return .timeOff }

        return .calendar
    }

    func effectiveLoggedHours(for project: ProjectStatus) -> Double {
        project.loggedHours + (project.isTracking ? elapsedOffset : 0)
    }

    /// Format a "tracked / budget" pair: "7:50 / 8:00"
    private func formatPair(_ tracked: Double, _ budget: Double) -> String {
        "\(formatHM(tracked)) / \(formatHM(budget))"
    }

    /// Format raw hours: "7:50"
    private func formatHM(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h):\(String(format: "%02d", m))"
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
        // Soft refresh every minute: a single lightweight API call to pick up
        // timer state changes made outside the app. Hard refresh happens on
        // menu open and manual refresh, so no need for a periodic hard refresh.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.activeRefreshTask?.cancel()
            self.activeRefreshTask = Task { @MainActor in
                await self.softRefresh()
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

        // Get system-wide idle time — shortest idle across major input types.
        // CGEventType(rawValue: ~0) (kCGAnyInputEventType) returns nil in
        // Swift because the enum has no case for that raw value, so we check
        // each input family individually and take the minimum (most recent).
        let idleSeconds: TimeInterval = [
            CGEventType.mouseMoved,
            CGEventType.leftMouseDown,
            CGEventType.rightMouseDown,
            CGEventType.keyDown,
            CGEventType.scrollWheel,
        ].map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0

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

    /// If the project is already at or over its booked budget, mark it as already-notified
    /// so starting a timer on it doesn't fire a duplicate notification.
    private func suppressBookedHoursNotificationIfOver(_ project: ProjectStatus) {
        guard project.bookedHours > 0, project.loggedHours >= project.bookedHours else { return }
        notifiedProjectIds.insert(project.id)
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
            // Running first, then by date ascending (Mon → Fri), then by hours descending
            if a.isRunning != b.isRunning { return a.isRunning }
            if a.date != b.date { return a.date < b.date }
            return a.hours > b.hours
        }
    }

    /// Summarize time-off assignments that fall within the current week.
    /// Returns nil when no matching assignments exist (or no "Time Off"
    /// project was found in Forecast).
    ///
    /// Forecast conventions we handle:
    /// - Full-day time off → `allocation == 0` with a date range. We assume
    ///   a standard 8h workday so the hours total still reads sensibly,
    ///   especially when mixed with partial-day blocks in the same week.
    /// - Partial-day time off → `allocation` holds seconds-per-day. We sum
    ///   it directly.
    /// - Weekends are skipped because they're not work days.
    private static func computeTimeOffBlock(
        assignments: [ForecastAssignment],
        timeOffProjectId: Int?,
        weekStart: Date,
        weekEnd: Date
    ) -> TimeOffBlock? {
        guard let timeOffProjectId else { return nil }

        let calendar = Calendar.current
        let dayLabels = Array(DateHelpers.weekdayLabels.prefix(5))  // Mon–Fri
        let defaultFullDayHours = 8.0

        var totalHours = 0.0
        var affectedDays: Set<Int> = []  // weekday indices 0–4 relative to Mon
        var fullDays: Set<Int> = []      // subset that had any allocation=0 assignment

        for assignment in assignments where assignment.projectId == timeOffProjectId {
            guard let aStart = DateHelpers.dateFormatter.date(from: assignment.startDate),
                  let aEnd = DateHelpers.dateFormatter.date(from: assignment.endDate) else { continue }

            let allocationSeconds = assignment.allocation ?? 0
            let isFullDay = allocationSeconds == 0
            let hoursPerDay = isFullDay
                ? defaultFullDayHours
                : Double(allocationSeconds) / 3600.0

            for dayOffset in 0..<5 {  // Mon–Fri
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                      day >= aStart, day <= aEnd, day <= weekEnd else { continue }
                affectedDays.insert(dayOffset)
                totalHours += hoursPerDay
                if isFullDay { fullDays.insert(dayOffset) }
            }
        }

        guard !affectedDays.isEmpty else { return nil }
        let sortedLabels = affectedDays.sorted().map { dayLabels[$0] }
        let fullDayLabels = Set(fullDays.map { dayLabels[$0] })
        return TimeOffBlock(
            totalHours: totalHours,
            dayLabels: sortedLabels,
            fullDayLabels: fullDayLabels
        )
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
                suppressBookedHoursNotificationIfOver(project)
                _ = try await service.restartTimer(entryId: todayEntryId)
            } else {
                // No entry for today — create a new one (timer starts automatically)
                // Use known task ID, or fetch the first active task for this project
                var taskId = project.lastTaskId
                if taskId == nil {
                    let assignments = try await service.getMyProjectAssignments()
                    let tasks = assignments.first(where: { $0.project.id == harvestProjectId })?.taskAssignments.filter { $0.isActive }
                    taskId = tasks?.first?.task.id
                }
                guard let resolvedTaskId = taskId else {
                    errorMessage = "No tasks assigned to this project in Harvest."
                    return
                }
                suppressBookedHoursNotificationIfOver(project)
                _ = try await service.createTimeEntry(projectId: harvestProjectId, taskId: resolvedTaskId)
            }

            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                    clientName: assignment.client?.name,
                    taskAssignments: assignment.taskAssignments.filter { $0.isActive }
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
        let taskAssignments: [HarvestProjectTaskAssignment]
    }

    /// Start a new timer for a specific project and task, stopping any running timer first
    @MainActor
    func startNewTimer(projectId: Int, taskId: Int, hours: Double? = nil, notes: String? = nil) async {
        guard let (harvestService, _) = makeServices() else { return }
        pausedState = nil

        do {
            // Stop any currently running timer
            if let running = projectStatuses.first(where: { $0.isTracking }),
               let runningEntryId = running.todayEntryId {
                _ = try await harvestService.stopTimer(entryId: runningEntryId)
            }

            // Suppress over-budget notification if the target project is already over
            if let target = projectStatuses.first(where: { $0.harvestProjectId == projectId }) {
                suppressBookedHoursNotificationIfOver(target)
            }

            // Create new entry. Harvest auto-starts a timer only when `hours` is
            // omitted; posting with `hours` creates a stopped entry, so we need to
            // explicitly restart it to get a running timer pre-filled with that time.
            let created = try await harvestService.createTimeEntry(projectId: projectId, taskId: taskId, hours: hours, notes: notes)
            if hours != nil {
                _ = try await harvestService.restartTimer(entryId: created.id)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Log a time entry with specific hours (no running timer). If `spentDate` is nil, defaults to today.
    @MainActor
    func logTimeEntry(projectId: Int, taskId: Int, hours: Double, notes: String? = nil, spentDate: String? = nil) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.createTimeEntry(
                projectId: projectId,
                taskId: taskId,
                hours: hours,
                notes: notes,
                spentDate: spentDate
            )
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
                // Suppress over-budget notification if the entry's project is already over
                if let target = projectStatuses.first(where: { project in
                    project.timeEntries.contains(where: { $0.id == entryId })
                }) {
                    suppressBookedHoursNotificationIfOver(target)
                }
                _ = try await harvestService.restartTimer(entryId: entryId)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var lastRefreshAt: Date?

    /// Refresh only if we haven't refreshed in the last `interval` seconds.
    /// Used by menu-open refresh to keep state fresh without hammering the API.
    @MainActor
    func refreshIfStale(interval: TimeInterval = 5) async {
        if let last = lastRefreshAt, Date().timeIntervalSince(last) < interval {
            return
        }
        await refresh()
    }

    @MainActor
    func refresh() async {
        guard isConfigured else {
            errorMessage = "Open Settings to configure your API credentials."
            return
        }
        lastRefreshAt = Date()

        // A hard refresh invalidates any cached non-current-week snapshots
        // too (they'd now be stale, and we should avoid the dictionary
        // growing indefinitely as the user browses weeks).
        weekSnapshots.removeAll(keepingCapacity: true)

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

            // Forecast represents time off as a single undeletable project
            // literally named "Time Off" — identify it by name so we can
            // surface those assignments separately from real project work.
            let timeOffProjectId = projects.first(where: { $0.name == "Time Off" })?.id

            // Aggregate booked hours by Forecast project ID, splitting out
            // time off into its own per-day collection for a bottom-of-list
            // summary row.
            var bookedByForecastProject: [Int: Double] = [:]
            let timeOffBlock = Self.computeTimeOffBlock(
                assignments: allAssignments,
                timeOffProjectId: timeOffProjectId,
                weekStart: weekBounds.start,
                weekEnd: weekBounds.end
            )
            for assignment in allAssignments {
                guard let projectId = assignment.projectId,
                      projectId != timeOffProjectId else { continue }
                let weekdays = DateHelpers.countOverlappingWeekdays(
                    assignmentStart: assignment.startDate,
                    assignmentEnd: assignment.endDate,
                    weekStart: weekBounds.start,
                    weekEnd: weekBounds.end
                )
                let hoursPerDay = Double(assignment.allocation ?? 0) / 3600.0
                bookedByForecastProject[projectId, default: 0] += hoursPerDay * Double(weekdays)
            }

            // Cache everything needed for a future soft refresh
            cachedHarvestUserId = user.id
            cachedForecastPersonId = person.id
            currentWeekStart = weekBounds.start
            cachedWeekEntries = entries
            cachedForecastBookings = bookedByForecastProject
            cachedProjectMap = projectMap
            cachedClientMap = clientMap
            cachedTimeOffBlock = timeOffBlock

            applyRefreshedData(
                entries: entries,
                bookedByForecastProject: bookedByForecastProject,
                projectMap: projectMap,
                clientMap: clientMap,
                timeOffBlock: timeOffBlock
            )

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

    /// Rebuild projectStatuses and derived view state from entries + Forecast data.
    /// Called by both full refresh and soft refresh.
    @MainActor
    private func applyRefreshedData(
        entries: [HarvestTimeEntry],
        bookedByForecastProject: [Int: Double],
        projectMap: [Int: ForecastProject],
        clientMap: [Int: ForecastClient],
        timeOffBlock: TimeOffBlock?
    ) {
        let weekBounds = DateHelpers.currentWeekBounds()
        let todayString = DateHelpers.dateFormatter.string(from: Date())

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
            let dayLabels = DateHelpers.weekdayLabels
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
            self.timeOffBlock = timeOffBlock

            // Reset budget-notification state on week rollover. Within a week
            // the set is sticky so stopping/restarting a timer on an already-
            // over project doesn't re-fire the notification. The previous
            // behavior dropped IDs for any non-tracking project and caused
            // exactly that bug.
            if currentWeekStart != weekBounds.start {
                notifiedProjectIds.removeAll()
                currentWeekStart = weekBounds.start
            }
            if statuses.contains(where: { $0.isTracking }) {
                startElapsedTimer()
                checkBookedHoursReached()
            } else {
                stopElapsedTimer()
            }
    }

    /// Lightweight refresh: fetches today's time entries only, merges with cached
    /// non-today entries, and rebuilds view state using cached Forecast data.
    /// Falls back to a hard refresh if cache is empty.
    @MainActor
    func softRefresh() async {
        guard isConfigured else { return }

        // If we haven't done a hard refresh yet, or the week rolled over since
        // the cache was built, fall back to a full refresh so we don't mix
        // stale forecast bookings / old-week entries with the new week's data.
        guard let userId = cachedHarvestUserId,
              !cachedForecastBookings.isEmpty,
              currentWeekStart == DateHelpers.currentWeekBounds().start
        else {
            await refresh()
            return
        }

        guard let (harvestService, _) = makeServices() else { return }

        let todayString = DateHelpers.dateFormatter.string(from: Date())

        do {
            let todayEntries = try await harvestService.getTimeEntries(
                userId: userId,
                from: todayString,
                to: todayString
            )
            // Replace today's slice of the cached week with fresh data
            let nonTodayEntries = cachedWeekEntries.filter { $0.spentDate != todayString }
            let merged = nonTodayEntries + todayEntries
            cachedWeekEntries = merged

            applyRefreshedData(
                entries: merged,
                bookedByForecastProject: cachedForecastBookings,
                projectMap: cachedProjectMap,
                clientMap: cachedClientMap,
                timeOffBlock: cachedTimeOffBlock
            )
            // Intentionally not updating lastRefreshAt — that tracks hard refreshes
            // only, so menu-open still gets a full refresh after a soft one.
        } catch {
            // Silent — soft refresh failures shouldn't interrupt the user.
            // The next hard refresh will surface any real issue.
        }
    }

    // MARK: - Week look-ahead / look-back

    /// Fetch Forecast assignments (always) + Harvest time entries (for past
    /// weeks only) for the target week offset, then build and cache a
    /// WeekSnapshot. Future weeks skip the Harvest fetch since there are
    /// no logged entries yet.
    @MainActor
    func fetchWeek(offset: Int) async {
        guard offset != 0 else { return }
        guard isConfigured, let (harvestService, forecastService) = makeServices() else {
            otherWeekError = "API credentials not configured."
            return
        }

        isLoadingOtherWeek = true
        otherWeekError = nil
        defer { isLoadingOtherWeek = false }

        let bounds = DateHelpers.weekBounds(offset: offset)
        let startStr = DateHelpers.dateFormatter.string(from: bounds.start)
        let endStr = DateHelpers.dateFormatter.string(from: bounds.end)

        do {
            // Fan out prerequisite lookups so cold-cache fetches don't
            // serialize: person + (optionally) /projects + /clients for
            // Forecast, and the Harvest user lookup for past weeks. The
            // person and user IDs are account-stable, so cached values are
            // used when available.
            async let personId: Int = {
                if let id = cachedForecastPersonId { return id }
                let person = try await forecastService.getCurrentPerson()
                cachedForecastPersonId = person.id
                return person.id
            }()
            async let projects: [ForecastProject] = {
                if !cachedProjectMap.isEmpty { return Array(cachedProjectMap.values) }
                return try await forecastService.getProjects()
            }()
            async let clients: [ForecastClient] = {
                if !cachedClientMap.isEmpty { return Array(cachedClientMap.values) }
                return try await forecastService.getClients()
            }()
            async let harvestUserId: Int? = {
                guard offset < 0 else { return nil }
                if let id = cachedHarvestUserId { return id }
                let user = try await harvestService.getCurrentUser()
                cachedHarvestUserId = user.id
                return user.id
            }()

            let resolvedPersonId = try await personId
            let resolvedProjects = try await projects
            let resolvedClients = try await clients
            let resolvedHarvestUserId = try await harvestUserId

            // Now issue the per-week lookups concurrently.
            async let assignments = forecastService.getAssignments(
                personId: resolvedPersonId,
                startDate: startStr,
                endDate: endStr
            )
            async let entries: [HarvestTimeEntry] = {
                guard let uid = resolvedHarvestUserId else { return [] }
                return try await harvestService.getTimeEntries(
                    userId: uid,
                    from: startStr,
                    to: endStr
                )
            }()

            let snapshot = Self.buildSnapshot(
                offset: offset,
                weekBounds: bounds,
                entries: try await entries,
                assignments: try await assignments,
                projects: resolvedProjects,
                clients: resolvedClients
            )
            weekSnapshots[offset] = snapshot
        } catch {
            otherWeekError = friendlyErrorMessage(error)
        }
    }

    /// Pure function that builds a WeekSnapshot from raw fetched data.
    /// Mirrors the current-week pipeline in applyRefreshedData but without
    /// touching any instance state.
    private static func buildSnapshot(
        offset: Int,
        weekBounds: (start: Date, end: Date),
        entries: [HarvestTimeEntry],
        assignments: [ForecastAssignment],
        projects: [ForecastProject],
        clients: [ForecastClient]
    ) -> WeekSnapshot {
        let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let clientMap = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
        let timeOffProjectId = projects.first(where: { $0.name == "Time Off" })?.id

        // Aggregate booked hours by Forecast project ID (excluding time off)
        var bookedByForecastProject: [Int: Double] = [:]
        for assignment in assignments {
            guard let projectId = assignment.projectId,
                  projectId != timeOffProjectId else { continue }
            let weekdays = DateHelpers.countOverlappingWeekdays(
                assignmentStart: assignment.startDate,
                assignmentEnd: assignment.endDate,
                weekStart: weekBounds.start,
                weekEnd: weekBounds.end
            )
            let hoursPerDay = Double(assignment.allocation ?? 0) / 3600.0
            bookedByForecastProject[projectId, default: 0] += hoursPerDay * Double(weekdays)
        }

        let timeOff = computeTimeOffBlock(
            assignments: assignments,
            timeOffProjectId: timeOffProjectId,
            weekStart: weekBounds.start,
            weekEnd: weekBounds.end
        )

        // Aggregate logged hours by Harvest project ID (empty for future weeks)
        var loggedByHarvestProject: [Int: Double] = [:]
        var harvestProjectNames: [Int: String] = [:]
        var harvestClientNames: [Int: String] = [:]
        var entriesByHarvestProject: [Int: [HarvestTimeEntry]] = [:]
        for entry in entries {
            entriesByHarvestProject[entry.project.id, default: []].append(entry)
            loggedByHarvestProject[entry.project.id, default: 0] += entry.hours
            harvestProjectNames[entry.project.id] = entry.project.name
            if let client = entry.client {
                harvestClientNames[entry.project.id] = client.name
            }
        }

        // Build ProjectStatus list
        var statuses: [ProjectStatus] = []
        var processedHarvestIds: Set<Int> = []

        // Forecasted projects first
        for (forecastProjectId, bookedHours) in bookedByForecastProject {
            let project = projectMap[forecastProjectId]
            if project?.harvestId == nil { continue }
            let projectName = project?.name ?? "Unknown Project"
            let clientName = project?.clientId.flatMap { clientMap[$0]?.name }

            var logged: Double = 0
            var harvestId: Int? = nil
            if let hId = project?.harvestId {
                harvestId = hId
                logged = loggedByHarvestProject[hId] ?? 0
                processedHarvestIds.insert(hId)
            }

            statuses.append(ProjectStatus(
                id: "forecast-\(forecastProjectId)-\(offset)",
                clientName: clientName,
                projectName: projectName,
                bookedHours: bookedHours,
                loggedHours: logged,
                todayHours: 0,
                isTracking: false,
                harvestProjectId: harvestId,
                todayEntryId: nil,
                lastTaskId: nil,
                lastTrackedAt: nil,
                timeEntries: makeEntryInfos(from: harvestId.flatMap { entriesByHarvestProject[$0] } ?? [])
            ))
        }

        // Harvest-only projects — logged without a Forecast booking
        for (harvestProjectId, loggedHours) in loggedByHarvestProject {
            if processedHarvestIds.contains(harvestProjectId) { continue }
            let projectName = harvestProjectNames[harvestProjectId] ?? "Unknown Project"
            let clientName = harvestClientNames[harvestProjectId]
            statuses.append(ProjectStatus(
                id: "harvest-\(harvestProjectId)-\(offset)",
                clientName: clientName,
                projectName: projectName,
                bookedHours: 0,
                loggedHours: loggedHours,
                todayHours: 0,
                isTracking: false,
                harvestProjectId: harvestProjectId,
                todayEntryId: nil,
                lastTaskId: nil,
                lastTrackedAt: nil,
                timeEntries: makeEntryInfos(from: entriesByHarvestProject[harvestProjectId] ?? [])
            ))
        }

        // Sort: forecasted projects first (alphabetical by client/project),
        // then logged-only Harvest projects by name.
        statuses.sort { a, b in
            if (a.bookedHours > 0) != (b.bookedHours > 0) { return a.bookedHours > 0 }
            let aClient = a.clientName ?? ""
            let bClient = b.clientName ?? ""
            if aClient != bClient {
                return aClient.localizedCaseInsensitiveCompare(bClient) == .orderedAscending
            }
            return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
        }

        // Daily hours breakdown for the header's weekday mini-bar. Future
        // weeks will be all zeros (no logged time yet) but we populate the
        // day labels anyway.
        let calendar = Calendar.current
        let dayLabels = DateHelpers.weekdayLabels
        var hoursByDate: [String: Double] = [:]
        for entry in entries {
            hoursByDate[entry.spentDate, default: 0] += entry.hours
        }
        var dailyHours: [DayHours] = []
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: i, to: weekBounds.start) else { continue }
            let dateStr = DateHelpers.dateFormatter.string(from: date)
            let isToday = calendar.isDateInToday(date)
            dailyHours.append(DayHours(
                id: dateStr,
                dayLabel: dayLabels[i],
                hours: hoursByDate[dateStr] ?? 0,
                isToday: isToday
            ))
        }

        return WeekSnapshot(
            weekOffset: offset,
            weekLabel: DateHelpers.formattedWeekRange(offset: offset),
            weekStart: weekBounds.start,
            statuses: statuses,
            timeOff: timeOff,
            dailyHours: dailyHours
        )
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
