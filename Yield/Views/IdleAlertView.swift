import SwiftUI

struct IdleAlertView: View {
    let viewModel: TimeComparisonViewModel

    var body: some View {
        if let alert = viewModel.idleAlertState {
            // TimelineView updates every 30s so the idle minutes tick up live
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                idleContent(alert: alert)
            }
        }
    }

    private func idleContent(alert: TimeComparisonViewModel.IdleAlertState) -> some View {
        let minutes = alert.currentIdleMinutes
        let label = "\(minutes) minute\(minutes == 1 ? "" : "s")"

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.yellowAccent)

                Text("Idle for \(label)")
                    .font(YieldFonts.dmSans(11, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)

                Spacer()

                Button {
                    viewModel.idleDismiss()
                } label: {
                    Text("Ignore")
                        .font(YieldFonts.dmSans(10, weight: .medium))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Description
            Text("You've been idle while tracking **\(alert.projectName)**. How would you like to handle the idle time?")
                .font(YieldFonts.dmSans(10))
                .foregroundStyle(YieldColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Divider()
                .background(YieldColors.border)

            // Action: Continue and remove time
            idleActionButton(
                label: "Continue Timing and Remove \(label)",
                icon: "play.fill"
            ) {
                Task { await viewModel.idleContinueAndRemoveTime() }
            }

            Divider()
                .background(YieldColors.border)

            // Action: Stop and remove time
            idleActionButton(
                label: "Stop Timer and Remove \(label)",
                icon: "stop.fill"
            ) {
                Task { await viewModel.idleStopAndRemoveTime() }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    YieldColors.yellowFaint,
                    YieldColors.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(YieldColors.yellowDim)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private func idleActionButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(YieldColors.yellowAccent)
                    .frame(width: 14)

                Text(label)
                    .font(YieldFonts.dmSans(11, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
