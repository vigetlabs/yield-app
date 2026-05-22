import SwiftUI

/// Harvest account info + sign-in/sign-out controls.
struct AccountCard: View {
    let oAuthService: OAuthService
    let onDismiss: () -> Void

    @State private var showSignOutConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader(
                "Account",
                info: "Your Harvest sign-in token is stored in the macOS Keychain. Your preferences live locally in UserDefaults. Nothing leaves your machine except API calls to Harvest and Forecast."
            )

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

                // Sign out row. We render confirmation INLINE rather
                // than via `.confirmationDialog` because system
                // dialogs presented from a MenuBarExtra panel make
                // the panel resign key → panel auto-dismisses →
                // dialog gets cancelled before the button action
                // fires. Inline confirmation keeps everything within
                // the panel so the action lands.
                if showSignOutConfirm {
                    InlineConfirmationRow(
                        confirmLabel: "Sign Out",
                        onCancel: { showSignOutConfirm = false },
                        onConfirm: {
                            showSignOutConfirm = false
                            oAuthService.signOut()
                            AppState.shared.viewModel.resetForSignOut()
                            // Return to the main panel — once
                            // signed out, the Settings page has
                            // little meaningful content to show
                            // (no account, no projects), and the
                            // main panel surfaces the onboarding
                            // prompt the user needs to act on
                            // next.
                            onDismiss()
                        }
                    )
                    .padding(12)
                } else {
                    Button {
                        showSignOutConfirm = true
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
                }
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
        .yieldCard()
    }

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
}
