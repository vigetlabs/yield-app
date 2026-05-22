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
    /// The active project's tracked hours vs. its weekly booking. Falls
    /// back to the week-wide total / weekly budget when no timer is
    /// running.
    case projectTime
    /// The current timer's hours vs. the running total of all logged
    /// time today. Falls back to today's total / 8h when no timer is
    /// running.
    case dayTime
    /// The current timer's hours vs. the remaining budget on its
    /// project. Goes negative (with a leading minus) when the project
    /// is over budget — the gauge icon already signals over-state
    /// visually, so the negative number is the precise amount over.
    /// Mirrors `projectTime` fallbacks for unbooked / no-timer states.
    case currentRemaining
    /// Just the current running timer's hours, in compact form (no
    /// denominator). A paused timer keeps showing its frozen value;
    /// once all timers are stopped, falls back to today's running total.
    case currentTimer

    var label: String {
        switch self {
        case .projectTime:      return "Project tracked / booked"
        case .dayTime:          return "Current / day total"
        case .currentRemaining: return "Current / remaining"
        case .currentTimer:     return "Current timer"
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
                MenuBarFooterView(viewModel: viewModel) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSettings = true
                    }
                }
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
                MenuBarHeaderView(viewModel: viewModel) {
                    showNewTimerForm.toggle()
                }

                if !viewModel.serviceErrors.isEmpty {
                    ServiceWarningBanner(viewModel: viewModel)
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
                // Eager `VStack` rather than `LazyVStack` so the
                // stack's intrinsic height animates *with* the row
                // transitions instead of jumping straight to the
                // post-diff total. With LazyVStack the panel popped
                // to the new height immediately while the rows were
                // still mid-fade — looked like two separate animations
                // running at different speeds. The project list is
                // bounded (typically <30 rows) so eager construction
                // costs nothing meaningful here.
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
        // Rows with stable IDs re-render in place; new/removed rows
        // fade as their slot collapses/expands — each row clips its
        // content to its own frame so the collapsing slot doesn't
        // let text bleed onto neighboring rows during the transition.
        // Tab changes are handled by `withAnimation` on the tab
        // button (which also covers the panel's NSPanel resize),
        // not via a value-keyed `.animation(value: selectedTab)`.
        .animation(.easeInOut(duration: 0.22), value: viewModel.weekOffset)
        .animation(.easeInOut(duration: 0.22), value: viewModel.displayedFilteredStatuses.map(\.id))
    }

    /// The variable-height project / chart / empty-state region inside
    /// the scrollable container.
    @ViewBuilder
    private var listSection: some View {
        // `filteredStatuses` re-runs the tab/day filters on every
        // access, so cache once per body pass.
        let statuses = viewModel.filteredStatuses
        if viewModel.isViewingOtherWeek {
            otherWeekList
        } else if viewModel.selectedTab == .chart {
            ProjectChartView(viewModel: viewModel)
        } else if statuses.isEmpty {
            Text(viewModel.dayFilter != nil
                ? "No projects found for this day."
                : "No projects found for this week.")
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
                .padding(16)
        } else {
            ForEach(statuses) { project in
                ProjectRowView(
                    project: project,
                    effectiveLoggedHours: viewModel.effectiveLoggedHours(for: project),
                    visibleEntries: viewModel.visibleEntries(for: project),
                    dayFilteredHours: viewModel.dayFilteredHours(for: project),
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
                    },
                    onQuickStartFavorite: { projectId, taskId in
                        // Mark the favorite used before the await so the
                        // next auto-select picks the right one — same
                        // ordering NewTimerFormView uses.
                        FavoritesStore.shared.markUsed(projectId: projectId, taskId: taskId)
                        Task { await viewModel.startNewTimer(projectId: projectId, taskId: taskId) }
                    },
                    onResumeToday: { entryId in
                        Task { await viewModel.toggleEntryTimer(entryId: entryId, isRunning: false) }
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
        // Defer until the view is in a window — `makeNSView` returns
        // before the view is attached, so `view.window` is nil here.
        Task { @MainActor in
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
struct ServiceErrorRow: View {
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
