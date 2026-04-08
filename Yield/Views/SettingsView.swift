import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let oAuthService: OAuthService
    let onDismiss: () -> Void

    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("idleDetectionEnabled") private var idleDetectionEnabled = true
    @AppStorage("idleMinutes") private var idleMinutes = 10
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(YieldFonts.dmSans(11, weight: .medium))
                    }
                    .foregroundStyle(YieldColors.greenAccent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(YieldFonts.dmSans(13, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)

                Spacer()

                // Invisible spacer to center title
                Text("Back")
                    .font(YieldFonts.dmSans(11, weight: .medium))
                    .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)
            }

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    accountSection
                    settingsDivider
                    preferencesSection
                    settingsDivider
                    aboutSection
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Account")

            if oAuthService.isAuthenticated {
                if let name = oAuthService.userName {
                    settingsRow(label: "Signed in as", value: name)
                }
                if let harvestId = oAuthService.harvestAccountId {
                    settingsRow(label: "Harvest Account", value: harvestId)
                }
                if let forecastId = oAuthService.forecastAccountId {
                    settingsRow(label: "Forecast Account", value: forecastId)
                }

                Button {
                    oAuthService.signOut()
                    Task {
                        await AppState.shared.viewModel.refresh()
                    }
                } label: {
                    Text("Sign Out")
                        .font(YieldFonts.dmSans(11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in with your Harvest account to get started.")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textSecondary)

                    Button {
                        oAuthService.startOAuthFlow()
                    } label: {
                        HStack(spacing: 6) {
                            if oAuthService.isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Sign in with Harvest")
                                .font(YieldFonts.dmSans(11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.greenOutlined)
                    .disabled(oAuthService.isAuthenticating)

                    if let error = oAuthService.authError {
                        Text(error)
                            .font(YieldFonts.dmSans(10))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Preferences")

            // Launch at login
            settingsToggleRow(label: "Launch at Login", isOn: $launchAtLogin)
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

            // Idle detection
            HStack(spacing: 0) {
                Toggle("Idle detection after", isOn: $idleDetectionEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textPrimary)

                TextField("", value: $idleMinutes, format: .number)
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textPrimary)
                    .textFieldStyle(.plain)
                    .frame(width: 28)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(YieldColors.surfaceDefault)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(YieldColors.border, lineWidth: 1)
                    )
                    .disabled(!idleDetectionEnabled)
                    .opacity(idleDetectionEnabled ? 1 : 0.5)

                Text("min")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .padding(.leading, 4)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("About")

            settingsRow(label: "Version", value: appVersion)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                AppState.shared.updaterController?.checkForUpdates(nil)
            } label: {
                HStack {
                    Text("Check for Updates...")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(YieldFonts.dmSans(9, weight: .semibold))
            .foregroundStyle(YieldColors.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
            Spacer()
            Text(value)
                .font(YieldFonts.dmSans(11, weight: .medium))
                .foregroundStyle(YieldColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func settingsToggleRow(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(YieldFonts.dmSans(11))
            .foregroundStyle(YieldColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(YieldColors.border)
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version)"
    }
}
