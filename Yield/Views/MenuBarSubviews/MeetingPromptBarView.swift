import SwiftUI

/// Passive meeting-start nudge: a slim bar above the timer banner that
/// appears while a calendar event is inside its prompt window. Offers
/// to start (or switch) a timer for the meeting — including moving the
/// minutes elapsed since the event's start off the currently running
/// timer, so the timeline reads as if you'd switched on time.
///
/// The complement to Move Time: that flow repairs a meeting you sat
/// through on the wrong timer; this one catches it as it starts.
struct MeetingPromptBarView: View {
    let viewModel: TimeComparisonViewModel
    let event: CalendarEvent
    /// Start Timer routed through the parent: the view model handles
    /// remembered meetings itself; unknown ones need the form, which
    /// MenuBarContentView owns.
    let onStartTimer: () -> Void

    /// Compact "9:00am" formatter, matching the event picker's style.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    var body: some View {
        // Minute-driven timeline so the "started Xm ago" line and the
        // move amount tick while the panel sits open.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(YieldColors.yellowAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.summary)
                            .font(YieldFonts.titleSmall)
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(statusLine(now: now))
                            .font(YieldFonts.dmSans(10))
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        onStartTimer()
                    } label: {
                        Text(startLabel(now: now))
                    }
                    .buttonStyle(.greenOutlined)
                    .disabledWhenHarvestDown(viewModel.isHarvestDown)

                    // Per-event dismiss — quiet for the rest of the day.
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.dismissMeetingPrompt()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(YieldColors.textSecondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }

                // The permanent escape hatch, styled as a quiet link so
                // it reads as the exception rather than a peer action.
                // Undoable from the Calendar settings card.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.muteMeetingPrompt()
                    }
                } label: {
                    Text("Don't prompt for meetings like this")
                        .font(YieldFonts.dmSans(10))
                        .foregroundStyle(YieldColors.textSecondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.leading, 23)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(YieldColors.yellowFaint)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    /// "9:00am – 9:30am · started 6m ago" (or "starts in 2m").
    private func statusLine(now: Date) -> String {
        let range = "\(Self.timeFormatter.string(from: event.start)) – \(Self.timeFormatter.string(from: event.end))"
        let delta = now.timeIntervalSince(event.start)
        if delta < -30 {
            let minutes = max(1, Int((-delta / 60).rounded()))
            return "\(range) · starts in \(minutes)m"
        }
        let minutes = Int((delta / 60).rounded())
        if minutes < 1 { return "\(range) · starting now" }
        return "\(range) · started \(minutes)m ago"
    }

    /// The primary action's label carries the move offer when there's
    /// a running timer to move from and the meeting already started:
    /// "Start & move 0:06". Otherwise a plain "Start Timer".
    private func startLabel(now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(event.start) / 3600)
        guard viewModel.trackingEntry != nil, elapsed * 60 >= 1 else { return "Start Timer" }
        return "Start & move \(elapsed.formattedColon)"
    }
}
