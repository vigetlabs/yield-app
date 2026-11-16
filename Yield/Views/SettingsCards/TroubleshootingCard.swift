import SwiftUI

/// The last section of Settings: the things you reach for when
/// something looks wrong. Kept apart from the everyday settings so the
/// two resets aren't a stray click away from a toggle.
struct TroubleshootingCard: View {
    private let viewModel: TimeComparisonViewModel = AppState.shared.viewModel

    @State private var showResetConfirm = false
    @State private var showForgetConfirm = false
    /// `MeetingHistoryStore` isn't observable (nothing else binds to
    /// it), so the count is read on appear and after a forget.
    @State private var rememberedCount = MeetingHistoryStore.shared.memories.count

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardSectionHeader("Troubleshooting")

            syncRow

            SettingsRowDivider()

            // Reveal logs in Finder — utility row for attaching
            // logs to a bug report.
            Button {
                LogStore.shared.revealInFinder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .settingsRowIcon()
                    Text("Reveal Logs in Finder")
                        .font(YieldFonts.settingsLabel())
                        .foregroundStyle(YieldColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
                }
                .settingsRowPadding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open ~/Library/Logs/Yield in Finder so you can attach logs to a bug report")

            SettingsRowDivider()

            // Inline confirmations, as for Sign Out: a system dialog
            // from this panel would dismiss the panel and cancel itself.
            if showResetConfirm {
                InlineConfirmationRow(
                    message: "Put every setting back to its default?",
                    confirmLabel: "Reset",
                    onCancel: { showResetConfirm = false },
                    onConfirm: {
                        showResetConfirm = false
                        PreferencesReset.reset()
                        // The theme is held live by its store as well
                        // as in defaults.
                        ThemeStore.shared.select(.default)
                    }
                )
                .settingsBlockPadding()
            } else {
                actionRow(
                    icon: "arrow.counterclockwise",
                    label: "Reset Preferences",
                    help: "Puts every setting back to its default. Your sign-ins, favorites and muted meetings are kept."
                ) { showResetConfirm = true }
            }

            SettingsRowDivider()

            if showForgetConfirm {
                InlineConfirmationRow(
                    message: "Forget which project each meeting goes to?",
                    confirmLabel: "Forget All",
                    onCancel: { showForgetConfirm = false },
                    onConfirm: {
                        showForgetConfirm = false
                        MeetingHistoryStore.shared.forgetAll()
                        rememberedCount = 0
                    }
                )
                .settingsBlockPadding()
            } else {
                actionRow(
                    icon: "calendar.badge.minus",
                    label: "Forget Remembered Meetings",
                    detail: rememberedCount == 0 ? "None" : "\(rememberedCount)",
                    help: "Yield remembers which project and task you used for each meeting title, and starts those meetings' timers there in one click. Forgetting them makes it ask again the next time."
                ) { showForgetConfirm = true }
                .disabled(rememberedCount == 0)
                .opacity(rememberedCount == 0 ? 0.5 : 1)
            }
        }
        .settingsCard()
        .onAppear { rememberedCount = MeetingHistoryStore.shared.memories.count }
    }

    // MARK: - Rows

    /// "Last synced 2 min ago" with a Sync Now button. The panel syncs
    /// on its own; this is for the one thing that doesn't reload on
    /// demand anywhere else — the calendar, cached for a few minutes —
    /// and for seeing when the numbers on screen are from.
    private var syncRow: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .settingsRowIcon()
            Text("Last synced")
                .font(YieldFonts.settingsLabel())
                .foregroundStyle(YieldColors.textSecondary)
            // Re-evaluated on a timer so "2 min ago" keeps moving
            // while Settings sits open.
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Text(viewModel.isLoading
                     ? "Syncing…"
                     : Self.lastSyncedText(viewModel.lastUpdated, now: timeline.date))
                    .font(YieldFonts.settingsValue)
                    .foregroundStyle(YieldColors.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await viewModel.syncNow() }
            } label: {
                Text("Sync Now")
                    .font(YieldFonts.settingsButton(10))
            }
            .buttonStyle(.greenOutlined)
            .disabled(viewModel.isLoading || !viewModel.isConfigured)
            .help("Reload everything from Harvest and Forecast, and your calendar from Google")
        }
        .settingsRowPadding()
    }

    /// A row that does something when clicked, with an optional value
    /// before the chevron.
    private func actionRow(
        icon: String,
        label: String,
        detail: String? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .settingsRowIcon()
                Text(label)
                    .font(YieldFonts.settingsLabel())
                    .foregroundStyle(YieldColors.textPrimary)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(YieldFonts.settingsCaption)
                        .foregroundStyle(YieldColors.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
            }
            .settingsRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// "just now", "2 min ago", "1 hr ago", or "never".
    static func lastSyncedText(_ date: Date?, now: Date) -> String {
        guard let date else { return "never" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) hr ago"
    }
}
