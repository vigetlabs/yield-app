import SwiftUI

/// Section header above a client's projects in the grouped list layout
/// (System theme): the client name, in full-strength ink, on a tinted
/// band that runs the width of the panel.
///
/// As small grey capitals it was the quietest text in the list and
/// got lost above the bold project names it was meant to group. The
/// band gives it its own row, so the list reads as clients first and
/// projects within them.
///
/// The band draws only its bottom rule: above it is always a rule
/// already — the last row of the group before it, or the header or
/// timer bar at the top of the list. Its tint is lighter than an open
/// project's, so an open project directly under it still reads as its
/// own block.
///
/// Leading inset matches the row content's left edge: the 3pt status
/// stripe plus the 16pt content inset.
struct ClientSectionHeader: View {
    let client: String

    var body: some View {
        Text(client)
            .font(YieldFonts.sectionHeader)
            .foregroundStyle(YieldColors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 3 + 16)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .background(YieldColors.sectionBand)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)
            }
    }
}
