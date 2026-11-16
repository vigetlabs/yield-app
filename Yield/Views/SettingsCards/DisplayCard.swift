import SwiftUI

/// The look of the app and its menu bar item. Owns its pickers so a
/// single `@AppStorage` flip only invalidates this card — not the
/// entire Settings panel.
struct DisplayCard: View {
    @AppStorage(DefaultsKey.appearanceMode) private var appearanceMode: String = AppearanceMode.default.rawValue
    @AppStorage(DefaultsKey.menuBarLabelMode) private var menuBarLabelMode: String = MenuBarLabelMode.projectTime.rawValue
    @AppStorage(DefaultsKey.menuBarStyle) private var menuBarStyle: String = MenuBarStyle.default.rawValue

    var body: some View {
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
    }

    // MARK: - Rows

    private var appearanceRow: some View {
        SettingsEnumPickerRow(
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
        SettingsEnumPickerRow(
            icon: "textformat",
            label: "Theme",
            cases: YieldTheme.allCases,
            selectedRawValue: ThemeStore.shared.theme.rawValue,
            title: { $0.label }
        ) { ThemeStore.shared.select(YieldTheme(rawValue: $0) ?? .default) }
    }

    private var menuBarStyleRow: some View {
        SettingsEnumPickerRow(
            icon: "circle.dashed",
            label: "Menu bar style",
            cases: MenuBarStyle.allCases,
            selectedRawValue: menuBarStyle,
            title: { $0.label }
        ) { menuBarStyle = $0 }
    }

    private var menuBarDisplayRow: some View {
        SettingsEnumPickerRow(
            icon: "menubar.rectangle",
            label: "Menu bar text",
            cases: MenuBarLabelMode.allCases,
            selectedRawValue: menuBarLabelMode,
            title: { $0.label }
        ) { menuBarLabelMode = $0 }
    }
}
