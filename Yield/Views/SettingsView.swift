import SwiftUI

struct SettingsView: View {
    let oAuthService: OAuthService
    let onDismiss: () -> Void

    /// All Harvest projects the current user has access to, fetched
    /// when the Settings panel appears so the favorites card can
    /// resolve `(projectId, taskId)` pairs to human-readable names.
    @State private var allProjects: [TimeComparisonViewModel.TimerProjectOption] = []
    @State private var isLoadingProjects = false

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
            SettingsHeader(onDismiss: onDismiss)

            // Content — scrollable so a long Settings panel (e.g.
            // many favorites) doesn't push past the menu-bar panel's
            // available height on short screens. `fixedSize(vertical:
            // true)` lets the scroll view shrink to its content's
            // ideal height when everything fits — same pattern the
            // main panel's project list uses.
            ScrollView {
                SettingsCardStack(
                    oAuthService: oAuthService, onDismiss: onDismiss,
                    allProjects: allProjects, isLoadingProjects: isLoadingProjects
                )
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
}

/// The Settings panel's title bar: back button, centered title.
/// A view of its own so the snapshot harness can render it.
struct SettingsHeader: View {
    let onDismiss: () -> Void

    var body: some View {
        if SettingsStyle.refreshed {
            // No rule: the first section's band draws it.
            SubpageTitleBar(title: "Settings", onBack: onDismiss, ruled: false)
        } else {
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(YieldFonts.label(11, weight: .medium))
                    }
                    .foregroundStyle(YieldColors.textPrimary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(YieldFonts.label(13, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)

                Spacer()

                // Invisible spacer to center title
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Back")
                        .font(YieldFonts.label(11, weight: .medium))
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
        }
    }
}

/// The Settings cards, in order, with the panel's margins. A view of
/// its own — outside the `ScrollView` that hosts it — so the snapshot
/// harness can render it (`ImageRenderer` can't draw a scroll view).
struct SettingsCardStack: View {
    let oAuthService: OAuthService
    let onDismiss: () -> Void
    let allProjects: [TimeComparisonViewModel.TimerProjectOption]
    let isLoadingProjects: Bool

    var body: some View {
        // System: the sections are bands that run edge to edge, so
        // there is no gap between them and no margin around them.
        VStack(spacing: SettingsStyle.refreshed ? 0 : 12) {
            // Account leads: nothing else works until Harvest is
            // connected. Then the app's own housekeeping, how it looks,
            // the calendar, how it tracks, the two lists, and last the
            // things you only reach for when something looks wrong.
            AccountCard(oAuthService: oAuthService, onDismiss: onDismiss)
            GeneralCard()
            DisplayCard()
            GoogleCalendarCard()
            TrackingCard()
            FavoritesCard(allProjects: allProjects, isLoadingProjects: isLoadingProjects)
            MutedMeetingsCard()
            TroubleshootingCard()
        }
        .padding(SettingsStyle.refreshed ? 0 : 16)
    }
}
