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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        AppState.shared.updaterController = updaterController
        AppState.shared.start()
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
            if label.isEmpty {
                Image(nsImage: menuBarIcon(tracking: nil, progress: 0))
            } else {
                HStack(spacing: 4) {
                    Image(nsImage: menuBarIcon(tracking: tracking, progress: progress))
                    Text(label)
                }
            }
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
        return effective / project.bookedHours
    }

    private func gaugeSymbolName(progress: Double) -> String {
        switch progress {
        case ..<0.17: return "gauge.with.dots.needle.0percent"
        case ..<0.42: return "gauge.with.dots.needle.33percent"
        case ..<0.59: return "gauge.with.dots.needle.50percent"
        case ..<0.84: return "gauge.with.dots.needle.67percent"
        default:      return "gauge.with.dots.needle.100percent"
        }
    }

    private func statusColor(for project: ProjectStatus) -> NSColor {
        let effective = viewModel.effectiveLoggedHours(for: project)
        let threshold = max(project.bookedHours * 0.1, 0.5)
        if effective > project.bookedHours + threshold { return NSColor(red: 0.80, green: 0.45, blue: 0.40, alpha: 1.0) }
        if effective < project.bookedHours - threshold { return NSColor(red: 0.55, green: 0.75, blue: 0.50, alpha: 1.0) }
        return NSColor(red: 0.85, green: 0.78, blue: 0.45, alpha: 1.0)
    }

    private func menuBarIcon(tracking: ProjectStatus?, progress: Double) -> NSImage {
        let symbolName = tracking != nil ? gaugeSymbolName(progress: progress) : "gauge.with.dots.needle.0percent"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Yield")!
            .withSymbolConfiguration(config)!
        if let tracking {
            let tintColor = statusColor(for: tracking)
            let size = image.size
            let colored = NSImage(size: size, flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ctx.clip(to: rect, mask: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                ctx.setFillColor(tintColor.cgColor)
                ctx.fill(rect)
                return true
            }
            colored.isTemplate = false
            return colored
        }
        image.isTemplate = true
        return image
    }
}
