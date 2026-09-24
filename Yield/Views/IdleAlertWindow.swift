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
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = IdleAlertWindowContent(viewModel: viewModel) { [weak self] in
            self?.hide()
        }

        // .nonactivatingPanel is deliberately NOT set: this is an
        // interruption, and it should take focus the way the panel
        // opening in your face used to.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: YieldDimensions.panelWidth, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
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

        // Activate first, then take key. The other order raced:
        // `activate` is asynchronous, and an activation landing after
        // makeKeyAndOrderFront could leave the panel visible but not
        // key — on screen, unfocused, easy to miss. Re-asserting key on
        // the next runloop pass covers the case where activation is
        // still in flight when this returns.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
        #if DEBUG
        LogStore.shared.log("[idle-diag] window shown for \(viewModel.idleAlertState?.projectName ?? "?")", category: .info)
        #endif
    }

    /// Close and tear down. Idempotent.
    func hide() {
        guard let window else { return }
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
