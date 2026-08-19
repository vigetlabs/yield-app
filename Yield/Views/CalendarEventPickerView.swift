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

    /// Day-timeline rendering: hour gridlines with a time gutter,
    /// events as blocks positioned and sized by their actual times
    /// (overlaps split into columns), and a "now" line — the picker
    /// reads as a calendar day rather than a list. Sizing follows the
    /// main panel's pattern: `fixedSize(vertical:)` collapses to the
    /// timeline's natural height, `frame(maxHeight:)` caps with
    /// scrolling on a long day.
    @ViewBuilder
    private func eventList(_ events: [CalendarEvent]) -> some View {
        let timeline = DayTimeline(events: events)
        ScrollViewReader { proxy in
            ScrollView {
                timelineCanvas(timeline)
                    .padding(.vertical, 8)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: maxListHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                // Land the user at "now" (or the first event when the
                // day hasn't started) instead of the top of a timeline
                // that may begin hours ago.
                if timeline.containsNow {
                    proxy.scrollTo(DayTimeline.nowLineID, anchor: .center)
                } else if let first = timeline.blocks.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    /// The positioned canvas: gridlines + gutter labels underneath,
    /// event blocks above, now-line on top.
    private func timelineCanvas(_ timeline: DayTimeline) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Hour gridlines + gutter labels
                ForEach(timeline.hourMarks, id: \.hour) { mark in
                    HStack(alignment: .center, spacing: 6) {
                        Text(mark.label)
                            .font(YieldFonts.monoXS)
                            .foregroundStyle(YieldColors.textSecondary)
                            .frame(width: DayTimeline.gutterWidth - 12, alignment: .trailing)
                        Rectangle()
                            .fill(YieldColors.border)
                            .frame(height: 1)
                    }
                    .offset(y: timeline.y(for: mark.hour) - 6)
                }

                // Event blocks
                ForEach(timeline.blocks) { block in
                    eventBlock(block, timeline: timeline, canvasWidth: geo.size.width)
                        .id(block.id)
                }

                // Now line — the red horizontal marker every calendar
                // app trains the eye on.
                if timeline.containsNow {
                    HStack(spacing: 0) {
                        Circle()
                            .fill(YieldStatusColors.over)
                            .frame(width: 6, height: 6)
                        Rectangle()
                            .fill(YieldStatusColors.over)
                            .frame(height: 1)
                    }
                    .padding(.leading, DayTimeline.gutterWidth - 3)
                    .offset(y: timeline.yForNow - 3)
                    .id(DayTimeline.nowLineID)
                }
            }
        }
        .frame(height: timeline.canvasHeight)
    }

    /// One event block: accent left rail, title + time, and the two
    /// always-visible quick actions. Dimmed once the event has ended;
    /// the accent strengthens while it's happening.
    private func eventBlock(_ block: DayTimeline.Block, timeline: DayTimeline, canvasWidth: CGFloat) -> some View {
        let contentWidth = max(canvasWidth - DayTimeline.gutterWidth - 12, 60)
        let columnWidth = contentWidth / CGFloat(block.columnCount)
        let x = DayTimeline.gutterWidth + CGFloat(block.column) * columnWidth
        let y = timeline.y(for: block.event.start)
        let height = max(timeline.y(for: block.event.end) - y, DayTimeline.minBlockHeight)
        let isPast = block.event.end <= Date()
        let isHappening = !isPast && block.event.start <= Date()

        return EventBlockView(
            event: block.event,
            isHappening: isHappening,
            onSelect: { onSelect(block.event) },
            onStartTimer: { onStartTimer(block.event) }
        )
        .frame(width: columnWidth - 4, height: height)
        .opacity(isPast ? 0.55 : 1)
        .offset(x: x, y: y)
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

// MARK: - Day Timeline Layout

/// Pure layout math for the picker's day-timeline: the hour span the
/// canvas covers, y-positions for dates, and column assignments for
/// overlapping events (Calendar.app-style side-by-side splitting).
/// Internal so XCTest can drive the overlap/bounds logic directly.
struct DayTimeline {
    static let pointsPerHour: CGFloat = 56
    static let gutterWidth: CGFloat = 56
    /// Floor so a 15-minute block still fits its title and quick-action
    /// icons — positions stay truthful; only the visual height clamps
    /// (tiny events may slightly overhang the next gridline, as in
    /// Calendar.app).
    static let minBlockHeight: CGFloat = 28
    static let nowLineID = "day-timeline-now"

    struct Block: Identifiable {
        let event: CalendarEvent
        let column: Int
        var columnCount: Int
        var id: String { event.id }
    }

    struct HourMark {
        let hour: Date
        let label: String
    }

    /// First gridline (the hour at or before the earliest start).
    let timelineStart: Date
    /// Last gridline (the hour at or after the latest end).
    let timelineEnd: Date
    let blocks: [Block]

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    init(events: [CalendarEvent], calendar: Calendar = .current) {
        let sorted = events.sorted { a, b in
            a.start != b.start ? a.start < b.start : a.end > b.end
        }

        let earliest = sorted.map(\.start).min() ?? Date()
        let latest = sorted.map(\.end).max() ?? Date()
        // Floor to the hour via dateInterval — `date(bySetting:)`
        // searches forward and doesn't zero smaller components.
        timelineStart = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        // Round the end UP to the next hour boundary so the last event
        // never touches the canvas edge.
        let hoursSpan = ceil(latest.timeIntervalSince(timelineStart) / 3600)
        timelineEnd = timelineStart.addingTimeInterval(max(hoursSpan, 1) * 3600)

        // Column assignment: greedy interval partitioning, scoped per
        // overlap cluster so a lone 3pm meeting isn't narrowed by two
        // overlapping ones at 9am. A cluster closes when an event
        // starts at/after every active column's end.
        var built: [Block] = []
        var clusterIndices: [Int] = []
        var columnEnds: [Date] = []
        var clusterMaxColumns = 0

        func closeCluster() {
            for i in clusterIndices { built[i].columnCount = clusterMaxColumns }
            clusterIndices = []
            columnEnds = []
            clusterMaxColumns = 0
        }

        for event in sorted {
            if let maxEnd = columnEnds.max(), event.start >= maxEnd {
                closeCluster()
            }
            let column: Int
            if let free = columnEnds.firstIndex(where: { $0 <= event.start }) {
                columnEnds[free] = event.end
                column = free
            } else {
                columnEnds.append(event.end)
                column = columnEnds.count - 1
            }
            clusterMaxColumns = max(clusterMaxColumns, columnEnds.count)
            built.append(Block(event: event, column: column, columnCount: 1))
            clusterIndices.append(built.count - 1)
        }
        closeCluster()
        blocks = built
    }

    var canvasHeight: CGFloat {
        y(for: timelineEnd) + 12
    }

    func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(timelineStart) / 3600) * Self.pointsPerHour
    }

    var containsNow: Bool {
        let now = Date()
        return now >= timelineStart && now <= timelineEnd
    }

    var yForNow: CGFloat { y(for: Date()) }

    /// One mark per hour boundary across the span, inclusive.
    var hourMarks: [HourMark] {
        var marks: [HourMark] = []
        var cursor = timelineStart
        while cursor <= timelineEnd {
            marks.append(HourMark(hour: cursor, label: Self.hourFormatter.string(from: cursor)))
            cursor = cursor.addingTimeInterval(3600)
        }
        return marks
    }
}

