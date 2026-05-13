import SwiftUI

struct ProjectRowView: View {
    let project: ProjectStatus
    var effectiveLoggedHours: Double
    /// Entries to render in the drawer + day-by-day bar. The parent
    /// passes a day-filtered list when the weekday mini-bar filter is
    /// active; otherwise it passes `project.timeEntries`.
    let visibleEntries: [TimeEntryInfo]
    /// When non-nil, the row is being shown under an active day filter.
    /// The header time label switches from "week / booked" to
    /// "day / week-so-far" so the user can see how the filtered day
    /// contributes to the week total. Progress bar still reflects the
    /// week against booked.
    var dayFilteredHours: Double? = nil
    var onToggleTimer: (() -> Void)? = nil
    var onToggleEntryTimer: ((Int, Bool) -> Void)? = nil
    var onEditEntry: ((TimeEntryInfo) -> Void)? = nil
    var onDeleteEntry: ((TimeEntryInfo) -> Void)? = nil
    var isHarvestDown: Bool = false
    var onStartTimerForProject: (() -> Void)? = nil
    /// Quick-start a timer using this project's most-recently-used
    /// favorite task, bypassing the new-timer form. Wired only when
    /// `FavoritesStore` has a favorite for `project.harvestProjectId`.
    /// Receives `(projectId, taskId)` for the favorite to start.
    var onQuickStartFavorite: ((Int, Int) -> Void)? = nil
    /// Restart this project's most recent today entry. Shown in the
    /// right-click menu when there's a today entry on the project and
    /// it's not currently running. Receives the entry id.
    var onResumeToday: ((Int) -> Void)? = nil
    /// When true, all write interactions are suppressed — no play/stop
    /// buttons, no context menus, no double-click-to-edit. Used for
    /// rendering past weeks (Harvest "submits" those entries and locking
    /// makes editing moot).
    var isReadOnly: Bool = false
    /// Monday of the week this row represents. Defaults to nil (current
    /// week); set to a specific date when rendering a past-week snapshot
    /// so the segmented bar aligns with that week's entries.
    var weekStart: Date? = nil
    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false
    /// True while the cursor is over the row's right-side zone
    /// (time / progress / actions). Drives the second stage of the
    /// quick-action reveal: row-hover shows a peek; zone-hover shows
    /// the icons in full.
    @State private var isActionZoneHovered: Bool = false

    private var hasEntries: Bool { !visibleEntries.isEmpty }

