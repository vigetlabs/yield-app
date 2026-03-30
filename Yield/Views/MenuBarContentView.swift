import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

struct MenuBarContentView: View {
    let viewModel: TimeComparisonViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.isConfigured {
                notConfiguredView
            } else if viewModel.isLoading && viewModel.projectStatuses.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.projectStatuses.isEmpty {
                errorView(error)
            } else {
                contentView
            }

            Divider()

            footerView
        }
        .padding(12)
        .frame(width: 480)
        .background(OpaqueMenuBarPanel())
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Week header
            Text(viewModel.weekLabel)
                .font(.headline)

            // Total summary
            HStack {
                Text("Today: \(formatDecimalHours(viewModel.totalTodayLogged))")
                    .fontWeight(.medium)
                Spacer()
                Text(totalLabel)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            if viewModel.projectStatuses.isEmpty {
                Text("No projects found for this week.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(viewModel.projectStatuses) { project in
                    ProjectRowView(
                        project: project,
                        effectiveLoggedHours: viewModel.effectiveLoggedHours(for: project),
                        totalWeeklyBookedHours: viewModel.totalBooked,
                        onToggleTimer: {
                            Task { await viewModel.toggleTimer(for: project) }
                        },
                        onToggleEntryTimer: { entryId, isRunning in
                            Task { await viewModel.toggleEntryTimer(entryId: entryId, isRunning: isRunning) }
                        }
                    )
                }
            }
        }
    }

    private var totalLabel: String {
        let totalLogged = viewModel.totalLogged + viewModel.totalUnbookedLogged
        let target = max(viewModel.totalBooked, 40.0)
        let logged = formatDecimalHours(totalLogged)
        let targetStr = formatDecimalHours(target)
        let base = "\(logged) / \(targetStr)"
        if viewModel.totalUnbookedLogged > 0 {
            let unbooked = formatDecimalHours(viewModel.totalUnbookedLogged)
            return "\(base) (\(unbooked) unbooked)"
        }
        return base
    }

    private func formatDecimalHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - States

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Sign in to connect your Harvest and Forecast accounts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Sign in with Harvest") {
                AppState.shared.oAuthService.startOAuthFlow()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                SettingsLink {
                    Text("Settings...")
                }

                Button("Check for Updates...") {
                    NSApp.activate(ignoringOtherApps: true)
                    AppState.shared.updaterController?.checkForUpdates(nil)
                }

                Divider()

                Text(appVersion)

                Divider()

                Button("Quit Yield") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - About

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version)"
    }
}

// MARK: - Opaque Panel Background

private struct OpaqueMenuBarPanel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            // Remove the visual effect (vibrancy) view if present
            if let contentView = window.contentView {
                for subview in contentView.subviews where subview is NSVisualEffectView {
                    (subview as! NSVisualEffectView).state = .inactive
                    (subview as! NSVisualEffectView).material = .windowBackground
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
