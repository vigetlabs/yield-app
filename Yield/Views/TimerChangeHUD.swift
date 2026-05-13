import AppKit
import SwiftUI

/// What kind of external timer change to announce.
enum TimerChangeKind {
    case started, stopped
}

struct TimerChangeInfo {
    let kind: TimerChangeKind
    let clientName: String?
    let projectName: String
    let taskName: String?
}

/// Shows a small HUD-style panel near the top of the active screen
/// when an external Harvest action changes the running timer (e.g. the
/// browser extension starts a timer on a GitHub issue). Modeled on the
/// macOS volume / brightness HUDs: a borderless floating NSPanel with
/// a blurred background, fades in and auto-dismisses.
@MainActor
final class TimerChangeHUDController {
    static let shared = TimerChangeHUDController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private static let displayDuration: TimeInterval = 5.0
    private static let fadeIn: TimeInterval = 0.18
    private static let fadeOut: TimeInterval = 0.30

    func show(_ info: TimerChangeInfo) {
        // No-op under XCTest — tests drive the view model directly and
        // shouldn't paint floating panels onto the host's screen.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        // Respect the user's preference. The default registered at
        // launch is `true`, so an unset key still surfaces the HUD.
        guard UserDefaults.standard.bool(forKey: DefaultsKey.timerChangeHUDEnabled) else { return }
        // Suppressed while the panel is open — the user is already
        // looking at the timer state, the HUD would be noise.
        guard !AppState.shared.isPanelOpen else { return }

        let panel = ensurePanel()
        let host = NSHostingView(rootView: TimerChangeHUDView(info: info))
        host.frame = NSRect(origin: .zero, size: Self.contentSize)
        panel.contentView = host
        panel.setFrame(targetFrame(), display: false)

        dismissTask?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.dismiss()
        }
    }

    /// Fade out and hide. Safe to call when nothing is showing — does
    /// nothing if the panel hasn't been built or is already invisible.
    func dismiss() {
        dismissTask?.cancel()
        guard let panel, panel.isVisible, panel.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    // MARK: - Panel construction

    private static let contentSize = NSSize(width: 320, height: 64)

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func targetFrame() -> NSRect {
        // Anchor the HUD's left edge to the status item's left edge,
        // top edge tucked just below the menu bar so it hangs down-and-
        // to-the-right from the icon. Falls back to the screen's top-
        // left corner if the status item can't be located (menu bar
        // hidden in fullscreen, etc.).
        let size = Self.contentSize
        let edgeInset: CGFloat = 8
        let gapBelowMenuBar: CGFloat = 6

        guard let button = MenuBarStatusItem.button,
              let buttonWindow = button.window else {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let visible = screen?.visibleFrame ?? .zero
            return NSRect(
                x: visible.minX + edgeInset,
                y: visible.maxY - size.height - 32,
                width: size.width,
                height: size.height
            )
        }

        let buttonScreenRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? buttonScreenRect

        var x = buttonScreenRect.minX
        x = max(visible.minX + edgeInset, min(x, visible.maxX - size.width - edgeInset))
        let y = buttonScreenRect.minY - size.height - gapBelowMenuBar
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// MARK: - HUD content

private struct TimerChangeHUDView: View {
    let info: TimerChangeInfo

    private var iconName: String {
        switch info.kind {
        case .started: return "play.fill"
        case .stopped: return "stop.fill"
        }
    }

    private var titleText: String {
        switch info.kind {
        case .started: return "Timer started"
        case .stopped: return "Timer stopped"
        }
    }

    private var subtitleText: String {
        let project = ProjectStatus.qualifiedName(client: info.clientName, project: info.projectName)
        guard let task = info.taskName, !task.isEmpty else { return project }
        return "\(project) / \(task)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(YieldColors.greenAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(YieldFonts.dmSans(12, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)
                Text(subtitleText)
                    .font(YieldFonts.dmSans(10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HUDBlurBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// `.popover` material gives a noticeably more translucent backdrop
/// than `.hudWindow` — the system HUD material is dense enough that
/// content behind it gets washed out, which made the HUD harder to
/// read against busy wallpapers.
private struct HUDBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
