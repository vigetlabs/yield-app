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
    var updaterController: SPUStandardUpdaterController?
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
        // Register defaults so @AppStorage and UserDefaults agree on initial values
        UserDefaults.standard.register(defaults: [
            "idleDetectionEnabled": true,
            "idleMinutes": 10,
        ])

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        AppState.shared.updaterController = updaterController
        AppState.shared.start()

        // Force dark mode until light/system modes are designed
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Refresh whenever the MenuBarExtra panel opens, so state reflects
        // any changes made outside the app (e.g. starting a timer in Harvest).
        // Throttled to avoid excess API calls when opening/closing rapidly.
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
                await AppState.shared.viewModel.refreshIfStale()
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
}

@main
struct YieldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private var viewModel: TimeComparisonViewModel { AppState.shared.viewModel }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            let isTracking = viewModel.projectStatuses.contains(where: { $0.isTracking })
            Image(nsImage: composedMenuBarImage(
                label: viewModel.menuBarLabel,
                icon: viewModel.menuBarIcon,
                isTracking: isTracking
            ))
        }
        .menuBarExtraStyle(.window)

    }

    /// Memoization key for `composedMenuBarImage`. MenuBarIcon is already
    /// Equatable so this gets automatic synthesis.
    private struct MenuBarImageKey: Equatable {
        let label: String
        let icon: TimeComparisonViewModel.MenuBarIcon
        let isTracking: Bool
    }

    /// Process-global cache for the composed menu bar image. SwiftUI re-runs
    /// the MenuBarExtra label closure on every observable mutation (timer
    /// tick, each refresh), but the rendered image only changes when the
    /// label text, icon, or tracking dot does. Without this cache we'd
    /// allocate an NSImage + re-render an SF Symbol + measure attributed
    /// strings multiple times per minute even when nothing visibly changed.
    private static var cache: (key: MenuBarImageKey, image: NSImage)?

    /// Compose the full menu bar image: [tracking dot] [time text] [state icon]
    /// Draws into a single NSImage so MenuBarExtra renders it reliably.
    private func composedMenuBarImage(label: String, icon: TimeComparisonViewModel.MenuBarIcon, isTracking: Bool) -> NSImage {
        let key = MenuBarImageKey(label: label, icon: icon, isTracking: isTracking)
        if let cached = Self.cache, cached.key == key {
            return cached.image
        }

        let image = renderMenuBarImage(label: label, icon: icon, isTracking: isTracking)
        Self.cache = (key, image)
        return image
    }

    private func renderMenuBarImage(label: String, icon: TimeComparisonViewModel.MenuBarIcon, isTracking: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textColor = NSColor.black
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        // Resolve symbol name and rotation behavior from icon state
        let symbolName: String
        let rotationProgress: Double?  // nil = no rotation
        switch icon {
        case .calendar:
            symbolName = "calendar.day.timeline.left"
            rotationProgress = nil
        case .gaugeUnder(let progress):
            symbolName = "gauge.with.needle"
            rotationProgress = progress
        case .gaugeOver:
            symbolName = "gauge.open.with.lines.needle.84percent.exclamation"
            rotationProgress = nil
        case .timer:
            symbolName = "timer"
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
        let dotSize: CGFloat = 6

        // Fixed-width text area — measure widest possible string to prevent width jitter
        let maxLabel = "88:88 / 88:88"
        let fixedTextWidth: CGFloat = (maxLabel as NSString).size(withAttributes: attrs).width
        let textSize: CGSize = label.isEmpty ? .zero : (label as NSString).size(withAttributes: attrs)

        // Calculate total width (fixed regardless of label content)
        var totalWidth: CGFloat = iconSize.width
        if !label.isEmpty {
            totalWidth += fixedTextWidth + spacing
        }
        // Always reserve dot space so width doesn't shift when timer starts/stops
        totalWidth += dotSize + spacing

        let image = NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { rect in
            var x: CGFloat = 0

            // Tracking dot (always reserve space, only draw when tracking)
            if isTracking {
                let dotY = (barHeight - dotSize) / 2
                let dotRect = CGRect(x: x, y: dotY, width: dotSize, height: dotSize)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            x += dotSize + spacing

            // Time text — right-aligned within fixed-width area
            if !label.isEmpty {
                let textY = (barHeight - textSize.height) / 2
                let textX = x + (fixedTextWidth - textSize.width)
                (label as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                x += fixedTextWidth + spacing
            }

            // Icon — tint and optionally rotate
            let iconY = (barHeight - iconSize.height) / 2

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
                let iconCenterX = x + iconSize.width / 2
                let iconCenterY = iconY + iconSize.height / 2
                ctx.translateBy(x: iconCenterX, y: iconCenterY)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -iconCenterX, y: -iconCenterY)
            }
            tintedIcon.draw(in: CGRect(x: x, y: iconY, width: iconSize.width, height: iconSize.height))
            ctx.restoreGState()

            return true
        }
        image.isTemplate = true
        return image
    }
}
