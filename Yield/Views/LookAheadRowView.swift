import SwiftUI

/// Compact, read-only row for rendering a project in a future (look-ahead)
/// week. Shows only client / project name / booked hours — no progress bar,
/// no expandable drawer, no timer controls, no context menu. Matches the
/// layout proportions of `ProjectRowView` so the list reads as a continuous
/// extension of the main UI.
struct LookAheadRowView: View {
    let project: ProjectStatus
    /// System: whether the bottom rule is inset to the text margins
    /// (every row of a client's group but the last).
    var insetRule: Bool = false

    var body: some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            groupedRow
        } else {
            editorialRow
        }
    }

    /// System: the current week's row with the logging taken out. The
    /// client is the band above the group, so the row is the project
    /// name (its code in secondary ink) over a line saying what the
    /// booking is, with the booked hours as the figure. No edge line:
    /// in this theme that marks the running project, and nothing runs
    /// in a week that hasn't started.
    private var groupedRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Color.clear.frame(width: 3)

            HStack {
                if let notes = project.forecastNotes {
                    ForecastNotesIcon(notes: notes)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        GroupedRowLayout.title(project)
                            .font(YieldFonts.titleMedium)
                            .lineLimit(1)

                        HarvestLinkIcon(
                            state: project.harvestLinkState,
                            projectName: project.displayName
                        )
                    }

                    Text(bookingNote.text)
                        .font(YieldFonts.rowSubtitle)
                        .foregroundStyle(bookingNote.color)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(RowFormat.colon(project.bookedHours))
                    .font(YieldFonts.figureLarge)
                    .foregroundStyle(YieldColors.textPrimary)
                    .fixedSize()
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
        }
        .frame(height: YieldDimensions.projectRowDefaultHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
                .padding(.leading, insetRule ? 19 : 0)
                .padding(.trailing, insetRule ? 16 : 0)
        }
    }

    /// The line under the name: what's wrong with the booking if
    /// Harvest can't take time for it, otherwise simply that it is one.
    private var bookingNote: (text: String, color: Color) {
        switch project.harvestLinkState {
        case .prospective: return ("Not linked to a Harvest project", YieldStatusColors.prospective)
        case .unassigned:  return ("Not a member of the Harvest project", YieldStatusColors.warning)
        case .linked:      return ("Booked", YieldColors.textSecondary)
        }
    }

    private var editorialRow: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left colored line, matching the current-week list: pink for
            // prospective (no Harvest link yet), amber when booked but the
            // user isn't a member of the Harvest project, otherwise the
            // white hairline used on normal booked rows.
            Rectangle()
                .fill(statusLineColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            HStack {
                if let notes = project.forecastNotes {
                    ForecastNotesIcon(notes: notes)
                }

                // Client + project name
                VStack(alignment: .leading, spacing: 6) {
                    if let clientName = project.clientName {
                        Text(clientName.uppercased())
                            .font(YieldFonts.labelProject)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        Text(project.displayName)
                            .font(YieldFonts.titleMedium)
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)

                        // Booked here but the Harvest side can't take
                        // time — flag it in look-ahead weeks too so the
                        // gap is visible before the week arrives.
                        HarvestLinkIcon(
                            state: project.harvestLinkState,
                            projectName: project.displayName
                        )
                    }
                }

                Spacer(minLength: 8)

                // Booked hours only — no logged comparison for future weeks
                Text(formatBookedHours(project.bookedHours))
                    .font(YieldFonts.monoSmall)
                    .foregroundStyle(YieldColors.textSecondary)
                    .fixedSize()
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
        }
        .frame(height: YieldDimensions.projectRowDefaultHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    /// Leading status-line color, mirroring `ProjectRowView`: prospective
    /// (no Harvest link) is pink, booked-but-unassigned is amber, a normal
    /// linked booking is the white hairline.
    private var statusLineColor: Color {
        switch project.harvestLinkState {
        case .prospective: return YieldStatusColors.prospective
        case .unassigned:  return YieldStatusColors.warning
        case .linked:      return YieldColors.onBackground.opacity(0.7)
        }
    }

    private func formatBookedHours(_ hours: Double) -> String {
        let (h, m) = hours.roundedHM
        if m == 0 { return "\(h)h" }
        return "\(h)h \(String(format: "%02d", m))m"
    }
}
