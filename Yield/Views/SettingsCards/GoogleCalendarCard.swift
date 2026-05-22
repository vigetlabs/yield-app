import SwiftUI

/// Connect/disconnect Google Calendar so the Add Time form's calendar
/// picker can pull today's events. Independent of the Harvest sign-in;
/// you can be signed into one without the other.
struct GoogleCalendarCard: View {
    /// Pulled from `AppState.shared` rather than the init signature so
    /// existing call sites don't need updating. SwiftUI tracks the
    /// `@Observable` correctly through this stored reference.
    private let googleAuth: GoogleAuthService = AppState.shared.googleAuthService

    @State private var showGoogleDisconnectConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader(
                "Calendar",
                info: "Yield reads only your primary calendar's events for today, and only when you open the picker. Nothing is written back to Google. The OAuth token lives in the macOS Keychain."
            )

            if googleAuth.isAuthenticated {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(YieldColors.greenAccent.opacity(0.15))
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(YieldColors.greenAccent)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Calendar")
                            .font(YieldFonts.dmSans(12, weight: .semibold))
                            .foregroundStyle(YieldColors.textPrimary)
                        if let email = googleAuth.userEmail {
                            Text(email)
                                .font(YieldFonts.dmSans(11))
                                .foregroundStyle(YieldColors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()
                }
                .padding(12)

                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)

                if showGoogleDisconnectConfirm {
                    InlineConfirmationRow(
                        confirmLabel: "Disconnect",
                        onCancel: { showGoogleDisconnectConfirm = false },
                        onConfirm: {
                            showGoogleDisconnectConfirm = false
                            googleAuth.signOut()
                        }
                    )
                    .padding(12)
                } else {
                    Button {
                        showGoogleDisconnectConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 10))
                            Text("Disconnect")
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
                    Text("Pull events from your Google Calendar into time entries — pick an event from today and the duration and title fill the form for you.")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineSpacing(2)

                    Button {
                        googleAuth.startOAuthFlow()
                    } label: {
                        HStack(spacing: 6) {
                            if googleAuth.isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 11))
                            }
                            Text("Connect Google Calendar")
                                .font(YieldFonts.dmSans(11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.greenOutlined)
                    .disabled(googleAuth.isAuthenticating)

                    if let error = googleAuth.authError {
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
}
