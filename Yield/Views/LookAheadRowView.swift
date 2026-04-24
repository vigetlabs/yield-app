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
            // Left colored line — same white hairline used on booked rows so
            // the visual rhythm matches the current-week list.
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            HStack {
                // Client + project name
                VStack(alignment: .leading, spacing: 6) {
                    if let clientName = project.clientName {
                        Text(clientName.uppercased())
                            .font(YieldFonts.labelProject)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                    }
                    Text(project.projectName)
                        .font(YieldFonts.titleMedium)
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Booked hours only — no logged comparison for future weeks
                Text(formatBookedHours(project.bookedHours))
                    .font(YieldFonts.monoSmall)
                    .foregroundStyle(YieldColors.textSecondary)
                    .fixedSize()

                // Forecast notes icon — hover for the full text.
                if let notes = project.forecastNotes {
                    Image(systemName: "text.page")
                        .font(.system(size: 12))
                        .foregroundStyle(YieldColors.textSecondary)
                        .help(notes)
                        .padding(.leading, 8)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
        }
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private func formatBookedHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return "\(h)h \(String(format: "%02d", m))m"
    }
}
