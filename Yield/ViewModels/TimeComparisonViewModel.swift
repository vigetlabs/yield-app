import CoreGraphics
import Foundation
import SwiftUI
import UserNotifications

@Observable
@MainActor
final class TimeComparisonViewModel {
    // No deinit cleanup: this VM is singleton-held by `AppState.shared`
    // for the app's lifetime, and all scheduled timers / tasks use
    // `[weak self]` so they don't keep the instance alive. The system
    // reclaims them at process termination.

    private(set) var projectStatuses: [ProjectStatus] = []
    private(set) var totalLogged: Double = 0
    private(set) var totalBooked: Double = 0
    private(set) var totalUnbookedLogged: Double = 0
    private(set) var totalTodayLogged: Double = 0
    private(set) var dailyHours: [DayHours] = []
    private(set) var timeOffBlock: TimeOffBlock? = nil

    /// Week offset: 0 = current week, <0 = past, >0 = future.
    private(set) var weekOffset: Int = 0

    /// Cached snapshots for non-current weeks, keyed by weekOffset.
    private(set) var weekSnapshots: [Int: WeekSnapshot] = [:]

    /// Loading + error state for non-current week fetches. Kept separate
    /// from `isLoading` / `errorMessage` so the current-week state isn't
    /// disturbed when a look-ahead/back fetch is in flight.
    private(set) var isLoadingOtherWeek: Bool = false
    private(set) var otherWeekError: String? = nil

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
        /// True when any entry in the displayed week is locked in
        /// Harvest. Lock state is week-granular — a single locked
        /// entry marks every day of the week (including untracked
        /// days) so the user sees the whole locked period at a
        /// glance. Drives the lock icon in the weekday strip.
        let isLocked: Bool
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
    private(set) var weekLabel: String = ""
    private(set) var lastUpdated: Date? = nil
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String? = nil {
        didSet {
            // Mirror user-visible errors to the local log so bug
            // reports include them. Empty strings and clears (set
            // to nil) aren't logged — they're noise.
            if let errorMessage, !errorMessage.isEmpty, errorMessage != oldValue {
                LogStore.shared.log(errorMessage)
            }
        }
    }
    private(set) var serviceErrors: [ServiceError] = [] {
        didSet {
            // Log newly-appended service errors as warnings. We use
            // a count delta rather than diffing contents — close
            // enough for an event log, avoids dragging Equatable
            // requirements through ServiceError.
            if serviceErrors.count > oldValue.count {
                let newCount = serviceErrors.count - oldValue.count
                for err in serviceErrors.suffix(newCount) {
                    LogStore.shared.log("\(err.service.rawValue): \(err.message)", category: .warning)
                }
            }
        }
    }
    /// Snapshot of harveststatus.com state, fetched on demand whenever
    /// `serviceErrors` is non-empty. Lets the error banner enrich its
    /// message with confirmed-incident context (or note when the status
    /// page reports no issues, so the user looks at their own connection
    /// / auth rather than waiting it out).
    private(set) var statusSnapshot: HarvestStatusService.Snapshot?
    private let statusService = HarvestStatusService()

    /// True when the most recent fetch attempt (hard or soft) failed due to
    /// a connectivity problem. Drives the menu bar icon, "offline" signals,
    /// freezing the elapsed timer, and hiding data that would go stale
    /// silently (Time Off bar). Flipped back to false on any successful
    /// fetch.
    private(set) var hasConnectivityError: Bool = false

    /// Count of consecutive failed soft refreshes. Used to back off the
    /// polling cadence so a long outage doesn't hammer the API every 60s.
    private var consecutiveSoftFailures: Int = 0

    /// Earliest time the next soft refresh may fire. Set when backoff
    /// extends beyond the normal 60s interval.
    private var softRefreshBackoffUntil: Date?

    /// Reachability monitor — triggers an immediate refresh when the
    /// machine reconnects, so the UI catches up without waiting for the
    /// next 60s tick.
    private let networkMonitor = NetworkMonitor()

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

