import AppKit
import Observation
import UserNotifications

/// Tracks the macOS notification permission state for Yield so the
/// Settings panel can surface a hint when notifications are denied.
/// Without this, the budget "Time's up!" alert silently fails and the
/// user has no idea why they're not getting nudged.
@Observable
@MainActor
final class NotificationPermission {
    static let shared = NotificationPermission()

    enum Status {
        /// Permission hasn't been requested yet. (We request on launch
        /// so this should be transient.)
        case unknown
        /// User granted the permission — notifications will fire.
        case allowed
        /// User denied (or has notifications globally off for Yield).
        /// We can't re-prompt; the user has to enable it from System
        /// Settings → Notifications → Yield.
        case denied
    }

    private(set) var status: Status = .unknown

    /// Refresh the cached status from `UNUserNotificationCenter`.
    /// Cheap to call; the OS caches the answer.
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let next: Status
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            next = .allowed
        case .denied:
            next = .denied
        case .notDetermined:
            next = .unknown
        @unknown default:
            next = .unknown
        }
        if next != status {
            status = next
            if next == .denied {
                LogStore.shared.log(
                    "Notification permission is denied — budget \"Time's up!\" alerts won't fire.",
                    category: .warning
                )
            }
        }
    }

    /// Request permission and refresh `status` to reflect the user's
    /// answer. Called once at launch from `AppDelegate`.
    func requestAndRefresh() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    /// Open the Notifications pane of System Settings, scrolled to
    /// Yield. macOS doesn't expose a way to scroll to a specific app
    /// reliably — this opens the Notifications pane and the user
    /// finds Yield in the list.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
