import SwiftUI

struct MenuBarHeaderView: View {
    let viewModel: TimeComparisonViewModel
    let onToggleNewTimerForm: () -> Void

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
                WeekDayBarView(viewModel: viewModel)
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
struct HeaderTextButton: View {
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