    /// Today's effective hours on this project (includes live-ticking offset
    /// while a timer is running on it). Used to drive the today segment in
    /// the expanded day-by-day bar so it updates in real time.
    private var effectiveTodayHours: Double {
        project.todayHours + (project.isTracking ? effectiveLoggedHours - project.loggedHours : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader
                .background(isHovered ? YieldColors.surfaceDefault : Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
                .onTapGesture {
                    guard hasEntries else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

            // Accordion drawer: day-by-day breakdown bar at the top, then the
            // project's time entries. Always in the view tree so the container
            // can animate between 0 and natural height; clipped() hides
            // overflow so contents reveal top-to-bottom as the height grows.
            VStack(spacing: 0) {
                if project.isForecasted || !visibleEntries.isEmpty {
                    SegmentedProgressBarView(
                        entries: visibleEntries,
                        todayEffectiveHours: effectiveTodayHours,
                        booked: project.bookedHours,
                        isDrawerExpanded: isExpanded,
                        weekStart: weekStart
                    )
                    // Left padding matches the task-entry text indent (32)
                    // so the bar aligns with the rows below it. Top padding
                    // doubled (20) so there's room for the hover tooltip to
                    // float above the bar without being clipped.
                    .padding(.leading, 32)
                    .padding(.trailing, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                }

                ForEach(visibleEntries) { entry in
                    TaskEntryRowView(
                        entry: entry,
                        isHarvestDown: isHarvestDown,
                        isReadOnly: isReadOnly,
                        onToggleTimer: {
                            onToggleEntryTimer?(entry.id, entry.isRunning)
                        },
                        onEditEntry: {
                            onEditEntry?(entry)
                        },
                        onDeleteEntry: {
                            onDeleteEntry?(entry)
                        }
                    )
                }
            }
            .frame(maxHeight: isExpanded ? .infinity : 0, alignment: .top)
            .clipped()
            // Clipped content still captures hit tests in SwiftUI, so collapsed
            // task rows can swallow right-clicks on views rendered below (e.g.
            // the Time Off row), showing their Edit/Delete Timer menu by
            // surprise. Disable hit testing while collapsed to prevent that.
            .allowsHitTesting(isExpanded)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
        // Auto-collapse the drawer when its last visible entry disappears
        // (typically: user deletes the only entry from the drawer). The
        // drawer has nothing to show in that state, and the
        // `hasEntries`-guarded tap gesture would prevent re-opening it
        // anyway — leaving it stuck open is just visual dead space.
        .onChange(of: visibleEntries.isEmpty) { _, isEmpty in
            if isEmpty, isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Project Header

    private var projectHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left colored line
            statusLine

            // Project details + time
            HStack {
                if let notes = project.forecastNotes {
                    ForecastNotesIcon(notes: notes)
                }

                // Left: client, name, remaining
                VStack(alignment: .leading, spacing: 6) {
                    // Client name
                    if let clientName = project.clientName {
                        Text(clientName.uppercased())
                            .font(YieldFonts.labelProject)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                    }

                    // Project name + chevron
                    HStack(spacing: 10) {
                        Text(project.projectName)
                            .font(YieldFonts.titleMedium)
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)

                        if hasEntries {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(YieldColors.textPrimary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        }
                    }

                    // Remaining / over label (forecasted only)
                    if project.isForecasted {
                        let remaining = project.bookedHours - effectiveLoggedHours
                        if remaining != 0 {
                            Text(formatRemainingLabel(remaining))
                                .font(YieldFonts.labelTimeRemaining)
                                .foregroundStyle(remaining < 0 ? YieldStatusColors.over : YieldColors.greenAccent)
                                .tracking(0.18)
                        }
                    }
                }

                Spacer(minLength: 8)

                // Right-side zone: time/progress + quick actions.
                // Wrapped so we can attach a focused `.onHover` that
                // triggers the second stage of the action reveal.
                // Stage 1 (row-hover): icons peek at a few pt of width
                // — hint that they're there. Stage 2 (zone-hover):
                // icons reveal fully and the progress bar reflows. No
                // popover (popovers inside MenuBarExtra panels cause
                // window resize jumps).
                HStack {
                    VStack(alignment: .trailing, spacing: 8) {
                        timeLabel

                        if project.isForecasted {
                            ProgressBarView(
                                logged: effectiveLoggedHours,
                                booked: project.bookedHours,
                                dayLogged: dayFilteredHours
                            )
                        }
                    }

                    if hasOverflowActions {
                        // Cross-faded reveal:
                        //   - Row hover → ellipsis "peek" icon (single
                        //     22pt affordance hinting that actions
                        //     exist).
                        //   - Zone hover → icon fades out, action bar
                        //     fades in with its trailing-aligned slide.
                        // Both children share the ZStack's trailing
                        // edge so the visual swap happens in place.
                        ZStack(alignment: .trailing) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(YieldColors.textSecondary)
                                .frame(width: 22, height: 22)
                                .opacity(showPeekIcon ? 1 : 0)

                            quickActionsBar
                                .fixedSize()
                                .opacity(isActionZoneHovered ? 1 : 0)
                        }
                        .frame(width: rightZoneWidth, alignment: .trailing)
                        .clipped()
                    }
                }
                // Expand the hit area to the full row height so the
                // cursor doesn't drift out of the hover zone when it
                // strays above or below the icons. The visible content
                // stays centered (HStack default), only the hit-test
                // frame grows. `.contentShape` applied after the frame
                // uses the taller bounds; it also collapses any
                // transparent gaps between the time VStack and the
                // action bar so hover doesn't flip false/true as the
                // cursor crosses invisible HStack-spacing.
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isActionZoneHovered = hovering
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
        }
        .frame(height: project.isForecasted ? YieldDimensions.projectRowForecastedHeight : YieldDimensions.projectRowDefaultHeight)
    }

    // MARK: - Hover Quick-Action Buttons

    private var hasOverflowActions: Bool {
        !isReadOnly && project.harvestProjectId != nil
    }

    /// Number of quick-action buttons that will render for this row.
    /// Add Time is always present (when actionable); Resume and Quick
    /// Start are conditional on entry/favorite state.
    private var quickActionCount: Int {
        guard let projectId = project.harvestProjectId else { return 0 }
        var count = 1 // Add Time
        if !project.isTracking, project.todayEntryId != nil { count += 1 }
        if FavoritesStore.shared.mostRecentlyUsedFavorite(forProjectId: projectId) != nil { count += 1 }
        return count
    }

    /// Full natural width of the action bar: 22pt per button, 4pt
    /// spacing between, +4pt leading padding.
    private var quickActionsFullWidth: CGFloat {
        let n = quickActionCount
        guard n > 0 else { return 0 }
        return CGFloat(n) * 22 + CGFloat(max(n - 1, 0)) * 4 + 4
    }

    /// Three-stage reveal width for the right-side zone:
    ///   - Zone hovered → full action-bar width
    ///   - Row hovered  → 22pt (single peek-icon slot)
    ///   - Neither      → 0
    private var rightZoneWidth: CGFloat {
        guard hasOverflowActions else { return 0 }
        if isActionZoneHovered { return quickActionsFullWidth }
        if isHovered { return 22 }
        return 0
    }

    /// The peek ellipsis shows only when the row is hovered but the
    /// zone is not — i.e. the user has surfaced the affordance but
    /// hasn't committed to using it.
    private var showPeekIcon: Bool {
        hasOverflowActions && isHovered && !isActionZoneHovered
    }

    /// Row of icon buttons that appears on the right side of the
    /// project row while hovered. Each icon is a direct action — no
    /// menu / popover layer, so the click count drops from two to one.
    /// Number of buttons varies (1–3) depending on which actions apply.
    @ViewBuilder
    private var quickActionsBar: some View {
        HStack(spacing: 4) {
            if let projectId = project.harvestProjectId {
                if !project.isTracking, let entryId = project.todayEntryId {
                    quickActionButton(systemImage: "arrow.clockwise", help: "Resume Timer") {
                        onResumeToday?(entryId)
                    }
                }
                if let favorite = FavoritesStore.shared.mostRecentlyUsedFavorite(forProjectId: projectId) {
                    quickActionButton(systemImage: "bolt.fill", help: "Quick Start") {
                        onQuickStartFavorite?(projectId, favorite.taskId)
                    }
                }
                quickActionButton(systemImage: "plus.circle.fill", help: "Add Time") {
                    onStartTimerForProject?()
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func quickActionButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(isHarvestDown)
        .opacity(isHarvestDown ? 0.4 : 1)
    }

    // MARK: - Status Line

    private var statusLine: some View {
        Rectangle()
            .fill(statusLineColor)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    /// Color of the leading status line.
    /// - Clear: project has no booking (Harvest-only tracked time)
    /// - Pink: prospective / proposal-stage (booked but no Harvest link)
    /// - White: normal booked project
    private var statusLineColor: Color {
        guard project.isForecasted else { return .clear }
        if project.harvestProjectId == nil { return YieldStatusColors.prospective }
        return YieldColors.onBackground.opacity(0.7)
    }

    // MARK: - Time Label

    private var timeLabel: some View {
        Group {
            if let dayHours = dayFilteredHours {
                // Day filter active: show "day total / week-so-far" so the
                // filtered day's contribution is framed against the week.
                HStack(spacing: 0) {
                    Text(formatHoursMinutes(dayHours) + " / ")
                        .foregroundStyle(YieldColors.textPrimary)
                    Text(formatHoursMinutes(effectiveLoggedHours))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .font(YieldFonts.monoSmall)
            } else if project.isForecasted {
                HStack(spacing: 0) {
                    Text(formatHoursMinutes(effectiveLoggedHours) + " / ")
                        .foregroundStyle(YieldColors.textPrimary)
                    Text(formatHoursOnly(project.bookedHours))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .font(YieldFonts.monoSmall)
            } else {
                Text(formatHoursMinutes(effectiveLoggedHours))
                    .font(YieldFonts.monoSmall)
                    .foregroundStyle(YieldColors.textPrimary)
            }
        }
        .fixedSize()
    }

    // MARK: - Formatting

    private func formatHoursMinutes(_ hours: Double) -> String {
        formatHM(hours)
    }

    private func formatHoursOnly(_ hours: Double) -> String {
        let h = Int(hours)
        return "\(h)h"
    }

    private func formatRemainingLabel(_ remaining: Double) -> String {
        let suffix = remaining < 0 ? "over this week" : "remaining this week"
        return "\(Swift.abs(remaining).formattedHoursMinutes) \(suffix)"
    }
}

// Shared hours:minutes formatter used by ProjectRowView and TaskEntryRowView
private func formatHM(_ hours: Double) -> String {
    Swift.abs(hours).formattedHoursMinutes
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    let logged: Double
    let booked: Double
    /// When non-nil, the row is filtered to a single day. The week fill
    /// dims to 50% and a full-opacity overlay shows the day's portion of
    /// the week so far.
    var dayLogged: Double? = nil

    private var ratio: Double {
        guard booked > 0 else { return 0 }
        return max(logged / booked, 0)
    }

    private var isOver: Bool { ratio > 1.0 }

    private var barColor: Color {
        isOver ? YieldStatusColors.over : YieldStatusColors.under
    }

    /// Normalized fill: when over, the "booked" portion shrinks to show overage visually.
    /// e.g. 24h/12h (2x) → booked fills 50%, overage fills remaining 50%.
    private var bookedFill: Double {
        guard ratio > 1.0 else { return max(ratio, 0) }
        // Invert: booked portion = 1/ratio (shrinks as overage grows), min 20% so it stays visible
        return max(1.0 / min(ratio, 5.0), 0.2)
    }

    /// Width fraction for the day overlay. Scales the day's share of the
    /// week against the week's rendered fill, so the overlay always sits
    /// within the week fill regardless of over/under state.
    private var dayFill: Double {
        guard let dayLogged, dayLogged > 0, logged > 0 else { return 0 }
        return bookedFill * min(max(dayLogged / logged, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background: overage color when over, default otherwise
            RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                .fill(isOver ? YieldStatusColors.over.opacity(0.4) : YieldColors.surfaceActive)
                .frame(width: YieldDimensions.progressBarWidth, height: YieldDimensions.progressBarHeight)

            // Fill: booked portion. Dimmed when a day filter is active so
            // the day overlay reads as the focal element.
            RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                .fill(barColor)
                .opacity(dayLogged != nil ? 0.4 : 1.0)
                .frame(
                    width: YieldDimensions.progressBarWidth * bookedFill,
                    height: YieldDimensions.progressBarHeight
                )
                .animation(.easeInOut(duration: 0.4), value: bookedFill)

            // Day overlay: full-opacity slice of the week fill.
            if dayLogged != nil {
                RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                    .fill(barColor)
                    .frame(
                        width: YieldDimensions.progressBarWidth * dayFill,
                        height: YieldDimensions.progressBarHeight
                    )
                    .animation(.easeInOut(duration: 0.4), value: dayFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.progressBar))
    }
}

// MARK: - Segmented Progress Bar (expanded day-by-day view)

/// Full-width progress bar broken into per-day segments. Each visible
/// segment's width is proportional to that day's hours vs. the weekly
/// booked budget, so empty days show no segment and the gaps between
/// segments visually separate days. Day labels sit underneath each
/// segment. Clicking anywhere in the parent collapses this view.
struct SegmentedProgressBarView: View {
    let entries: [TimeEntryInfo]
    let todayEffectiveHours: Double
    let booked: Double
    let isDrawerExpanded: Bool
    /// Monday of the week this bar represents. Defaults to the current
    /// week; pass a different value when rendering a past-week snapshot
    /// so the day grid matches the entries' spent_date values.
    var weekStart: Date? = nil

    /// Scales every segment width from 0 → 1. Animated to 1 when the parent
    /// drawer opens and snapped back to 0 when it closes, giving a "fill
    /// sweep" on each open without playing the animation in reverse when
    /// the drawer collapses (clipped content doesn't need to animate).
    @State private var fillProgress: Double = 0

    private struct DayFill: Identifiable {
        let id: String          // date string
        let label: String       // "Mon", etc.
        let hours: Double
        let isToday: Bool
    }


    /// One entry per day of the target week. Today's hours are replaced
    /// with `todayEffectiveHours` so the live-ticking timer shows up.
    private var days: [DayFill] {
        let resolvedWeekStart = weekStart ?? DateHelpers.currentWeekBounds().start
        let todayString = DateHelpers.dateFormatter.string(from: Date())
        let calendar = Calendar.current

        // Sum hours per date from the entries
        var hoursByDate: [String: Double] = [:]
        for entry in entries {
            hoursByDate[entry.date, default: 0] += entry.hours
        }

        var result: [DayFill] = []
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: i, to: resolvedWeekStart) else { continue }
            let dateStr = DateHelpers.dateFormatter.string(from: date)
            let isToday = dateStr == todayString
            let hours = isToday ? todayEffectiveHours : (hoursByDate[dateStr] ?? 0)
            result.append(DayFill(id: dateStr, label: DateHelpers.weekdayLabels[i], hours: hours, isToday: isToday))
        }
        return result
    }

    /// Only weekdays with logged time (plus today, even if zero, so the
    /// current day is always represented).
    private var activeDays: [DayFill] {
        days.filter { $0.hours > 0 || $0.isToday }
    }

    private var totalHours: Double { days.reduce(0) { $0 + $1.hours } }

    var body: some View {
        GeometryReader { geo in
            segmentedBar(totalWidth: geo.size.width)
        }
        .frame(height: 8)
        .onChange(of: isDrawerExpanded) { _, expanded in
            if expanded {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                    fillProgress = 1
                }
            } else {
                // Wait until the drawer's close animation (0.2s) finishes
                // before snapping the fill back to 0, so the bar stays
                // visible during the close and the reset happens while
                // the drawer is already clipped out of view.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    fillProgress = 0
                }
            }
        }
    }

    /// Over budget when booked is positive and total logged exceeds it.
    /// Mirrors ProgressBarView's semantics so the two stay in sync.
    private var isOver: Bool {
        booked > 0 && totalHours > booked
    }

    private var barColor: Color {
        isOver ? YieldStatusColors.over : YieldStatusColors.under
    }

    private var backgroundColor: Color {
        isOver ? YieldStatusColors.over.opacity(0.4) : YieldColors.surfaceActive
    }

    @ViewBuilder
    private func segmentedBar(totalWidth: CGFloat) -> some View {
        let denominator = max(booked, totalHours, 0.0001)
        ZStack(alignment: .leading) {
            // Background — over color (dim) when past budget, matches the
            // mini ProgressBarView treatment.
            Rectangle()
                .fill(backgroundColor)

            // Per-day filled segments, separated by 2px gaps. Widths are
            // scaled by fillProgress (0→1) so the bar "sweeps" in when the
            // drawer opens. Native .help() tooltip reveals day + hours on
            // hover.
            HStack(spacing: 2) {
                ForEach(activeDays) { day in
                    let fullWidth = CGFloat(day.hours / denominator) * totalWidth
                    let w = max(fullWidth * fillProgress, 0)
                    Rectangle()
                        .fill(barColor)
                        .frame(width: w)
                        .opacity(day.isToday ? 1.0 : 0.75)
                        .help("\(day.label): \(formatHMColon(day.hours))")
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Format hours as "H:MM" (e.g. 3.25 → "3:15"). Tooltip-friendly.
    private func formatHMColon(_ hours: Double) -> String { hours.formattedColon }
}

// MARK: - Task Entry Row

struct TaskEntryRowView: View {
    let entry: TimeEntryInfo
    var isHarvestDown: Bool = false
    var isReadOnly: Bool = false
    var onToggleTimer: (() -> Void)? = nil
    var onEditEntry: (() -> Void)? = nil
    var onDeleteEntry: (() -> Void)? = nil
    @State private var isHovered: Bool = false

    private var hasNotes: Bool {
        if let notes = entry.notes, !notes.isEmpty { return true }
        return false
    }

    private var isToday: Bool {
        guard let date = DateHelpers.dateFormatter.date(from: entry.date) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        HStack {
            // Task details + time info (double-click to edit)
            HStack {
                VStack(alignment: .leading, spacing: hasNotes ? 6 : 0) {
                    Text(entry.taskName)
                        .font(YieldFonts.titleSmall)
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 226, alignment: .leading)

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(YieldFonts.labelNote)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tracking(0.36)
                    }
                }
                .frame(width: 268, alignment: .leading)

                Spacer()

                HStack(spacing: 8) {
                    if entry.isRunning {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(YieldColors.greenAccent)
                    }

                    Text(formatHoursMinutes(entry.hours))
                        .font(YieldFonts.monoXS)
                        .foregroundStyle(entry.isRunning ? YieldColors.greenAccent : YieldColors.textSecondary)

                    if entry.isRunning {
                        Text("Now")
                            .font(YieldFonts.monoXS)
                            .foregroundStyle(YieldColors.greenAccent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(YieldColors.greenDim)
                            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
                    } else {
                        Text(formatDay(entry.date))
                            .font(YieldFonts.monoXS)
                            .foregroundStyle(YieldColors.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !isHarvestDown, !isReadOnly else { return }
                onEditEntry?()
            }

            // Play/stop button (only for today's entries, hidden when read-only)
            if isToday && !isReadOnly {
                Button(action: { onToggleTimer?() }) {
                    Image(systemName: entry.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(TimerControlButtonStyle(
                    borderColor: entry.isRunning ? YieldColors.greenAccent : YieldColors.buttonBorder,
                    foregroundColor: entry.isRunning ? YieldColors.greenAccent : YieldColors.textSecondary,
                    destructiveOnHover: entry.isRunning
                ))
                .disabledWhenHarvestDown(isHarvestDown)
            }
        }
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(isHovered ? YieldColors.surfaceDefault : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .contextMenu {
            if !isReadOnly {
                Button {
                    onEditEntry?()
                } label: {
                    Label("Edit Timer", systemImage: "pencil")
                }
                .disabled(isHarvestDown)
                Button(role: .destructive) {
                    onDeleteEntry?()
                } label: {
                    Label("Delete Timer", systemImage: "trash")
                }
                .disabled(isHarvestDown)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private func formatHoursMinutes(_ hours: Double) -> String {
        formatHM(hours)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private func formatDay(_ dateString: String) -> String {
        guard let date = DateHelpers.dateFormatter.date(from: dateString) else { return dateString }
        if Calendar.current.isDateInToday(date) { return "Today" }
        return Self.dayFormatter.string(from: date)
    }
}
