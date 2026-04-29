import SwiftUI

/// Top-of-panel banner for the active (or paused) Harvest timer. Always
/// rendered — when no timer is set it shrinks to a thin gradient strip;
/// when one is set it expands to its natural ~74pt height with the
/// project/task/timer/controls fading in. One persistent component
/// instead of a strip-vs-banner swap means the height interpolation
/// reads as the same row growing into a banner, not as one component
/// being torn down and another inserted.
struct TimerBannerView: View {
    let viewModel: TimeComparisonViewModel
    var onEditEntry: ((TimeEntryInfo) -> Void)? = nil
    var onDeleteEntry: ((TimeEntryInfo) -> Void)? = nil

    @State private var colonOn: Bool = true
    /// Toggles between scale 1.0 and 1.25 on a slow ease-in-out loop while
    /// the timer is active, so the status dot reads as a "heartbeat."
    /// Frozen when paused.
    @State private var dotPulse: Bool = false
    /// Measured natural height of the timer-content layout. Used as the
    /// expanded frame height; we don't hard-code so a longer client/
    /// project name that wraps to two lines stays accommodated.
    @State private var contentHeight: CGFloat = 74

    /// Empty-state strip height — kept thin enough to read as "ready"
    /// without dominating the panel.
    private let emptyHeight: CGFloat = 16

    private var isVisible: Bool { viewModel.isTimerBannerVisible }
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

    private var clientName: String? {
        viewModel.trackingProject?.clientName ?? viewModel.pausedState?.clientName
    }

    private var projectName: String {
        viewModel.trackingProject?.projectName ?? viewModel.pausedState?.projectName ?? ""
    }

    /// Top-line label: "CLIENT — PROJECT" when a client is known, just
    /// the project name otherwise. Em-dash separator matches the
    /// convention used elsewhere in the codebase (idle alert, budget
    /// notification body).
    private var contextLabel: String {
        [clientName, projectName].compactMap { $0 }.joined(separator: " — ")
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
        ZStack(alignment: .top) {
            // Always-visible backdrop. Its color tracks state — green
            // when active or empty, yellow when paused.
            LinearGradient(
                colors: [gradientColor, Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.7, y: 0.5)
            )

            // Timer content laid out at its natural height always so we
            // can measure it; opacity fades it in/out, frame cap below
            // shrinks the visible slot to a thin strip when invisible.
            timerContent
                .opacity(isVisible ? 1 : 0)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                .allowsHitTesting(isVisible)
        }
        // Slot height: full content height when a timer is set, the
        // thin strip otherwise. The animation that drives this is
        // applied at the MenuBarContentView body level so the parent
        // VStack and the panel's outer frame all participate in the
        // same animation context — without that, the parent reflows
        // discretely and the panel "pops" around the smoothly-animating
        // banner.
        .frame(height: isVisible ? contentHeight : emptyHeight, alignment: .top)
        .clipped()
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
        .onAppear { syncDotPulse() }
        .onChange(of: isActive) { _, _ in syncDotPulse() }
    }

    @ViewBuilder
    private var timerContent: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let totalSeconds = computeTotalSeconds(at: timeline.date)

            HStack(spacing: 10) {
                // Left: dot + project/task info
                HStack(spacing: 8) {
                    // Status dot (green active, yellow paused). Pulses
                    // gently while active so the row reads as "live"
                    // even when the timer text is between ticks.
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotPulse ? 1.25 : 1.0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(contextLabel.uppercased())
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
    }

    /// Drive the dot's heartbeat: a slow easeInOut.repeatForever while
    /// active, snap back to scale 1.0 when paused (a non-repeating
    /// animation cancels the repeating one).
    private func syncDotPulse() {
        if isActive {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                dotPulse = false
            }
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
}
