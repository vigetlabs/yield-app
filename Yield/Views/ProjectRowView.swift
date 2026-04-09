import SwiftUI

struct ProjectRowView: View {
    let project: ProjectStatus
    var effectiveLoggedHours: Double
    var onToggleTimer: (() -> Void)? = nil
    var onToggleEntryTimer: ((Int, Bool) -> Void)? = nil
    var onEditEntry: ((TimeEntryInfo) -> Void)? = nil
    var onDeleteEntry: ((TimeEntryInfo) -> Void)? = nil
    var onStartTimerForProject: (() -> Void)? = nil
    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false

    private var hasEntries: Bool { !project.timeEntries.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header row
            projectHeader
                .background(isHovered ? YieldColors.surfaceDefault : Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
                .onTapGesture {
                    guard hasEntries else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .contextMenu {
                    Button {
                        onStartTimerForProject?()
                    } label: {
                        Label("Start Timer", systemImage: "play.fill")
                    }
                }

            // Expanded time entries
            if isExpanded {
                ForEach(project.timeEntries) { entry in
                    TaskEntryRowView(entry: entry, onToggleTimer: {
                        onToggleEntryTimer?(entry.id, entry.isRunning)
                    }, onEditEntry: {
                        onEditEntry?(entry)
                    }, onDeleteEntry: {
                        onDeleteEntry?(entry)
                    })
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    // MARK: - Project Header

    private var projectHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left colored line
            statusLine

            // Project details + time
            HStack {
                // Left: client, name, remaining
                VStack(alignment: .leading, spacing: 6) {
                    // Client name
                    if let clientName = project.clientName {
                        Text(clientName.uppercased())
                            .font(YieldFonts.labelProject)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                    }

                    // Project name + chevron
                    HStack(spacing: 10) {
                        Text(project.projectName)
                            .font(YieldFonts.titleMedium)
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)

                        if hasEntries {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(YieldColors.textPrimary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        }
                    }

                    // Remaining label (forecasted only)
                    if project.isForecasted && project.remainingHours > 0 {
                        Text(project.remainingFormatted)
                            .font(YieldFonts.labelTimeRemaining)
                            .foregroundStyle(YieldColors.greenAccent)
                            .tracking(0.18)
                    }
                }

                Spacer(minLength: 8)

                // Right: time + progress bar
                VStack(alignment: .trailing, spacing: 8) {
                    timeLabel

                    if project.isForecasted {
                        ProgressBarView(
                            logged: effectiveLoggedHours,
                            booked: project.bookedHours
                        )
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
        }
        .frame(height: project.isForecasted ? 74 : 56)
    }

    // MARK: - Status Line

    private var statusLine: some View {
        Rectangle()
            .fill(project.isForecasted ? Color.white.opacity(0.7) : Color.clear)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    // MARK: - Time Label

    private var timeLabel: some View {
        Group {
            if project.isForecasted {
                HStack(spacing: 0) {
                    Text(formatHoursMinutes(effectiveLoggedHours) + " / ")
                        .foregroundStyle(YieldColors.textPrimary)
                    Text(formatHoursOnly(project.bookedHours))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .font(YieldFonts.monoSmall)
            } else {
                Text(formatHoursMinutes(effectiveLoggedHours))
                    .font(YieldFonts.monoSmall)
                    .foregroundStyle(YieldColors.textPrimary)
            }
        }
        .fixedSize()
    }

    // MARK: - Formatting

    private func formatHoursMinutes(_ hours: Double) -> String {
        formatHM(hours)
    }

    private func formatHoursOnly(_ hours: Double) -> String {
        let h = Int(hours)
        return "\(h)h"
    }
}

// Shared hours:minutes formatter used by ProjectRowView and TaskEntryRowView
private func formatHM(_ hours: Double) -> String {
    let abs = Swift.abs(hours)
    let h = Int(abs)
    let m = Int((abs - Double(h)) * 60)
    return "\(h)h \(String(format: "%02d", m))m"
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    let logged: Double
    let booked: Double

    private var ratio: Double {
        guard booked > 0 else { return 0 }
        return max(logged / booked, 0)
    }

    private var isOver: Bool { ratio > 1.0 }

    private var barColor: Color {
        isOver ? YieldStatusColors.over : YieldStatusColors.under
    }

    /// Normalized fill: when over, the "booked" portion shrinks to show overage visually.
    /// e.g. 24h/12h (2x) → booked fills 50%, overage fills remaining 50%.
    private var bookedFill: Double {
        guard ratio > 1.0 else { return max(ratio, 0) }
        // Invert: booked portion = 1/ratio (shrinks as overage grows), min 20% so it stays visible
        return max(1.0 / min(ratio, 5.0), 0.2)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background: overage color when over, default otherwise
            RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                .fill(isOver ? YieldStatusColors.over.opacity(0.4) : YieldColors.surfaceActive)
                .frame(width: YieldDimensions.progressBarWidth, height: YieldDimensions.progressBarHeight)

            // Fill: booked portion
            RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                .fill(barColor)
                .frame(
                    width: YieldDimensions.progressBarWidth * bookedFill,
                    height: YieldDimensions.progressBarHeight
                )
                .animation(.easeInOut(duration: 0.4), value: bookedFill)
        }
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.progressBar))
    }
}

// MARK: - Task Entry Row

struct TaskEntryRowView: View {
    let entry: TimeEntryInfo
    var onToggleTimer: (() -> Void)? = nil
    var onEditEntry: (() -> Void)? = nil
    var onDeleteEntry: (() -> Void)? = nil
    @State private var isHovered: Bool = false

    private var hasNotes: Bool {
        if let notes = entry.notes, !notes.isEmpty { return true }
        return false
    }

    private var isToday: Bool {
        guard let date = DateHelpers.dateFormatter.date(from: entry.date) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        HStack {
            // Task details + time info (double-click to edit)
            HStack {
                VStack(alignment: .leading, spacing: hasNotes ? 6 : 0) {
                    Text(entry.taskName)
                        .font(YieldFonts.titleSmall)
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 226, alignment: .leading)

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(YieldFonts.labelNote)
                            .foregroundStyle(YieldColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tracking(0.36)
                    }
                }
                .frame(width: 268, alignment: .leading)

                Spacer()

                HStack(spacing: 8) {
                    if entry.isRunning {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(YieldColors.greenAccent)
                    }

                    Text(formatHoursMinutes(entry.hours))
                        .font(YieldFonts.monoXS)
                        .foregroundStyle(entry.isRunning ? YieldColors.greenAccent : YieldColors.textSecondary)

                    if entry.isRunning {
                        Text("Now")
                            .font(YieldFonts.monoXS)
                            .foregroundStyle(YieldColors.greenAccent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(YieldColors.greenDim)
                            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
                    } else {
                        Text(formatDay(entry.date))
                            .font(YieldFonts.monoXS)
                            .foregroundStyle(YieldColors.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                }
            }
            .contentShape(Rectangle())

            // Play/stop button (only for today's entries)
            if isToday {
                Button(action: { onToggleTimer?() }) {
                    Image(systemName: entry.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(TimerControlButtonStyle(
                    borderColor: entry.isRunning ? YieldColors.greenAccent : YieldColors.buttonBorder,
                    foregroundColor: entry.isRunning ? YieldColors.greenAccent : YieldColors.textSecondary
                ))
            }
        }
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(isHovered ? YieldColors.surfaceDefault : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .contextMenu {
            Button {
                onEditEntry?()
            } label: {
                Label("Edit Entry", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDeleteEntry?()
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private func formatHoursMinutes(_ hours: Double) -> String {
        formatHM(hours)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private func formatDay(_ dateString: String) -> String {
        guard let date = DateHelpers.dateFormatter.date(from: dateString) else { return dateString }
        if Calendar.current.isDateInToday(date) { return "Today" }
        return Self.dayFormatter.string(from: date)
    }
}
