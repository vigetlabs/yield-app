import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    /// Single source of truth for the default appearance, referenced by
    /// the AppDelegate's UserDefaults registration, the @AppStorage
    /// fallbacks, and `applyAppearance`. Change here, change everywhere.
    static let `default`: AppearanceMode = .dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

/// What the menu bar shows next to the icon while a timer is running.
/// Persisted to UserDefaults via the `menuBarLabelMode` key.
enum MenuBarLabelMode: String, CaseIterable {
    /// Default: the active project's tracked hours vs. its weekly booking.
    /// Falls back to the week-wide total / weekly budget when no timer is
    /// running.
    case projectTime
    /// The current timer's hours vs. the running total of all logged time
    /// today. Falls back to today's total / 8h when no timer is running.
    case dayTime
    /// Just the current running timer's hours, in compact form (no
    /// denominator). A paused timer keeps showing its frozen value;
    /// once all timers are stopped, falls back to today's running total.
    case currentTimer

    var label: String {
        switch self {
        case .projectTime:  return "Project time"
        case .dayTime:      return "Day time"
        case .currentTimer: return "Current timer"
        }
    }
}


struct MenuBarContentView: View {
    let viewModel: TimeComparisonViewModel
    @State private var showNewTimerForm = false
    @State private var editingEntry: TimeEntryInfo? = nil
    @State private var preselectedProjectId: Int? = nil
    @State private var newTimerTargetDate: Date? = nil
    @State private var showSettings = false
    /// Natural heights of the panel's non-list regions, measured at
    /// runtime so we can subtract them from the screen-bounded ceiling
    /// to give the list section its scrolling budget.
    @State private var fixedTopHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    /// Visible-frame height of the screen the panel is currently on,
    /// reported by `OpaqueMenuBarPanel` from the panel's own window. The
    /// initial value is overwritten as soon as the window attaches.
    @State private var screenVisibleHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if viewModel.idleAlertState != nil {
                    IdleAlertView(viewModel: viewModel)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else if showSettings {
                    SettingsView(oAuthService: AppState.shared.oAuthService) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSettings = false
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if showNewTimerForm || editingEntry != nil || viewModel.pendingIdleMove != nil {
                    NewTimerFormView(
                        viewModel: viewModel,
                        editingEntry: editingEntry,
                        preselectedProjectId: preselectedProjectId,
                        targetDate: newTimerTargetDate,
                        idleMove: viewModel.pendingIdleMove
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if viewModel.pendingIdleMove != nil {
                                viewModel.idleMoveCancel()
                            }
                            showNewTimerForm = false
                            editingEntry = nil
                            preselectedProjectId = nil
                            newTimerTargetDate = nil
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if !viewModel.isConfigured {
                    notConfiguredView
                        .transition(.opacity)
                } else if viewModel.isLoading && viewModel.projectStatuses.isEmpty {
                    loadingView
                        .transition(.opacity)
                } else if let error = viewModel.errorMessage, viewModel.projectStatuses.isEmpty {
                    errorView(error)
                        .transition(.opacity)
                } else {
                    contentView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSettings)
            .animation(.easeInOut(duration: 0.2), value: showNewTimerForm)
            .animation(.easeInOut(duration: 0.2), value: editingEntry?.id)
            .animation(.easeInOut(duration: 0.2), value: viewModel.idleAlertState != nil)
            .animation(.easeInOut(duration: 0.2), value: viewModel.pendingIdleMove != nil)

            if viewModel.idleAlertState == nil && viewModel.pendingIdleMove == nil && !showSettings && !showNewTimerForm && editingEntry == nil {
                footerView
                    .transition(.opacity)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
            }
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
        .background(OpaqueMenuBarPanel(onVisibleHeightChange: { height in
            if height != screenVisibleHeight {
                screenVisibleHeight = height
            }
        }))
        // The timer banner's expand/collapse spring lives at the body
        // level so parent reflow and panel resize share its animation
        // context — scoped to just `TimerBannerView`, the parent would
        // snap discretely around the smoothly-animating banner.
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: viewModel.isTimerBannerVisible)
    }

    /// Maximum height for the project-list ScrollView. The 120pt floor
    /// guards against the very first frame, before fixed-section
    /// measurements have landed, collapsing the list to nothing.
    private var availableForList: CGFloat {
        max(120, maxPanelHeight - fixedTopHeight - footerHeight)
    }


    /// Cap the panel just under the screen's visible area. `visibleFrame`
    /// already excludes the menu bar and dock, so the 16pt buffer is just
    /// breathing room.
    private var maxPanelHeight: CGFloat {
        max(400, screenVisibleHeight - 16)
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed top region — measured as a single block so we know
            // how much vertical space the project list has left.
            VStack(alignment: .leading, spacing: 0) {
                headerView

                if !viewModel.serviceErrors.isEmpty {
                    serviceWarningBanner
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                // Time Off summary — pinned above the timer banner so the "you
                // have PTO this week" signal lives at the top of the panel.
                if let timeOff = viewModel.displayedTimeOff, viewModel.selectedTab != .chart {
                    TimeOffRowView(block: timeOff)
                }

                // Timer banner / inactive slot — only shown for the current
                // week; hidden on past/future weeks since no timer state is
                // meaningful there.
                if !viewModel.isViewingOtherWeek {
                    timerBannerSlot
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { fixedTopHeight = $0 }

            // `fixedSize(vertical:)` lets the ScrollView size to its
            // content's ideal height, clamped by the frame's maxHeight —
            // so the panel sizes naturally when the list fits and caps
            // (with scrolling) when it doesn't.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    listSection
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: availableForList)
            .fixedSize(horizontal: false, vertical: true)
        }
        // Cross-fade the Time Off row, timer banner, and project list
        // whenever we swap data via week navigation or a refresh lands.
        // Rows with stable IDs re-render in place; new/removed rows fade.
        .animation(.easeInOut(duration: 0.22), value: viewModel.weekOffset)
        .animation(.easeInOut(duration: 0.22), value: viewModel.displayedFilteredStatuses.map(\.id))
    }

    /// The variable-height project / chart / empty-state region inside
    /// the scrollable container.
    @ViewBuilder
    private var listSection: some View {
        if viewModel.isViewingOtherWeek {
            otherWeekList
        } else if viewModel.selectedTab == .chart {
            ProjectChartView(viewModel: viewModel)
        } else if viewModel.filteredStatuses.isEmpty {
            Text(viewModel.dayFilter != nil
                ? "No projects found for this day."
                : "No projects found for this week.")
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
                .padding(16)
        } else {
            ForEach(viewModel.filteredStatuses) { project in
                ProjectRowView(
                    project: project,
                    effectiveLoggedHours: viewModel.effectiveLoggedHours(for: project),
                    visibleEntries: viewModel.visibleEntries(for: project),
                    dayFilteredHours: viewModel.dayFilteredHours(for: project),
                    onToggleTimer: {
                        Task { await viewModel.toggleTimer(for: project) }
                    },
                    onToggleEntryTimer: { entryId, isRunning in
                        Task { await viewModel.toggleEntryTimer(entryId: entryId, isRunning: isRunning) }
                    },
                    onEditEntry: { entry in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editingEntry = entry
                        }
                    },
                    onDeleteEntry: { entry in
                        Task { await viewModel.deleteTimeEntry(entryId: entry.id) }
                    },
                    isHarvestDown: viewModel.isHarvestDown,
                    onStartTimerForProject: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            preselectedProjectId = project.harvestProjectId
                            showNewTimerForm = true
                        }
                    }
                )
            }
        }
    }

