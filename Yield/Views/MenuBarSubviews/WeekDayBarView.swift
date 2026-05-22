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

        HStack(spacing: 0) {
            ForEach(days) { day in
                let displayHours = day.hours + (day.isToday ? liveOffset : 0)
                let isFiltered = isCurrent && viewModel.dayFilter == day.id

                let cell = VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Text(day.dayLabel)
                            .font(YieldFonts.dmSans(9, weight: (day.isToday || isFiltered) ? .semibold : .medium))
                            .foregroundStyle((day.isToday || isFiltered) ? YieldColors.textPrimary : YieldColors.textSecondary)
                        if day.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(YieldColors.textSecondary)
                                .help("This week has been submitted in Harvest")
                        }
                    }

                    HStack(spacing: 2) {
                        Text(formatDayHours(displayHours))
                            .font(YieldFonts.jetBrainsMono(10, weight: (day.isToday || isFiltered) ? .medium : .regular))
                            .foregroundStyle((day.isToday || isFiltered) ? YieldColors.textPrimary : YieldColors.textSecondary)

                        if day.isToday && isCurrent && isAnyTracking {
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
                    .font(YieldFonts.dmSans(9, weight: .semibold))
                    .foregroundStyle(YieldColors.textSecondary)

                Text(formatDayHours(weekTotal))
                    .font(YieldFonts.jetBrainsMono(10, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
