import SwiftUI

/// Compact, read-only row for rendering a project in a future (look-ahead)
/// week. Shows only client / project name / booked hours — no progress bar,
/// no expandable drawer, no timer controls, no context menu. Matches the
/// layout proportions of `ProjectRowView` so the list reads as a continuous
/// extension of the main UI.
struct LookAheadRowView: View {
    let project: ProjectStatus

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left colored line, matching the current-week list: pink for
            // prospective (no Harvest link yet), amber when booked but the
            // user isn't a member of the Harvest project, otherwise the
            // white hairline used on normal booked rows.
            Rectangle()
                .fill(statusLineColor)
                .frame(width: 2)
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

                        // Booked here but not a member of the Harvest
                        // project — flag it in look-ahead weeks too so the
                        // gap is visible before the week arrives.
                        if project.harvestLinkState == .unassigned {
                            HarvestUnassignedIcon(projectName: project.displayName)
                        }
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
