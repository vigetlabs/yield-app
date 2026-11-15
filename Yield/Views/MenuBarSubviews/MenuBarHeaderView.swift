import SwiftUI

struct MenuBarHeaderView: View {
    let viewModel: TimeComparisonViewModel
    let onToggleNewTimerForm: () -> Void
    /// Opens the new-timer form directly on the calendar event picker —
    /// the one-click "log a meeting" shortcut next to + Timer.
    var onOpenCalendarTimerForm: (() -> Void)? = nil
    /// The list filter to return to when the chart toggle is switched
    /// off (System theme, where the chart is a separate control).
    @State private var lastListTab: TimeComparisonViewModel.ProjectTab = .recent

    var body: some View {
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
                    if ThemeStore.shared.theme.usesRefreshedLayout {
                        // System: "All / Booked" filters the list; the
                        // chart is a different view of the week. One
                        // segmented control for both made a filter and
                        // a view switch look like three of a kind.
                        listFilterToggle
                        chartToggle
                    } else {
                        tabToggle
                    }
                }

                // Only rendered when Google Calendar is connected — a
                // shortcut that can't work is header noise; the in-form
                // Settings pointer covers discovery.
                if AppState.shared.googleAuthService.isAuthenticated {
                    calendarTimerButton
                }

                timerButton
            }
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoadingOtherWeek)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isViewingOtherWeek)
            // System: one left margin for the whole panel — the 19pt
            // the timer bar, client names and project names sit on.
            .padding(.leading, Self.leadingInset)
            .padding(.trailing, 16)
            .padding(.vertical, 16)

            // Weekday mini-bar: past/current weeks show tracked hours per
            // day; future weeks show scheduled (Forecast-booked) hours.
            if !viewModel.displayedDailyHours.isEmpty {
                // Each day cell pads its text by 6pt, so System's strip
                // starts 6pt short of the margins to land the text on
                // them: "Mon" on the 19pt edge, the week total on the
                // 16pt one.
                WeekDayBarView(viewModel: viewModel)
                    .padding(.leading, ThemeStore.shared.theme.usesRefreshedLayout ? Self.leadingInset - 6 : 18)
                    .padding(.trailing, ThemeStore.shared.theme.usesRefreshedLayout ? 10 : 16)
                    .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    /// Left margin of the header's controls.
    static var leadingInset: CGFloat {
        ThemeStore.shared.theme.usesRefreshedLayout ? 16 + 3 : 16
    }

    /// Back/forward week chevrons. Editorial: a grouped pair styled to
    /// match the tab toggle — filled subtle bg, no outer border, thin
    /// panel-colored seam between the two buttons so they read as
    /// distinct halves. System: two round buttons, like every other
    /// icon button in the theme.
    @ViewBuilder
    private var weekNavControls: some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            HStack(spacing: 6) {
                HeaderIconButton(systemImage: "chevron.left", help: "Previous week") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.goBackWeek()
                    }
                }
                .clipShape(Circle())

                HeaderIconButton(systemImage: "chevron.right", help: "Next week") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.advanceWeek()
                    }
                }
                .clipShape(Circle())
            }
        } else {
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
                    .frame(width: 0.5, height: YieldDimensions.buttonHeight)

                HeaderIconButton(systemImage: "chevron.right", help: "Next week") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.advanceWeek()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
        }
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
                    // `withAnimation` (rather than relying on a
                    // parent `.animation(value:)` modifier) creates
                    // a broad animation transaction that catches the
                    // MenuBarExtra panel's height reflow too — the
                    // value-keyed modifier alone doesn't propagate
                    // through to AppKit's NSPanel resize, so the
                    // panel snaps to the new height while the rows
                    // animate. Duration matches the
                    // `.animation(value: displayedFilteredStatuses)`
                    // modifier below so panel + rows stay locked.
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.selectTab(tab)
                    }
                } label: {
                    tabLabel(tab, isSelected: isSelected)
                        .padding(.horizontal, 9)
                        .frame(height: YieldDimensions.buttonHeight)
                        .background(isSelected ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
                }
                .buttonStyle(.plain)
                .help(tabHelp(tab))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
    }

    /// System: the two list filters on their own, as the kit's
    /// segmented control — a grey trough with the selected segment
    /// lifted out of it in white. Neither is selected while the chart
    /// is showing; picking one leaves the chart.
    private var listFilterToggle: some View {
        HStack(spacing: 2) {
            ForEach([TimeComparisonViewModel.ProjectTab.recent, .forecasted], id: \.self) { tab in
                let isSelected = viewModel.selectedTab == tab
                Button {
                    lastListTab = tab
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.selectTab(tab)
                    }
                } label: {
                    Text(tab == .recent ? "All" : "Booked")
                        .font(YieldFonts.label(12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? YieldColors.textPrimary : YieldColors.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: YieldDimensions.buttonHeight - 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: YieldRadius.pill - 1)
                                    .fill(YieldColors.raised)
                                    .kitShadow(YieldColors.shadow, dp: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tabHelp(tab))
            }
        }
        .padding(3)
        .background(YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill + 2))
    }

    /// System: the chart as its own toggle. Pressing it again returns
    /// to whichever list filter was showing before.
    private var chartToggle: some View {
        let isChart = viewModel.selectedTab == .chart
        return HeaderIconButton(
            systemImage: "chart.xyaxis.line",
            help: isChart ? "Back to the project list" : "Weekly time chart",
            isSelected: isChart
        ) {
            if !isChart, viewModel.selectedTab != .chart {
                lastListTab = viewModel.selectedTab
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                viewModel.selectTab(isChart ? lastListTab : .chart)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.iconButton))
    }

    @ViewBuilder
    private func tabLabel(_ tab: TimeComparisonViewModel.ProjectTab, isSelected: Bool) -> some View {
        switch tab {
        case .recent, .forecasted:
            Text(tab == .recent ? "All" : "Booked")
                .font(isSelected
                    ? YieldFonts.label(10, weight: .semibold)
                    : YieldFonts.label(10, weight: .medium))
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

    /// Calendar shortcut beside + Timer: jumps straight into the
    /// new-timer form with the calendar event picker already open, so
    /// logging a meeting is one click instead of form → calendar icon.
    /// Callers only render this when Google Calendar is connected.
    private var calendarTimerButton: some View {
        HeaderIconButton(
            systemImage: "calendar",
            help: "New timer from a calendar event"
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                onOpenCalendarTimerForm?()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.iconButton))
        .disabledWhenHarvestDown(viewModel.isHarvestDown)
    }

    private var timerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                onToggleNewTimerForm()
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
}

