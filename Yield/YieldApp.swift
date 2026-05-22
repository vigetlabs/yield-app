import AppKit
import Sparkle
import SwiftUI
import UserNotifications

@Observable
@MainActor
final class AppState {
    static let shared = AppState()
    let viewModel = TimeComparisonViewModel()
    let oAuthService = OAuthService()
    /// Google Calendar OAuth client. Independent of the Harvest
    /// `oAuthService`; used by the Add Time form's calendar picker
    /// to fetch the signed-in user's events.
    let googleAuthService = GoogleAuthService()
    var updaterController: SPUStandardUpdaterController?
    /// Whether the MenuBarExtra panel is currently open. Maintained by
    /// the AppDelegate's window key/resign observers. The HUD that
    /// announces external timer changes consults this so it stays
    /// silent while the user is already looking at the panel.
    var isPanelOpen: Bool = false
    func start() {
        viewModel.startAutoRefresh()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Translocation check runs first — before any defaults
        // registration, OAuth setup, or menu bar appearance.
        // If the user opts to move, the moved copy launches and
        // this process terminates from inside `checkAndPrompt()`;
        // no need to gate the rest of this function on the return.
        AppLocationCheck.checkAndPrompt()

        // Register defaults so @AppStorage and UserDefaults agree on initial values
        UserDefaults.standard.register(defaults: [
            DefaultsKey.idleDetectionEnabled: true,
            DefaultsKey.idleMinutes: 10,
            DefaultsKey.menuBarLabelMode: MenuBarLabelMode.projectTime.rawValue,
            DefaultsKey.appearanceMode: AppearanceMode.default.rawValue,
            DefaultsKey.timerChangeHUDEnabled: true,
            DefaultsKey.weeklyHoursTarget: 40,
        ])

        Task { @MainActor in
            await NotificationPermission.shared.requestAndRefresh()
        }
        DateHelpers.installTimezoneChangeObserver()
        AppState.shared.updaterController = updaterController
        AppState.shared.start()

        // Apply the persisted appearance choice. The App's body also
        // observes `appearanceMode` and updates this on change, so the
        // user's selection takes effect without restarting.
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.appearanceMode) ?? AppearanceMode.default.rawValue
        applyAppearance(raw)

        // Refresh whenever the MenuBarExtra panel opens, so state reflects
        // any changes made outside the app (e.g. starting a timer in Harvest).
        // Throttled to avoid excess API calls when opening/closing rapidly.
        // Also tracks `AppState.isPanelOpen` so the timer-change HUD stays
        // silent while the panel is already visible.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            let className = String(describing: type(of: window))
            // MenuBarExtra's panel window has "MenuBarExtra" in its class name
            guard className.contains("MenuBarExtra") else { return }
            Task { @MainActor in
                AppState.shared.isPanelOpen = true
                // Tear down any visible timer-change HUD — the panel
                // about to open shows the same state, so leaving the
                // HUD up would be redundant noise.
                TimerChangeHUDController.shared.dismiss()
                await AppState.shared.viewModel.refreshIfStale()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            let className = String(describing: type(of: window))
            guard className.contains("MenuBarExtra") else { return }
            Task { @MainActor in
                AppState.shared.isPanelOpen = false
            }
        }

        // Force a hard refresh when the Mac wakes from sleep. The 60s
        // soft-refresh timer should fire on wake too, but its behavior
        // across long sleeps isn't 100% reliable — when it misses, the
        // cache stays pinned to whatever the last refresh saw before
        // sleep (e.g. yesterday's entries leaking into today, see the
        // bug report about Sunday's logged hours showing up Monday
        // morning until the user quit and relaunched).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await AppState.shared.viewModel.refresh()
            }
        }
    }

    // MARK: - SPUStandardUserDriverDelegate (Gentle Reminders)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if state.userInitiated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // No-op: Sparkle handles dismissing the reminder
    }

    /// Apply an appearance choice (raw `AppearanceMode` value) to
    /// `NSApp.appearance`. Called on launch with the persisted value
    /// and from `YieldApp` whenever the setting changes.
    func applyAppearance(_ raw: String) {
        let mode = AppearanceMode(rawValue: raw) ?? .default
        NSApp.appearance = mode.nsAppearance
    }
}

