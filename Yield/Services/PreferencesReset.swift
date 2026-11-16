import Foundation

/// "Reset preferences" in Settings → Troubleshooting: every setting
/// back to its default.
///
/// Settings only. What you've built up — favorites, muted meetings,
/// the meetings and tasks Yield has learned — and both sign-ins are
/// left alone; so is Launch at Login, which macOS holds rather than
/// these defaults.
enum PreferencesReset {
    /// The keys behind the controls in Settings. A new preference has
    /// to be added here to be reset — `PreferencesResetTests` checks
    /// the list against what must survive.
    static let keys: [String] = [
        DefaultsKey.appearanceMode,
        DefaultsKey.uiTheme,
        DefaultsKey.menuBarLabelMode,
        DefaultsKey.menuBarStyle,
        DefaultsKey.meetingCountdownMode,
        DefaultsKey.meetingCountdownTitleLength,
        DefaultsKey.idleDetectionEnabled,
        DefaultsKey.idleMinutes,
        DefaultsKey.timerChangeHUDEnabled,
        DefaultsKey.weeklyHoursTarget,
        DefaultsKey.meetingPromptsEnabled,
        DefaultsKey.postMeetingRemindersEnabled,
    ]

    /// Removing a key (rather than writing its default) lets the
    /// registered defaults and each `@AppStorage`'s own default take
    /// over, so there is one place each default is written down.
    static func reset(in defaults: UserDefaults = .standard) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
