import AppKit
import Sparkle
import SwiftUI
import UserNotifications

@Observable
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
            let tracking = viewModel.projectStatuses.first(where: { $0.isTracking })
            let label = viewModel.menuBarLabel
            let progress = trackingProgress(tracking)
            Image(nsImage: composedMenuBarImage(
                label: label,
                isTracking: tracking != nil,
                progress: progress
            ))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(oAuthService: AppState.shared.oAuthService)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }

    private func trackingProgress(_ project: ProjectStatus?) -> Double {
        guard let project, project.bookedHours > 0 else { return 0 }
        let effective = viewModel.effectiveLoggedHours(for: project)
        return min(effective / project.bookedHours, 1.0)
    }

    /// Compose the full menu bar image: [green dot] [time text] [gauge icon]
    /// Draws into a single NSImage so MenuBarExtra renders it reliably.
    private func composedMenuBarImage(label: String, isTracking: Bool, progress: Double) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textColor = NSColor.black
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        // Gauge icon
        let gaugeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let gaugeBase = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Yield")!
            .withSymbolConfiguration(gaugeConfig)!

        let gaugeSize = gaugeBase.size
        let barHeight: CGFloat = max(gaugeSize.height, 18)
        let spacing: CGFloat = 4
        let dotSize: CGFloat = 6

        // Fixed-width text area — measure widest possible string to prevent width jitter
        let maxLabel = "88:88 over"
        let fixedTextWidth: CGFloat = (maxLabel as NSString).size(withAttributes: attrs).width
        let textSize: CGSize = label.isEmpty ? .zero : (label as NSString).size(withAttributes: attrs)

        // Calculate total width (fixed regardless of label content)
        var totalWidth: CGFloat = gaugeSize.width
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

            // Gauge icon — tint and rotate based on progress
            // Rotation: progress 0 → -90° (needle left), 0.5 → 0° (center), 1 → +90° (right)
            let rotation = (progress - 0.5) * 180.0 * (.pi / 180.0)
            let gaugeY = (barHeight - gaugeSize.height) / 2
            let gaugeCenterX = x + gaugeSize.width / 2
            let gaugeCenterY = gaugeY + gaugeSize.height / 2

            // Tint the gauge to match text color
            let tintedGauge = NSImage(size: gaugeSize, flipped: false) { gaugeRect in
                guard let ctx = NSGraphicsContext.current?.cgContext,
                      let cgImage = gaugeBase.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
                ctx.clip(to: gaugeRect, mask: cgImage)
                ctx.setFillColor(textColor.cgColor)
                ctx.fill(gaugeRect)
                return true
            }

            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: gaugeCenterX, y: gaugeCenterY)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -gaugeCenterX, y: -gaugeCenterY)
            tintedGauge.draw(in: CGRect(x: x, y: gaugeY, width: gaugeSize.width, height: gaugeSize.height))
            ctx.restoreGState()

            return true
        }
        image.isTemplate = true
        return image
    }
}
