import SwiftUI

/// Compact, read-only summary of Forecast time-off bookings for the current
/// week. Forecast lumps vacation/sick/holiday/PTO into a single "Time Off"
/// project with no type discriminator, so this row just shows the total
/// hours and the days affected — no progress bar, no timer controls.
struct TimeOffRowView: View {
    let block: TimeComparisonViewModel.TimeOffBlock

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Neutral status line (matches the structure of ProjectRowView
            // so the row visually aligns with the projects above it).
            Rectangle()
                .fill(Color.clear)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(YieldColors.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Off")
                        .font(YieldFonts.titleMedium)
                        .foregroundStyle(YieldColors.textPrimary)
                    if !block.dayLabels.isEmpty {
                        Text(block.dayLabels.joined(separator: ", "))
                            .font(YieldFonts.labelProject)
                            .foregroundStyle(YieldColors.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                Text(formatHours(block.totalHours))
                    .font(YieldFonts.monoSmall)
                    .foregroundStyle(YieldColors.textSecondary)
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

    /// Format with 8h = 1d, skipping any zero components so we read "3d"
    /// instead of "3d 0h 0m", "1d 4h" instead of "1d 4h 0m", etc.
    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int(round(hours * 60))
        let minutesPerDay = 8 * 60
        let d = totalMinutes / minutesPerDay
        let remainder = totalMinutes % minutesPerDay
        let h = remainder / 60
        let m = remainder % 60

        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