// MARK: - Header button primitives (shared look)

/// Compact icon button inside the header's grouped nav control. Matches
/// the tab-toggle aesthetic: filled `surfaceDefault` bg by default,
/// `surfaceActive` on hover, no outer border.
struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    /// Draws the button in its "on" state — for toggles such as the
    /// System header's chart switch. Off by default.
    var isSelected: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    private var kit: Bool { ThemeStore.shared.theme.usesRefreshedLayout }

    /// System: the kit's shaded icon button — primary glyph on a grey
    /// tint — and its contained one when switched on.
    private var foreground: Color {
        if kit { return isSelected ? YieldColors.onControlFill : YieldColors.controlAccent }
        return isSelected ? YieldColors.textPrimary : YieldColors.textSecondary
    }

    private var fill: Color {
        if kit, isSelected { return isHovered ? YieldColors.controlFillHover : YieldColors.controlFill }
        return (isHovered || isSelected) ? YieldColors.surfaceActive : YieldColors.surfaceDefault
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: kit ? 12 : 10, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: YieldDimensions.headerIconWidth, height: YieldDimensions.buttonHeight)
                .background(fill)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

/// System theme: the title bar of a page that replaces the panel's
/// main view — Settings, the calendar event picker. The main header
/// in miniature: a round tinted back chevron, then the title beside
/// it on the left, where the week title sits. Editorial's pages keep
/// their own centered-title bars.
struct SubpageTitleBar: View {
    let title: String
    let onBack: () -> Void
    /// Whether the bar rules itself off underneath. Off when what
    /// follows draws that rule itself (Settings' first section band).
    var ruled: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            HeaderIconButton(systemImage: "chevron.left", help: "Back", action: onBack)
                .clipShape(Circle())
            Text(title)
                .font(YieldFonts.titleMedium)
                .foregroundStyle(YieldColors.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, MenuBarHeaderView.leadingInset)
        .padding(.trailing, 16)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            if ruled {
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)
            }
        }
    }
}

/// Compact text chip matching HeaderIconButton. Used for "This Week" so
/// it sits in the same visual family as the tabs and nav chevrons.
struct HeaderTextButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(YieldFonts.labelButton)
                .foregroundStyle(ThemeStore.shared.theme.usesRefreshedLayout ? YieldColors.controlAccent : YieldColors.textPrimary)
                .padding(.horizontal, YieldDimensions.buttonHorizontalPadding)
                .frame(height: YieldDimensions.buttonHeight)
                .background(isHovered ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}
