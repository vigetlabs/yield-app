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
    /// Meeting-start timer prompts (notification + panel bar). Only
    /// surfaced while connected — an irrelevant toggle is noise.
    @AppStorage(DefaultsKey.meetingPromptsEnabled) private var meetingPromptsEnabled = true
    /// Post-meeting overage reminders — the bookend nudge when a
    /// calendar-started timer is still running past the event's end.
    @AppStorage(DefaultsKey.postMeetingRemindersEnabled) private var postMeetingRemindersEnabled = true

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

                // Meeting-start timer prompts: when an event begins,
                // Yield nudges (notification + a bar above the timer)
                // to start or switch a timer for it.
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 11))
                        .foregroundStyle(YieldColors.textSecondary)
                        .frame(width: 16)
                    Text("Meeting timer prompts")
                        .font(YieldFonts.dmSans(11, weight: .medium))
                        .foregroundStyle(YieldColors.textPrimary)
                        .help("When a calendar event starts, Yield offers to start a timer for it — including moving the minutes since the event began off the running timer.")
                    Spacer()
                    Toggle("Meeting timer prompts", isOn: $meetingPromptsEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)

                // Post-meeting reminders: when a timer started from a
                // calendar event is still running past the event's end
                // (by the idle-detection threshold), Yield nudges to
                // move the overage.
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 11))
                        .foregroundStyle(YieldColors.textSecondary)
                        .frame(width: 16)
                    Text("Post-meeting reminders")
                        .font(YieldFonts.dmSans(11, weight: .medium))
                        .foregroundStyle(YieldColors.textPrimary)
                        .help("When a timer you started from a calendar event keeps running past the event's end, Yield offers to move the extra time to another timer.")
                    Spacer()
                    Toggle("Post-meeting reminders", isOn: $postMeetingRemindersEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

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
