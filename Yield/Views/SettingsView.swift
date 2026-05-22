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
                    AboutCard()
                    // Account + Calendar share a row at 50/50.
                    // `alignment: .top` keeps both cards anchored at
                    // the top edge so the shorter of the two doesn't
                    // stretch — they grow vertically independently
                    // based on their own sign-in state.
                    HStack(alignment: .top, spacing: 12) {
                        AccountCard(oAuthService: oAuthService, onDismiss: onDismiss)
                            .frame(maxWidth: .infinity)
                        GoogleCalendarCard()
                            .frame(maxWidth: .infinity)
                    }
                    PreferencesCard()
                    FavoritesCard(allProjects: allProjects, isLoadingProjects: isLoadingProjects)
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
}
