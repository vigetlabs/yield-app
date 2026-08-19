import Foundation

/// Single source of truth for every UserDefaults key the app reads or
/// writes. Centralizing prevents typo-driven phantom keys (we had a
/// historical split between `"harvestAccountId"` and
/// `"oauthHarvestAccountId"` that this enum makes obvious) and makes
/// it easier to audit what the app persists.
///
/// Keys are exposed as `static let` so `@AppStorage` and direct
/// `UserDefaults` calls can both reference the same constants.
enum DefaultsKey {
    // MARK: - Preferences (Settings panel)
    static let appearanceMode = "appearanceMode"
    static let menuBarLabelMode = "menuBarLabelMode"
    static let idleDetectionEnabled = "idleDetectionEnabled"
    static let idleMinutes = "idleMinutes"
    /// Whether externally-triggered timer starts/stops (e.g. from the
    /// Harvest browser extension) are announced via a system
    /// notification. Key name predates the move from a custom HUD to
    /// system notifications — kept so existing users' preference
    /// survives.
    static let timerChangeHUDEnabled = "timerChangeHUDEnabled"
    /// Weekly hours target. Default 40. Daily target is derived as
    /// `DateHelpers.dailyHours(fromWeekly:)`.
    static let weeklyHoursTarget = "weeklyHoursTarget"
    /// Whether meeting-start timer prompts (notification + panel bar)
    /// are shown. Only meaningful — and only surfaced in Settings —
    /// while Google Calendar is connected. Default on: connecting the
    /// calendar is the opt-in signal.
    static let meetingPromptsEnabled = "meetingPromptsEnabled"

    // MARK: - User data
    static let favorites = "favorites"
    /// Cap-bounded `[normalizedTitle: (projectId, taskId, lastUsedAt)]`
    /// map used to pre-fill the new-timer form when a calendar event
    /// title matches a previous time entry's notes. See
    /// `MeetingHistoryStore`.
    static let meetingHistory = "meetingHistory"
    /// Cap-bounded per-project task usage scores (recency-weighted
    /// frequency) powering the implicit "soft favorite" task pre-fill in
    /// the new-timer form. See `ProjectTaskHistoryStore`.
    static let projectTaskHistory = "projectTaskHistory"
    /// Normalized meeting titles the user has permanently muted from
    /// meeting-start timer prompts ("Don't prompt for meetings like
    /// this"). See `MutedMeetingsStore`; managed from the Calendar
    /// settings card.
    static let mutedMeetingTitles = "mutedMeetingTitles"
    /// Cached Forecast project id for the global "Time Off" project,
    /// so the first refresh after relaunch doesn't pay for a second
    /// lookup. See TimeComparisonViewModel.
    static let forecastTimeOffProjectId = "forecastTimeOffProjectId"

    // MARK: - OAuth tokens (current sign-in path)
    enum OAuth {
        static let tokenExpiresAt = "oauthTokenExpiresAt"
        static let harvestAccountId = "oauthHarvestAccountId"
        static let forecastAccountId = "oauthForecastAccountId"
        static let userName = "oauthUserName"
    }

    // MARK: - Google Calendar OAuth (separate provider)
    /// Google Calendar uses its own OAuth client and tokens. The
    /// access/refresh tokens themselves live in the Keychain under
    /// `googleAccessToken`/`googleRefreshToken`; only the expiry stamp
    /// and user-facing identity (email) live in UserDefaults.
    enum GoogleCalendar {
        static let tokenExpiresAt = "googleCalendarTokenExpiresAt"
        static let userEmail      = "googleCalendarUserEmail"
    }

    // MARK: - Legacy PAT-based credentials
    /// Personal-access-token credentials from before the OAuth flow.
    /// Read at startup as a fallback when no OAuth tokens are present.
    ///
    /// The `harvestToken` key was historically stored here in
    /// plist-readable UserDefaults. `TimeComparisonViewModel.init()`
    /// now migrates any value found to the Keychain under
    /// `"legacyHarvestToken"` on first launch after that change, and
    /// `TimeComparisonViewModel.legacyHarvestToken()` is the
    /// authoritative read (Keychain first, this key as a fallback for
    /// pre-migration state). The account-id keys here are not
    /// sensitive and continue to live in UserDefaults.
    enum Legacy {
        static let harvestToken = "harvestToken"
        static let harvestAccountId = "harvestAccountId"
        static let forecastAccountId = "forecastAccountId"
    }
}
