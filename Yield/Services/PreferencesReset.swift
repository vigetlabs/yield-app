import Foundation

/// "Reset preferences" in Settings → Troubleshooting: every setting
/// back to its default.
///
/// Settings only. What you've built up — favorites, muted meetings,
/// the meetings and tasks Yield has learned — and both sign-ins are
/// left alone; so is Launch at Login, which macOS holds rather than
/// these defaults.
enum PreferencesReset {
    /// Every setting in Settings and its default. The one list: the
    /// app registers it at launch, so `@AppStorage` and `UserDefaults`
    /// agree on initial values, and a reset removes exactly these keys
    /// — a preference added here is registered and resettable at once.
    static let defaults: [String: Any] = [
        DefaultsKey.appearanceMode: AppearanceMode.default.rawValue,
        DefaultsKey.uiTheme: YieldTheme.default.rawValue,
        DefaultsKey.menuBarLabelMode: MenuBarLabelMode.projectTime.rawValue,
        DefaultsKey.menuBarStyle: MenuBarStyle.default.rawValue,
        DefaultsKey.meetingCountdownMode: MeetingCountdownMode.default.rawValue,
        DefaultsKey.meetingCountdownTitleLength: MeetingCountdown.defaultTitleLength,
        DefaultsKey.idleDetectionEnabled: true,
        DefaultsKey.idleMinutes: 10,
        DefaultsKey.timerChangeHUDEnabled: true,
        DefaultsKey.weeklyHoursTarget: 40,
        DefaultsKey.meetingPromptsEnabled: true,
        DefaultsKey.postMeetingRemindersEnabled: true,
    ]

    static var keys: [String] { Array(defaults.keys) }

    /// Removing a key (rather than writing its default) lets the
    /// registered defaults and each `@AppStorage`'s own default take
    /// over, so there is one place each default is written down.
    static func reset(in defaults: UserDefaults = .standard) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
