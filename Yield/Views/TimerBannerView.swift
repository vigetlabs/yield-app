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
    /// Banner-level hover — stage 1 of the action reveal (the ellipsis
    /// peek). Mirrors the project rows' two-stage quick-action system.
    @State private var isHovered: Bool = false
    /// True while the cursor is over the action zone itself — stage 2:
    /// the ellipsis cross-fades to the Edit / Move / Delete icons.
    @State private var isActionZoneHovered: Bool = false

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

    /// Display-friendly project name including the `[code]` prefix
    /// when the project has a Forecast code. Reads from either the
    /// live tracking project or the paused snapshot — both expose a
    /// `displayName`/`projectDisplayName` accessor.
    private var projectName: String {
        viewModel.trackingProject?.displayName ?? viewModel.pausedState?.projectDisplayName ?? ""
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

    /// Tooltip shown on the timer display: "Started at 11:18 AM · 2:35 elapsed".
    /// Sourced from Harvest's `timer_started_at` which is non-nil iff
    /// the entry is currently running, so paused/stopped timers return
    /// an empty string (and SwiftUI omits the tooltip).
    private var timerStartedTooltip: String {
        guard let started = viewModel.trackingEntry?.timerStartedAt else { return "" }
        let startedString = Self.timeOfDayFormatter.string(from: started)
        let elapsedHours = Date().timeIntervalSince(started) / 3600.0
        return "Started at \(startedString) · \(elapsedHours.formattedColon) elapsed"
    }

    private static let timeOfDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

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
        // Right-click menu: secondary path to the same actions the
        // hover reveal offers — a backup with text labels alongside
        // the icons, for anyone who reaches for it by muscle memory.
        // Kept in lockstep with `overflowActionsBar`.
        .contextMenu {
            Button {
                if let entry = currentEntry { onEditEntry?(entry) }
            } label: {
                Label("Edit Timer", systemImage: "pencil")
            }
            .disabled(viewModel.isHarvestDown || currentEntry == nil)
            Button {
                viewModel.startTimerMove()
            } label: {
                Label("Move Time…", systemImage: "arrow.turn.up.right")
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
        .onChange(of: hasTimer) { _, _ in
            syncDotPulse()
            // The banner can collapse out from under the cursor (timer
            // stopped from the reveal itself) — clear the hover states
            // so the next timer doesn't appear with the zone pre-opened.
            if !hasTimer {
                isHovered = false
                isActionZoneHovered = false
            }
        }
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

                        HStack(spacing: 4) {
                            Text(taskName)
                                .font(YieldFonts.titleMedium)
                                .foregroundStyle(YieldColors.textPrimary)
                                .lineLimit(1)

                            // Discoverable affordance for the timer
                            // start info. Only shows when the timer is
                            // actually running — Harvest only populates
                            // `timer_started_at` while a timer is live.
                            if !timerStartedTooltip.isEmpty {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(YieldColors.textSecondary)
                                    .offset(y: -1)
                                    .help(timerStartedTooltip)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: timer + hover-revealed overflow actions +
                // controls. The reveal zone sits BEFORE pause/stop:
                // the whole cluster is trailing-anchored, so expanding
                // the zone pushes the timer *text* left while pause and
                // stop never move — revealing (or collapsing) the icons
                // can't slide the primary controls out from under a
                // cursor that's heading for them. spacing 0 (not the
                // HStack default) so the zero-width resting zone doesn't
                // reserve a phantom gap — the real gaps are explicit
                // paddings, mirroring the project rows' fix.
                HStack(spacing: 0) {
                    timerDisplay(totalSeconds: totalSeconds)

                    actionRevealZone

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
                            foregroundColor: YieldColors.textSecondary,
                            destructiveOnHover: true
                        ))
                        .disabledWhenHarvestDown(viewModel.isHarvestDown)
                    }
                    .padding(.leading, 12)
                }
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Overflow Action Reveal

    /// Same two-stage reveal as the project rows: banner hover → 22pt
    /// ellipsis peek; zone hover → the ellipsis cross-fades to the
    /// Edit / Move / Delete icon bar sliding in from the trailing edge.
    /// The formerly-right-click-only actions become one-click and
    /// discoverable.
    private var actionRevealZone: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 22, height: 22)
                .opacity(showPeekIcon ? 1 : 0)

            overflowActionsBar
                .fixedSize()
                .opacity(isActionZoneHovered ? 1 : 0)
        }
        .frame(width: actionZoneWidth, alignment: .trailing)
        .clipped()
        // Gap between the timer text and the zone, only while the zone
        // has width — collapsed, the timer sits at its usual 12pt from
        // the pause button with no phantom inset.
        .padding(.leading, actionZoneWidth > 0 ? 8 : 0)
        // Full-height hit area so the cursor doesn't drop out of the
        // zone when it strays above or below the icons.
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isActionZoneHovered = hovering
            }
        }
    }

    /// Reveal-zone width staging, mirroring the project rows:
    ///   - Zone hovered  → full bar (3 × 22pt icons + 2 × 4pt gaps + 4pt lead)
    ///   - Banner hovered → 22pt peek slot
    ///   - Neither        → 0
    private var actionZoneWidth: CGFloat {
        guard hasTimer else { return 0 }
        if isActionZoneHovered { return 3 * 22 + 2 * 4 + 4 }
        if isHovered { return 22 }
        return 0
    }

    private var showPeekIcon: Bool {
        hasTimer && isHovered && !isActionZoneHovered
    }

    /// Edit / Move / Delete, in the old context menu's order. Styled
    /// identically to the project rows' quick-action buttons so the two
    /// reveal systems read as one.
    private var overflowActionsBar: some View {
        HStack(spacing: 4) {
            overflowActionButton(systemImage: "pencil", help: "Edit Timer") {
                if let entry = currentEntry { onEditEntry?(entry) }
            }
            // Relocate part of this timer's time to another task — the
            // "left it running through a meeting" fix. Presentation is
            // driven by `pendingTimerMove` on the view model (like the
            // idle-move flow), so no callback plumbing is needed here.
            overflowActionButton(systemImage: "arrow.turn.up.right", help: "Move Time…") {
                viewModel.startTimerMove()
            }
            overflowActionButton(systemImage: "trash", help: "Delete Timer") {
                if let entry = currentEntry { onDeleteEntry?(entry) }
            }
        }
        .padding(.leading, 4)
    }

    private func overflowActionButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        let disabled = viewModel.isHarvestDown || currentEntry == nil
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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
        // Only spin a per-second blink loop when we actually need one
        // (timer set + running). The banner is rendered even when no
        // timer is set so its height can be measured for the
        // strip-to-banner animation — that previously meant a
        // Timer.publish subscription firing 60×/min for no visible
        // change. `.task(id:)` cancels and respawns when the gating
        // expression flips, so the loop is alive exactly when needed.
        .task(id: hasTimer && isActive) {
            guard hasTimer && isActive else {
                // Make the colon steady-on when the blink loop isn't
                // running (paused, or no timer at all).
                if !colonOn { colonOn = true }
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                colonOn.toggle()
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