    /// Kick off a status-page fetch in the background; updates
    /// `statusSnapshot` when the response lands. Silent-fails — the
    /// status page itself being down isn't something to surface.
    private func refreshStatusSnapshot() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.statusSnapshot = try? await self.statusService.fetch()
        }
    }
    private(set) var elapsedOffset: Double = 0  // hours elapsed locally since last API refresh
    var selectedTab: ProjectTab = .recent
    private(set) var pausedState: PausedTimerState? = nil

    enum ProjectTab: String, CaseIterable {
        case recent, forecasted, chart
    }

    /// Per-project, per-day hours for the current week — used by the chart tab.
    struct ChartPoint: Identifiable {
        let id: String  // "\(projectId)-\(date)"
        let projectId: Int
        /// Display string already including any `[code]` prefix —
        /// flowed straight to the chart's legend / foregroundStyle
        /// `by:` value where projects are identified by name.
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
                    projectName: project.displayName,
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

        var days = Array(allDays.prefix(DateHelpers.workdaysPerWeek))
        if satHours > 0 || sunHours > 0 {
            days.append(allDays[5])  // Sat — include if weekend was worked at all
        }
        if sunHours > 0 {
            days.append(allDays[6])  // Sun
        }
        return days
    }

    struct PausedTimerState {
        let clientName: String?
        let projectName: String
        /// Optional Forecast project code captured at pause time so
        /// the banner can render "[02] Project Name" while paused
        /// without re-fetching ProjectStatus.
        let projectCode: String?
        let taskName: String
        let entryId: Int
        let frozenHours: Double

        /// Display-friendly project name with the code prefix when set.
        var projectDisplayName: String {
            ProjectStatus.displayName(code: projectCode, project: projectName)
        }
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

    private(set) var idleAlertState: IdleAlertState? = nil

    /// In-flight idle-time relocation. Set when the user picks "Move
    /// Time…" on the idle alert; the source entry is left untouched
    /// until the destination commit succeeds, so cancelling out of the
    /// form leaves data unchanged.
    struct PendingIdleMove {
        let sourceEntryId: Int
        let sourceAdjustedHours: Double
        let idleHours: Double
        let sourceProjectName: String
    }

    private(set) var pendingIdleMove: PendingIdleMove? = nil

    // MARK: - External timer-change detection
    //
    // Tracks the running entry across refreshes so we can pop a HUD when
    // the timer changes from outside Yield (e.g. the Harvest browser
    // extension started a new timer). User-initiated mutations call
    // `markUserTimerMutation()` first so the next refresh's diff is
    // suppressed — only changes we didn't make ourselves trigger the HUD.
    private var hasSeenInitialTrackingState = false
    private var suppressNextTimerChangeHUD = false
    private var lastTrackingEntryId: Int?
    private var lastTrackingClientName: String?
    private var lastTrackingProjectName: String?
    private var lastTrackingProjectCode: String?
    private var lastTrackingTaskName: String?

    /// Call from any user-initiated method that may change the running
    /// timer (start / stop / pause / resume / delete-running-entry / idle
    /// actions). The next refresh's change-detection sees the resulting
    /// transition as expected and skips the HUD.
    private func markUserTimerMutation() {
        suppressNextTimerChangeHUD = true
    }

    // MARK: - Optimistic timer mutations
    //
    // The Harvest start/stop endpoints take a moment to round-trip; the
    // helpers below mutate `projectStatuses` in place so the UI flips
    // immediately while the API call is still in flight. The next
    // refresh reconciles to the server state — and on API failure, the
    // mutation methods call `refresh()` from the catch branch to undo
    // any divergence.

    /// Mark `entryId` as no longer running. Updates the owning
    /// project's `isTracking` flag based on whether any other entries
    /// are still running on it.
    @MainActor
    /// Internal (vs. private) so XCTest can drive it directly.
    func optimisticallyStopEntry(_ entryId: Int) {
        for i in projectStatuses.indices {
            var didChange = false
            for j in projectStatuses[i].timeEntries.indices
                where projectStatuses[i].timeEntries[j].id == entryId {
                projectStatuses[i].timeEntries[j].isRunning = false
                didChange = true
            }
            if didChange {
                projectStatuses[i].isTracking = projectStatuses[i].timeEntries.contains { $0.isRunning }
            }
        }
        if !projectStatuses.contains(where: { $0.isTracking }) {
            stopElapsedTimer()
        }
    }

    /// Mark `entryId` as running, stop any other running entries, and
    /// reset the elapsed-offset clock. The banner will start counting
    /// from now until the refresh lands.
    @MainActor
    /// Internal (vs. private) so XCTest can drive it directly.
    func optimisticallyStartEntry(_ entryId: Int) {
        for i in projectStatuses.indices {
            var anyRunning = false
            for j in projectStatuses[i].timeEntries.indices {
                let shouldRun = projectStatuses[i].timeEntries[j].id == entryId
                if projectStatuses[i].timeEntries[j].isRunning != shouldRun {
                    projectStatuses[i].timeEntries[j].isRunning = shouldRun
                }
                if shouldRun { anyRunning = true }
            }
            projectStatuses[i].isTracking = anyRunning
                || projectStatuses[i].timeEntries.contains { $0.isRunning }
        }
        startElapsedTimer()
    }

    @MainActor
    private func detectExternalTimerChange() {
        let currentEntry = trackingEntry
        let currentProject = trackingProject
        let currentId = currentEntry?.id

        defer {
            lastTrackingEntryId = currentId
            lastTrackingClientName = currentProject?.clientName
            lastTrackingProjectName = currentProject?.projectName
            lastTrackingProjectCode = currentProject?.projectCode
            lastTrackingTaskName = currentEntry?.taskName
            hasSeenInitialTrackingState = true
            suppressNextTimerChangeHUD = false
        }

        // Skip the very first refresh — discovering an existing running
        // timer at launch isn't a "change" worth announcing.
        guard hasSeenInitialTrackingState else { return }
        if suppressNextTimerChangeHUD { return }
        if currentId == lastTrackingEntryId { return }

        if let project = currentProject, let entry = currentEntry {
            TimerChangeHUDController.shared.show(TimerChangeInfo(
                kind: .started,
                clientName: project.clientName,
                projectName: project.projectName,
                projectCode: project.projectCode,
                taskName: entry.taskName
            ))
        } else if let projectName = lastTrackingProjectName {
            TimerChangeHUDController.shared.show(TimerChangeInfo(
                kind: .stopped,
                clientName: lastTrackingClientName,
                projectName: projectName,
                projectCode: lastTrackingProjectCode,
                taskName: lastTrackingTaskName
            ))
        }
    }

    /// Current-week day filter. When non-nil, the project list hides
    /// unbooked projects that didn't log time on that day; booked
    /// (forecasted) projects always show regardless. Set by tapping a
    /// day cell in the weekday mini-bar; cleared by tapping the same day
    /// again or tapping the "Week" total. Date string format: YYYY-MM-DD.
    private(set) var dayFilter: String? = nil

    @MainActor
    func toggleDayFilter(_ date: String) {
        dayFilter = (dayFilter == date) ? nil : date
    }

    @MainActor
    func clearDayFilter() {
        dayFilter = nil
    }

    var filteredStatuses: [ProjectStatus] {
        let byTab: [ProjectStatus]
        switch selectedTab {
        case .recent:
            byTab = projectStatuses
        case .forecasted:
            byTab = projectStatuses.filter { $0.bookedHours > 0 }
        case .chart:
            return []  // chart tab renders its own view; list is hidden
        }
        // Day-filter guard: validate the filter date is still within the
        // current week (protects against a lingering filter after a week
        // rollover). If stale, treat as unfiltered.
        guard let dayFilter,
              dailyHours.contains(where: { $0.id == dayFilter })
        else { return byTab }
        // Show only projects that actually logged time on the filtered
        // day — booked or not. Booked projects without time on the day
        // would be noise in this view since the day-filter is meant to
        // answer "what did I work on this day".
        return byTab.filter { project in
            project.timeEntries.contains { $0.date == dayFilter }
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
        // While we're showing a service-error banner, hide the Time Off row.
        // It's forward-looking Forecast data and a stale value next to the
        // banner would read as current. Gating on serviceErrors (rather
        // than any transient connectivity blip) avoids flickering the row
        // in and out during brief soft-refresh failures.
        guard serviceErrors.isEmpty else { return nil }
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

    /// Per-project `loggedHours` snapshot taken when the project entered
    /// the tracking state. Used by `checkBookedHoursReached` so the
    /// "Time's up!" notification only fires when this session's elapsed
    /// time crossed the booking — starting a timer on an already-over
    /// project (or having one running externally at app launch) leaves
    /// the project silently marked as notified.
    private var trackingSessionBaseline: [String: Double] = [:]
    private var idleNotificationSent: Bool = false

    /// Week-start date (Monday) for both the soft-refresh cache and the
    /// notification suppression set. When the week rolls over we clear both
    /// so stale data doesn't leak across weeks.
    private var currentWeekStart: Date?

    /// YYYY-MM-DD of the last successful hard refresh. Soft refresh skips
    /// the Forecast call by reusing `cachedTimeOffBlock` / `cachedForecastBookings`
    /// — but if the day rolls over while the app is open, day-dependent
    /// state (today's PTO, today's bookings) can go stale. Compare this
    /// against today on each soft refresh and fall back to a hard refresh
    /// when they don't match.
    private var currentRefreshDay: String?

    // Cached state from last hard refresh — used by softRefresh() to avoid
    // re-fetching Forecast data and non-today Harvest entries every minute.
    private var cachedWeekEntries: [HarvestTimeEntry] = []
    private var cachedForecastBookings: [Int: Double] = [:]
    private var cachedProjectMap: [Int: ForecastProject] = [:]
    private var cachedClientMap: [Int: ForecastClient] = [:]
    private var cachedTimeOffBlock: TimeOffBlock?
    private var cachedForecastNotes: [Int: String] = [:]
    /// The Forecast Time Off project ID, cached from the first successful
    /// refresh. Used to scope the "Everyone" (company holidays) query
    /// server-side so the response size doesn't scale with org headcount.
    /// Persisted to UserDefaults so even the first refresh after relaunch
    /// can skip the unfiltered-query cold-start penalty.
    private var cachedTimeOffProjectId: Int? {
        get { UserDefaults.standard.object(forKey: DefaultsKey.forecastTimeOffProjectId) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.forecastTimeOffProjectId) }
    }
    private var cachedHarvestUserId: Int?
    private var cachedForecastPersonId: Int?

    enum AuthMode {
        case oauth, pat, none
    }

    var authMode: AuthMode {
        // OAuth takes priority
        if KeychainHelper.load(key: "accessToken") != nil,
           let hId = UserDefaults.standard.string(forKey: DefaultsKey.OAuth.harvestAccountId), !hId.isEmpty,
           let fId = UserDefaults.standard.string(forKey: DefaultsKey.OAuth.forecastAccountId), !fId.isEmpty {
            return .oauth
        }
        // Fall back to PAT
        let token = Self.legacyHarvestToken() ?? ""
        let harvestId = UserDefaults.standard.string(forKey: DefaultsKey.Legacy.harvestAccountId) ?? ""
        let forecastId = UserDefaults.standard.string(forKey: DefaultsKey.Legacy.forecastAccountId) ?? ""
        if !token.isEmpty && !harvestId.isEmpty && !forecastId.isEmpty {
            return .pat
        }
        return .none
    }

    var isConfigured: Bool {
        authMode != .none
    }

    enum MenuBarIcon: Equatable {
        case calendar                      // no timer running
        case gaugeUnder(progress: Double)  // active timer, under budget (rotates)
        case gaugeOver                     // active timer, over budget
        case timer                         // active timer, unbooked project
        case paused                        // timer paused (any budget state)
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

    /// User's weekly-hours target (default 40, floored at 1). Mirrored
    /// from UserDefaults into observable stored state — a computed
    /// reader would have bypassed `@Observable`'s dependency tracker,
    /// silently breaking reactivity on any surface that depends on
    /// this (`menuBarLabel`, daily target conversions, etc.).
    /// `defaultsObserver` refreshes this when the user changes the
    /// setting.
    private(set) var weeklyHoursTarget: Double = 40

    /// Derived daily-hours target.
    private var dailyHoursTarget: Double {
        DateHelpers.dailyHours(fromWeekly: weeklyHoursTarget)
    }

    /// What the menu bar label shows. User-configurable in Settings.
    /// Mirrored from UserDefaults into observable stored state for the
    /// same reactivity reason as `weeklyHoursTarget`.
    private(set) var menuBarLabelMode: MenuBarLabelMode = .projectTime

    /// Token from `NotificationCenter.addObserver(forName:…)`. Held so
    /// the observer's lifetime is tied to the VM (which lives for the
    /// app's lifetime as a singleton — see the no-deinit note above).
    @ObservationIgnored
    private var defaultsObserver: NSObjectProtocol?

    init() {
        Self.migrateLegacyHarvestTokenIfNeeded()
        reloadDefaults()
        // Re-mirror on every UserDefaults write. The handler guards
        // each property against no-op writes so identical values
        // don't fire spurious `@Observable` notifications, even
        // though `didChangeNotification` itself posts on every set.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadDefaults()
            }
        }
    }

    /// Move a pre-OAuth Harvest PAT out of plist-readable UserDefaults
    /// into the Keychain on first launch after the upgrade. Idempotent:
    /// once the Keychain entry exists the UserDefaults value is gone
    /// and this is a no-op. If the Keychain save fails (unexpected)
    /// the UserDefaults copy is preserved so the user's sign-in isn't
    /// lost — `legacyHarvestToken()` falls back to UserDefaults.
    private static func migrateLegacyHarvestTokenIfNeeded() {
        guard let token = UserDefaults.standard.string(forKey: DefaultsKey.Legacy.harvestToken),
              !token.isEmpty,
              KeychainHelper.load(key: "legacyHarvestToken") == nil else {
            return
        }
        do {
            try KeychainHelper.save(key: "legacyHarvestToken", value: token)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.Legacy.harvestToken)
        } catch {
            // Leave the UserDefaults value in place — partial migration
            // would lose the user's sign-in.
        }
    }

    /// Read the legacy Harvest PAT. Prefers the Keychain (post-migration)
    /// and falls back to UserDefaults so a one-off Keychain failure or
    /// a downgrade->upgrade roundtrip doesn't lock the user out.
    private static func legacyHarvestToken() -> String? {
        KeychainHelper.load(key: "legacyHarvestToken")
            ?? UserDefaults.standard.string(forKey: DefaultsKey.Legacy.harvestToken)
    }

    private func reloadDefaults() {
        let newTarget = Double(max(UserDefaults.standard.integer(forKey: DefaultsKey.weeklyHoursTarget), 1))
        if newTarget != weeklyHoursTarget { weeklyHoursTarget = newTarget }

        let rawMode = UserDefaults.standard.string(forKey: DefaultsKey.menuBarLabelMode)
            ?? MenuBarLabelMode.projectTime.rawValue
        let newMode = MenuBarLabelMode(rawValue: rawMode) ?? .projectTime
        if newMode != menuBarLabelMode { menuBarLabelMode = newMode }
    }

    var menuBarLabel: String {
        guard lastUpdated != nil else { return "" }

        switch menuBarLabelMode {
        case .projectTime:      return projectTimeLabel()
        case .dayTime:          return dayTimeLabel()
        case .currentRemaining: return currentRemainingLabel()
        case .currentTimer:     return currentTimerLabel()
        }
    }

    /// `tracked / booked` for the running project's weekly slot. Falls
    /// back to `weekTotal / weeklyBudget` (user's weekly target as floor) when no timer is
    /// running, mirroring the original menu-bar behavior.
    private func projectTimeLabel() -> String {
        if let tracking = projectStatuses.first(where: { $0.isTracking }) {
            if tracking.bookedHours == 0 {
                let entryHours = (trackingEntry?.hours ?? 0) + elapsedOffset
                let todayTotal = totalTodayLogged + elapsedOffset
                return formatPair(entryHours, todayTotal)
            }
            let tracked = tracking.loggedHours + elapsedOffset
            return formatPair(tracked, tracking.bookedHours)
        }
        if let project = pausedProject {
            if project.bookedHours == 0 {
                let entryHours = pausedState?.frozenHours ?? 0
                return formatPair(entryHours, totalTodayLogged)
            }
            return formatPair(project.loggedHours, project.bookedHours)
        }
        let allTracked = totalLogged + totalUnbookedLogged
        let budget = max(totalBooked, weeklyHoursTarget)
        return formatPair(allTracked, budget)
    }

    /// `currentEntry / todayTotal`. Both tick live while a timer runs.
    /// Falls back to `todayTotal / 8h` when nothing is running so the
    /// label still conveys day progress.
    private func dayTimeLabel() -> String {
        if let entry = trackingEntry {
            let entryHours = entry.hours + elapsedOffset
            let todayTotal = totalTodayLogged + elapsedOffset
            return formatPair(entryHours, todayTotal)
        }
        if let paused = pausedState {
            return formatPair(paused.frozenHours, totalTodayLogged)
        }
        return formatPair(totalTodayLogged, dailyHoursTarget)
    }

    /// `currentEntry / projectRemaining` for the running project. Falls
    /// back to `entryHours / todayTotal` on unbooked projects and to
    /// `weekTotal / weeklyBudget` (user's weekly target as floor) when nothing is running —
    /// mirroring `projectTimeLabel` so the two modes feel consistent.
    /// Remaining goes negative (with a leading minus) when the project
    /// is over budget; the gauge icon already signals over-state, so
    /// the negative is just the precise amount.
    private func currentRemainingLabel() -> String {
        if let tracking = projectStatuses.first(where: { $0.isTracking }) {
            let entryHours = (trackingEntry?.hours ?? 0) + elapsedOffset
            if tracking.bookedHours == 0 {
                let todayTotal = totalTodayLogged + elapsedOffset
                return formatPair(entryHours, todayTotal)
            }
            let trackedOnProject = tracking.loggedHours + elapsedOffset
            let remaining = tracking.bookedHours - trackedOnProject
            return formatPair(entryHours, remaining)
        }
        if let project = pausedProject {
            let entryHours = pausedState?.frozenHours ?? 0
            if project.bookedHours == 0 {
                return formatPair(entryHours, totalTodayLogged)
            }
            let remaining = project.bookedHours - project.loggedHours
            return formatPair(entryHours, remaining)
        }
        let allTracked = totalLogged + totalUnbookedLogged
        let budget = max(totalBooked, weeklyHoursTarget)
        return formatPair(allTracked, budget)
    }

    /// Just the current timer's hours, no denominator. A paused timer
    /// keeps showing its frozen value; once all timers are stopped, falls
    /// back to today's total so the menu bar still says something useful
    /// instead of going blank.
    private func currentTimerLabel() -> String {
        if let entry = trackingEntry {
            return formatHM(entry.hours + elapsedOffset)
        }
        if let paused = pausedState {
            return formatHM(paused.frozenHours)
        }
        return formatHM(totalTodayLogged)
    }

    var menuBarIcon: MenuBarIcon {
        if !serviceErrors.isEmpty { return .error }
        // Any recent connectivity failure (hard or soft) also flips the
        // icon to error so the user can see at a glance the data is stale.
        if hasConnectivityError { return .error }
        guard lastUpdated != nil else { return .calendar }

        if let tracking = projectStatuses.first(where: { $0.isTracking }) {
            if tracking.bookedHours == 0 { return .timer }
            let effectiveLogged = tracking.loggedHours + elapsedOffset
            if effectiveLogged > tracking.bookedHours { return .gaugeOver }
            let progress = min(effectiveLogged / tracking.bookedHours, 1.0)
            return .gaugeUnder(progress: progress)
        }

        // When a timer is paused, surface a dedicated pause glyph so
        // the menu bar visually distinguishes paused from active
        // (both used to show the gauge/timer icon, distinguished
        // only by the now-removed tracking dot). The trade-off:
        // budget over/under isn't reflected in the icon while
        // paused — that context lives in the time label text
        // (e.g. "8:14 / 16:00") and the in-panel banner.
        if pausedProject != nil { return .paused }

        if isFullDayOffToday { return .timeOff }

        return .calendar
    }

    func effectiveLoggedHours(for project: ProjectStatus) -> Double {
        // Always the week total (plus live-ticking offset when tracking).
        // A day filter changes what's shown inside the drawer via
        // visibleEntries — but the row header's hours label, progress
        // bar, and remaining-for-the-week label stay week-level so the
        // user sees the filtered day's contribution in context, not in
        // isolation.
        project.loggedHours + (project.isTracking ? elapsedOffset : 0)
    }

    /// Entries to show in the expanded drawer / segmented bar for a given
    /// project. Filtered to the selected day when a day filter is active.
    func visibleEntries(for project: ProjectStatus) -> [TimeEntryInfo] {
        guard let dayFilter else { return project.timeEntries }
        return project.timeEntries.filter { $0.date == dayFilter }
    }

    /// Hours logged on the filtered day for a project, plus the live-ticking
    /// offset when the running timer falls on that day. Returns nil when no
    /// day filter is active — callers use that signal to render the default
    /// "week / booked" label instead of "day / week-so-far".
    func dayFilteredHours(for project: ProjectStatus) -> Double? {
        guard let dayFilter else { return nil }
        let base = project.timeEntries
            .filter { $0.date == dayFilter }
            .reduce(0.0) { $0 + $1.hours }
        let runningOnFilteredDay = project.isTracking && project.timeEntries.contains {
            $0.isRunning && $0.date == dayFilter
        }
        return base + (runningOnFilteredDay ? elapsedOffset : 0)
    }

    /// Tooltip shown when hovering the menu bar icon while a timer is
    /// set — matches the banner's top-line format ("Client — Project")
    /// so the menu bar surface reveals the same identifying context
    /// the open panel shows. Nil when no timer is set.
    var menuBarTooltip: String? {
        if let tracking = trackingProject {
            return tracking.qualifiedName
        }
        if let paused = pausedState {
            return ProjectStatus.qualifiedName(client: paused.clientName, project: paused.projectName)
        }
        return nil
    }

    /// Format a "tracked / budget" pair: "7:50 / 8:00"
    private func formatPair(_ tracked: Double, _ budget: Double) -> String {
        "\(formatHM(tracked)) / \(formatHM(budget))"
    }

    /// Format raw hours: "7:50".
    private func formatHM(_ hours: Double) -> String { hours.formattedColon }

    private func makeServices() -> (HarvestService, ForecastService)? {
        switch authMode {
        case .oauth:
            let oAuth = AppState.shared.oAuthService
            guard let harvestId = UserDefaults.standard.string(forKey: DefaultsKey.OAuth.harvestAccountId),
                  let forecastId = UserDefaults.standard.string(forKey: DefaultsKey.OAuth.forecastAccountId) else {
                return nil
            }
            let tokenProvider: () async throws -> String = { try await oAuth.getAccessToken() }
            return (
                HarvestService(tokenProvider: tokenProvider, accountId: harvestId),
                ForecastService(tokenProvider: tokenProvider, accountId: forecastId)
            )
        case .pat:
            guard let token = Self.legacyHarvestToken(),
                  let harvestId = UserDefaults.standard.string(forKey: DefaultsKey.Legacy.harvestAccountId),
                  let forecastId = UserDefaults.standard.string(forKey: DefaultsKey.Legacy.forecastAccountId) else {
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

    @MainActor
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        activeRefreshTask?.cancel()
        // Soft refresh every minute: a single lightweight API call to pick up
        // timer state changes made outside the app. Hard refresh happens on
        // menu open and manual refresh, so no need for a periodic hard refresh.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.triggerSoftRefresh()
        }

        // Fire an immediate refresh when network connectivity comes back
        // instead of waiting up to a full minute for the next timer tick.
        // A reconnect is strong evidence that prior failures were caused by
        // the now-resolved outage, so reset both the deadline and the
        // failure counter — otherwise the *next* failure would jump
        // straight to the 15-minute backoff tier.
        networkMonitor.start { [weak self] in
            guard let self else { return }
            self.softRefreshBackoffUntil = nil
            self.consecutiveSoftFailures = 0
            self.triggerSoftRefresh()
        }

        activeRefreshTask = Task { @MainActor in
            await refresh()
        }
    }

    /// Cancels any in-flight refresh and starts a new soft-refresh task.
    /// Shared by the 60s tick and the NWPathMonitor reconnect callback.
    @MainActor
    private func triggerSoftRefresh() {
        activeRefreshTask?.cancel()
        activeRefreshTask = Task { @MainActor in
            await self.softRefresh()
        }
    }

    @MainActor
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopElapsedTimer()
    }

    /// Wipe every piece of view-model state that's tied to a Harvest
    /// account so the UI lands in a clean "not signed in" state and a
    /// subsequent sign-in (potentially with a different account) can't
    /// see any leakage from the prior session. Call after
    /// `OAuthService.signOut()`.
    @MainActor
    func resetForSignOut() {
        stopAutoRefresh()

        // UI state
        projectStatuses = []
        totalLogged = 0
        totalBooked = 0
        totalUnbookedLogged = 0
        totalTodayLogged = 0
        dailyHours = []
        timeOffBlock = nil
        weekOffset = 0
        weekSnapshots.removeAll()
        transitionSnapshot = TransitionSnapshot()
        isLoadingOtherWeek = false
        otherWeekError = nil
        weekLabel = ""
        lastUpdated = nil
        isLoading = false
        errorMessage = nil
        serviceErrors = []
        statusSnapshot = nil
        dayFilter = nil
        selectedTab = .recent

        // Tracking + pause + idle state
        pausedState = nil
        idleAlertState = nil
        pendingIdleMove = nil
        notifiedProjectIds.removeAll()
        trackingSessionBaseline.removeAll()
        currentWeekStart = nil
        currentRefreshDay = nil
        elapsedOffset = 0

        // External-change detection state
        hasSeenInitialTrackingState = false
        suppressNextTimerChangeHUD = false
        lastTrackingEntryId = nil
        lastTrackingClientName = nil
        lastTrackingProjectName = nil
        lastTrackingTaskName = nil

        // API-fetch caches
        cachedWeekEntries = []
        cachedForecastBookings = [:]
        cachedProjectMap = [:]
        cachedClientMap = [:]
        cachedTimeOffBlock = nil
        cachedForecastNotes = [:]
        cachedHarvestUserId = nil
        cachedForecastPersonId = nil
    }

    @MainActor
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedOffset = 0
        idleNotificationSent = false
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Don't advance the local tick while Harvest is confirmed
                // unreachable — the server-side timer state is unknown and
                // accumulating phantom hours would mislead the user. A
                // Forecast-only failure is fine; Harvest data is still
                // fresh.
                guard !self.isHarvestDown else { return }
                self.elapsedOffset += 1.0 / 60.0  // add 1 minute in hours
                self.checkBookedHoursReached()
                self.checkIdleTime()
            }
        }
    }

    @MainActor
    private func checkIdleTime() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.idleDetectionEnabled)
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

        let idleMinutes = UserDefaults.standard.integer(forKey: DefaultsKey.idleMinutes)
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

                let name = project.qualifiedName

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
    @MainActor
    private func openMenuBarPanel() {
        MenuBarStatusItem.button?.performClick(nil)
    }

    // MARK: - Idle Alert Actions

    /// Whether the entry the idle alert references is still actually
    /// running on Harvest right now. Returns false if the entry was
    /// stopped externally (Harvest web, Harvest for iOS, another
    /// device) since the alert appeared.
    @MainActor
    private func isEntryStillRunning(_ entryId: Int) -> Bool {
        projectStatuses.contains { project in
            project.timeEntries.contains { $0.id == entryId && $0.isRunning }
        }
    }

    /// Continue timing but subtract the idle time from the entry.
    /// If the entry was stopped externally since the alert appeared,
    /// just dismiss the alert — there's nothing to adjust. On any
    /// other failure, surface the error and dismiss the alert anyway
    /// so the user isn't stuck staring at a modal they can't
    /// resolve.
    @MainActor
    func idleContinueAndRemoveTime() async {
        guard let alert = idleAlertState,
              let (harvestService, _) = makeServices() else { return }

        do {
            markUserTimerMutation()
            await refresh()

            guard isEntryStillRunning(alert.entryId) else {
                idleDismiss()
                return
            }

            markUserTimerMutation()
            _ = try await harvestService.stopTimer(entryId: alert.entryId)
            do {
                _ = try await harvestService.updateTimeEntry(entryId: alert.entryId, hours: alert.adjustedHours, notes: nil)
            } catch {
                // Update failed — restart timer to avoid leaving it stopped
                _ = try? await harvestService.restartTimer(entryId: alert.entryId)
                throw error
            }
            _ = try await harvestService.restartTimer(entryId: alert.entryId)
            idleDismiss()
            await refresh()
        } catch {
            errorMessage = "Failed to adjust idle time: \(error.localizedDescription)"
            idleDismiss()
        }
    }

    /// Stop the timer and subtract the idle time. Same external-
    /// change + always-dismiss behavior as
    /// `idleContinueAndRemoveTime`.
    @MainActor
    func idleStopAndRemoveTime() async {
        guard let alert = idleAlertState,
              let (harvestService, _) = makeServices() else { return }

        do {
            markUserTimerMutation()
            await refresh()

            guard isEntryStillRunning(alert.entryId) else {
                idleDismiss()
                return
            }

            markUserTimerMutation()
            _ = try await harvestService.stopTimer(entryId: alert.entryId)
            _ = try await harvestService.updateTimeEntry(entryId: alert.entryId, hours: alert.adjustedHours, notes: nil)
            idleDismiss()
            pausedState = nil
            await refresh()
        } catch {
            errorMessage = "Failed to adjust idle time: \(error.localizedDescription)"
            idleDismiss()
        }
    }

    /// Keep all the time (including idle) and dismiss
    @MainActor
    func idleDismiss() {
        idleAlertState = nil
        idleNotificationSent = false
    }

    /// Start an idle-move flow: capture the idle hours and source-entry
    /// info into `pendingIdleMove`, then dismiss the idle alert. The
    /// source entry isn't touched until the destination commit succeeds,
    /// so cancelling the form is a no-op on data.
    @MainActor
    func idleStartMove() {
        guard let alert = idleAlertState else { return }
        let idleHours = max(0, Date().timeIntervalSince(alert.idleStartDate) / 3600)
        pendingIdleMove = PendingIdleMove(
            sourceEntryId: alert.entryId,
            sourceAdjustedHours: alert.adjustedHours,
            idleHours: idleHours,
            sourceProjectName: alert.projectName
        )
        idleAlertState = nil
        idleNotificationSent = false
    }

    /// Cancel an in-progress idle move without touching any data.
    @MainActor
    func idleMoveCancel() {
        pendingIdleMove = nil
    }

    /// Add the pending idle hours to an existing time entry, then
    /// subtract them from the source. Destination-first so a cancel or
    /// network failure leaves the user with extra time on the source
    /// (visible and easy to fix) rather than missing time. Takes the
    /// move struct explicitly so the form can dismiss (which clears
    /// `pendingIdleMove`) before invoking this.
    @MainActor
    func idleMoveAddToExisting(_ move: PendingIdleMove, entryId: Int) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            // Look up current hours on the destination so we can add idle to it.
            let target = projectStatuses
                .flatMap { $0.timeEntries }
                .first(where: { $0.id == entryId })
            let baseHours = target?.hours ?? 0
            let newHours = baseHours + move.idleHours

            _ = try await harvestService.updateTimeEntry(entryId: entryId, hours: newHours, notes: nil)

            do {
                _ = try await harvestService.updateTimeEntry(
                    entryId: move.sourceEntryId,
                    hours: move.sourceAdjustedHours,
                    notes: nil
                )
            } catch {
                errorMessage = "Idle time was added to the destination, but the source timer could not be reduced. Edit it manually."
            }

            await refresh()
        } catch {
            errorMessage = "Failed to move idle time: \(error.localizedDescription)"
        }
    }

    /// Create a brand-new time entry for the pending idle hours, then
    /// subtract from the source. Always today (idle moves are
    /// constrained to the current day).
    @MainActor
    func idleMoveCreateNew(_ move: PendingIdleMove, projectId: Int, taskId: Int, notes: String?) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.createTimeEntry(
                projectId: projectId,
                taskId: taskId,
                hours: move.idleHours,
                notes: notes,
                spentDate: nil
            )

            do {
                _ = try await harvestService.updateTimeEntry(
                    entryId: move.sourceEntryId,
                    hours: move.sourceAdjustedHours,
                    notes: nil
                )
            } catch {
                errorMessage = "Idle time was logged on the destination, but the source timer could not be reduced. Edit it manually."
            }

            await refresh()
        } catch {
            errorMessage = "Failed to move idle time: \(error.localizedDescription)"
        }
    }

    /// If the project is already at or over its booked budget, mark it as already-notified
    /// so starting a timer on it doesn't fire a duplicate notification.
    private func suppressBookedHoursNotificationIfOver(_ project: ProjectStatus) {
        guard project.bookedHours > 0, project.loggedHours >= project.bookedHours else { return }
        notifiedProjectIds.insert(project.id)
    }

    @MainActor
    /// Internal (vs. private) so XCTest can drive it directly.
    func checkBookedHoursReached() {
        for project in projectStatuses where project.isTracking {
            guard project.bookedHours > 0,
                  !notifiedProjectIds.contains(project.id) else { continue }

            // The session baseline is captured when the project first
            // becomes tracking. If it was already over before this
            // session, silently mark notified — the user already knows.
            let baseline = trackingSessionBaseline[project.id] ?? project.loggedHours
            if baseline >= project.bookedHours {
                notifiedProjectIds.insert(project.id)
                continue
            }

            let effective = effectiveLoggedHours(for: project)
            if effective >= project.bookedHours {
                notifiedProjectIds.insert(project.id)
                sendBookedHoursNotification(for: project)
            }
        }
    }

    @MainActor
    private func sendBookedHoursNotification(for project: ProjectStatus) {
        // No-op under XCTest so unit tests can drive
        // `checkBookedHoursReached` without scheduling real
        // user-visible notifications.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        let hours = project.bookedHours == project.bookedHours.rounded()
            ? String(format: "%.0f", project.bookedHours)
            : String(format: "%.1f", project.bookedHours)
        content.body = "\(project.qualifiedName): You've reached your booked hours (\(hours)h)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "booked-hours-\(project.id)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static let iso8601Parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func makeEntryInfos(from entries: [HarvestTimeEntry]) -> [TimeEntryInfo] {
        entries.compactMap { entry in
            guard let taskId = entry.task?.id ?? entry.taskAssignment?.task?.id else { return nil }
            let startedAt = entry.timerStartedAt.flatMap { iso8601Parser.date(from: $0) }
            return TimeEntryInfo(
                id: entry.id,
                harvestProjectId: entry.project.id,
                taskId: taskId,
                taskName: entry.task?.name ?? entry.taskAssignment?.task?.name ?? "Unknown Task",
                hours: entry.hours,
                date: entry.spentDate,
                isRunning: entry.isRunning,
                notes: entry.notes,
                timerStartedAt: startedAt
            )
        }.sorted { a, b in
            // Newest day first so today's entries sit at the top of the
            // drawer (the active timer naturally ends up there). Within a
            // day, longer entries first.
            if a.date != b.date { return a.date > b.date }
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
    /// Shared project sort: alphabetical by client name, then project
    /// name — booked and logged-only projects intermingle so the list
    /// reads as one alphabetical sweep. Deliberately stable (no
    /// tracking or recency component) so the list doesn't reshuffle
    /// between refreshes.
    static func projectSortOrder(_ a: ProjectStatus, _ b: ProjectStatus) -> Bool {
        let aClient = a.clientName ?? ""
        let bClient = b.clientName ?? ""
        if aClient != bClient {
            return aClient.localizedCaseInsensitiveCompare(bClient) == .orderedAscending
        }
        return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
    }

    /// Aggregate non-empty assignment notes by project ID. Multiple
    /// assignments against the same project (e.g. split across days) get
    /// their notes joined with a blank line between. Time-off and
    /// projectless assignments are skipped.
    private static func aggregateNotesByProject(
        assignments: [ForecastAssignment],
        timeOffProjectId: Int?
    ) -> [Int: String] {
        var collected: [Int: [String]] = [:]
        for assignment in assignments {
            guard let projectId = assignment.projectId,
                  projectId != timeOffProjectId,
                  let note = assignment.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty
            else { continue }
            collected[projectId, default: []].append(note)
        }
        return collected.mapValues { $0.joined(separator: "\n\n") }
    }

    private static func computeTimeOffBlock(
        assignments: [ForecastAssignment],
        timeOffProjectId: Int?,
        weekStart: Date,
        weekEnd: Date,
        /// Hours per "full day off" — Forecast's allocation=0
        /// convention has no inherent length, so the caller supplies
        /// the user's daily target.
        fullDayHours: Double
    ) -> TimeOffBlock? {
        guard let timeOffProjectId else { return nil }

        let calendar = Calendar.current
        let dayLabels = Array(DateHelpers.weekdayLabels.prefix(DateHelpers.workdaysPerWeek))

        var totalHours = 0.0
        var affectedDays: Set<Int> = []  // weekday indices 0–4 relative to Mon
        var fullDays: Set<Int> = []      // subset that had any allocation=0 assignment

        for assignment in assignments where assignment.projectId == timeOffProjectId {
            guard let aStart = DateHelpers.dateFormatter.date(from: assignment.startDate),
                  let aEnd = DateHelpers.dateFormatter.date(from: assignment.endDate) else { continue }

            let allocationSeconds = assignment.allocation ?? 0
            let isFullDay = allocationSeconds == 0
            let hoursPerDay = isFullDay
                ? fullDayHours
                : Double(allocationSeconds) / 3600.0

            for dayOffset in 0..<DateHelpers.workdaysPerWeek {
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

    @MainActor
    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedOffset = 0
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
                    projectCode: assignment.project.code,
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
        /// Project code (Harvest's `code` field). Mirrors the same
        /// `displayName` pattern as `ProjectStatus`.
        let projectCode: String?
        let clientName: String?
        let taskAssignments: [HarvestProjectTaskAssignment]

        /// "[code] Project Name" when a code is set; bare project
        /// name otherwise. Use everywhere the picker surfaces a
        /// project to the user.
        var displayName: String {
            ProjectStatus.displayName(code: projectCode, project: projectName)
        }
    }

    /// Start a new timer for a specific project and task, stopping any running timer first
    @MainActor
    func startNewTimer(projectId: Int, taskId: Int, hours: Double? = nil, notes: String? = nil) async {
        guard let (harvestService, _) = makeServices() else { return }
        markUserTimerMutation()
        pausedState = nil

        // Snapshot the previously-running entry id BEFORE the optimistic
        // flip clears it, so the API call still has it to stop server-side.
        let previouslyRunningEntryId = projectStatuses
            .first(where: { $0.isTracking })?
            .todayEntryId

        // Optimistic stop of the previous timer. The new timer's create
        // can't be optimistic (no entry id until the API responds) but
        // the old timer flips off in the UI immediately.
        if let prev = previouslyRunningEntryId {
            optimisticallyStopEntry(prev)
        }

        do {
            // Stop any currently running timer
            if let prev = previouslyRunningEntryId {
                _ = try await harvestService.stopTimer(entryId: prev)
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
            await refresh()  // reconcile — undo the optimistic stop if the API never landed
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
            // Suppress the timer-change HUD if we're deleting the
            // running entry — the resulting "stopped" transition is
            // user-initiated and shouldn't pop the HUD.
            if trackingEntry?.id == entryId {
                markUserTimerMutation()
            }
            try await harvestService.deleteTimeEntry(entryId: entryId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update an existing time entry's project, task, hours, and/or notes
    @MainActor
    func updateExistingEntry(entryId: Int, projectId: Int, taskId: Int, hours: Double, notes: String) async {
        guard let (harvestService, _) = makeServices() else { return }

        do {
            _ = try await harvestService.updateTimeEntry(
                entryId: entryId,
                projectId: projectId,
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

        markUserTimerMutation()

        // Save paused state before stopping. `frozenHours` is the
        // running entry's elapsed time, not the project's week total —
        // the banner shows the running entry while active and we want
        // the same number frozen on pause. Using `loggedHours` here
        // (the project's week total) caused the banner to jump up by
        // any other entries on the same project this week.
        let frozenEntryHours = entry.hours + elapsedOffset
        pausedState = PausedTimerState(
            clientName: project.clientName,
            projectName: project.projectName,
            projectCode: project.projectCode,
            taskName: entry.taskName,
            entryId: entry.id,
            frozenHours: frozenEntryHours
        )

        // Optimistic flip: with `pausedState` set and the entry no
        // longer running, the banner immediately switches green→yellow
        // and the pause button becomes play.fill, instead of waiting
        // for the API round-trip + refresh.
        optimisticallyStopEntry(entry.id)

        do {
            _ = try await harvestService.stopTimer(entryId: entry.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            pausedState = nil
            await refresh()  // reconcile — undo the optimistic stop
        }
    }

    @MainActor
    func resumeTimer() async {
        guard let paused = pausedState,
              let (harvestService, _) = makeServices() else { return }

        markUserTimerMutation()

        // Optimistic flip: re-mark the paused entry as running so the
        // banner switches yellow→green and play.fill→pause.fill before
        // the restart API call lands.
        optimisticallyStartEntry(paused.entryId)

        do {
            _ = try await harvestService.restartTimer(entryId: paused.entryId)
            // Hold `pausedState` through the refresh so the banner has
            // continuous coverage — clearing first leaves a gap before
            // `trackingProject` lands where neither is set and the
            // banner would briefly disappear/reappear.
            await refresh()
            pausedState = nil
        } catch {
            errorMessage = error.localizedDescription
            await refresh()  // reconcile — undo the optimistic start
        }
    }

    @MainActor
    func stopBannerTimer() async {
        if let entry = trackingEntry,
           let (harvestService, _) = makeServices() {
            // Suppress the external-change HUD — the refresh below
            // would otherwise see the running→stopped transition and
            // announce it as if it came from outside Yield.
            markUserTimerMutation()
            optimisticallyStopEntry(entry.id)
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
        markUserTimerMutation()
        if !isRunning { pausedState = nil }

        // Snapshot the currently-running entry (if any) BEFORE the
        // optimistic mutation clears it, so the stop-then-restart path
        // below still knows what to stop on the server.
        let previouslyRunningEntryId: Int? = isRunning ? nil
            : projectStatuses.first(where: { $0.isTracking })?.todayEntryId
        let target = projectStatuses.first {
            $0.timeEntries.contains(where: { $0.id == entryId })
        }

        // Flip the UI immediately, then run the API call.
        if isRunning {
            optimisticallyStopEntry(entryId)
        } else {
            optimisticallyStartEntry(entryId)
        }

        do {
            if isRunning {
                _ = try await harvestService.stopTimer(entryId: entryId)
            } else {
                if let prev = previouslyRunningEntryId, prev != entryId {
                    _ = try await harvestService.stopTimer(entryId: prev)
                }
                if let target {
                    suppressBookedHoursNotificationIfOver(target)
                }
                _ = try await harvestService.restartTimer(entryId: entryId)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            await refresh()  // reconcile — undo the optimistic mutation if the API never landed
        }
    }

    private var lastRefreshAt: Date?

    /// Refresh only if we haven't refreshed in the last `interval` seconds —
    /// or if the day has rolled over since the last hard refresh, in which
    /// case the cached week-entries set is stale regardless of how recently
    /// a soft refresh ran. Used by the menu-open observer.
    @MainActor
    func refreshIfStale(interval: TimeInterval = 5) async {
        let today = DateHelpers.dateFormatter.string(from: Date())
        let dayChangedSinceHardRefresh = currentRefreshDay != nil && currentRefreshDay != today
        if !dayChangedSinceHardRefresh,
           let last = lastRefreshAt,
           Date().timeIntervalSince(last) < interval {
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

        // A hard refresh invalidates the cached non-current-week snapshots
        // (they'd now be stale, and we should avoid the dictionary growing
        // indefinitely as the user browses weeks) — but preserve the
        // currently-viewed week's snapshot so the UI keeps showing its
        // data until the triggered refetch at the end of this function
        // lands. Without this, `displayedStatuses` would fall through to
        // `transitionSnapshot`, flashing the user to current-week data on
        // a non-current-week view.
        let preservedSnapshot = weekSnapshots[weekOffset]
        weekSnapshots.removeAll(keepingCapacity: true)
        if weekOffset != 0, let preservedSnapshot {
            weekSnapshots[weekOffset] = preservedSnapshot
        }

        isLoading = true
        errorMessage = nil
        serviceErrors = []
        statusSnapshot = nil

        guard let (harvestService, forecastService) = makeServices() else {
            errorMessage = "API credentials not configured."
            isLoading = false
            return
        }

        let weekDates = DateHelpers.weekDateStrings()
        let weekBounds = DateHelpers.currentWeekBounds()

        do {
            // Fetch Harvest data. User ID is account-stable so we reuse the
            // cached one when available and only hit /users/me on the first
            // refresh of a session (or if the cache was cleared).
            let userId: Int
            let entries: [HarvestTimeEntry]
            do {
                if let cachedId = cachedHarvestUserId {
                    userId = cachedId
                } else {
                    let user = try await harvestService.getCurrentUser()
                    userId = user.id
                    cachedHarvestUserId = user.id

                    // Backfill user name if missing (e.g. after cache clear).
                    if AppState.shared.oAuthService.userName == nil {
                        let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
                        if !name.isEmpty {
                            UserDefaults.standard.set(name, forKey: DefaultsKey.OAuth.userName)
                        }
                    }
                }

                // Date-range fetch + an unfiltered running-entries
                // fetch in parallel. A timer started before midnight
                // and still running afterward keeps its original
                // `spent_date`, so the date-range query alone misses
                // it on the next day. The running fetch is
                // best-effort — its failure doesn't block refresh.
                async let weekEntries = harvestService.getTimeEntries(
                    userId: userId,
                    from: weekDates.start,
                    to: weekDates.end
                )
                async let runningEntries = harvestService.getRunningTimeEntries(userId: userId)
                let dateRangeEntries = try await weekEntries
                let extraRunning = ((try? await runningEntries) ?? [])
                    .filter { running in !dateRangeEntries.contains(where: { $0.id == running.id }) }
                entries = dateRangeEntries + extraRunning
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

                // Fan out the personal assignments query and the
                // "Everyone" query in parallel. Forecast stores company
                // holidays / org-wide time off as assignments with
                // person_id == null, which the person-scoped query
                // doesn't return — so we pull them separately and merge.
                async let personal = forecastService.getAssignments(
                    personId: person.id,
                    startDate: weekDates.start,
                    endDate: weekDates.end
                )
                async let everyone = forecastService.getEveryoneAssignments(
                    startDate: weekDates.start,
                    endDate: weekDates.end,
                    restrictToProjectId: cachedTimeOffProjectId
                )
                allAssignments = try await personal + (try await everyone)
            } catch {
                serviceErrors.append(ServiceError(service: .forecast, message: friendlyErrorMessage(error)))
                throw error
            }

            // Build lookups
            let projectMap = projects.indexed { $0.id }
            let clientMap = clients.indexed { $0.id }

            // Identify Forecast's built-in time-off project by name so we
            // can surface those assignments separately from real work.
            // Cache the ID so the next refresh's "Everyone" query can
            // scope to just this project server-side (keeps the response
            // size bounded regardless of org headcount).
            //
            // Fall back to the previously-cached ID when the name match
            // misses — a flaky `/projects` response (incomplete list,
            // Forecast-side caching, transient blip) would otherwise
            // silently drop PTO from the panel AND leak it into booked
            // totals, since assignments aren't filtered out when the
            // sentinel ID is nil. Only overwrite the cache when we have
            // a fresh non-nil hit, so a single bad response can't
            // poison the cache.
            let freshTimeOffProjectId = projects.first(where: { $0.name == YieldConstants.timeOffProjectName })?.id
            let timeOffProjectId = freshTimeOffProjectId ?? cachedTimeOffProjectId
            if let freshTimeOffProjectId {
                cachedTimeOffProjectId = freshTimeOffProjectId
            }

            // Aggregate booked hours by Forecast project ID, splitting out
            // time off into its own per-day collection for a bottom-of-list
            // summary row.
            var bookedByForecastProject: [Int: Double] = [:]
            let timeOffBlock = Self.computeTimeOffBlock(
                assignments: allAssignments,
                timeOffProjectId: timeOffProjectId,
                weekStart: weekBounds.start,
                weekEnd: weekBounds.end,
                fullDayHours: dailyHoursTarget
            )
            let notesByForecastProject = Self.aggregateNotesByProject(
                assignments: allAssignments,
                timeOffProjectId: timeOffProjectId
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

            // Cache everything needed for a future soft refresh. userId
            // was either freshly fetched above or already matched the cache.
            cachedHarvestUserId = userId
            cachedForecastPersonId = person.id
            currentWeekStart = weekBounds.start
            currentRefreshDay = DateHelpers.dateFormatter.string(from: Date())
            cachedWeekEntries = entries
            cachedForecastBookings = bookedByForecastProject
            cachedProjectMap = projectMap
            cachedClientMap = clientMap
            cachedTimeOffBlock = timeOffBlock
            cachedForecastNotes = notesByForecastProject

            applyRefreshedData(
                entries: entries,
                bookedByForecastProject: bookedByForecastProject,
                projectMap: projectMap,
                clientMap: clientMap,
                timeOffBlock: timeOffBlock,
                notesByForecastProject: notesByForecastProject
            )
            noteFetchSucceeded()

        } catch {
            noteFetchFailed(error)
            if serviceErrors.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = serviceErrors.map { "\($0.service.rawValue): \($0.message)" }.joined(separator: "\n")
            }
            refreshStatusSnapshot()
        }

        #if DEBUG
        // Inject simulated service failures after real data loads
        if !simulateServiceFailures.isEmpty {
            serviceErrors = []
            for service in simulateServiceFailures {
                serviceErrors.append(ServiceError(service: service, message: "Service unavailable (simulated)"))
            }
            errorMessage = serviceErrors.map { "\($0.service.rawValue): \($0.message)" }.joined(separator: "\n")
            refreshStatusSnapshot()
        }
        #endif

        isLoading = false

        // If the user is viewing a non-current week, refetch that week
        // now — `refresh()` only repopulates current-week state, so
        // without this the viewed snapshot would stay stale (or, on a
        // cold cache, fall through to current-week data in
        // `transitionSnapshot`).
        if weekOffset != 0 {
            Task { await fetchWeek(offset: weekOffset) }
        }
    }

    /// Rebuild projectStatuses and derived view state from entries + Forecast data.
    /// Called by both full refresh and soft refresh.
    @MainActor
    /// Internal (vs. private) so XCTest can drive it directly with
    /// fixture entries / Forecast data.
    func applyRefreshedData(
        entries: [HarvestTimeEntry],
        bookedByForecastProject: [Int: Double],
        projectMap: [Int: ForecastProject],
        clientMap: [Int: ForecastClient],
        timeOffBlock: TimeOffBlock?,
        notesByForecastProject: [Int: String]
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
                // Track today's entry: a running entry always wins;
                // otherwise pick the entry with the latest updated_at
                // (i.e. the one the user touched most recently).
                // Iteration-order picking (the previous behavior)
                // returned whatever Harvest sorted first — which is by
                // `id DESC`, so it locked onto the newest-CREATED entry
                // even after the user restarted an older one. Quick
                // Resume then resumed the wrong entry.
                if entry.spentDate == todayString {
                    let existing = todayEntryByProject[entry.project.id]
                    let existingIsRunning = existing?.isRunning ?? false
                    if !existingIsRunning,
                       existing == nil || entry.updatedAt > existing!.updatedAt {
                        todayEntryByProject[entry.project.id] = entry
                    }
                }
                // Track latest entry overall (for task ID when creating new entries)
                if latestEntryByProject[entry.project.id] == nil {
                    latestEntryByProject[entry.project.id] = entry
                }
            }

        // Merge into ProjectStatus list
            var statuses: [ProjectStatus] = []
            var processedHarvestIds: Set<Int> = []

            // Start with Forecast projects (booked), skip non-Harvest projects (e.g. Time Off)
            for (forecastProjectId, bookedHours) in bookedByForecastProject {
                let project = projectMap[forecastProjectId]
                // Time Off is already filtered out of bookedByForecastProject
                // upstream, so this loop only sees real projects. Projects
                // without a Harvest link (prospective / proposal-stage)
                // still appear — they show booked hours but can't have
                // logged time tracked against them.
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
                    projectCode: project?.code,
                    bookedHours: bookedHours,
                    loggedHours: logged,
                    todayHours: today,
                    isTracking: tracking,
                    harvestProjectId: harvestId,
                    todayEntryId: todayEntry?.id,
                    lastTaskId: (latestEntry ?? todayEntry)?.taskAssignment?.task?.id,
                    timeEntries: Self.makeEntryInfos(from: harvestId.flatMap { entriesByHarvestProject[$0] } ?? []),
                    forecastNotes: notesByForecastProject[forecastProjectId]
                ))
            }

            // Add Harvest-only projects (logged but not booked).
            // No `projectCode` — codes live in Forecast and Harvest-
            // only projects by definition aren't in Forecast.
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
                    projectCode: nil,
                    bookedHours: 0,
                    loggedHours: loggedHours,
                    todayHours: todayByHarvestProject[harvestProjectId] ?? 0,
                    isTracking: runningHarvestProjectIds.contains(harvestProjectId),
                    harvestProjectId: harvestProjectId,
                    todayEntryId: todayEntry?.id,
                    lastTaskId: (latestEntry ?? todayEntry)?.taskAssignment?.task?.id,
                    timeEntries: Self.makeEntryInfos(from: entriesByHarvestProject[harvestProjectId] ?? []),
                    forecastNotes: nil
                ))
            }

            // Sort: booked projects before logged-only, then alphabetical
            // by client then project name. Deliberately stable — we don't
            // sort by tracking or recency so the order doesn't shuffle
            // between refreshes (or while a timer auto-saves).
            statuses.sort(by: Self.projectSortOrder)

            projectStatuses = statuses
            let booked = statuses.filter { $0.bookedHours > 0 }
            let unbooked = statuses.filter { $0.bookedHours == 0 }
            totalLogged = booked.reduce(0) { $0 + $1.loggedHours }
            totalBooked = booked.reduce(0) { $0 + $1.bookedHours }
            totalUnbookedLogged = unbooked.reduce(0) { $0 + $1.loggedHours }
            totalTodayLogged = statuses.reduce(0) { $0 + $1.todayHours }

            // Build daily hours breakdown (Mon–Sun). Lock state is
            // week-granular: Harvest submits an entire timesheet at
            // once, so if any entry in the visible week has been
            // submitted or approved, the whole week is locked from
            // edits — including empty weekend days the user didn't
            // track. We key off `approvalStatus` rather than the
            // looser `isLocked` (which also fires for invoiced
            // entries on closed projects, leading to false positives
            // on the current week).
            var hoursByDate: [String: Double] = [:]
            for entry in entries {
                hoursByDate[entry.spentDate, default: 0] += entry.hours
            }
            let weekIsSubmitted = entries.contains { entry in
                entry.approvalStatus == "submitted" || entry.approvalStatus == "approved"
            }
            let calendar = Calendar.current
            let dayLabels = DateHelpers.weekdayLabels
            dailyHours = DateHelpers.weekDays(starting: weekBounds.start).enumerated().map { i, day in
                DayHours(
                    id: day.str,
                    dayLabel: dayLabels[i],
                    hours: hoursByDate[day.str] ?? 0,
                    isToday: calendar.isDateInToday(day.date),
                    isLocked: weekIsSubmitted
                )
            }

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
                trackingSessionBaseline.removeAll()
                currentWeekStart = weekBounds.start
            }
            // Maintain the per-project tracking-session baseline used by
            // `checkBookedHoursReached`. Capture loggedHours when a
            // project enters the tracking state; drop the baseline when
            // it leaves so the next start gets a fresh snapshot.
            for project in statuses {
                if project.isTracking {
                    if trackingSessionBaseline[project.id] == nil {
                        trackingSessionBaseline[project.id] = project.loggedHours
                    }
                } else {
                    trackingSessionBaseline.removeValue(forKey: project.id)
                }
            }

            if statuses.contains(where: { $0.isTracking }) {
                startElapsedTimer()
                checkBookedHoursReached()
            } else {
                stopElapsedTimer()
            }

            detectExternalTimerChange()
    }

    /// Lightweight refresh: fetches today's time entries only, merges with cached
    /// non-today entries, and rebuilds view state using cached Forecast data.
    /// Falls back to a hard refresh if cache is empty.
    @MainActor
    func softRefresh() async {
        guard isConfigured else { return }

        // Respect backoff — if a recent attempt failed we skip until the
        // cool-off period has elapsed.
        if let until = softRefreshBackoffUntil, Date() < until { return }

        // If we haven't done a hard refresh yet, or the week rolled over since
        // the cache was built, fall back to a full refresh so we don't mix
        // stale forecast bookings / old-week entries with the new week's data.
        // The day check catches a subtler case: app open across midnight
        // within the same week, where day-dependent Forecast state (today's
        // PTO, today's bookings) would otherwise stay stale until the user
        // manually refreshes — see the bug report about PTO not picking up
        // until the app was quit and relaunched.
        let todayString = DateHelpers.dateFormatter.string(from: Date())
        guard let userId = cachedHarvestUserId,
              !cachedForecastBookings.isEmpty,
              currentWeekStart == DateHelpers.currentWeekBounds().start,
              currentRefreshDay == todayString
        else {
            // Day rolled over while the app was running — a lingering
            // dayFilter from yesterday would silently hide unbooked
            // projects that only logged time on the new day (PTO logged
            // today, etc.). Clear it so the user sees the full list.
            // The week-rollover case is dominated by `refresh()`'s own
            // snapshot wipe and an empty filter is the right default.
            if dayFilter != nil { dayFilter = nil }
            await refresh()
            return
        }

        guard let (harvestService, _) = makeServices() else { return }

        do {
            // Today's entries + any currently-running entry, in
            // parallel. The running fetch covers timers started
            // before midnight that are still going on the next day —
            // those keep their original `spent_date` and would
            // otherwise be missed by the today-only query (and would
            // have been pruned out of `cachedWeekEntries` on the
            // most recent week-rollover hard refresh).
            async let todayEntries = harvestService.getTimeEntries(
                userId: userId,
                from: todayString,
                to: todayString
            )
            async let runningEntries = harvestService.getRunningTimeEntries(userId: userId)
            let fetchedToday = try await todayEntries
            let fetchedRunning = (try? await runningEntries) ?? []

            // Replace today's slice of the cached week with fresh
            // data, then layer in any running entries that aren't
            // already part of the merged set (covers cross-midnight
            // running timers attached to past dates).
            let nonTodayEntries = cachedWeekEntries.filter { $0.spentDate != todayString }
            let baseMerged = nonTodayEntries + fetchedToday
            let mergedIds = Set(baseMerged.map { $0.id })
            let extraRunning = fetchedRunning.filter { !mergedIds.contains($0.id) }
            let merged = baseMerged + extraRunning
            cachedWeekEntries = merged

            applyRefreshedData(
                entries: merged,
                bookedByForecastProject: cachedForecastBookings,
                projectMap: cachedProjectMap,
                clientMap: cachedClientMap,
                timeOffBlock: cachedTimeOffBlock,
                notesByForecastProject: cachedForecastNotes
            )
            noteFetchSucceeded()
            // Intentionally not updating lastRefreshAt — that tracks hard refreshes
            // only, so menu-open still gets a full refresh after a soft one.
        } catch {
            noteFetchFailed(error)
            scheduleSoftRefreshBackoff()
        }
    }

    /// Exponential backoff after consecutive soft-refresh failures so a
    /// long outage doesn't hammer the API every 60s. Resets to 0 on any
    /// successful fetch. Cadence: 60s → 2m → 5m → 15m → 15m …
    @MainActor
    private func scheduleSoftRefreshBackoff() {
        consecutiveSoftFailures += 1
        let extraSeconds: TimeInterval
        switch consecutiveSoftFailures {
        case 1: extraSeconds = 0          // next 60s tick as normal
        case 2: extraSeconds = 60         // wait ~2 min total
        case 3: extraSeconds = 4 * 60     // wait ~5 min total
        default: extraSeconds = 14 * 60   // cap at ~15 min between attempts
        }
        softRefreshBackoffUntil = extraSeconds > 0 ? Date().addingTimeInterval(extraSeconds) : nil
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
            // Explicit @MainActor on the async let closures because
            // they touch MainActor-isolated cache state. Network
            // awaits inside still release the actor, so the four
            // closures still overlap.
            async let personId: Int = { @MainActor in
                if let id = cachedForecastPersonId { return id }
                let person = try await forecastService.getCurrentPerson()
                cachedForecastPersonId = person.id
                return person.id
            }()
            async let projects: [ForecastProject] = { @MainActor in
                if !cachedProjectMap.isEmpty { return Array(cachedProjectMap.values) }
                return try await forecastService.getProjects()
            }()
            async let clients: [ForecastClient] = { @MainActor in
                if !cachedClientMap.isEmpty { return Array(cachedClientMap.values) }
                return try await forecastService.getClients()
            }()
            async let harvestUserId: Int? = { @MainActor in
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

            // Now issue the per-week lookups concurrently. We fetch both
            // the person-scoped assignments AND the company-wide
            // "Everyone" assignments (e.g. holidays) and merge.
            async let personalAssignments = forecastService.getAssignments(
                personId: resolvedPersonId,
                startDate: startStr,
                endDate: endStr
            )
            async let everyoneAssignments = forecastService.getEveryoneAssignments(
                startDate: startStr,
                endDate: endStr,
                restrictToProjectId: cachedTimeOffProjectId
            )
            async let entries: [HarvestTimeEntry] = {
                guard let uid = resolvedHarvestUserId else { return [] }
                return try await harvestService.getTimeEntries(
                    userId: uid,
                    from: startStr,
                    to: endStr
                )
            }()

            let resolvedAssignments = try await personalAssignments + (try await everyoneAssignments)


            let snapshot = Self.buildSnapshot(
                offset: offset,
                weekBounds: bounds,
                entries: try await entries,
                assignments: resolvedAssignments,
                projects: resolvedProjects,
                clients: resolvedClients,
                fallbackTimeOffProjectId: cachedTimeOffProjectId,
                fullDayHours: dailyHoursTarget
            )
            weekSnapshots[offset] = snapshot
            noteFetchSucceeded()
        } catch {
            noteFetchFailed(error)
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
        clients: [ForecastClient],
        fallbackTimeOffProjectId: Int?,
        /// Daily-hours target — passed in to keep this static helper
        /// pure (no UserDefaults access).
        fullDayHours: Double
    ) -> WeekSnapshot {
        let projectMap = projects.indexed { $0.id }
        let clientMap = clients.indexed { $0.id }
        // Same defensive fallback as the current-week refresh: if /projects
        // didn't include the Time Off project this time, use the last-known
        // good ID so PTO doesn't disappear and leak into booked totals.
        let timeOffProjectId = projects.first(where: { $0.name == YieldConstants.timeOffProjectName })?.id
            ?? fallbackTimeOffProjectId

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
            weekEnd: weekBounds.end,
            fullDayHours: fullDayHours
        )
        let notesByForecastProject = aggregateNotesByProject(
            assignments: assignments,
            timeOffProjectId: timeOffProjectId
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

        // Forecasted projects first. Prospective / proposal-stage
        // projects (no Harvest link yet) are still included — they show
        // booked hours but have no logged time.
        for (forecastProjectId, bookedHours) in bookedByForecastProject {
            let project = projectMap[forecastProjectId]
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
                id: "forecast-\(forecastProjectId)",
                clientName: clientName,
                projectName: projectName,
                projectCode: project?.code,
                bookedHours: bookedHours,
                loggedHours: logged,
                todayHours: 0,
                isTracking: false,
                harvestProjectId: harvestId,
                todayEntryId: nil,
                lastTaskId: nil,
                timeEntries: makeEntryInfos(from: harvestId.flatMap { entriesByHarvestProject[$0] } ?? []),
                forecastNotes: notesByForecastProject[forecastProjectId]
            ))
        }

        // Harvest-only projects — logged without a Forecast booking.
        // No `projectCode` (codes live in Forecast).
        for (harvestProjectId, loggedHours) in loggedByHarvestProject {
            if processedHarvestIds.contains(harvestProjectId) { continue }
            let projectName = harvestProjectNames[harvestProjectId] ?? "Unknown Project"
            let clientName = harvestClientNames[harvestProjectId]
            statuses.append(ProjectStatus(
                id: "harvest-\(harvestProjectId)",
                clientName: clientName,
                projectName: projectName,
                projectCode: nil,
                bookedHours: 0,
                loggedHours: loggedHours,
                todayHours: 0,
                isTracking: false,
                harvestProjectId: harvestProjectId,
                todayEntryId: nil,
                lastTaskId: nil,
                timeEntries: makeEntryInfos(from: entriesByHarvestProject[harvestProjectId] ?? []),
                forecastNotes: nil
            ))
        }

        // Sort: forecasted projects first (alphabetical by client/project),
        // then logged-only Harvest projects by name.
        statuses.sort(by: projectSortOrder)

        // Daily hours breakdown for the header's weekday mini-bar.
        // - Past weeks / current (offset ≤ 0): sum of Harvest entries
        //   per day — i.e. tracked time.
        // - Future weeks (offset > 0): sum of Forecast assignment
        //   allocations per day, INCLUDING time off (holidays, PTO) so
        //   the daily and week totals reflect the full booked picture.
        //   Time-off assignments with allocation=0 (Forecast's "full
        //   day off" convention) are treated as the user's daily-
        //   hours target (default 8).
        let calendar = Calendar.current
        let dayLabels = DateHelpers.weekdayLabels
        let weekDays = DateHelpers.weekDays(starting: weekBounds.start)

        var hoursByDate: [String: Double] = [:]
        if offset > 0 {
            for assignment in assignments {
                guard assignment.projectId != nil,
                      let aStart = DateHelpers.dateFormatter.date(from: assignment.startDate),
                      let aEnd = DateHelpers.dateFormatter.date(from: assignment.endDate) else { continue }
                let allocationSeconds = assignment.allocation ?? 0
                let isTimeOff = assignment.projectId == timeOffProjectId
                let hoursPerDay = (isTimeOff && allocationSeconds == 0)
                    ? fullDayHours
                    : Double(allocationSeconds) / 3600.0
                for (day, dateStr) in weekDays where day >= aStart && day <= aEnd && day <= weekBounds.end {
                    hoursByDate[dateStr, default: 0] += hoursPerDay
                }
            }
        } else {
            for entry in entries {
                hoursByDate[entry.spentDate, default: 0] += entry.hours
            }
        }
        // See applyRefreshedData: lock state is week-granular,
        // derived from `approvalStatus` so weekend days without
        // entries still inherit the lock icon when the timesheet
        // was submitted.
        let weekIsSubmitted = entries.contains { entry in
            entry.approvalStatus == "submitted" || entry.approvalStatus == "approved"
        }
        var dailyHours: [DayHours] = []
        for (i, day) in weekDays.enumerated() {
            dailyHours.append(DayHours(
                id: day.str,
                dayLabel: dayLabels[i],
                hours: hoursByDate[day.str] ?? 0,
                isToday: calendar.isDateInToday(day.date),
                isLocked: weekIsSubmitted
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

    /// URL loading error codes that indicate a transport-layer
    /// connectivity problem (as opposed to a server/API error). Single
    /// source of truth — consumed by both `isConnectivityError` and
    /// `friendlyErrorMessage`.
    private static let connectivityErrorCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet,
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDataNotAllowed,
        NSURLErrorInternationalRoamingOff,
    ]

    /// True when an error represents a transport-layer connectivity
    /// problem rather than a server/API error.
    private func isConnectivityError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return Self.connectivityErrorCodes.contains(nsError.code)
    }

    /// Mark a fetch attempt as successful — clears the offline signal and
    /// resets the soft-refresh backoff. Called after every successful fetch
    /// path (hard refresh, soft refresh, fetchWeek).
    @MainActor
    private func noteFetchSucceeded() {
        hasConnectivityError = false
        consecutiveSoftFailures = 0
        softRefreshBackoffUntil = nil
    }

    /// Mark a fetch attempt as failed due to connectivity, so the UI can
    /// signal staleness. No-op for non-connectivity errors.
    @MainActor
    private func noteFetchFailed(_ error: Error) {
        guard isConnectivityError(error) else { return }
        hasConnectivityError = true
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let code) where (500...599).contains(code):
                return "Service unavailable (HTTP \(code))"
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
            case _ where Self.connectivityErrorCodes.contains(nsError.code):
                return "Unable to connect"
            default:
                return "Network error"
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Test-only state helpers
//
// XCTest needs to seed internal state (projectStatuses, the
// budget-notification baselines, change-detection bookkeeping)
// before exercising the methods that depend on it. An extension
// declared in the same file as the type can reach `private` and
// `private(set)` members, so this surface is testable without
// weakening visibility in production.
extension TimeComparisonViewModel {
    /// Bulk-set the bookkeeping state needed by tests. Every
    /// argument is optional so a test only sets what it needs.
    @MainActor
    func _setStateForTesting(
        projectStatuses: [ProjectStatus]? = nil,
        notifiedProjectIds: Set<String>? = nil,
        trackingSessionBaseline: [String: Double]? = nil,
        elapsedOffset: Double? = nil,
        currentWeekStart: Date? = nil,
        currentRefreshDay: String? = nil,
        hasSeenInitialTrackingState: Bool? = nil,
        lastTrackingEntryId: Int? = nil,
        suppressNextTimerChangeHUD: Bool? = nil
    ) {
        if let projectStatuses { self.projectStatuses = projectStatuses }
        if let notifiedProjectIds { self.notifiedProjectIds = notifiedProjectIds }
        if let trackingSessionBaseline { self.trackingSessionBaseline = trackingSessionBaseline }
        if let elapsedOffset { self.elapsedOffset = elapsedOffset }
        if let currentWeekStart { self.currentWeekStart = currentWeekStart }
        if let currentRefreshDay { self.currentRefreshDay = currentRefreshDay }
        if let hasSeenInitialTrackingState { self.hasSeenInitialTrackingState = hasSeenInitialTrackingState }
        if let lastTrackingEntryId { self.lastTrackingEntryId = lastTrackingEntryId }
        if let suppressNextTimerChangeHUD { self.suppressNextTimerChangeHUD = suppressNextTimerChangeHUD }
    }

    /// Read-only mirror of `notifiedProjectIds`. The set itself stays
    /// `private` so production code can't accidentally write to it
    /// from outside the budget-notification gate.
    @MainActor
    var _notifiedProjectIdsForTesting: Set<String> { notifiedProjectIds }
}
