import SwiftUI

struct WeekDayBarView: View {
    let viewModel: TimeComparisonViewModel

    var body: some View {
        // Live-ticking elapsed offset only applies to the current week.
        let isCurrent = !viewModel.isViewingOtherWeek
        // Hoisted: previously evaluated twice — once for `liveOffset`,
        // then again per-day inside the ForEach (so 8 contains-walks
        // across `projectStatuses` per render). The result is invariant
        // across the loop; capture once.
        let isAnyTracking = viewModel.projectStatuses.contains(where: { $0.isTracking })
        let liveOffset = (isCurrent && isAnyTracking) ? viewModel.elapsedOffset : 0
        let days = viewModel.displayedDailyHours
        let weekTotal = days.reduce(0) { $0 + $1.hours } + liveOffset
        // System: empty days read as a dash rather than "0:00" at the
        // same weight as real numbers, each day gets a small bar
        // against the daily target, and the labels are a point larger.
        let refreshed = ThemeStore.shared.theme.usesRefreshedLayout
        let dailyTarget = DateHelpers.dailyHours(fromWeekly: viewModel.weeklyHoursTarget)
        // The bars mean *logged* time against the target, always. In a
        // future week the numbers above them are scheduled hours, and
        // filling a bar from those made a booked day look like a
        // finished one — so there the tracks stay empty (kept, not
        // hidden, so the strip doesn't change height between weeks).
        let barsShowLogged = viewModel.weekOffset <= 0

        HStack(spacing: 0) {
            ForEach(days) { day in
                let displayHours = day.hours + (day.isToday ? liveOffset : 0)
                let isFiltered = isCurrent && viewModel.dayFilter == day.id

                let cell = VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Text(day.dayLabel)
                            .font(YieldFonts.label(refreshed ? 10 : 9, weight: (day.isToday || isFiltered) ? .semibold : .medium))
                            .foregroundStyle((day.isToday || isFiltered) ? YieldColors.textPrimary : YieldColors.textSecondary)
                        if day.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(YieldColors.textSecondary)
                                .help("This week has been submitted in Harvest")
                        }
                    }

                    HStack(spacing: 2) {
                        Text(refreshed && displayHours <= 0 ? "–" : formatDayHours(displayHours))
                            .font(YieldFonts.mono(10, weight: (day.isToday || isFiltered) ? .medium : .regular))
                            .foregroundStyle((day.isToday || isFiltered) ? YieldColors.textPrimary : YieldColors.textSecondary)

                        if day.isToday && isCurrent && isAnyTracking {
                            Image(systemName: "clock")
                                .font(.system(size: 7))
                                .foregroundStyle(YieldColors.greenAccent)
                        }
                    }

                    if refreshed {
                        DayTargetBar(
                            fraction: barsShowLogged ? displayHours / dailyTarget : 0,
                            color: (day.isToday && isCurrent && isAnyTracking)
                                ? YieldStatusColors.under
                                : (day.isToday ? YieldColors.controlFill : YieldColors.idleFill)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isFiltered ? (refreshed ? YieldColors.controlAccentSubtle : YieldColors.surfaceActive) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))

                // Past/future weeks render the cell as a static label
                // (no Button) so `.disabled` doesn't dim it. Only the
                // current week is interactive.
                if isCurrent {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleDayFilter(day.id)
                        }
                    } label: {
                        cell.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isFiltered ? "Show all projects" : "Show only \(day.dayLabel)")
                } else {
                    cell
                }
            }

            // Week total — doubles as "clear filter" when a day is filtered.
            let totalCell = VStack(alignment: .trailing, spacing: 4) {
                Text("Week")
                    .font(YieldFonts.label(refreshed ? 10 : 9, weight: .semibold))
                    .foregroundStyle(YieldColors.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatDayHours(weekTotal))
                        .font(YieldFonts.mono(10, weight: .medium))
                        .foregroundStyle(YieldColors.textPrimary)

                    if refreshed {
                        // Written the way the rows are: total / target.
                        Text("/ " + formatDayHours(viewModel.weeklyHoursTarget))
                            .font(YieldFonts.mono(10))
                            .foregroundStyle(YieldColors.textSecondary)
                    }
                }

                if refreshed {
                    // The week against the weekly target, so the total
                    // column lines up with the day bars beside it.
                    DayTargetBar(
                        fraction: barsShowLogged ? weekTotal / max(viewModel.weeklyHoursTarget, 1) : 0,
                        color: YieldColors.controlFill
                    )
                }
            }
            // System: the cell takes the width its "total / target"
            // needs and the seven days share the rest; an equal eighth
            // of the strip is too narrow for the pair.
            .fixedSize(horizontal: refreshed, vertical: false)
            .frame(maxWidth: refreshed ? nil : .infinity, alignment: .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            if isCurrent && viewModel.dayFilter != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.clearDayFilter()
                    }
                } label: {
                    totalCell.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show all projects")
            } else {
                totalCell
            }
        }
    }

    private func formatDayHours(_ hours: Double) -> String { hours.formattedColon }
}

/// A small bar showing hours against a target — the System day strip's
/// version of the menu bar's week-bars style. Fills and stops at the
/// target; the number above it carries any excess.
private struct DayTargetBar: View {
    let fraction: Double
    let color: Color

    private static let width: CGFloat = 30
    private static let height: CGFloat = 3

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(YieldColors.progressTrack)
            Capsule()
                .fill(color)
                .frame(width: Self.width * CGFloat(min(max(fraction, 0), 1)))
        }
        .frame(width: Self.width, height: Self.height)
    }
}
