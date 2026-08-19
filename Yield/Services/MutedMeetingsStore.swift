import Foundation

/// Meeting titles the user has permanently excluded from meeting-start
/// timer prompts ("Don't prompt for meetings like this" on the prompt
/// bar). Keyed by normalized title — the same normalization
/// `MeetingHistoryStore` uses, so muting and remembering agree on what
/// counts as the same meeting. Recurring meetings keep stable titles,
/// which is what makes title-level muting the right granularity: one
/// mute kills the daily standup's prompt forever.
///
/// `@Observable` (unlike the history store) because the Settings card
/// binds to the muted list directly for the management/undo UI.
@Observable
@MainActor
final class MutedMeetingsStore {
    static let shared = MutedMeetingsStore()

    /// Normalized titles, with the original-cased title kept for
    /// display in the Settings list. Internal-settable so tests can
    /// seed state; production callers mutate through mute/unmute.
    var titles: [String: String] = [:]  // normalized → display title

    private let storageKey = DefaultsKey.mutedMeetingTitles

    /// `loadFromDefaults: false` produces a fresh store with no
    /// UserDefaults round-trip — used by tests.
    init(loadFromDefaults: Bool = true) {
        if loadFromDefaults { load() }
    }

    func isMuted(title: String) -> Bool {
        let key = MeetingHistoryStore.normalize(title)
        guard !key.isEmpty else { return false }
        return titles[key] != nil
    }

    /// No-op for empty/whitespace-only titles — untitled events have
    /// no stable identity to mute (and are excluded from prompting
    /// anyway).
    func mute(title: String) {
        let key = MeetingHistoryStore.normalize(title)
        guard !key.isEmpty else { return }
        titles[key] = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func unmute(normalizedTitle: String) {
        titles.removeValue(forKey: normalizedTitle)
        save()
    }

    /// Display titles sorted for the Settings management list —
    /// (normalized key, display title) pairs so rows can unmute by key.
    var sortedMuted: [(key: String, title: String)] {
        titles
            .map { (key: $0.key, title: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(titles, forKey: storageKey)
    }

    private func load() {
        guard let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] else { return }
        titles = stored
    }
}
