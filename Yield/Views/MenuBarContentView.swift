import SwiftUI

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
        let logged = formatDecimalHours(viewModel.totalLogged)
        let booked = formatDecimalHours(viewModel.totalBooked)
        let base = "\(logged) / \(booked)"
        if viewModel.totalUnbookedLogged > 0 {
            let unbooked = formatDecimalHours(viewModel.totalUnbookedLogged)
            return "\(base) (+ \(unbooked) unbooked)"
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
            SettingsLink {
                Text("Other options...")
            }
            .font(.caption)
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
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}
