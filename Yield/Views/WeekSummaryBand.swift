import SwiftUI

/// Week total at the foot of the grouped list (System theme): booked
/// projects' logged hours over their booked total, as one full-width
/// bar, with unbooked time called out separately so it doesn't inflate
/// the ratio. Hairline above, no fill — a band, not a card.
struct WeekSummaryBand: View {
    /// Logged hours on booked projects only.
    let logged: Double
    let booked: Double
    /// Logged hours on projects with no booking.
    let unbooked: Double

    private var ratio: Double { booked > 0 ? logged / booked : 0 }
    private var isOver: Bool { ratio > 1 }

    var body: some View {
        if booked > 0 {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("This week")
                        .font(YieldFonts.sectionHeader)
                        .foregroundStyle(YieldColors.textSecondary)

                    Spacer()

                    if unbooked > 0 {
                        Text("+ \(unbooked.formattedHoursMinutes) unbooked")
                            .font(YieldFonts.rowSubtitle)
                            .foregroundStyle(YieldColors.textSecondary)
                            .padding(.trailing, 8)
                    }

                    Text(logged.formattedHoursMinutes)
                        .font(YieldFonts.figureLarge)
                        .foregroundStyle(YieldColors.textPrimary)
                    Text("/ " + bookedLabel)
                        .font(YieldFonts.figureDenominator)
                        .foregroundStyle(YieldColors.textSecondary)
                }

                // Same color rules as ProgressBarView; full width, and
                // over-budget shows the booked share with the overage
                // in the remaining track, like the row bars do.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isOver ? YieldStatusColors.over.opacity(0.4) : YieldColors.progressTrack)
                        Capsule()
                            .fill(isOver ? YieldStatusColors.over : YieldStatusColors.under)
                            .frame(width: geo.size.width * (isOver ? max(1 / min(ratio, 5), 0.2) : min(ratio, 1)))
                    }
                }
                .frame(height: YieldDimensions.progressBarHeight)
            }
            .padding(.leading, 3 + 16)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(YieldColors.border).frame(height: 1)
            }
        }
    }

    private var bookedLabel: String {
        booked == booked.rounded() ? "\(Int(booked))h" : booked.formattedHoursMinutes
    }
}
