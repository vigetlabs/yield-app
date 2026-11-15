import SwiftUI

/// The Material-X kit's badge (System theme): a 16pt-high, 4pt-cornered
/// tint with an uppercase, widely tracked label in the darker step of
/// the same hue. Used for the row's "Unbooked" tag and the running
/// entry's "Now".
struct YieldBadge: View {
    let text: String
    /// The hue. The fill is this at low strength — the kit's "Light / …"
    /// styles — and the label is this at full strength.
    var tint: Color = YieldColors.textSecondary
    /// Neutral badges sit on the kit's grey tint rather than a wash of
    /// their own label colour.
    var neutral: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(YieldFonts.label(9, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(neutral ? YieldColors.surfaceActive : tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
