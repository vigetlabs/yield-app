import SwiftUI

/// The Display and Tracking sections. Owns their toggles and pickers so
/// a single `@AppStorage` flip only invalidates these — not the entire
/// Settings panel.
struct PreferencesCard: View {
    @AppStorage(DefaultsKey.appearanceMode) private var appearanceMode: String = AppearanceMode.default.rawValue
    @AppStorage(DefaultsKey.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(DefaultsKey.timerChangeHUDEnabled) private var timerChangeHUDEnabled = true
    @AppStorage(DefaultsKey.idleMinutes) private var idleMinutes = 10
    @AppStorage(DefaultsKey.weeklyHoursTarget) private var weeklyHoursTarget = 40
    @AppStorage(DefaultsKey.menuBarLabelMode) private var menuBarLabelMode: String = MenuBarLabelMode.projectTime.rawValue
    @AppStorage(DefaultsKey.menuBarStyle) private var menuBarStyle: String = MenuBarStyle.default.rawValue

    /// Which of the two sections this instance draws. They are placed
    /// separately in Settings — Calendar sits between them.
    enum Section {
        /// The look of the app and its menu bar item.
        case display
        /// How time is tracked.
        case tracking
    }

    let section: Section

    var body: some View {
        switch section {
        case .display:
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardSectionHeader("Display")

                // Appearance (System / Light / Dark)
                appearanceRow

                SettingsRowDivider()

                // Theme (Editorial / System)
                themeRow

                SettingsRowDivider()

                // Menu bar graphic (Classic / ring / capsule / week bars)
                menuBarStyleRow

                SettingsRowDivider()

                // Menu bar text
                menuBarDisplayRow
            }
            .settingsCard()

        case .tracking:
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
                        .font(YieldFonts.settingsValue)
                        .foregroundStyle(YieldColors.textPrimary)
                        .textFieldStyle(.plain)
                        .frame(width: SettingsStyle.refreshed ? 34 : 26)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(YieldColors.background)
                        .yieldBorder(radius: YieldRadius.button)
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

                settingsToggleRow(
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
    }

    // MARK: - Rows

    private var appearanceRow: some View {
        settingsEnumPickerRow(
            icon: "circle.lefthalf.filled",
            label: "Appearance",
            cases: AppearanceMode.allCases,
            selectedRawValue: appearanceMode,
            title: { $0.label }
        ) { appearanceMode = $0 }
    }

    /// Reads `ThemeStore.shared.theme` directly rather than through
    /// `@AppStorage`: the store is the one place the choice is written
    /// so persistence and the live `@Observable` value can't drift.
    private var themeRow: some View {
        settingsEnumPickerRow(
            icon: "textformat",
            label: "Theme",
            cases: YieldTheme.allCases,
            selectedRawValue: ThemeStore.shared.theme.rawValue,
            title: { $0.label }
        ) { ThemeStore.shared.select(YieldTheme(rawValue: $0) ?? .default) }
    }

    private var menuBarStyleRow: some View {
        settingsEnumPickerRow(
            icon: "circle.dashed",
            label: "Menu bar style",
            cases: MenuBarStyle.allCases,
            selectedRawValue: menuBarStyle,
            title: { $0.label }
        ) { menuBarStyle = $0 }
    }

    private var menuBarDisplayRow: some View {
        settingsEnumPickerRow(
            icon: "menubar.rectangle",
            label: "Menu bar text",
            cases: MenuBarLabelMode.allCases,
            selectedRawValue: menuBarLabelMode,
            title: { $0.label }
        ) { menuBarLabelMode = $0 }
    }

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
                .font(YieldFonts.settingsValue)
                .foregroundStyle(YieldColors.textPrimary)
                .textFieldStyle(.plain)
                .frame(width: SettingsStyle.refreshed ? 38 : 32)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(YieldColors.background)
                .yieldBorder(radius: YieldRadius.button)
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
