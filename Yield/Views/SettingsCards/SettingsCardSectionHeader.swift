import SwiftUI

/// Title (with optional info icon + tooltip) that anchors the top of
/// each Settings section. Extracted from `SettingsView` so each card
/// struct can render the header without reaching back into the parent.
struct SettingsCardSectionHeader: View {
    let title: String
    let info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        if SettingsStyle.refreshed {
            band
        } else {
            card
        }
    }

    /// Editorial: small capitals at the top of the section's card.
    private var card: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(YieldFonts.label(9, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .tracking(0.5)
            if let info {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .help(info)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// System: the band a client gets in the project list — the name
    /// in quiet secondary ink on a tinted strip across the panel. It
    /// rules itself off above and below: a section's last row draws no
    /// rule of its own, and the title bar above the first band leaves
    /// its rule to this one.
    private var band: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(YieldFonts.sectionHeader)
                .foregroundStyle(YieldColors.textSecondary)
            if let info {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .help(info)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, SettingsStyle.leading)
        .padding(.trailing, SettingsStyle.trailing)
        .padding(.vertical, 8)
        .background(YieldColors.sectionBand)
        .overlay(alignment: .top) {
            Rectangle().fill(YieldColors.border).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(YieldColors.border).frame(height: 1)
        }
    }
}
