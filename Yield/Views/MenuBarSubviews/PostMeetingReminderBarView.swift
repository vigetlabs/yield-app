import SwiftUI

/// Post-meeting overage nudge: a slim bar above the timer banner that
/// appears when a timer started from a calendar event is still running
/// well past the event's end (by the idle-detection threshold). Offers
/// to move the overage — the minutes since the meeting ended — onto
/// whatever the user actually switched to.
///
/// The bookend to `MeetingPromptBarView`: that one catches a meeting
/// starting on the wrong timer; this one catches a meeting's timer
/// outliving the meeting.
struct PostMeetingReminderBarView: View {
    let viewModel: TimeComparisonViewModel
    let reminder: TimeComparisonViewModel.CalendarSourcedTimer
    /// Move routed through the parent: the timer-move form lives in
    /// MenuBarContentView's presentation state.
    let onMoveTime: () -> Void

    /// Compact "3:30pm" formatter, matching the prompt bar's style.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    var body: some View {
        // Minute-driven timeline so the overage amount ticks while the
        // panel sits open.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let refreshed = ThemeStore.shared.theme.usesRefreshedLayout
            HStack(spacing: 10) {
                // Editorial leads with the glyph. System keeps its text on
                // the margin the timer bar and the list use, and carries
                // the glyph on the status line instead.
                if !refreshed {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(YieldColors.yellowAccent)
                }

                VStack(alignment: .leading, spacing: refreshed ? 3 : 2) {
                    // System: the timer bar's sizes, as on the prompt bar.
                    Text(reminder.eventTitle)
                        .font(refreshed ? YieldFonts.titleMedium : YieldFonts.titleSmall)
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if refreshed {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "calendar.badge.exclamationmark")
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
                    onMoveTime()
                } label: {
                    Text(moveLabel(now: now))
                }
                .meetingBarButtonStyle()
                .disabledWhenHarvestDown(viewModel.isHarvestDown)

                // Per-event dismiss — the timer keeps running; the
                // reminder just stops asking.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.dismissPostMeetingReminder()
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

    /// "Ended 3:30pm · timer running 12m over".
    private func statusLine(now: Date) -> String {
        let ended = Self.timeFormatter.string(from: reminder.eventEnd)
        let minutes = max(1, Int((now.timeIntervalSince(reminder.eventEnd) / 60).rounded()))
        return "Ended \(ended) · timer running \(minutes)m over"
    }

    /// "Move 0:12" — the overage ready to relocate.
    private func moveLabel(now: Date) -> String {
        let overage = max(0, now.timeIntervalSince(reminder.eventEnd) / 3600)
        return "Move \(overage.formattedColon)"
    }
}
