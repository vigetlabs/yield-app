import AppKit
import SwiftUI

/// Free-standing window for the idle alert.
///
/// The alert used to live only inside the MenuBarExtra panel, which
/// idle detection forced open by clicking the status item. macOS 27
/// stopped honoring that: the synthetic click lands (the button even
/// highlights) but SwiftUI never creates the panel window, so the alert
/// was staged and never seen. Notifications reach the user but aren't
/// interruptive enough for "you've been tracking the wrong thing for an
/// hour" — and they need a permission the app may not have.
///
/// A window we own ourselves has neither problem. It's an ordinary
/// `NSPanel`, so nothing about MenuBarExtra's private behavior applies,
/// and it needs no notification permission.
///
/// It hosts the same `IdleAlertView` the panel shows, and then the
/// same `NewTimerFormView` if the user picks "Move Time…" — otherwise
/// that action would strand them, since it hands off to a form that
/// renders inside the panel we can no longer open. The window closes
/// itself once the view model says both states are resolved.
@MainActor
final class IdleAlertWindow: NSObject, NSWindowDelegate {
    static let shared = IdleAlertWindow()

    private var window: NSPanel?
    /// Held so the close button routes through the same view model the
    /// alert was staged on, rather than assuming the app-wide one.
    private var viewModel: TimeComparisonViewModel?

    /// Show the alert, or bring an already-open one forward. Safe to
    /// call repeatedly — `checkIdleTime` guards against re-firing, but
    /// this shouldn't depend on that.
    func show(viewModel: TimeComparisonViewModel) {
        if let window {
            Self.present(window)
            return
        }

        let content = IdleAlertWindowContent(viewModel: viewModel) { [weak self] in
            self?.hide()
        }

        // `.nonactivatingPanel` is load-bearing. Without it, an
        // ordinary panel is not put on screen while its application is
        // inactive — and Yield is inactive by definition when idle
        // fires, since the user has been away from the keyboard for
        // minutes. Measured on macOS 27 with the app deliberately in
        // the background: the same panel with this flag is in the
        // window server's on-screen list, and without it is absent
        // until something activates the app. That is the reported
        // symptom exactly — no alert on returning to the Mac, then the
        // alert appearing the instant the menu bar icon was clicked.
        //
        // The cost is that clicking the window doesn't bring Yield
        // forward, which doesn't matter: every action here is a button,
        // and none of them need keyboard focus.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: YieldDimensions.panelWidth, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // Survives Spaces switches and shows over full-screen apps —
        // an idle alert that only appears on one desktop is an idle
        // alert you miss.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: content)
        panel.center()

        window = panel
        self.viewModel = viewModel

        viewModel.setIdleAlertInWindow(true)
        Self.present(panel)
        #if DEBUG
        LogStore.shared.log("[idle-diag] window shown for \(viewModel.idleAlertState?.projectName ?? "?")", category: .info)
        #endif
    }

    /// Put the panel on screen.
    ///
    /// `orderFrontRegardless()` rather than `makeKeyAndOrderFront`: the
    /// latter won't display a window whose application is inactive,
    /// which is always the case here. Paired with the panel's
    /// `.nonactivatingPanel` mask, this shows it without needing the
    /// app to come forward at all.
    ///
    /// `NSApp.activate` is a deliberate non-participant. macOS only
    /// grants activation to apps with a recent user interaction, so a
    /// background app that has been quiet for an hour — exactly this
    /// case — is the one it refuses. Depending on it is what made the
    /// alert invisible in the first place.
    private static func present(_ panel: NSPanel) {
        panel.orderFrontRegardless()
    }

    /// Close and tear down. Idempotent.
    func hide() {
        guard let window else { return }
        viewModel?.setIdleAlertInWindow(false)
        self.window = nil
        self.viewModel = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    /// Closing via the title bar's × means "leave the time alone" —
    /// the same reading as dismissing the inline alert, or backing out
    /// of the move form. Routing it through the view model rather than
    /// just hiding matters: `checkIdleTime` returns early while
    /// `idleAlertState` is non-nil, so a window closed without clearing
    /// it would suppress every future idle check.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if viewModel?.pendingIdleMove != nil {
            viewModel?.idleMoveCancel()
        } else {
            viewModel?.idleDismiss()
        }
        viewModel?.setIdleAlertInWindow(false)
        window = nil
        viewModel = nil
        return true
    }
}

/// Window chrome around the alert: shows the alert, then the move form
/// if the user routes into it, and reports back when there's nothing
/// left to show.
private struct IdleAlertWindowContent: View {
    let viewModel: TimeComparisonViewModel
    let onResolved: () -> Void

    private var isResolved: Bool {
        viewModel.idleAlertState == nil && viewModel.pendingIdleMove == nil
    }

    var body: some View {
        Group {
            if viewModel.idleAlertState != nil {
                IdleAlertView(viewModel: viewModel)
            } else if viewModel.pendingIdleMove != nil {
                NewTimerFormView(
                    viewModel: viewModel,
                    editingEntry: nil,
                    preselectedProjectId: nil,
                    targetDate: nil,
                    idleMove: viewModel.pendingIdleMove,
                    timerMove: nil,
                    startInCalendarPicker: false,
                    meetingEvent: nil,
                    timerMovePrefillHours: nil
                ) {
                    viewModel.idleMoveCancel()
                }
            }
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: isResolved) { _, resolved in
            if resolved { onResolved() }
        }
    }
}
