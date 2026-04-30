import SwiftUI

/// Top-of-panel banner for the active or paused Harvest timer. Always
/// rendered: when no timer is set it shrinks to a thin gradient strip,
/// when one is set it expands to its natural height with the timer
/// content fading in. One persistent view (rather than a swap between
/// a strip and a banner) keeps the transition reading as one row
/// growing rather than two components handing off.
struct TimerBannerView: View {
    let viewModel: TimeComparisonViewModel
    var onEditEntry: ((TimeEntryInfo) -> Void)? = nil
    var onDeleteEntry: ((TimeEntryInfo) -> Void)? = nil

    @State private var colonOn: Bool = true
    @State private var dotPulse: Bool = false
    /// Measured at first layout via `onGeometryChange`; the initial
    /// value is just a stale-until-measured estimate.
    @State private var contentHeight: CGFloat = 74

    private let emptyHeight: CGFloat = 16

    /// Whether a timer is set (active or paused). The view is always
    /// rendered; this drives the slot's expanded vs. strip height and
    /// whether the timer content fades in.
    private var hasTimer: Bool { viewModel.isTimerBannerVisible }
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

    private var contextLabel: String {
        ProjectStatus.qualifiedName(client: clientName, project: projectName)
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
            LinearGradient(
                colors: [gradientColor, Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.7, y: 0.5)
            )

            timerContent
                .opacity(hasTimer ? 1 : 0)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                .allowsHitTesting(hasTimer)
                // Gesture sits on `timerContent` (not the outer ZStack)
                // so the gradient backdrop stays tap-through when the
                // banner is in its empty-strip state.
                .onTapGesture(count: 2) {
                    guard !viewModel.isHarvestDown, let entry = currentEntry else { return }
                    onEditEntry?(entry)
                }
        }
        // The animation driving this height change is applied at the
        // panel body level (MenuBarContentView) so the parent VStack
        // and the outer frame reflow inside the same context — a local
        // animation here would let the parent layout snap discretely
        // around a smooth banner.
        .frame(height: hasTimer ? contentHeight : emptyHeight, alignment: .top)
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
        .onChange(of: hasTimer) { _, _ in syncDotPulse() }
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
                        .disabledWhenHarvestDown(viewModel.isHarvestDown)

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
                        .disabledWhenHarvestDown(viewModel.isHarvestDown)
                    }
                }
            }
            .padding(16)
        }
        .contentShape(Rectangle())
    }

    /// Heartbeat for the status dot — only when a timer is set AND
    /// active. Paused or empty: hard-stop with `withAnimation(nil)` so
    /// the repeating animation doesn't keep ticking on a hidden view
    /// (the banner stays alive in MenuBarExtra even after the panel
    /// closes).
    private func syncDotPulse() {
        if hasTimer && isActive {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        } else {
            withAnimation(nil) { dotPulse = false }
        }
    }

    /// Timer text with a flashing colon while the timer is active — matches
    /// the macOS menu-bar clock's "Flash the time separators" behavior:
    /// 1s visible, 1s hidden, hard on/off (no fade).
    @ViewBuilder
    private func timerDisplay(totalSeconds: Int) -> some View {
        // Round seconds to the nearest minute so the banner agrees with
        // the project drawer / row totals (which all round Harvest's
        // 0.01h-precision values to the nearest minute via formatHM).
        // Pure `% 60 / 60` truncation here was showing one minute below
        // the drawer for the same underlying entry.
        let totalMinutes = Int((Double(totalSeconds) / 60.0).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
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
            // Skip when no timer is set — the banner is rendered (so we
            // can measure its height) but invisible; toggling state
            // would invalidate the view 60×/min for nothing.
            guard hasTimer else { return }
            if isActive {
                colonOn.toggle()
            } else if !colonOn {
                colonOn = true
            }
        }
    }

    private func computeTotalSeconds(at now: Date) -> Int {
        // Round (rather than truncate) the seconds conversion so binary
        // floating-point error doesn't cost us a minute at boundaries
        // — `3.525 * 3600` evaluates to 12689.999…, and `Int(...)`
        // would chop it to 12689 = 3:31:29 while the drawer's formatHM
        // (which works in `hours * 60`) sees 3:32. With `.rounded()`
        // the two display paths agree.
        let baseSeconds = Int((baseHours * 3600).rounded())
        if isActive, let lastUpdated = viewModel.lastUpdated, lastUpdated <= now {
            // Clamp elapsed to 1 min — soft refresh polls every 60s, so local
            // ticking only has to bridge that window.
            let elapsed = min(Int(now.timeIntervalSince(lastUpdated)), 60)
            return max(0, baseSeconds + elapsed)
        }
        return max(0, baseSeconds)
    }
}
