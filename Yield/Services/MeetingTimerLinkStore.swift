import Foundation

/// Keeps the link between a Harvest entry and the calendar event its
/// timer was started from, across relaunches.
///
/// The link used to live only in the view model's memory, so an update,
/// a crash or a quit in the middle of a meeting silently dropped it:
/// the timer bar lost its meeting mark and the post-meeting reminder
/// never came. One record at a time — only one timer runs.
@MainActor
final class MeetingTimerLinkStore {
    /// Production reads and writes the app's own defaults. Under XCTest
    /// the shared store keeps nothing: the test bundle is hosted inside
    /// Yield.app, so `.standard` there is the user's real preferences,
    /// and a view model built by any test would otherwise overwrite a
    /// live link. Tests that cover persistence pass a scratch suite.
    static let shared = MeetingTimerLinkStore(
        defaults: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? .standard
            : nil
    )

    private let defaults: UserDefaults?
    private let storageKey = DefaultsKey.meetingTimerLink

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    func load() -> TimeComparisonViewModel.CalendarSourcedTimer? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(TimeComparisonViewModel.CalendarSourcedTimer.self, from: data)
    }

    /// Nil removes the record.
    func save(_ link: TimeComparisonViewModel.CalendarSourcedTimer?) {
        guard let defaults else { return }
        guard let link, let data = try? JSONEncoder().encode(link) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
