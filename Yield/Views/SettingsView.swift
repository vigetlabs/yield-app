import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let oAuthService: OAuthService
    let onDismiss: () -> Void

    @AppStorage(DefaultsKey.appearanceMode) private var appearanceMode: String = AppearanceMode.default.rawValue
    @AppStorage(DefaultsKey.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(DefaultsKey.idleMinutes) private var idleMinutes = 10
    @AppStorage(DefaultsKey.menuBarLabelMode) private var menuBarLabelMode: String = MenuBarLabelMode.projectTime.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// All Harvest projects the current user has access to, fetched
    /// when the Settings panel appears so the favorites card can
    /// resolve `(projectId, taskId)` pairs to human-readable names.
    @State private var allProjects: [TimeComparisonViewModel.TimerProjectOption] = []
    @State private var isLoadingProjects = false
    /// Bump on toggle so the favorites list re-derives from the store.
    private var favoritesStore: FavoritesStore { FavoritesStore.shared }

    /// Cap on the cards' scroll area so the Settings panel can't
    /// grow past the screen's visible frame on short displays. The
    /// `48` accounts for the back-button header + small breathing
    /// room. The `400` floor protects the very first frame before
    /// `NSScreen.main` is meaningful.
    private var settingsContentMaxHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(400, visible - 48)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(YieldFonts.dmSans(11, weight: .medium))
                    }
                    .foregroundStyle(YieldColors.textPrimary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(YieldFonts.dmSans(13, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)

                Spacer()

                // Invisible spacer to center title
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Back")
                        .font(YieldFonts.dmSans(11, weight: .medium))
                }
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)
            }

            // Content — scrollable so a long Settings panel (e.g.
            // many favorites) doesn't push past the menu-bar panel's
            // available height on short screens. `fixedSize(vertical:
            // true)` lets the scroll view shrink to its content's
            // ideal height when everything fits — same pattern the
            // main panel's project list uses.
            ScrollView {
                VStack(spacing: 12) {
                    accountCard
                    preferencesCard
                    favoritesCard
                    aboutCard
                }
                .padding(16)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: settingsContentMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            isLoadingProjects = true
            allProjects = (try? await AppState.shared.viewModel.fetchAllProjects()) ?? []
            isLoadingProjects = false
        }
    }

    // MARK: - Account Card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Account")

            if oAuthService.isAuthenticated {
                // User info
                HStack(spacing: 10) {
                    // Avatar circle
                    ZStack {
                        Circle()
                            .fill(YieldColors.greenAccent.opacity(0.15))
                        Text(initials)
                            .font(YieldFonts.dmSans(11, weight: .semibold))
                            .foregroundStyle(YieldColors.greenAccent)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        if let name = oAuthService.userName {
                            Text(name)
                                .font(YieldFonts.dmSans(12, weight: .semibold))
                                .foregroundStyle(YieldColors.textPrimary)
                        }
                        HStack(spacing: 6) {
                            if let harvestId = oAuthService.harvestAccountId {
                                accountBadge("Harvest \(harvestId)")
                            }
                            if let forecastId = oAuthService.forecastAccountId {
                                accountBadge("Forecast \(forecastId)")
                            }
                        }
                    }

                    Spacer()
                }
                .padding(12)

                // Divider
                Rectangle()
                    .fill(YieldColors.border)
                    .frame(height: 1)

                // Sign out row
                Button {
                    oAuthService.signOut()
                    Task {
                        await AppState.shared.viewModel.refresh()
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 10))
                        Text("Sign Out")
                            .font(YieldFonts.dmSans(11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your Harvest account to compare logged hours against Forecast bookings.")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineSpacing(2)

                    Button {
                        oAuthService.startOAuthFlow()
                    } label: {
                        HStack(spacing: 6) {
                            if oAuthService.isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 11))
                            }
                            Text("Sign in with Harvest")
                                .font(YieldFonts.dmSans(11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.greenOutlined)
                    .disabled(oAuthService.isAuthenticating)

                    if let error = oAuthService.authError {
                        Text(error)
                            .font(YieldFonts.dmSans(10))
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
            }
        }
        .yieldCard()
    }

    // MARK: - Preferences Card

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Preferences")

            // Launch at login
            settingsToggleRow(
                icon: "sunrise",
                label: "Launch at Login",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Appearance (System / Light / Dark)
            appearanceRow

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Menu bar display
            menuBarDisplayRow

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Idle detection
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 16)

                Toggle("Idle detection", isOn: $idleDetectionEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textPrimary)
                    .labelsHidden()

                Text("Idle detection after")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(idleDetectionEnabled ? YieldColors.textPrimary : YieldColors.textSecondary)

                TextField("", value: $idleMinutes, format: .number)
                    .font(YieldFonts.monoXS)
                    .foregroundStyle(YieldColors.textPrimary)
                    .textFieldStyle(.plain)
                    .frame(width: 26)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(YieldColors.background)
                    .yieldBorder(radius: YieldRadius.button)
                    .disabled(!idleDetectionEnabled)
                    .opacity(idleDetectionEnabled ? 1 : 0.4)
                    .onChange(of: idleMinutes) { _, newValue in
                        if newValue < 1 { idleMinutes = 1 }
                    }

                Text("min")
                    .font(YieldFonts.dmSans(10))
                    .foregroundStyle(YieldColors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .yieldCard()
    }

    // MARK: - Favorites Card

    /// Display row for a single favorite, used to populate the
    /// favorites card. Resolved at render time from `allProjects`.
    private struct FavoriteEntry: Identifiable {
        let projectId: Int
        let taskId: Int
        let clientName: String?
        let projectName: String
        let taskName: String

        var id: String { "\(projectId)-\(taskId)" }
    }

    /// Resolved favorites sorted alphabetically by client → project → task,
    /// with unresolved (project no longer accessible to the user) entries
    /// pushed to the bottom under a generic name so they're still removable.
    private var resolvedFavorites: [FavoriteEntry] {
        let projectsById = allProjects.indexed(by: \.harvestProjectId)
        let entries: [FavoriteEntry] = favoritesStore.favorites.map { fav in
            let project = projectsById[fav.projectId]
            let task = project?.taskAssignments.first(where: { $0.task.id == fav.taskId })?.task
            return FavoriteEntry(
                projectId: fav.projectId,
                taskId: fav.taskId,
                clientName: project?.clientName,
                projectName: project?.projectName ?? "Unknown project",
                taskName: task?.name ?? "Unknown task"
            )
        }
        return entries.sorted { a, b in
            // Resolved (has a real project) first, then alphabetical.
            let aResolved = a.projectName != "Unknown project"
            let bResolved = b.projectName != "Unknown project"
            if aResolved != bResolved { return aResolved }
            let ac = a.clientName ?? ""
            let bc = b.clientName ?? ""
            if ac != bc { return ac.localizedCaseInsensitiveCompare(bc) == .orderedAscending }
            if a.projectName != b.projectName {
                return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
            }
            return a.taskName.localizedCaseInsensitiveCompare(b.taskName) == .orderedAscending
        }
    }

    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Favorites")

            if isLoadingProjects && resolvedFavorites.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .tint(YieldColors.textSecondary)
                    Text("Loading…")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else if resolvedFavorites.isEmpty {
                Text("No favorites yet. Add one from the new/edit timer screen.")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                // Cap the list at ~3 rows of height with a partial 4th
                // row peeking, so 4+ favorites trigger scrolling.
                // `fixedSize(vertical: true)` lets the scroll view
                // shrink to its content's natural height when there
                // are few favorites — the cap only kicks in once the
                // list would overflow.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(resolvedFavorites.enumerated()), id: \.element.id) { index, fav in
                            favoriteRow(fav)
                            if index < resolvedFavorites.count - 1 {
                                Rectangle()
                                    .fill(YieldColors.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .yieldCard()
    }

    private func favoriteRow(_ fav: FavoriteEntry) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProjectStatus.qualifiedName(client: fav.clientName, project: fav.projectName))
                    .font(YieldFonts.dmSans(11, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(fav.taskName)
                    .font(YieldFonts.dmSans(10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button {
                favoritesStore.remove(projectId: fav.projectId, taskId: fav.taskId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove favorite")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("About")

            // Version + Check for Updates inline so the action sits
            // alongside the info it acts on.
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 16)
                Text("Version")
                    .font(YieldFonts.dmSans(11))
                    .foregroundStyle(YieldColors.textSecondary)
                Text(appVersion)
                    .font(YieldFonts.monoXS)
                    .foregroundStyle(YieldColors.textPrimary)
                Spacer()
                Button {
                    // Close the MenuBarExtra panel first — it runs at
                    // `.statusBar` window level, which sits above
                    // Sparkle's normal-level update window. Without
                    // closing it, the Sparkle dialog opens *behind*
                    // the popup and can look like nothing happened.
                    if let panel = NSApp.windows.first(where: {
                        String(describing: type(of: $0)).contains("MenuBarExtra")
                    }) {
                        panel.orderOut(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                    AppState.shared.updaterController?.checkForUpdates(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Check for Updates")
                            .font(YieldFonts.dmSans(10, weight: .semibold))
                    }
                }
                .buttonStyle(.greenOutlined)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)

            // Reveal logs in Finder — utility row for attaching
            // logs to a bug report.
            Button {
                LogStore.shared.revealInFinder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(YieldColors.textSecondary)
                        .frame(width: 16)
                    Text("Reveal Logs in Finder")
                        .font(YieldFonts.dmSans(11))
                        .foregroundStyle(YieldColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open ~/Library/Logs/Yield in Finder so you can attach logs to a bug report")
        }
        .yieldCard()
    }

    // MARK: - Helpers

    private var initials: String {
        guard let name = oAuthService.userName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ", omittingEmptySubsequences: true)
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? (parts.last.map { String($0.prefix(1)) } ?? "") : ""
        let result = (first + last).uppercased()
        return result.isEmpty ? "?" : result
    }

    private func accountBadge(_ text: String) -> some View {
        Text(text)
            .font(YieldFonts.dmSans(8, weight: .medium))
            .foregroundStyle(YieldColors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(YieldColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(YieldFonts.dmSans(9, weight: .semibold))
            .foregroundStyle(YieldColors.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var appearanceRow: some View {
        enumPickerRow(
            icon: "circle.lefthalf.filled",
            label: "Appearance",
            cases: AppearanceMode.allCases,
            selectedRawValue: appearanceMode,
            title: \.label
        ) { appearanceMode = $0 }
    }

    private var menuBarDisplayRow: some View {
        enumPickerRow(
            icon: "menubar.rectangle",
            label: "Menu bar display",
            cases: MenuBarLabelMode.allCases,
            selectedRawValue: menuBarLabelMode,
            title: \.label
        ) { menuBarLabelMode = $0 }
    }

    /// Settings row that binds a string-backed enum to a `DropdownPicker`.
    /// The picker is keyed by `Int` tags so we use each case's `allCases`
    /// index as the id.
    private func enumPickerRow<T: RawRepresentable>(
        icon: String,
        label: String,
        cases: [T],
        selectedRawValue: String,
        title: KeyPath<T, String>,
        onSelect: @escaping (String) -> Void
    ) -> some View where T.RawValue == String {
        let items = cases.enumerated().map { (id: $0.offset, title: $0.element[keyPath: title]) }
        let selectedId = cases.firstIndex { $0.rawValue == selectedRawValue } ?? 0

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 16)
            Text(label)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textPrimary)
            Spacer()
            DropdownPicker(
                label: label,
                placeholder: "Select",
                items: items,
                selectedId: selectedId
            ) { id in
                guard cases.indices.contains(id) else { return }
                onSelect(cases[id].rawValue)
            }
            .frame(width: YieldDimensions.settingsRowControlWidth)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func settingsToggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 16)
            Text(label)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version)"
    }
}
