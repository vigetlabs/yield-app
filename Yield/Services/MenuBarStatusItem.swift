import AppKit

/// Locates the running app's `NSStatusBarButton` — the menu-bar
/// affordance that anchors `MenuBarExtra`. SwiftUI's MenuBarExtra
/// doesn't expose this directly, so we walk `NSApp.windows` and
/// pull the `statusItem` ivar via KVC from the private window
/// class that owns it.
///
/// Centralized here so the two safety guards live in one place:
///
/// - `NSApp` is `NSApplication!` (implicitly-unwrapped). On
///   macOS 14.x SwiftUI evaluates the `MenuBarExtra` label closure
///   during scene-graph build — *before* `NSApplicationMain` sets
///   the global pointer — and the unguarded unwrap traps. The
///   `NSApp` nil check returns nil so the body re-evaluates later
///   when the pointer is live.
/// - `value(forKey: "statusItem")` raises `NSUndefinedKeyException`
///   on windows that don't declare the key. The `responds(to:)`
///   gate keeps the probe scoped to the windows that do.
@MainActor
enum MenuBarStatusItem {
    private static let selector = NSSelectorFromString("statusItem")

    /// The `NSStatusBarButton` for this app's menu-bar item, or
    /// nil during the early-launch window before `NSApp` is set.
    static var button: NSStatusBarButton? {
        guard let app = NSApp else { return nil }
        return app.windows
            .compactMap { window -> NSStatusItem? in
                guard window.responds(to: selector) else { return nil }
                return window.value(forKey: "statusItem") as? NSStatusItem
            }
            .first?.button
    }
}
