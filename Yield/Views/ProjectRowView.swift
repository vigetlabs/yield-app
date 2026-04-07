import SwiftUI

struct ProjectRowView: View {
    let project: ProjectStatus
    var effectiveLoggedHours: Double
    var onToggleTimer: (() -> Void)? = nil
    var onToggleEntryTimer: ((Int, Bool) -> Void)? = nil
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header row
            projectHeader
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

            // Expanded time entries
            if isExpanded {
                ForEach(project.timeEntries) { entry in
                    TaskEntryRowView(entry: entry) {
                        onToggleEntryTimer?(entry.id, entry.isRunning)
                    }
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
        HStack(alignment: .center, spacing: 16) {
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

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(YieldColors.textPrimary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isExpanded)
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
        }
        .padding(.vertical, project.isForecasted ? 0 : 0)
        .frame(height: project.isForecasted ? 74 : 56)
    }

    // MARK: - Status Line

    private var statusLine: some View {
        Rectangle()
            .fill(statusLineColor)
            .frame(width: 3)
            .frame(maxHeight: .infinity)
    }

    private var statusLineColor: Color {
        if project.isTracking { return YieldColors.greenAccent }
        if !project.isForecasted { return YieldColors.textSecondary.opacity(0.3) }
        switch project.status {
        case .under: return YieldColors.greenAccent
        case .onTrack: return YieldColors.greenAccent
        case .over: return Color(red: 0.80, green: 0.45, blue: 0.40)
        }
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
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(String(format: "%02d", m))m"
    }

    private func formatHoursOnly(_ hours: Double) -> String {
        let h = Int(hours)
        return "\(h)h"
    }
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    let logged: Double
    let booked: Double

    private var progress: Double {
        guard booked > 0 else { return 0 }
        return min(logged / booked, 1.0)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                .fill(YieldColors.surfaceActive)
                .frame(width: YieldDimensions.progressBarWidth, height: YieldDimensions.progressBarHeight)

            RoundedRectangle(cornerRadius: YieldRadius.progressBar)
                .fill(YieldColors.greenAccent)
                .frame(
                    width: YieldDimensions.progressBarWidth * progress,
                    height: YieldDimensions.progressBarHeight
                )
        }
    }
}

// MARK: - Task Entry Row

struct TaskEntryRowView: View {
    let entry: TimeEntryInfo
    var onToggleTimer: (() -> Void)? = nil

    private var hasNotes: Bool {
        if let notes = entry.notes, !notes.isEmpty { return true }
        return false
    }

    var body: some View {
        HStack {
            // Task details
            VStack(alignment: .leading, spacing: hasNotes ? 6 : 0) {
                Text(entry.taskName)
                    .font(YieldFonts.titleSmall)
                    .foregroundStyle(YieldColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 226, alignment: .leading)

                if hasNotes {
                    Text(entry.notes!)
                        .font(YieldFonts.labelNote)
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .tracking(0.36)
                }
            }
            .frame(width: 268, alignment: .leading)

            Spacer()

            // Time + day + play button
            HStack(spacing: 24) {
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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }

    private func formatHoursMinutes(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private func formatDay(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = "EEE"
        return display.string(from: date)
    }
}
