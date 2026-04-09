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
    @State private var showNewTimerForm = false
    @State private var editingEntry: TimeEntryInfo? = nil
    @State private var preselectedProjectId: Int? = nil
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if viewModel.idleAlertState != nil {
                    IdleAlertView(viewModel: viewModel)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else if showSettings {
                    SettingsView(oAuthService: AppState.shared.oAuthService) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSettings = false
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if showNewTimerForm || editingEntry != nil {
                    NewTimerFormView(
                        viewModel: viewModel,
                        editingEntry: editingEntry,
                        preselectedProjectId: preselectedProjectId
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNewTimerForm = false
                            editingEntry = nil
                            preselectedProjectId = nil
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if !viewModel.isConfigured {
                    notConfiguredView
                        .transition(.opacity)
                } else if viewModel.isLoading && viewModel.projectStatuses.isEmpty {
                    loadingView
                        .transition(.opacity)
                } else if let error = viewModel.errorMessage, viewModel.projectStatuses.isEmpty {
                    errorView(error)
                        .transition(.opacity)
                } else {
                    contentView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSettings)
            .animation(.easeInOut(duration: 0.2), value: showNewTimerForm)
            .animation(.easeInOut(duration: 0.2), value: editingEntry?.id)
            .animation(.easeInOut(duration: 0.2), value: viewModel.idleAlertState != nil)

            if viewModel.idleAlertState == nil && !showSettings && !showNewTimerForm && editingEntry == nil {
                footerView
                    .transition(.opacity)
            }
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
        .background(OpaqueMenuBarPanel())
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if !viewModel.serviceErrors.isEmpty {
                serviceWarningBanner
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            if viewModel.isTimerBannerVisible {
                TimerBannerView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Inactive timer slot — subtle green gradient bar
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                YieldColors.greenAccent.opacity(0.15),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: UnitPoint(x: 0.7, y: 0.5)
                        )
                    )
                    .frame(height: 16)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(YieldColors.border)
                            .frame(height: 1)
                    }
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
                        },
                        onEditEntry: { entry in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                editingEntry = entry
                            }
                        },
                        onDeleteEntry: { entry in
                            Task { await viewModel.deleteTimeEntry(entryId: entry.id) }
                        },
                        onStartTimerForProject: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                preselectedProjectId = project.harvestProjectId
                                showNewTimerForm = true
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(viewModel.weekLabel)
                .font(YieldFonts.titleMedium)
                .foregroundStyle(YieldColors.textPrimary)

            Spacer()

            tabToggle

            timerButton
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private var tabToggle: some View {
        HStack(spacing: 0) {
            ForEach(TimeComparisonViewModel.ProjectTab.allCases, id: \.self) { tab in
                let isSelected = viewModel.selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    Text(tab == .recent ? "Recent" : "Forecasted")
                        .font(isSelected
                            ? YieldFonts.dmSans(10, weight: .semibold)
                            : YieldFonts.dmSans(10, weight: .medium))
                        .foregroundStyle(isSelected
                            ? YieldColors.textPrimary
                            : YieldColors.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .frame(height: 20)
                        .background(isSelected
                            ? Color(red: 0.184, green: 0.188, blue: 0.200)
                            : Color(red: 0.141, green: 0.145, blue: 0.149))
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
        .frame(height: 22)
    }

    private var timerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showNewTimerForm.toggle()
            }
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
                .foregroundStyle(YieldColors.textSecondary)
            Text("Sign in to connect your Harvest and Forecast accounts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
            Button("Sign in with Harvest") {
                AppState.shared.oAuthService.startOAuthFlow()
            }
            .buttonStyle(.greenOutlined)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(YieldColors.yellowAccent)

            if !viewModel.serviceErrors.isEmpty {
                ForEach(viewModel.serviceErrors) { error in
                    Text("\(error.service.rawValue) — \(error.message)")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(YieldColors.textSecondary)
                        .font(YieldFonts.dmSans(11))
                }
            } else {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(YieldColors.textSecondary)
                    .font(YieldFonts.dmSans(11))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Service Warning Banner

    private var serviceWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(YieldColors.yellowAccent)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.serviceErrors) { error in
                    Text("\(error.service.rawValue) — \(error.message)")
                        .font(YieldFonts.dmSans(10))
                        .foregroundStyle(YieldColors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(YieldColors.yellowFaint)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                if let url = URL(string: "https://github.com/vigetlabs/yield-app/issues/new") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Report a bug")

            Spacer()

            Menu {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                Button("Settings...") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSettings = true
                    }
                }

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
                for case let effectView as NSVisualEffectView in contentView.subviews {
                    effectView.state = .inactive
                    effectView.material = .windowBackground
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
