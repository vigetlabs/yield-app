import SwiftUI

struct TimerBannerView: View {
    let viewModel: TimeComparisonViewModel

    private var isActive: Bool { !viewModel.isTimerPaused }

    /// Accent color: green when active, yellow when paused
    private var accentColor: Color { isActive ? YieldColors.greenAccent : YieldColors.yellowAccent }
    private var accentDim: Color { isActive ? YieldColors.greenBorderActive : YieldColors.yellowDim }
    private var gradientColor: Color {
        isActive ? YieldColors.greenAccent.opacity(0.15) : YieldColors.yellowFaint
    }

    private var projectName: String {
        viewModel.trackingProject?.projectName ?? viewModel.pausedState?.projectName ?? ""
    }

    private var taskName: String {
        viewModel.trackingEntry?.taskName ?? viewModel.pausedState?.taskName ?? ""
    }

    private var baseHours: Double {
        if let entry = viewModel.trackingEntry {
            return entry.hours
        }
        return viewModel.pausedState?.frozenHours ?? 0
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isActive ? 1 : 60)) { timeline in
            let totalSeconds = computeTotalSeconds(at: timeline.date)

            HStack(spacing: 10) {
                // Left: dot + project/task info
                HStack(spacing: 8) {
                    // Status dot (green active, yellow paused)
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(projectName.uppercased())
                            .font(YieldFonts.labelProject)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)

                        Text(taskName)
                            .font(YieldFonts.titleMedium)
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: timer + controls
                HStack(spacing: 12) {
                    Text(formatTimer(totalSeconds))
                        .font(YieldFonts.monoMedium)
                        .foregroundStyle(accentColor)
                        .monospacedDigit()

                    HStack(spacing: 8) {
                        // Pause / Play button
                        Button {
                            Task {
                                if isActive {
                                    await viewModel.pauseTimer()
                                } else {
                                    await viewModel.resumeTimer()
                                }
                            }
                        } label: {
                            Image(systemName: isActive ? "pause.fill" : "play.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(TimerControlButtonStyle(
                            borderColor: accentDim,
                            foregroundColor: accentColor
                        ))

                        // Stop button
                        Button {
                            Task { await viewModel.stopBannerTimer() }
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(TimerControlButtonStyle(
                            borderColor: YieldColors.buttonBorder,
                            foregroundColor: YieldColors.textSecondary
                        ))
                    }
                }
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    gradientColor,
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.7, y: 0.5)
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private func computeTotalSeconds(at now: Date) -> Int {
        let baseSeconds = Int(baseHours * 3600)
        if isActive, let lastUpdated = viewModel.lastUpdated {
            let elapsed = Int(now.timeIntervalSince(lastUpdated))
            return baseSeconds + elapsed
        }
        return baseSeconds
    }

    private func formatTimer(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
