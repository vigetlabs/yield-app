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
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.isConfigured {
                notConfiguredView
            } else if viewModel.isLoading && viewModel.projectStatuses.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.projectStatuses.isEmpty {
                errorView(error)
            } else {
                contentView
            }

            footerView
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
        .background(OpaqueMenuBarPanel())
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if viewModel.isTimerBannerVisible {
                TimerBannerView(viewModel: viewModel)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            if viewModel.filteredStatuses.isEmpty {
                Text("No projects found for this week.")
                    .foregroundStyle(YieldColors.textSecondary)
                    .font(YieldFonts.dmSans(11))
                    .padding(16)
            } else {
                ForEach(viewModel.filteredStatuses) { project in
                    ProjectRowView(
                        project: project,
                        effectiveLoggedHours: viewModel.effectiveLoggedHours(for: project),
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(viewModel.weekLabel)
                .font(YieldFonts.titleMedium)
                .foregroundStyle(YieldColors.textPrimary)

            Spacer()

            tabToggle
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private var tabToggle: some View {
        HStack(spacing: 2) {
            ForEach(TimeComparisonViewModel.ProjectTab.allCases, id: \.self) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    Text(tab == .recent ? "Recent" : "Forecasted")
                        .font(viewModel.selectedTab == tab
                            ? YieldFonts.dmSans(10, weight: .semibold)
                            : YieldFonts.dmSans(10, weight: .medium))
                        .foregroundStyle(viewModel.selectedTab == tab
                            ? YieldColors.textPrimary
                            : YieldColors.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .frame(height: 20)
                        .background(viewModel.selectedTab == tab
                            ? YieldColors.surfaceActive
                            : YieldColors.surfaceDefault)
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: tab == .recent ? YieldRadius.button : 0,
                                bottomLeadingRadius: tab == .recent ? YieldRadius.button : 0,
                                bottomTrailingRadius: tab == .forecasted ? YieldRadius.button : 0,
                                topTrailingRadius: tab == .forecasted ? YieldRadius.button : 0
                            )
                            .strokeBorder(YieldColors.border, lineWidth: 1)
                        )
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: tab == .recent ? YieldRadius.button : 0,
                            bottomLeadingRadius: tab == .recent ? YieldRadius.button : 0,
                            bottomTrailingRadius: tab == .forecasted ? YieldRadius.button : 0,
                            topTrailingRadius: tab == .forecasted ? YieldRadius.button : 0
                        ))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 22)
    }

    private var timerButton: some View {
        Button {
            // TODO: Phase 5 — open new timer form
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Timer")
                    .font(YieldFonts.labelButton)
            }
        }
        .buttonStyle(.greenOutlined)
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
                    .font(YieldFonts.dmSans(9))
                    .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
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
                    .font(.system(size: 12))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
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
