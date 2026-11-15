import SwiftUI

struct IdleAlertView: View {
    let viewModel: TimeComparisonViewModel

    var body: some View {
        if let alert = viewModel.idleAlertState {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                idleContent(alert: alert)
            }
        }
    }

    private func idleContent(alert: TimeComparisonViewModel.IdleAlertState) -> some View {
        let minutes = alert.currentIdleMinutes
        let label = Self.idleDurationLabel(minutes: minutes)
        let refreshed = ThemeStore.shared.theme.usesRefreshedLayout

        return VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(YieldColors.yellowAccent)

                Text("Idle for \(label)")
                    .font(YieldFonts.label(16, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)

                Text("You've been idle while tracking **\(alert.projectName)**.")
                    .font(YieldFonts.message)
                    .foregroundStyle(YieldColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .background(YieldColors.border)

            // Actions
            VStack(spacing: 0) {
                idleActionButton(
                    title: "Continue Timing",
                    subtitle: "Remove \(label) of idle time",
                    icon: refreshed ? "play" : "play.fill"
                ) {
                    Task { await viewModel.idleContinueAndRemoveTime() }
                    MenuBarStatusItem.closePanel()
                }

                Divider()
                    .background(YieldColors.border)
                    .padding(.leading, refreshed ? 16 + 3 : 16)
                    .padding(.trailing, 16)

                idleActionButton(
                    title: "Stop Timer",
                    subtitle: "Remove \(label) of idle time",
                    icon: refreshed ? "stop" : "stop.fill"
                ) {
                    Task { await viewModel.idleStopAndRemoveTime() }
                    MenuBarStatusItem.closePanel()
                }

                Divider()
                    .background(YieldColors.border)
                    .padding(.leading, refreshed ? 16 + 3 : 16)
                    .padding(.trailing, 16)

                idleActionButton(
                    title: "Move Time…",
                    subtitle: "Send \(label) of idle time to another timer",
                    icon: "arrow.uturn.right"
                ) {
                    viewModel.idleStartMove()
                }

                Divider()
                    .background(YieldColors.border)
                    .padding(.leading, refreshed ? 16 + 3 : 16)
                    .padding(.trailing, 16)

                idleActionButton(
                    title: "Keep All Time",
                    subtitle: "Dismiss and include idle time",
                    icon: "clock.arrow.circlepath",
                    isSecondary: true
                ) {
                    // "Do nothing and keep timing" has no follow-up
                    // view to show — close the panel so the user
                    // isn't dropped back into the main list they
                    // weren't trying to reach. The three other idle
                    // actions each transition to a meaningful next
                    // state (reduced timer, stopped timer, the
                    // Move Time form) and stay in the panel.
                    viewModel.idleDismiss()
                    MenuBarStatusItem.closePanel()
                }
            }
            .padding(.vertical, 8)
        }
        .background {
            if refreshed {
                // System has no gradients; the panel colour, with the
                // orange glyph as the cue.
                YieldColors.background
            } else {
                LinearGradient(
                    colors: [
                        YieldColors.yellowFaint,
                        YieldColors.background,
                        YieldColors.background,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    /// Format an idle duration for the alert's header and button
    /// subtitles. Under an hour stays as plain minutes; an hour or
    /// more switches to "Xh Ym" (or "Xh" on the round boundary) so
    /// an overnight idle reads as "12h" rather than "720 minutes".
    static func idleDurationLabel(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func idleActionButton(
        title: String,
        subtitle: String,
        icon: String,
        isSecondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        IdleActionButtonView(
            title: title,
            subtitle: subtitle,
            icon: icon,
            isSecondary: isSecondary,
            action: action
        )
    }
}

private struct IdleActionButtonView: View {
    let title: String
    let subtitle: String
    let icon: String
    var isSecondary: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    private var refreshed: Bool { ThemeStore.shared.theme.usesRefreshedLayout }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: refreshed ? 13 : 11, weight: refreshed ? .semibold : .regular))
                    .foregroundStyle(isSecondary ? YieldColors.textSecondary : YieldColors.yellowAccent)
                    .frame(width: refreshed ? 20 : 18)

                VStack(alignment: .leading, spacing: refreshed ? 2 : 1) {
                    Text(title)
                        .font(refreshed ? YieldFonts.titleMedium : YieldFonts.label(12, weight: .semibold))
                        .foregroundStyle(isSecondary ? YieldColors.textSecondary : YieldColors.textPrimary)

                    Text(subtitle)
                        .font(refreshed ? YieldFonts.rowSubtitle : YieldFonts.label(10))
                        .foregroundStyle(YieldColors.textSecondary)
                }

                Spacer()
            }
            // System: the list's margins and its row hover.
            .padding(.leading, refreshed ? 16 + 3 : 20)
            .padding(.trailing, refreshed ? 16 : 20)
            .padding(.vertical, 12)
            .background(isHovered ? (refreshed ? YieldColors.rowHover : YieldColors.surfaceDefault) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}
