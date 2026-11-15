import ServiceManagement
import SwiftUI

/// Owns every preference toggle/picker so a single `@AppStorage` flip
/// only invalidates this card — not the entire Settings panel.
struct PreferencesCard: View {
    @AppStorage(DefaultsKey.appearanceMode) private var appearanceMode: String = AppearanceMode.default.rawValue
    @AppStorage(DefaultsKey.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(DefaultsKey.timerChangeHUDEnabled) private var timerChangeHUDEnabled = true
    @AppStorage(DefaultsKey.idleMinutes) private var idleMinutes = 10
    @AppStorage(DefaultsKey.weeklyHoursTarget) private var weeklyHoursTarget = 40
    @AppStorage(DefaultsKey.menuBarLabelMode) private var menuBarLabelMode: String = MenuBarLabelMode.projectTime.rawValue
    @AppStorage(DefaultsKey.menuBarStyle) private var menuBarStyle: String = MenuBarStyle.default.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader("Preferences")

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

            SettingsRowDivider()

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

            SettingsRowDivider()

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

    // MARK: - Rows

    private var appearanceRow: some View {
        enumPickerRow(
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
        enumPickerRow(
            icon: "textformat",
            label: "Theme",
            cases: YieldTheme.allCases,
            selectedRawValue: ThemeStore.shared.theme.rawValue,
            title: { $0.label }
        ) { ThemeStore.shared.select(YieldTheme(rawValue: $0) ?? .default) }
    }

    private var menuBarStyleRow: some View {
        enumPickerRow(
            icon: "circle.dashed",
            label: "Menu bar style",
            cases: MenuBarStyle.allCases,
            selectedRawValue: menuBarStyle,
            title: { $0.label }
        ) { menuBarStyle = $0 }
    }

    private var menuBarDisplayRow: some View {
        enumPickerRow(
            icon: "menubar.rectangle",
            label: "Menu bar text",
            cases: MenuBarLabelMode.allCases,
            selectedRawValue: menuBarLabelMode,
            title: { $0.label }
        ) { menuBarLabelMode = $0 }
    }

    /// Settings row that binds a string-backed enum to a `DropdownPicker`.
    /// The picker is keyed by `Int` tags so we use each case's `allCases`
    /// index as the id.
    private func enumPickerRow<T: RawRepresentable>(
        icon: String,
        label: String,
        cases: [T],
        selectedRawValue: String,
        title: (T) -> String,
        onSelect: @escaping (String) -> Void
    ) -> some View where T.RawValue == String {
        // `title` was `KeyPath<T, String>` until a launch crash on
        // macOS 14.6.1 (`EXC_BREAKPOINT` in `AnyKeyPath` equality)
        // pushed us off generic-context KeyPaths — closures avoid
        // the runtime's KeyPath cache.
        let items = cases.enumerated().map { (id: $0.offset, title: title($0.element)) }
        let selectedId = cases.firstIndex { $0.rawValue == selectedRawValue } ?? 0

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .settingsRowIcon()
            Text(label)
                .font(YieldFonts.settingsLabel())
                .foregroundStyle(YieldColors.textPrimary)
            Spacer()
            DropdownPicker(
                label: label,
                placeholder: "Select",
                items: items,
                selectedId: selectedId
            ) { id in
                guard cases.indices.contains(id) else { return }
                onSelect(cases[id].rawValue)
            }
            .frame(width: YieldDimensions.settingsRowControlWidth)
        }
        .settingsRowPadding()
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

    private func settingsToggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .settingsRowIcon()
            Text(label)
                .font(YieldFonts.settingsLabel())
                .foregroundStyle(YieldColors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .settingsSwitch()
        }
        .settingsRowPadding()
    }
}