// MARK: - Event Block

private struct EventBlockView: View {
    let event: CalendarEvent
    let isHappening: Bool
    let onSelect: () -> Void
    let onStartTimer: () -> Void

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    private var displayTitle: String {
        event.summary.isEmpty ? "(No title)" : event.summary
    }

    /// Full range + duration, surfaced via tooltip on every block —
    /// the visible line carries only the start time, calendar-style.
    private var fullTimeLine: String {
        let start = Self.timeFormatter.string(from: event.start)
        let end = Self.timeFormatter.string(from: event.end)
        let (h, m) = event.durationHours.roundedHM
        let duration = h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
        return "\(start) \u{2013} \(end) (\(duration))"
    }

    var body: some View {
        // Not a Button: the quick-action icons are the only click
        // targets. The block itself just hovers to show where they are.
        HStack(alignment: .top, spacing: 8) {
            // Accent rail — stronger while the event is happening,
            // mirroring the project rows' status line.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(YieldColors.greenAccent.opacity(isHappening ? 1 : 0.45))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            // Calendar-style single line: start time leading the title,
            // no end/duration (those live in the tooltip).
            (Text(Self.timeFormatter.string(from: event.start))
                .font(YieldFonts.monoXS)
                .foregroundStyle(YieldColors.textSecondary)
             + Text("  ")
             + Text(displayTitle)
                .font(YieldFonts.titleSmall)
                .foregroundStyle(YieldColors.textPrimary))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            actionIcon("bolt.fill", help: "Start Timer", action: onStartTimer)
            actionIcon("plus.circle.fill", help: "Add Time", action: onSelect)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered
                    ? YieldColors.greenSubtle
                    : (isHappening ? YieldColors.greenSubtle : YieldColors.greenFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(YieldColors.greenBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .help("\(displayTitle) \u{2014} \(fullTimeLine)")
    }

    private func actionIcon(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
