import AppKit

/// Detects when Yield is running from macOS's translocated path
/// (typically `/private/var/folders/.../AppTranslocation/<UUID>/d/`)
/// and offers to move the bundle to /Applications before continuing.
///
/// Why this matters for Yield specifically: translocation serves the
/// app from a read-only mount that the system periodically unmounts
/// — Sequoia 15.x more aggressively than earlier OS releases. Most
/// apps you run from Downloads are short-lived and don't notice.
/// Yield is designed to live in the menu bar continuously, so an
/// overnight unmount kills the process with SIGBUS ("Object has no
/// pager because the backing vnode was force unmounted"). Running
/// from /Applications avoids translocation entirely.
///
/// Called once during `applicationDidFinishLaunching`, before the
/// MenuBarExtra item is constructed, so the alert (if any) doesn't
/// compete with the popup window.
@MainActor
enum AppLocationCheck {
    /// True when the running bundle's path is the translocated
    /// read-only mount macOS creates for quarantined apps launched
    /// outside /Applications. The `/AppTranslocation/` substring has
    /// been the canonical signal since macOS 10.12 introduced this
    /// feature; the path format has been stable across releases.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// Canonical destination for the moved copy.
    private static let applicationsURL = URL(fileURLWithPath: "/Applications/Yield.app")

    /// Run during launch. If the app is translocated, blocks on an
    /// alert asking the user how to proceed. Returns when the user
    /// either declines to move (app keeps running from the unstable
    /// path) or quits; the move path terminates the current process
    /// in its completion handler instead of returning.
    static func checkAndPrompt() {
        guard isTranslocated else { return }

        let alert = NSAlert()
        alert.messageText = "Move Yield to your Applications folder?"
        alert.informativeText = """
        Yield is running from a temporary location and may crash unexpectedly while it's there — particularly when left running overnight.

        To run reliably, Yield should live in your Applications folder. Click "Move to Applications" to do this automatically.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Don't Move")
        alert.addButton(withTitle: "Quit")

        // Without `.activate`, the alert appears behind whatever
        // window has focus when launch happens (often the Finder
        // window the user launched from). MenuBarExtra apps don't
        // get auto-focus on launch.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            moveAndRelaunch()
        case .alertThirdButtonReturn:
            NSApp.terminate(nil)
        default:
            // "Don't Move" — keep running. We deliberately don't
            // persist this choice: every launch should re-prompt
            // until the bundle is in /Applications, because the
            // risk (SIGBUS overnight) is non-trivial and the
            // dismissal is one click.
            break
        }
    }

    /// Copy the running bundle to /Applications, strip quarantine
    /// xattrs, launch the moved copy, and terminate. On any failure
    /// shows an alert and returns so the app can keep running from
    /// the translocated path — better than leaving the user with no
    /// app at all.
    private static func moveAndRelaunch() {
        let fm = FileManager.default
        let sourceURL = Bundle.main.bundleURL

        do {
            // If a stale /Applications/Yield.app exists (e.g. a
            // failed earlier attempt or an older install), replace
            // it. The user explicitly opted into the move, so a
            // silent overwrite is the expected behavior.
            if fm.fileExists(atPath: applicationsURL.path) {
                try fm.removeItem(at: applicationsURL)
            }

            try fm.copyItem(at: sourceURL, to: applicationsURL)

            // Strip every quarantine xattr from the destination,
            // including nested binaries (Sparkle framework). Without
            // this, macOS may translocate the *moved* copy on first
            // launch too, defeating the whole point.
            stripQuarantineRecursively(at: applicationsURL)

            // Launch the moved copy and exit. Using `openApplication`
            // with a completion handler ensures we don't terminate
            // ourselves until macOS confirms the new instance has
            // actually started — otherwise a brief race could leave
            // the user with no Yield running at all.
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: applicationsURL, configuration: config) { _, error in
                Task { @MainActor in
                    if let error {
                        showMoveFailureAlert(error.localizedDescription)
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        } catch {
            showMoveFailureAlert(error.localizedDescription)
        }
    }

    /// Shell out to `/usr/bin/xattr -cr` to strip every extended
    /// attribute on every file in the bundle. The Swift equivalent
    /// (walk the bundle and call `removexattr` per file) is several
    /// times the code for the same result. Best-effort: failure
    /// isn't fatal because the copy will usually launch fine on the
    /// signature alone.
    private static func stripQuarantineRecursively(at url: URL) {
        let proc = Process()
        proc.launchPath = "/usr/bin/xattr"
        proc.arguments = ["-cr", url.path]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // Ignore — the destination still has a valid signature.
        }
    }

    private static func showMoveFailureAlert(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't move Yield to Applications"
        alert.informativeText = "Yield will keep running from its current location, but may be unstable. You can move it manually by dragging it from Finder to your Applications folder.\n\nDetails: \(detail)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