    /// Timer banner area. `TimerBannerView` is always rendered and
    /// handles its own empty-strip vs. expanded-banner state with a
    /// height + opacity animation, so this slot is just responsible for
    /// hiding the row entirely on the chart tab.
    @ViewBuilder
    private var timerBannerSlot: some View {
        TimerBannerView(
            viewModel: viewModel,
            onEditEntry: { entry in
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingEntry = entry
                }
            },
            onDeleteEntry: { entry in
                Task { await viewModel.deleteTimeEntry(entryId: entry.id) }
            }
        )
        // On the chart tab the slot collapses to 0pt so the banner is
        // hidden; everywhere else `maxHeight: nil` lets the banner take
        // its natural ~74pt (running) or ~16pt (idle strip) height. The
        // earlier `.infinity` made the slot greedily fill any spare
        // vertical space, inflating the whole panel when content was
        // short.
        .frame(maxHeight: viewModel.selectedTab == .chart ? 0 : nil, alignment: .top)
        .clipped()
    }

    /// Project list for past (read-only) or future (look-ahead) weeks.
    @ViewBuilder
    private var otherWeekList: some View {
        if viewModel.isLoadingOtherWeek && viewModel.displayedFilteredStatuses.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(YieldColors.textSecondary)
                Spacer()
            }
            .padding(24)
        } else if let err = viewModel.otherWeekError {
            Text(err)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(.red)
                .padding(16)
        } else if viewModel.displayedFilteredStatuses.isEmpty {
            Text(viewModel.weekOffset > 0
                ? "Nothing booked for this week yet."
                : "No projects found for this week.")
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
                .padding(16)
        } else {
            let weekStart = viewModel.weekSnapshots[viewModel.weekOffset]?.weekStart
            ForEach(viewModel.displayedFilteredStatuses) { project in
                if viewModel.weekOffset > 0 {
                    LookAheadRowView(project: project)
                } else {
                    ProjectRowView(
                        project: project,
                        effectiveLoggedHours: project.loggedHours,
                        visibleEntries: project.timeEntries,
                        isHarvestDown: viewModel.isHarvestDown,
                        isReadOnly: true,
                        weekStart: weekStart
                    )
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                weekNavControls

                Text(viewModel.displayedWeekLabel)
                    .font(YieldFonts.titleMedium)
                    .foregroundStyle(YieldColors.textPrimary)
                    .frame(height: 22)
                    // Newsreader's optical center sits a hair above the
                    // frame's geometric center. Nudge down so the text reads
                    // as aligned with the surrounding 22pt-tall buttons.
                    .offset(y: 1)

                // Return-to-current pill — only appears when viewing a
                // non-current week.
                if viewModel.isViewingOtherWeek {
                    thisWeekPill
                        .transition(.opacity)
                }

                if viewModel.isLoading || viewModel.isLoadingOtherWeek {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.85)
                        .frame(width: 18, height: 18)
                        .tint(YieldColors.textSecondary)
                        .offset(y: -2)
                        .transition(.opacity)
                }

                Spacer()

                if !viewModel.isViewingOtherWeek {
                    tabToggle
                }

                timerButton
            }
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoadingOtherWeek)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isViewingOtherWeek)
            .padding(16)

            // Weekday mini-bar: past/current weeks show tracked hours per
            // day; future weeks show scheduled (Forecast-booked) hours.
            if !viewModel.displayedDailyHours.isEmpty {
                weekDayBar
                    .padding(.leading, 18)
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    // MARK: - Week Day Bar

    private var weekDayBar: some View {
        // Live-ticking elapsed offset only applies to the current week.
        let isCurrent = !viewModel.isViewingOtherWeek
        let liveOffset = (isCurrent && viewModel.projectStatuses.contains(where: { $0.isTracking }))
            ? viewModel.elapsedOffset : 0
        let days = viewModel.displayedDailyHours
        let weekTotal = days.reduce(0) { $0 + $1.hours } + liveOffset

        return HStack(spacing: 0) {
            ForEach(days) { day in
                let displayHours = day.hours + (day.isToday ? liveOffset : 0)
                let isFiltered = isCurrent && viewModel.dayFilter == day.id

                VStack(alignment: .leading, spacing: 4) {
                    Text(day.dayLabel)
                        .font(YieldFonts.dmSans(9, weight: (day.isToday || isFiltered) ? .semibold : .medium))
                        .foregroundStyle((day.isToday || isFiltered) ? YieldColors.textPrimary : YieldColors.textSecondary)

                    HStack(spacing: 2) {
                        Text(formatDayHours(displayHours))
                            .font(YieldFonts.jetBrainsMono(10, weight: (day.isToday || isFiltered) ? .medium : .regular))
                            .foregroundStyle((day.isToday || isFiltered) ? YieldColors.textPrimary : YieldColors.textSecondary)

                        if day.isToday && isCurrent && viewModel.projectStatuses.contains(where: { $0.isTracking }) {
                            Image(systemName: "clock")
                                .font(.system(size: 7))
                                .foregroundStyle(YieldColors.greenAccent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isFiltered ? YieldColors.surfaceActive : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isCurrent else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleDayFilter(day.id)
                    }
                }
                .help(isCurrent
                    ? (isFiltered ? "Show all projects" : "Show only \(day.dayLabel)")
                    : "")
            }

            // Week total — doubles as "clear filter" when a day is filtered.
            VStack(alignment: .trailing, spacing: 4) {
                Text("Week")
                    .font(YieldFonts.dmSans(9, weight: .semibold))
                    .foregroundStyle(YieldColors.textSecondary)

                Text(formatDayHours(weekTotal))
                    .font(YieldFonts.jetBrainsMono(10, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isCurrent, viewModel.dayFilter != nil else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.clearDayFilter()
                }
            }
            .help(isCurrent && viewModel.dayFilter != nil ? "Show all projects" : "")
        }
    }

    private func formatDayHours(_ hours: Double) -> String { hours.formattedColon }

    /// Grouped back/forward chevron controls, styled to match the tab
    /// toggle — filled subtle bg, no outer border, thin panel-colored seam
    /// between the two buttons so they read as distinct halves.
    private var weekNavControls: some View {
        HStack(spacing: 0) {
            HeaderIconButton(systemImage: "chevron.left", help: "Previous week") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.goBackWeek()
                }
            }

            // 0.5pt = 1 physical pixel on Retina displays. 1pt renders as
            // 2px on @2x which read as a visible gap rather than a seam.
            Rectangle()
                .fill(YieldColors.background)
                .frame(width: 0.5, height: 22)

            HeaderIconButton(systemImage: "chevron.right", help: "Next week") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.advanceWeek()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
    }

    /// "This Week" pill — matches the nav chevrons' outlined, transparent-bg
    /// treatment so the row of header controls reads cohesively.
    private var thisWeekPill: some View {
        HeaderTextButton(title: "This Week") {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.returnToCurrentWeek()
            }
        }
    }

    private var tabToggle: some View {
        HStack(spacing: 0) {
            ForEach(TimeComparisonViewModel.ProjectTab.allCases, id: \.self) { tab in
                let isSelected = viewModel.selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    tabLabel(tab, isSelected: isSelected)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(isSelected ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
                }
                .buttonStyle(.plain)
                .help(tabHelp(tab))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
    }

    @ViewBuilder
    private func tabLabel(_ tab: TimeComparisonViewModel.ProjectTab, isSelected: Bool) -> some View {
        switch tab {
        case .recent, .forecasted:
            Text(tab == .recent ? "All" : "Booked")
                .font(isSelected
                    ? YieldFonts.dmSans(10, weight: .semibold)
                    : YieldFonts.dmSans(10, weight: .medium))
                .foregroundStyle(isSelected
                    ? YieldColors.textPrimary
                    : YieldColors.textSecondary)
        case .chart:
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected
                    ? YieldColors.textPrimary
                    : YieldColors.textSecondary)
        }
    }

    private func tabHelp(_ tab: TimeComparisonViewModel.ProjectTab) -> String {
        switch tab {
        case .recent: return "All projects (booked + tracked)"
        case .forecasted: return "Projects booked in Forecast"
        case .chart: return "Weekly time chart"
        }
    }

    private var timerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showNewTimerForm.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Timer")
                    .font(YieldFonts.labelButton)
            }
        }
        .buttonStyle(.greenOutlined)
        .disabledWhenHarvestDown(viewModel.isHarvestDown)
    }

    // MARK: - States

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(YieldColors.textSecondary)
            Text("Sign in to connect your Harvest and Forecast accounts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
            Button("Sign in with Harvest") {
                AppState.shared.oAuthService.startOAuthFlow()
            }
            .buttonStyle(.greenOutlined)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(YieldColors.yellowAccent)

            if !viewModel.serviceErrors.isEmpty {
                ForEach(viewModel.serviceErrors) { error in
                    ServiceErrorRow(
                        error: error,
                        snapshot: viewModel.statusSnapshot,
                        compact: false
                    )
                }
            } else {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(YieldColors.textSecondary)
                    .font(YieldFonts.dmSans(11))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Service Warning Banner

    private var serviceWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(YieldColors.yellowAccent)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.serviceErrors) { error in
                    ServiceErrorRow(
                        error: error,
                        snapshot: viewModel.statusSnapshot,
                        compact: true
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(YieldColors.yellowFaint)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                if let url = URL(string: "https://github.com/vigetlabs/yield-app/issues/new") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Report a bug")

            Spacer()

            Menu {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                Button("Settings...") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSettings = true
                    }
                }

                Divider()

                Button("Quit Yield") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            // Pull up by 1pt so this divider paints into the same pixel
            // row as the last project's bottom border (when a row sits
            // directly above) — otherwise the two adjacent 1pt borders
            // read as a 2pt double line. When the section above has no
            // border (empty state, chart tab) the divider still shows.
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
                .offset(y: -1)
        }
    }

}

