import SwiftUI

/// How time is tracked: the weekly target, idle detection, and
/// timer-change notifications. Owns its controls so a single
/// `@AppStorage` flip only invalidates this card.
struct TrackingCard: View {
    @AppStorage(DefaultsKey.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(DefaultsKey.timerChangeHUDEnabled) private var timerChangeHUDEnabled = true
    @AppStorage(DefaultsKey.idleMinutes) private var idleMinutes = 10
    @AppStorage(DefaultsKey.weeklyHoursTarget) private var weeklyHoursTarget = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader("Tracking")

            hoursTargetRow(
                icon: "calendar.badge.clock",
                label: "Weekly hours target",
                value: $weeklyHoursTarget,
                upperBound: 168  // 24×7 ceiling
            )

            SettingsRowDivider()

            // Idle detection
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .settingsRowIcon()

                Text("Idle detection after")
                    .font(YieldFonts.settingsLabel())
                    .foregroundStyle(idleDetectionEnabled ? YieldColors.textPrimary : YieldColors.textSecondary)

                TextField("", value: $idleMinutes, format: .number)
                    .settingsNumberField(width: SettingsStyle.refreshed ? 34 : 26)
                    .disabled(!idleDetectionEnabled)
                    .opacity(idleDetectionEnabled ? 1 : 0.4)
                    .onChange(of: idleMinutes) { _, newValue in
                        if newValue < 1 { idleMinutes = 1 }
                    }

                Text("min")
                    .font(YieldFonts.settingsCaption)
                    .foregroundStyle(YieldColors.textSecondary)

                Spacer()

                Toggle("Idle detection", isOn: $idleDetectionEnabled)
                    .settingsSwitch()
            }
            .settingsRowPadding()

            SettingsRowDivider()

            SettingsToggleRow(
                icon: "megaphone",
                label: "External timer change notifications",
                isOn: $timerChangeHUDEnabled
            )

            // Notification permission warning — only renders when
            // permission is denied. Without this, the over-budget
            // "Time's up!" notification silently doesn't fire and
            // the user has no way to know why.
            if NotificationPermission.shared.status == .denied {
                SettingsRowDivider()

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(YieldColors.yellowAccent)
                    Text("Notifications are off — over-budget alerts won't fire.")
                        .font(YieldFonts.settingsCaption)
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Open Settings") {
                        NotificationPermission.shared.openSystemSettings()
                    }
                    .buttonStyle(.yieldBordered)
                    .font(SettingsStyle.refreshed ? YieldFonts.labelButton : YieldFonts.label(10, weight: .medium))
                }
                .settingsRowPadding()
            }
        }
        .settingsCard()
        .task {
            // Re-check permission whenever Settings appears so the
            // warning updates if the user toggled it from System
            // Settings between visits.
            await NotificationPermission.shared.refresh()
        }
    }

    // MARK: - Rows

    /// Reusable row for an integer "hours target" setting — small
    /// icon + label + numeric text field + "hr" suffix. Clamps to
    /// `1...upperBound` on edit so the persisted value stays sane.
    private func hoursTargetRow(
        icon: String,
        label: String,
        value: Binding<Int>,
        upperBound: Int
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .settingsRowIcon()

            Text(label)
                .font(YieldFonts.settingsLabel())
                .foregroundStyle(YieldColors.textPrimary)

            Spacer()

            TextField("", value: value, format: .number)
                .settingsNumberField(width: SettingsStyle.refreshed ? 38 : 32)
                .onChange(of: value.wrappedValue) { _, newValue in
                    if newValue < 1 { value.wrappedValue = 1 }
                    if newValue > upperBound { value.wrappedValue = upperBound }
                }

            Text("hr")
                .font(YieldFonts.settingsCaption)
                .foregroundStyle(YieldColors.textSecondary)
        }
        .settingsRowPadding()
    }
}
