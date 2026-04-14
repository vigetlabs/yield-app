import SwiftUI

struct TimerBannerView: View {
    let viewModel: TimeComparisonViewModel
    var onEditEntry: ((TimeEntryInfo) -> Void)? = nil
    var onDeleteEntry: ((TimeEntryInfo) -> Void)? = nil

    @State private var colonOn: Bool = true

    private var isActive: Bool { !viewModel.isTimerPaused }

    /// The entry represented by the banner — tracking entry when active, paused entry when paused
    private var currentEntry: TimeEntryInfo? {
        if let entry = viewModel.trackingEntry { return entry }
        if let paused = viewModel.pausedState {
            for project in viewModel.projectStatuses {
                if let entry = project.timeEntries.first(where: { $0.id == paused.entryId }) {
                    return entry
                }
            }
        }
        return nil
    }

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
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
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
                    timerDisplay(totalSeconds: totalSeconds)

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
                        .disabled(viewModel.isHarvestDown)
                        .opacity(viewModel.isHarvestDown ? 0.4 : 1.0)

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
                        .disabled(viewModel.isHarvestDown)
                        .opacity(viewModel.isHarvestDown ? 0.4 : 1.0)
                    }
                }
            }
            .padding(16)
        }
        .contentShape(Rectangle())
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
        .contextMenu {
            Button {
                if let entry = currentEntry { onEditEntry?(entry) }
            } label: {
                Label("Edit Timer", systemImage: "pencil")
            }
            .disabled(viewModel.isHarvestDown || currentEntry == nil)
            Button(role: .destructive) {
                if let entry = currentEntry { onDeleteEntry?(entry) }
            } label: {
                Label("Delete Timer", systemImage: "trash")
            }
            .disabled(viewModel.isHarvestDown || currentEntry == nil)
        }
    }

    /// Timer text with a flashing colon while the timer is active — matches
    /// the macOS menu-bar clock's "Flash the time separators" behavior:
    /// 1s visible, 1s hidden, hard on/off (no fade).
    @ViewBuilder
    private func timerDisplay(totalSeconds: Int) -> some View {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        HStack(spacing: 0) {
            Text(String(format: "%02d", h))
            Text(":")
                .opacity(isActive && !colonOn ? 0.0 : 1.0)
            Text(String(format: "%02d", m))
        }
        .font(YieldFonts.monoMedium)
        .foregroundStyle(accentColor)
        .monospacedDigit()
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if isActive {
                colonOn.toggle()
            } else if !colonOn {
                colonOn = true
            }
        }
    }

    private func computeTotalSeconds(at now: Date) -> Int {
        let baseSeconds = Int(baseHours * 3600)
        if isActive, let lastUpdated = viewModel.lastUpdated, lastUpdated <= now {
            // Clamp elapsed to 1 min — soft refresh polls every 60s, so local
            // ticking only has to bridge that window.
            let elapsed = min(Int(now.timeIntervalSince(lastUpdated)), 60)
            return max(0, baseSeconds + elapsed)
        }
        return max(0, baseSeconds)
    }

    private func formatTimer(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }
}