// MARK: - Header button primitives (shared look)

/// Compact icon button inside the header's grouped nav control. Matches
/// the tab-toggle aesthetic: filled `surfaceDefault` bg by default,
/// `surfaceActive` on hover, no outer border.
private struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 24, height: 22)
                .background(isHovered ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

/// Compact text chip matching HeaderIconButton. Used for "This Week" so
/// it sits in the same visual family as the tabs and nav chevrons.
private struct HeaderTextButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(YieldFonts.labelButton)
                .foregroundStyle(YieldColors.textPrimary)
                .padding(.horizontal, 11)
                .frame(height: 22)
                .background(isHovered ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Opaque Panel Background

private struct OpaqueMenuBarPanel: NSViewRepresentable {
    /// Reports the panel window's current visibleFrame height — initially
    /// when the window is first attached, then again whenever the panel
    /// moves to a different display (`NSWindow.didChangeScreenNotification`)
    /// or the system's screen layout changes
    /// (`NSApplication.didChangeScreenParametersNotification`). Reading
    /// from the panel's *own* window — rather than `NSScreen.main` — is
    /// the right primitive for multi-display setups where the menu bar
    /// may sit on a screen that isn't main.
    var onVisibleHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            // Remove the visual effect (vibrancy) view if present
            if let contentView = window.contentView {
                for case let effectView as NSVisualEffectView in contentView.subviews {
                    effectView.state = .inactive
                    effectView.material = .windowBackground
                }
            }

            let coordinator = context.coordinator
            coordinator.window = window
            coordinator.report()

            let nc = NotificationCenter.default
            coordinator.screenObserver = nc.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { _ in coordinator.report() }
            coordinator.paramsObserver = nc.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in coordinator.report() }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the latest callback; underlying observers stay tied to
        // the same window/notification subscriptions.
        context.coordinator.onVisibleHeightChange = onVisibleHeightChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibleHeightChange: onVisibleHeightChange)
    }

    final class Coordinator {
        var onVisibleHeightChange: (CGFloat) -> Void
        weak var window: NSWindow?
        var screenObserver: NSObjectProtocol?
        var paramsObserver: NSObjectProtocol?

        init(onVisibleHeightChange: @escaping (CGFloat) -> Void) {
            self.onVisibleHeightChange = onVisibleHeightChange
        }

        func report() {
            guard let height = window?.screen?.visibleFrame.height else { return }
            onVisibleHeightChange(height)
        }

        deinit {
            let nc = NotificationCenter.default
            if let screenObserver { nc.removeObserver(screenObserver) }
            if let paramsObserver { nc.removeObserver(paramsObserver) }
        }
    }
}

