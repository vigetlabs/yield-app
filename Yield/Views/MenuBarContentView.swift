import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

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

struct MenuBarContentView: View {
    let viewModel: TimeComparisonViewModel
    @State private var showNewTimerForm = false
    @State private var editingEntry: TimeEntryInfo? = nil
    @State private var preselectedProjectId: Int? = nil
    @State private var newTimerTargetDate: Date? = nil
    @State private var showSettings = false
    @State private var hoveredDayId: String? = nil

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
                } else if showNewTimerForm || editingEntry != nil {
                    NewTimerFormView(
                        viewModel: viewModel,
                        editingEntry: editingEntry,
                        preselectedProjectId: preselectedProjectId,
                        targetDate: newTimerTargetDate
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
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

            if viewModel.idleAlertState == nil && !showSettings && !showNewTimerForm && editingEntry == nil {
                footerView
                    .transition(.opacity)
            }
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
        .background(OpaqueMenuBarPanel())
    }

    // MARK: - Content

    private var contentView: some View {
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

            if viewModel.isViewingOtherWeek {
                otherWeekList
            } else if viewModel.selectedTab == .chart {
                ProjectChartView(viewModel: viewModel)
            } else if viewModel.filteredStatuses.isEmpty {
                Text("No projects found for this week.")
                    .foregroundStyle(YieldColors.textSecondary)
                    .font(YieldFonts.dmSans(11))
                    .padding(16)
            } else {
                ForEach(viewModel.filteredStatuses) { project in
                    ProjectRowView(
                        project: project,
                        effectiveLoggedHours: viewModel.effectiveLoggedHours(for: project),
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
    }

    /// Timer banner area — extracted so the contentView stays readable
    /// and we can skip rendering it entirely for non-current weeks.
    @ViewBuilder
    private var timerBannerSlot: some View {
        VStack(spacing: 0) {
            if viewModel.isTimerBannerVisible {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                YieldColors.greenAccent.opacity(0.15),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: UnitPoint(x: 0.7, y: 0.5)
                        )
                    )
                    .frame(height: 16)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(YieldColors.border)
                            .frame(height: 1)
                    }
            }
        }
        .frame(maxHeight: viewModel.selectedTab != .chart ? .infinity : 0, alignment: .top)
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
            let weekStart = DateHelpers.weekBounds(offset: viewModel.weekOffset).start
            ForEach(viewModel.displayedFilteredStatuses) { project in
                if viewModel.weekOffset > 0 {
                    LookAheadRowView(project: project)
                } else {
                    ProjectRowView(
                        project: project,
                        effectiveLoggedHours: project.loggedHours,
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

                // Tab toggle only makes sense on the current week; past/
                // future weeks render a single project list.
                if !viewModel.isViewingOtherWeek {
                    tabToggle
                }

                timerButton
            }
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoadingOtherWeek)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isViewingOtherWeek)
            .padding(16)

            // Weekday mini-bar: shown for current and past weeks (past
            // weeks display that week's logged totals, read-only). Hidden
            // for future weeks — nothing logged yet.
            if !viewModel.displayedDailyHours.isEmpty && viewModel.weekOffset <= 0 {
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
                let isHovered = hoveredDayId == day.id && isCurrent

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Text(day.dayLabel)
                            .font(YieldFonts.dmSans(9, weight: day.isToday ? .semibold : .medium))
                            .foregroundStyle(day.isToday ? YieldColors.textPrimary : YieldColors.textSecondary)

                        if isHovered {
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(YieldColors.textPrimary)
                        }
                    }

                    HStack(spacing: 2) {
                        Text(formatDayHours(displayHours))
                            .font(YieldFonts.jetBrainsMono(10, weight: day.isToday ? .medium : .regular))
                            .foregroundStyle(day.isToday ? YieldColors.textPrimary : YieldColors.textSecondary)

                        if day.isToday && isCurrent && viewModel.projectStatuses.contains(where: { $0.isTracking }) {
                            Image(systemName: "clock")
                                .font(.system(size: 7))
                                .foregroundStyle(YieldColors.greenAccent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard isCurrent else { return }
                    hoveredDayId = hovering ? day.id : (hoveredDayId == day.id ? nil : hoveredDayId)
                }
                .onTapGesture {
                    // Adding time to a non-current week is out of scope for
                    // the look-back view — past weeks are read-only.
                    guard isCurrent else { return }
                    openNewTimerForm(for: day)
                }
                .help(isCurrent ? "Add Time" : "")
            }

            // Week total
            VStack(alignment: .trailing, spacing: 4) {
                Text("Week")
                    .font(YieldFonts.dmSans(9, weight: .semibold))
                    .foregroundStyle(YieldColors.textSecondary)

                Text(formatDayHours(weekTotal))
                    .font(YieldFonts.jetBrainsMono(10, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func formatDayHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func openNewTimerForm(for day: TimeComparisonViewModel.DayHours) {
        guard !viewModel.isHarvestDown else { return }
        let date = DateHelpers.dateFormatter.date(from: day.id) ?? Date()
        withAnimation(.easeInOut(duration: 0.2)) {
            newTimerTargetDate = date
            showNewTimerForm = true
        }
    }

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
            Text(tab == .recent ? "Recent" : "Booked")
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
        case .recent: return "Projects with recent time entries"
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
        .disabled(viewModel.isHarvestDown)
        .opacity(viewModel.isHarvestDown ? 0.4 : 1.0)
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
                    Text("\(error.service.rawValue) — \(error.message)")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(YieldColors.textSecondary)
                        .font(YieldFonts.dmSans(11))
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

            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.serviceErrors) { error in
                    Text("\(error.service.rawValue) — \(error.message)")
                        .font(YieldFonts.dmSans(10))
                        .foregroundStyle(YieldColors.textSecondary)
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
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
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
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
