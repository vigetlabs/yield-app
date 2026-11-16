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
            let refreshed = ThemeStore.shared.theme.usesRefreshedLayout
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Editorial leads with the glyph. System keeps its text on
                    // the margin the timer bar and the list use, and carries
                    // the glyph on the status line instead.
                    if !refreshed {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(YieldColors.yellowAccent)
                    }

                    VStack(alignment: .leading, spacing: refreshed ? 3 : 2) {
                        // System: the timer bar's sizes — this is the
                        // same kind of row, one place above it.
                        Text(event.summary)
                            .font(refreshed ? YieldFonts.titleMedium : YieldFonts.titleSmall)
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if refreshed {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(YieldStatusColors.meeting)
                                Text(statusLine(now: now))
                                    .font(YieldFonts.rowSubtitle)
                                    .foregroundStyle(YieldColors.textSecondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(statusLine(now: now))
                                .font(YieldFonts.label(10))
                                .foregroundStyle(YieldColors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        onStartTimer()
                    } label: {
                        Text(startLabel(now: now))
                    }
                    .meetingBarButtonStyle()
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
                        .font(refreshed ? YieldFonts.rowSubtitle : YieldFonts.label(10))
                        .foregroundStyle(YieldColors.textSecondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.leading, refreshed ? 0 : 23)
            }
            .padding(.leading, refreshed ? 16 + 3 : 16)
            .padding(.trailing, 16)
            .padding(.vertical, refreshed ? 12 : 10)
            // System: a wash of the meeting blue, edge to edge, as the
            // timer bar is washed green. Blue is what the menu bar
            // shows for a meeting, and it keeps this bar apart from a
            // paused timer's amber one.
            .background(refreshed ? YieldStatusColors.meeting.opacity(0.08) : YieldColors.yellowFaint)
        }
        // One rule, underneath. Whatever is above — the header, or the
        // other meeting bar — has already drawn the one between them.
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
    /// a running timer with at least a minute worth moving: "Start &
    /// move 0:06". When the running timer is already on the meeting's
    /// task there is nothing to start or move — "Add to Timer" puts the
    /// title on that entry. Otherwise a plain "Start Timer". The view
    /// model owns the rules so the label and what the button does
    /// can't disagree.
    private func startLabel(now: Date) -> String {
        if viewModel.meetingPromptJoinsRunningTimer { return "Add to Timer" }
        guard let hours = viewModel.meetingPromptMoveHours(now: now) else { return "Start Timer" }
        return "Start & move \(hours.formattedColon)"
    }
}
