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
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Back")
                        .font(YieldFonts.dmSans(11, weight: .medium))
                }
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
            VStack(spacing: 12) {
                accountCard
                preferencesCard
                aboutCard
            }
            .padding(16)
        }
    }

    // MARK: - Account Card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Account")

            if oAuthService.isAuthenticated {
                // User info
                HStack(spacing: 10) {
                    // Avatar circle
                    ZStack {
                        Circle()
                            .fill(YieldColors.greenAccent.opacity(0.15))
                        Text(initials)
                            .font(YieldFonts.dmSans(11, weight: .semibold))
                            .foregroundStyle(YieldColors.greenAccent)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        if let name = oAuthService.userName {
                            Text(name)
                                .font(YieldFonts.dmSans(12, weight: .semibold))
                                .foregroundStyle(YieldColors.textPrimary)
                        }
                        HStack(spacing: 6) {
                            if let harvestId = oAuthService.harvestAccountId {
                                accountBadge("Harvest \(harvestId)")
                            }
                            if let forecastId = oAuthService.forecastAccountId {
                                accountBadge("Forecast \(forecastId)")
                            }
                        }
                    }

                    Spacer()
                }
                .padding(12)

                // Divider
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)

                // Sign out row
                Button {
                    oAuthService.signOut()
                    Task {
                        await AppState.shared.viewModel.refresh()
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 10))
                        Text("Sign Out")
                            .font(YieldFonts.dmSans(11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your Harvest account to compare logged hours against Forecast bookings.")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineSpacing(2)

                    Button {
                        oAuthService.startOAuthFlow()
                    } label: {
                        HStack(spacing: 6) {
                            if oAuthService.isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 11))
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
                .padding(12)
            }
        }
        .background(YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: YieldRadius.card)
                .strokeBorder(YieldColors.border, lineWidth: 1)
        )
    }

    // MARK: - Preferences Card

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Preferences")

            // Launch at login
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

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Idle detection
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 16)

                Toggle("Idle detection", isOn: $idleDetectionEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textPrimary)
                    .labelsHidden()

                Text("Idle detection after")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(idleDetectionEnabled ? YieldColors.textPrimary : YieldColors.textSecondary)

                TextField("", value: $idleMinutes, format: .number)
                    .font(YieldFonts.monoXS)
                    .foregroundStyle(YieldColors.textPrimary)
                    .textFieldStyle(.plain)
                    .frame(width: 26)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(YieldColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(YieldColors.border, lineWidth: 1)
                    )
                    .disabled(!idleDetectionEnabled)
                    .opacity(idleDetectionEnabled ? 1 : 0.4)
                    .onChange(of: idleMinutes) { _, newValue in
                        if newValue < 1 { idleMinutes = 1 }
                    }

                Text("min")
                    .font(YieldFonts.dmSans(10))
                    .foregroundStyle(YieldColors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: YieldRadius.card)
                .strokeBorder(YieldColors.border, lineWidth: 1)
        )
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("About")

            // Version row
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 16)
                Text("Version")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textSecondary)
                Spacer()
                Text(appVersion)
                    .font(YieldFonts.monoXS)
                    .foregroundStyle(YieldColors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Check for updates
            Button {
                NSApp.activate(ignoringOtherApps: true)
                AppState.shared.updaterController?.checkForUpdates(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(YieldColors.textSecondary)
                        .frame(width: 16)
                    Text("Check for Updates")
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
        }
        .background(YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: YieldRadius.card)
                .strokeBorder(YieldColors.border, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var initials: String {
        guard let name = oAuthService.userName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ", omittingEmptySubsequences: true)
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? (parts.last.map { String($0.prefix(1)) } ?? "") : ""
        let result = (first + last).uppercased()
        return result.isEmpty ? "?" : result
    }

    private func accountBadge(_ text: String) -> some View {
        Text(text)
            .font(YieldFonts.dmSans(8, weight: .medium))
            .foregroundStyle(YieldColors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(YieldColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(YieldFonts.dmSans(9, weight: .semibold))
            .foregroundStyle(YieldColors.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func settingsToggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 16)
            Text(label)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version)"
    }
}
