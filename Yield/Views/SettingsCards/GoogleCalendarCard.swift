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
    /// The menu bar's next-meeting countdown, and how much of a title it
    /// keeps. Here rather than with the menu bar's other settings: they
    /// are about the calendar, and only exist while it is connected.
    @AppStorage(DefaultsKey.meetingCountdownMode) private var meetingCountdownMode: String = MeetingCountdownMode.default.rawValue
    @AppStorage(DefaultsKey.meetingCountdownTitleLength) private var meetingTitleLength = MeetingCountdown.defaultTitleLength

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
                            .font(YieldFonts.settingsTitle)
                            .foregroundStyle(YieldColors.textPrimary)
                        if let email = googleAuth.userEmail {
                            Text(email)
                                .font(YieldFonts.settingsLabel())
                                .foregroundStyle(YieldColors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()
                }
                .settingsBlockPadding()

                SettingsRowDivider()

                // Meeting-start timer prompts: when an event begins,
                // Yield nudges (notification + a bar above the timer)
                // to start or switch a timer for it.
                SettingsToggleRow(
                    icon: "calendar.badge.clock",
                    label: "Meeting timer prompts",
                    isOn: $meetingPromptsEnabled
                )
                .help("When a calendar event starts, Yield offers to start a timer for it — including moving the minutes since the event began off the running timer.")

                SettingsRowDivider()

                // Post-meeting reminders: when a timer started from a
                // calendar event is still running past the event's end
                // (by the idle-detection threshold), Yield nudges to
                // move the overage.
                SettingsToggleRow(
                    icon: "calendar.badge.exclamationmark",
                    label: "Post-meeting reminders",
                    isOn: $postMeetingRemindersEnabled
                )
                .help("When a timer you started from a calendar event keeps running past the event's end, Yield offers to move the extra time to another timer.")

                SettingsRowDivider()

                // Next meeting beside the timer graphic
                meetingCountdownRow

                SettingsRowDivider()

                // Only titles get shortened — nothing to tune without them.
                if meetingCountdownMode == MeetingCountdownMode.titleAndTime.rawValue {
                    meetingTitleLengthRow

                    SettingsRowDivider()
                }

                if showGoogleDisconnectConfirm {
                    InlineConfirmationRow(
                        confirmLabel: "Disconnect",
                        onCancel: { showGoogleDisconnectConfirm = false },
                        onConfirm: {
                            showGoogleDisconnectConfirm = false
                            googleAuth.signOut()
                        }
                    )
                    .settingsBlockPadding()
                } else {
                    Button {
                        showGoogleDisconnectConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .settingsInlineIcon()
                            Text("Disconnect")
                                .font(YieldFonts.settingsLabel(weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(SettingsStyle.destructive)
                        .settingsRowPadding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pull events from your Google Calendar into time entries — pick an event from today and the duration and title fill the form for you.")
                        .font(YieldFonts.settingsLabel())
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
                                .font(YieldFonts.settingsButton(11))
                        }
                    }
                    .buttonStyle(.greenOutlined)
                    .disabled(googleAuth.isAuthenticating)

                    if let error = googleAuth.authError {
                        Text(error)
                            .font(YieldFonts.settingsCaption)
                            .foregroundStyle(YieldStatusColors.errorText())
                    }
                }
                .settingsBlockPadding()
            }
        }
        .settingsCard()
    }

    // MARK: - Menu bar meetings

    private var meetingCountdownRow: some View {
        SettingsEnumPickerRow(
            icon: "hourglass",
            label: "Menu bar meetings",
            cases: MeetingCountdownMode.allCases,
            selectedRawValue: meetingCountdownMode,
            title: { $0.label }
        ) { meetingCountdownMode = $0 }
        .help("Shows your next meeting in the menu bar and counts down to it. In a meeting it shows how long is left; if a meeting's timer is still running afterwards, how long ago it ended. Time only leaves titles out, for screen sharing.")
    }

    /// "Shorten titles to [−] 20 [+] characters": how much of a meeting's
    /// title the menu bar keeps. The buttons step by five; the field
    /// takes any number in range for finer tuning.
    private var meetingTitleLengthRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.size")
                .settingsRowIcon()

            Text("Shorten titles to")
                .font(YieldFonts.settingsLabel())
                .foregroundStyle(YieldColors.textPrimary)

            Spacer()

            titleLengthStepButton("minus", by: -MeetingCountdown.titleLengthStep)
                .help("Show fewer characters")

            TextField("", value: $meetingTitleLength, format: .number)
                .settingsNumberField(width: SettingsStyle.refreshed ? 34 : 26)
                .onChange(of: meetingTitleLength) { _, newValue in
                    let clamped = MeetingCountdown.clampedTitleLength(newValue)
                    if clamped != newValue { meetingTitleLength = clamped }
                }

            titleLengthStepButton("plus", by: MeetingCountdown.titleLengthStep)
                .help("Show more characters")

            Text("characters")
                .font(YieldFonts.settingsCaption)
                .foregroundStyle(YieldColors.textSecondary)
        }
        .settingsRowPadding()
    }

    private func titleLengthStepButton(_ symbol: String, by delta: Int) -> some View {
        let target = MeetingCountdown.clampedTitleLength(meetingTitleLength + delta)
        return Button {
            meetingTitleLength = target
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 22, height: 22)
                .background(YieldColors.background)
                .yieldBorder(radius: YieldRadius.button)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == meetingTitleLength)
        .opacity(target == meetingTitleLength ? 0.4 : 1)
    }
}