// MARK: - Service Error Row

/// Renders a single service error with optional incident context from
/// harveststatus.com. Two layout modes:
/// - `compact: true` for the inline warning banner (10pt text, single
///   line per error).
/// - `compact: false` for the full-screen error placeholder (11pt,
///   center-aligned, multi-line ok).
///
/// When the status snapshot has loaded, the row shows one of:
/// 1. *Confirmed incident* — incident name + "Started X ago" + a button
///    to open Harvest's status page.
/// 2. *Status page reports no issues* — original message + a hint that
///    the failure is more likely a connection/auth issue locally.
/// While the snapshot is still nil (loading or status page unreachable),
/// it falls back to the original "Service — Message" line.
private struct ServiceErrorRow: View {
    let error: TimeComparisonViewModel.ServiceError
    let snapshot: HarvestStatusService.Snapshot?
    let compact: Bool

    private var incident: HarvestStatusService.Incident? {
        snapshot?.incident(affecting: error.service.rawValue)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 2) {
            if let incident {
                primaryText("\(error.service.rawValue) — \(incident.statusLabel): \(incident.name)")
                HStack(spacing: 6) {
                    secondaryText("Started \(Self.relativeFormatter.localizedString(for: incident.createdAt, relativeTo: Date()))")
                    if let url = incident.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 2) {
                                Text("Status page")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: compact ? 8 : 9))
                            }
                            .font(YieldFonts.dmSans(compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(YieldColors.greenAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if snapshot != nil {
                // Status page loaded, no matching incident — point user
                // at their connection / auth instead of waiting it out.
                primaryText("\(error.service.rawValue) — \(error.message)")
                secondaryText("Status page reports no issues — check your connection or sign in again.")
            } else {
                // Snapshot not yet loaded (or fetch failed silently).
                primaryText("\(error.service.rawValue) — \(error.message)")
            }
        }
    }

    @ViewBuilder
    private func primaryText(_ s: String) -> some View {
        Text(s)
            .font(YieldFonts.dmSans(compact ? 10 : 11))
            .foregroundStyle(YieldColors.textSecondary)
            .multilineTextAlignment(compact ? .leading : .center)
    }

    @ViewBuilder
    private func secondaryText(_ s: String) -> some View {
        Text(s)
            .font(YieldFonts.dmSans(compact ? 9 : 10))
            .foregroundStyle(YieldColors.textSecondary.opacity(0.7))
            .multilineTextAlignment(compact ? .leading : .center)
    }
}
