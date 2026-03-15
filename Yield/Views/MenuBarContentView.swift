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
        .frame(width: 460)
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Week header
            Text(viewModel.weekLabel)
                .font(.headline)

            // Total summary
            HStack {
                Text("Total")
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
                        }
                    )
                }
            }
        }
    }

    private var totalLabel: String {
        let logged = formatDecimalHours(viewModel.totalLogged)
        let booked = formatDecimalHours(viewModel.totalBooked)
        return "\(logged) / \(booked)"
    }

    private func formatDecimalHours(_ hours: Double) -> String {
        if hours == 0 { return "0h" }
        if hours == hours.rounded() {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }

    // MARK: - States

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "gear")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Set up your API credentials to get started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SettingsLink {
                Text("Open Settings")
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
        VStack(alignment: .leading, spacing: 6) {
            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                Spacer()

                SettingsLink {
                    Text("Settings...")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
        }
    }
}
