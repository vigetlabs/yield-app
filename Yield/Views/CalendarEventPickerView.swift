import SwiftUI

/// Inline-replacement picker shown in place of the new-timer form
/// when the user taps the calendar icon. Lists today's primary-
/// calendar events; tapping one returns the event to the form via
/// `onSelect` so the form can pre-fill duration + title.
///
/// Lives inside `NewTimerFormView`'s body (not a sheet/popover —
/// MenuBarExtra panels can't host either) so the panel reflows to
/// the picker's natural height.
struct CalendarEventPickerView: View {
    let viewModel: TimeComparisonViewModel
    /// "Add Time" — apply the event's duration + title to the form.
    /// Also the whole-row tap action.
    let onSelect: (CalendarEvent) -> Void
    /// "Start Timer" — instantly start a timer when meeting history
    /// recognizes the event, otherwise land in the form with just the
    /// title prefilled (no duration) ready to start one manually.
    let onStartTimer: (CalendarEvent) -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .loading

    init(
        viewModel: TimeComparisonViewModel,
        onSelect: @escaping (CalendarEvent) -> Void,
        onStartTimer: @escaping (CalendarEvent) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onStartTimer = onStartTimer
        self.onCancel = onCancel
        // Seed the phase from the cache SYNCHRONOUSLY so the picker's
        // very first frame is already at its final height. Applying the
        // cache from `.task` (one frame later) re-targeted the panel's
        // height mid-transition — an unanimated snap that read as the
        // panel jumping taller while the open animation was running.
        if let cached = viewModel.cachedCalendarEvents {
            _phase = State(initialValue: cached.isEmpty ? .empty : .loaded(cached))
        }
    }

    /// The picker's render state. `loaded` carries the events so the
    /// view can switch on a single value rather than juggling parallel
    /// `events` + `isLoading` flags.
    private enum Phase {
        case loading
        case loaded([CalendarEvent])
        case empty
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch phase {
            case .loading:
                loadingState
            case .loaded(let events):
                eventList(events)
            case .empty:
                emptyState
            case .error(let message):
                errorState(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Cache-first: init already seeded the phase from the cache,
            // so the common case rendered instantly — this just silently
            // revalidates (no spinner — stale events beat one) and swaps
            // in anything new, animated so a height delta from a changed
            // calendar glides instead of snapping. Cold cache (first
            // open before any background fetch, or Google just
            // connected) falls back to the inline fetch with the full
            // loading/error UI.
            if let cached = viewModel.cachedCalendarEvents {
                await viewModel.refreshCalendarEventsIfStale()
                if let fresh = viewModel.cachedCalendarEvents, fresh != cached {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        phase = fresh.isEmpty ? .empty : .loaded(fresh)
                    }
                }
            } else {
                await loadEvents()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onCancel()
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

            Text("Today's events")
                .font(YieldFonts.dmSans(13, weight: .semibold))
                .foregroundStyle(YieldColors.textPrimary)

            Spacer()

            // Symmetry spacer so the title stays centered.
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
    }

    // MARK: - States

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading today's events…")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(YieldColors.textSecondary)
            Text("No events on your calendar today.")
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
            // Just "Back" — where it lands depends on where the picker
            // was opened from (main view via the header shortcut, or
            // the new-timer form), so naming a destination would lie
            // half the time.
            Button("Back", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(YieldColors.greenAccent)
                .font(YieldFonts.dmSans(11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.red.opacity(0.8))
            Text(message)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await loadEvents() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(YieldColors.greenAccent)
            .font(YieldFonts.dmSans(11, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func eventList(_ events: [CalendarEvent]) -> some View {
        // Size the scroll view to its content's ideal height, only
        // capping when the day's calendar is genuinely huge. Same
        // pattern the main panel + Settings use: `fixedSize(vertical:)`
        // collapses unused space when events fit, while
        // `frame(maxHeight:)` keeps the panel from overflowing the
        // screen on a 30-meeting day.
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events) { event in
                    EventRow(
                        event: event,
                        onSelect: { onSelect(event) },
                        onStartTimer: { onStartTimer(event) }
                    )
                }
            }
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Cap on the list's height so the menu bar panel can't grow past
    /// the screen on short displays. The `48` accounts for the back-
    /// button header + a touch of breathing room; the `300` floor
    /// protects the very first frame before `NSScreen.main` is
    /// meaningful.
    private var maxListHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(300, visible - 48)
    }

    // MARK: - Loading

    private func loadEvents() async {
        phase = .loading
        // Every terminal phase lands as an animated change: the panel
        // height difference between the spinner and the loaded list (or
        // an error card) glides instead of snapping.
        let resolved: Phase
        do {
            // Routed through the view model so a successful cold-open
            // fetch also seeds the background cache — the next open is
            // instant instead of re-fetching.
            try await viewModel.fetchAndCacheCalendarEvents()
            let events = viewModel.cachedCalendarEvents ?? []
            resolved = events.isEmpty ? .empty : .loaded(events)
        } catch APIError.unauthorized {
            resolved = .error("Reconnect Google Calendar in Settings.")
        } catch APIError.notConfigured {
            resolved = .error("Google Calendar isn't connected. Connect it in Settings.")
        } catch {
            resolved = .error("Couldn't reach Google Calendar.\n\(error.localizedDescription)")
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            phase = resolved
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: CalendarEvent
    let onSelect: () -> Void
    let onStartTimer: () -> Void

    @State private var isHovered = false

    /// Compact time formatter — "11:00am" instead of the system
    /// `.short` style's "11:00 AM". Forced 12-hour format via the
    /// explicit `h` token; users in 24-hour locales get the 12-hour
    /// rendering here too, which is intentional for the picker's
    /// tight horizontal layout.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    private var timeRange: String {
        let start = Self.timeFormatter.string(from: event.start)
        let end = Self.timeFormatter.string(from: event.end)
        return "\(start) – \(end)"
    }

    private var displayTitle: String {
        event.summary.isEmpty ? "(No title)" : event.summary
    }

    private var durationLabel: String {
        let (h, m) = event.durationHours.roundedHM
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Combined time-range + duration line, e.g. "9:00am – 9:30am (30m)".
    /// Reads as a sub-line under the title, mirroring the project-row
    /// pattern in the main panel where the project name sits on top
    /// and supporting metadata sits below.
    private var timeAndDurationLine: String {
        "\(timeRange) (\(durationLabel))"
    }

    var body: some View {
        Button(action: onSelect) {
            // Stacked layout matches the main panel's project rows:
            // headline on top (event title here / project name there),
            // monospace meta line beneath. Fonts pulled from the same
            // tokens (`titleMedium` + `monoSmall`) so the picker reads
            // as a sibling to the rest of the panel rather than a
            // separate visual system.
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(YieldFonts.titleMedium)
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(timeAndDurationLine)
                        .font(YieldFonts.monoSmall)
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 8)

                // Always-visible quick actions (no hover reveal — the
                // picker is a transient surface, so discoverability
                // beats quiet). Same glyphs as the project rows so the
                // verbs carry over: bolt = start timing, plus = add
                // logged time.
                actionIcon("bolt.fill", help: "Start Timer", action: onStartTimer)
                actionIcon("plus.circle.fill", help: "Add Time", action: onSelect)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? YieldColors.surfaceDefault : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    /// Same shape as the project rows' `quickActionButton`: plain
    /// style, 14pt semibold glyph in textSecondary, 22pt hit frame.
    private func actionIcon(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
