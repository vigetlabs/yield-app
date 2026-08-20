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
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(YieldColors.yellowAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.eventTitle)
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
                    onMoveTime()
                } label: {
                    Text(moveLabel(now: now))
                }
                .buttonStyle(.greenOutlined)
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
