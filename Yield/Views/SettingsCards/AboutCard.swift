import SwiftUI

/// Version + check-for-updates + reveal-logs row.
struct AboutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader("About")

            // Version + Check for Updates inline so the action sits
            // alongside the info it acts on.
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 16)
                Text("Version")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textSecondary)
                Text(appVersion)
                    .font(YieldFonts.monoXS)
                    .foregroundStyle(YieldColors.textPrimary)
                Spacer()
                Button {
                    // Close the MenuBarExtra panel first — it runs at
                    // `.statusBar` window level, which sits above
                    // Sparkle's normal-level update window. Without
                    // closing it, the Sparkle dialog opens *behind*
                    // the popup and can look like nothing happened.
                    MenuBarStatusItem.closePanel()
                    NSApp.activate(ignoringOtherApps: true)
                    AppState.shared.updaterController?.checkForUpdates(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Check for Updates")
                            .font(YieldFonts.dmSans(10, weight: .semibold))
                    }
                }
                .buttonStyle(.greenOutlined)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Reveal logs in Finder — utility row for attaching
            // logs to a bug report.
            Button {
                LogStore.shared.revealInFinder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(YieldColors.textSecondary)
                        .frame(width: 16)
                    Text("Reveal Logs in Finder")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open ~/Library/Logs/Yield in Finder so you can attach logs to a bug report")
        }
        .yieldCard()
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version)"
    }
}
