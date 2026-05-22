import SwiftUI

/// Uppercase title (with optional info icon + tooltip) that anchors the
/// top of each Settings card. Extracted from `SettingsView` so each card
/// struct can render the header without reaching back into the parent.
struct SettingsCardSectionHeader: View {
    let title: String
    let info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(YieldFonts.dmSans(9, weight: .semibold))
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
}
