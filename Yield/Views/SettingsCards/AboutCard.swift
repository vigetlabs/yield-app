import ServiceManagement
import SwiftUI

/// The app itself: launch at login, version + check-for-updates, and
/// reveal-logs.
struct AboutCard: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader("General")

            settingsToggleRow(
                icon: "sunrise",
                label: "Launch at Login",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            SettingsRowDivider()

            // Version + Check for Updates inline so the action sits
            // alongside the info it acts on.
            HStack {
                Image(systemName: "info.circle")
                    .settingsRowIcon()
                Text("Version")
                    .font(YieldFonts.settingsLabel())
                    .foregroundStyle(YieldColors.textSecondary)
                Text(appVersion)
                    .font(YieldFonts.settingsValue)
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
                            .font(YieldFonts.settingsButton(10))
                    }
                }
                .buttonStyle(.greenOutlined)
            }
            .settingsRowPadding()

            SettingsRowDivider()

            // Reveal logs in Finder — utility row for attaching
            // logs to a bug report.
            Button {
                LogStore.shared.revealInFinder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .settingsRowIcon()
                    Text("Reveal Logs in Finder")
                        .font(YieldFonts.settingsLabel())
                        .foregroundStyle(YieldColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
                }
                .settingsRowPadding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open ~/Library/Logs/Yield in Finder so you can attach logs to a bug report")
        }
        .settingsCard()
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version)"
    }
}
