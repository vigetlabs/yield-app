import AppKit
import Observation

/// Whether the menu bar itself is currently dark.
///
/// The colored menu bar styles draw a non-template image, so macOS no
/// longer picks black or white ink for us — and the right answer isn't
/// the app's appearance or even the system theme: the menu bar goes
/// dark or light with the *wallpaper* behind it. The status item's
/// button is the one object that knows, via its `effectiveAppearance`.
///
/// `isDark` is observable, so the MenuBarExtra label closure that
/// reads it re-runs (and re-renders the image) when the wallpaper or
/// theme flips the bar.
@Observable
@MainActor
final class MenuBarAppearance {
    static let shared = MenuBarAppearance()

    /// Best guess until the status item exists: the app's own
    /// appearance. Corrected as soon as the button is found.
    private(set) var isDark: Bool = MenuBarAppearance.isDark(NSApp?.effectiveAppearance)

    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var retriesLeft = 40
    @ObservationIgnored private var retryScheduled = false

    /// Start watching the status item's appearance. Cheap to call
    /// repeatedly — a no-op once attached. The status item doesn't
    /// exist yet the first time the label closure runs at launch, so a
    /// missing button schedules a bounded retry rather than giving up.
    func attachIfNeeded() {
        guard observation == nil else { return }
        guard let button = MenuBarStatusItem.button else {
            scheduleRetry()
            return
        }
        observation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] button, _ in
            let dark = MenuBarAppearance.isDark(button.effectiveAppearance)
            // Hop off the KVO callback: `.initial` fires synchronously
            // inside `attachIfNeeded`, which is called while SwiftUI is
            // evaluating the label — mutating observable state there
            // would be a write during a view update.
            Task { @MainActor in
                guard let self, self.isDark != dark else { return }
                self.isDark = dark
            }
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled, retriesLeft > 0 else { return }
        retryScheduled = true
        retriesLeft -= 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.retryScheduled = false
            self?.attachIfNeeded()
        }
    }

    nonisolated private static func isDark(_ appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