@main
struct YieldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Read here so SwiftUI tracks the dependency — changing the setting
    /// in Settings re-runs the MenuBarExtra label closure with the new
    /// mode, which produces a different cache key and a new image.
    @AppStorage(DefaultsKey.menuBarLabelMode) private var menuBarLabelModeRaw: String = MenuBarLabelMode.projectTime.rawValue
    /// Drives `NSApp.appearance` and the panel's preferred color scheme
    /// so the user's appearance choice is honored at runtime.
    @AppStorage(DefaultsKey.appearanceMode) private var appearanceModeRaw: String = AppearanceMode.default.rawValue
    private var viewModel: TimeComparisonViewModel { AppState.shared.viewModel }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .default
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
                .preferredColorScheme(appearanceMode.colorScheme)
                .onChange(of: appearanceModeRaw) { _, newValue in
                    appDelegate.applyAppearance(newValue)
                }
        } label: {
            let mode = MenuBarLabelMode(rawValue: menuBarLabelModeRaw) ?? .projectTime
            // SwiftUI's `.help()` doesn't propagate to MenuBarExtra's
            // `NSStatusBarButton`, so we set the AppKit `toolTip`
            // directly. Reading `menuBarTooltip` here makes the label
            // closure depend on it, so it re-runs whenever the tooltip
            // text changes — which is when we update the button.
            let tooltip = viewModel.menuBarTooltip ?? ""
            Self.applyStatusItemTooltip(tooltip)
            return Image(nsImage: composedMenuBarImage(
                label: viewModel.menuBarLabel,
                icon: viewModel.menuBarIcon,
                mode: mode
            ))
        }
        .menuBarExtraStyle(.window)

    }

    /// Memoization key for `composedMenuBarImage`. MenuBarIcon is already
    /// Equatable so this gets automatic synthesis. The icon enum
    /// captures every state distinction (active vs paused vs idle vs
    /// PTO vs error), so no separate tracking flag is needed.
    private struct MenuBarImageKey: Equatable {
        let label: String
        let icon: TimeComparisonViewModel.MenuBarIcon
        let mode: MenuBarLabelMode
    }

    /// Process-global cache for the composed menu bar image. SwiftUI re-runs
    /// the MenuBarExtra label closure on every observable mutation (timer
    /// tick, each refresh), but the rendered image only changes when the
    /// label text, icon, or tracking dot does. Without this cache we'd
    /// allocate an NSImage + re-render an SF Symbol + measure attributed
    /// strings multiple times per minute even when nothing visibly changed.
    private static var cache: (key: MenuBarImageKey, image: NSImage)?

    /// Set (or clear) the underlying NSStatusBarButton's tooltip. Walks
    /// `NSApp.windows` to find the MenuBarExtra's status item — same
    /// trick the view model uses to programmatically open the panel.
    /// Skips the AppKit hop when nothing changed so the label closure's
    /// hot path doesn't pay for it on every timer tick.
    private static var lastAppliedTooltip: String?
    private static func applyStatusItemTooltip(_ tooltip: String) {
        // The body closure that calls this re-runs on every
        // observable change — short-circuit before doing any AppKit
        // work when the tooltip text hasn't moved.
        guard tooltip != lastAppliedTooltip else { return }
        lastAppliedTooltip = tooltip
        MenuBarStatusItem.button?.toolTip = tooltip.isEmpty ? nil : tooltip
    }

    /// Compose the full menu bar image: [tracking dot] [time text] [state icon]
    /// Draws into a single NSImage so MenuBarExtra renders it reliably.
    private func composedMenuBarImage(label: String, icon: TimeComparisonViewModel.MenuBarIcon, mode: MenuBarLabelMode) -> NSImage {
        let key = MenuBarImageKey(label: label, icon: icon, mode: mode)
        if let cached = Self.cache, cached.key == key {
            return cached.image
        }

        let image = renderMenuBarImage(label: label, icon: icon, mode: mode)
        Self.cache = (key, image)
        return image
    }

    private func renderMenuBarImage(label: String, icon: TimeComparisonViewModel.MenuBarIcon, mode: MenuBarLabelMode) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textColor = NSColor.black
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        // Resolve symbol name and rotation behavior from icon state
        let symbolName: String
        let rotationProgress: Double?  // nil = no rotation
        switch icon {
        case .calendar:
            symbolName = "calendar"
            rotationProgress = nil
        case .gaugeUnder(let progress):
            symbolName = "gauge.with.needle"
            rotationProgress = progress
        case .gaugeOver:
            symbolName = "exclamationmark.circle.fill"
            rotationProgress = nil
        case .timer:
            symbolName = "timer"
            rotationProgress = nil
        case .paused:
            symbolName = "pause.circle.fill"
            rotationProgress = nil
        case .timeOff:
            symbolName = "moon.zzz.fill"
            rotationProgress = nil
        case .error:
            symbolName = "exclamationmark.triangle"
            rotationProgress = nil
        }

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let iconBase = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Yield")
            .flatMap { $0.withSymbolConfiguration(iconConfig) }
            ?? NSImage(size: NSSize(width: 14, height: 14))

        let iconSize = iconBase.size
        let barHeight: CGFloat = max(iconSize.height, 18)
        let spacing: CGFloat = 4
        let iconSlotWidth = Self.iconSlotWidth

        // Fixed-width text area — measure widest *realistic* string
        // to prevent width jitter. The left side of paired modes is
        // typically a single-digit hour (current entry / running
        // timer / today's working hours so far), so reserving slot
        // for only one digit there saves ~7pt in the common case.
        // Trade-off: when the left side actually crosses 10h (e.g.
        // a long week's tracked total) the menu bar shifts right by
        // a single digit's width. Rare and small enough to be a fair
        // exchange for the day-to-day tighter layout.
        let maxLabel = mode == .currentTimer ? "88:88" : "8:88 / 88:88"
        let reservedTextWidth: CGFloat = (maxLabel as NSString).size(withAttributes: attrs).width
        let textSize: CGSize = label.isEmpty ? .zero : (label as NSString).size(withAttributes: attrs)
        // The reserved width covers the typical case; when the actual
        // label is wider (e.g. left side crosses 10h: "10:17 / 12:00")
        // grow the slot to fit so the trailing digits aren't clipped.
        // The menu bar shifts by exactly the overflow on those rare
        // wider strings — the documented trade-off.
        let textSlotWidth: CGFloat = max(reservedTextWidth, textSize.width)

        // Calculate total width. Icon slot is fixed (different SF
        // Symbols have different intrinsic widths, so reserving the
        // widest prevents jitter when state flips). Text slot is
        // sized to the realistic max but grows for the rare wider
        // labels rather than clipping.
        var totalWidth: CGFloat = iconSlotWidth
        if !label.isEmpty {
            totalWidth += textSlotWidth + spacing
        }

        let image = NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { rect in
            var x: CGFloat = 0

            // Icon — drawn first (leading edge), centered within the
            // fixed-width slot so narrower icons (pause.circle.fill,
            // gauge) sit middle-aligned rather than pinned to the
            // slot's leading edge.
            let iconY = (barHeight - iconSize.height) / 2
            let iconX = x + (iconSlotWidth - iconSize.width) / 2
            x += iconSlotWidth

            // Time text — left-aligned within fixed-width area so it
            // sits snug against the icon. The slot's width is still
            // reserved against the widest possible string ("88:88 /
            // 88:88") so the overall menu bar width stays stable
            // regardless of the current label.
            if !label.isEmpty {
                x += spacing
                let textY = (barHeight - textSize.height) / 2
                (label as NSString).draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
            }

            // Tint the icon to match text color
            let tintedIcon = NSImage(size: iconSize, flipped: false) { iconRect in
                guard let ctx = NSGraphicsContext.current?.cgContext,
                      let cgImage = iconBase.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
                ctx.clip(to: iconRect, mask: cgImage)
                ctx.setFillColor(textColor.cgColor)
                ctx.fill(iconRect)
                return true
            }

            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            if let progress = rotationProgress {
                // Needle calibration (convention: 0° = straight up, clockwise positive).
                //   Default needle (gauge.with.needle): 315° (10:30, upper-left)
                //   Target sweep:
                //     0%   → 225° (7:30, lower-left)
                //     50%  → 0°   (12:00, straight up)
                //     100% → 135° (4:30, lower-right)
                //   Total sweep: 270° clockwise, passing through 12:00.
                //
                // Converting to CGContext math angles (CCW positive from east):
                //   neutral   = 135°
                //   target(p) = -135° - 270° * p
                //   rotation  = target - neutral = 90° - 270° * p
                //             = (0.5 - 1.5 * p) * π radians
                let rotation = (0.5 - 1.5 * progress) * .pi
                let iconCenterX = iconX + iconSize.width / 2
                let iconCenterY = iconY + iconSize.height / 2
                ctx.translateBy(x: iconCenterX, y: iconCenterY)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -iconCenterX, y: -iconCenterY)
            }
            tintedIcon.draw(in: CGRect(x: iconX, y: iconY, width: iconSize.width, height: iconSize.height))
            ctx.restoreGState()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Widest of every menu-bar SF Symbol at the configured point
    /// size + weight, measured once and cached. Without this the
    /// total menu-bar width drifts a few points when the state
    /// changes between symbols of different intrinsic widths,
    /// nudging the system clock and every neighboring menu-bar
    /// item to the right or left.
    private static let iconSlotWidth: CGFloat = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbolNames = [
            "calendar",
            "gauge.with.needle",
            "exclamationmark.circle.fill",
            "timer",
            "pause.circle.fill",
            "moon.zzz.fill",
            "exclamationmark.triangle",
        ]
        let widths = symbolNames.compactMap { name -> CGFloat? in
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)?
                .size.width
        }
        // Fallback matches the 14pt symbol's nominal square footprint
        // — only hit if every symbol lookup somehow fails, which would
        // mean the system is broken in deeper ways than this.
        return widths.max() ?? 18
    }()
}
