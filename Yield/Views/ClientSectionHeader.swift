import SwiftUI

/// Section label above a client's projects in the grouped list layout
/// (System theme). Quiet on purpose — it carries the client name that
/// the grouped row header no longer repeats, and nothing else.
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
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}
