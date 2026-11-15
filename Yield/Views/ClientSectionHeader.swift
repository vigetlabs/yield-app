import SwiftUI

/// Section header above a client's projects in the grouped list layout
/// (System theme): the client name on a tinted band that runs the
/// width of the panel.
///
/// The band is what makes the list scannable by client; the name on it
/// is deliberately quiet — secondary ink at medium weight — and the
/// band a little taller than its text needs, so the header separates
/// groups without competing with the bold project names beneath it.
/// (Bold, full-strength names on a tight band scanned well but left
/// the list with no breathing room.)
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
            .foregroundStyle(YieldColors.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 3 + 16)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .background(YieldColors.sectionBand)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)
            }
    }
}
