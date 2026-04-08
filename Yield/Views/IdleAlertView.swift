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
        let label = "\(minutes) minute\(minutes == 1 ? "" : "s")"

        return VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(YieldColors.yellowAccent)

                Text("Idle for \(label)")
                    .font(YieldFonts.dmSans(16, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)

                Text("You've been idle while tracking **\(alert.projectName)**.")
                    .font(YieldFonts.dmSans(11))
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
                    icon: "play.fill"
                ) {
                    Task { await viewModel.idleContinueAndRemoveTime() }
                }

                Divider()
                    .background(YieldColors.border)
                    .padding(.horizontal, 16)

                idleActionButton(
                    title: "Stop Timer",
                    subtitle: "Remove \(label) of idle time",
                    icon: "stop.fill"
                ) {
                    Task { await viewModel.idleStopAndRemoveTime() }
                }

                Divider()
                    .background(YieldColors.border)
                    .padding(.horizontal, 16)

                idleActionButton(
                    title: "Keep All Time",
                    subtitle: "Dismiss and include idle time",
                    icon: "clock.arrow.circlepath",
                    isSecondary: true
                ) {
                    viewModel.idleDismiss()
                }
            }
            .padding(.vertical, 8)
        }
        .background(
            LinearGradient(
                colors: [
                    YieldColors.yellowFaint,
                    YieldColors.background,
                    YieldColors.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func idleActionButton(
        title: String,
        subtitle: String,
        icon: String,
        isSecondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSecondary ? YieldColors.textSecondary : YieldColors.yellowAccent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(YieldFonts.dmSans(12, weight: .semibold))
                        .foregroundStyle(isSecondary ? YieldColors.textSecondary : YieldColors.textPrimary)

                    Text(subtitle)
                        .font(YieldFonts.dmSans(10))
                        .foregroundStyle(YieldColors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
