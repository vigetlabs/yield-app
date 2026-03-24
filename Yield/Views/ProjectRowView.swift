import SwiftUI

struct ProjectRowView: View {
    let project: ProjectStatus
    var effectiveLoggedHours: Double
    var totalWeeklyBookedHours: Double = 0
    var onToggleTimer: (() -> Void)? = nil
    var onToggleEntryTimer: ((Int, Bool) -> Void)? = nil
    @State private var isExpanded: Bool = false

    private var canToggleTimer: Bool {
        project.harvestProjectId != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                StatusIndicator(status: project.status, isTracking: project.isTracking, isUnbooked: project.bookedHours == 0)

                VStack(alignment: .leading, spacing: 1) {
                    if let clientName = project.clientName {
                        Text(clientName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Text(project.projectName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)

                Spacer(minLength: 4)

                Text(hoursLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                if canToggleTimer {
                    Button(action: { onToggleTimer?() }) {
                        Image(systemName: project.isTracking ? "stop.fill" : "play.fill")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .help(project.isTracking ? "Stop timer" : "Start timer")
                }

                if !project.timeEntries.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isExpanded)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ProgressBarView(
                progress: progress,
                status: project.status,
                isUnbooked: project.bookedHours == 0
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(project.timeEntries) { entry in
                        TimeEntryRowView(entry: entry) {
                            onToggleEntryTimer?(entry.id, entry.isRunning)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 2)
            }
        }
    }

    private var progress: Double {
        guard project.bookedHours > 0 else {
            // Unbooked: scale relative to total weekly booked hours
            guard totalWeeklyBookedHours > 0 else { return 0.0 }
            return effectiveLoggedHours / totalWeeklyBookedHours
        }
        return effectiveLoggedHours / project.bookedHours
    }

    private var hoursLabel: String {
        let today = formatDecimalHours(project.todayHours)
        let logged = formatDecimalHours(effectiveLoggedHours)
        let booked = formatDecimalHours(project.bookedHours)
        return "\(today) today | \(logged) / \(booked)"
    }

    private func formatDecimalHours(_ hours: Double) -> String {
        if hours == 0 { return "0h" }
        if hours == hours.rounded() {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }
}

struct ProgressBarView: View {
    let progress: Double
    let status: ProjectStatus.Status
    var isUnbooked: Bool = false

    private var barColor: Color {
        if isUnbooked { return Color(red: 0.60, green: 0.60, blue: 0.60) }
        switch status {
        case .under: return Color(red: 0.55, green: 0.75, blue: 0.50)
        case .onTrack: return Color(red: 0.85, green: 0.78, blue: 0.45)
        case .over: return Color(red: 0.80, green: 0.45, blue: 0.40)
        }
    }

    private var darkOverageColor: Color {
        switch status {
        case .onTrack: return Color(red: 0.60, green: 0.55, blue: 0.25)
        default: return Color(red: 0.55, green: 0.25, blue: 0.22)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)

                if progress > 1.0 {
                    // Over budget: dark shade for overage, normal for booked
                    let bookedFraction = 1.0 / progress
                    let fillWidth = geo.size.width

                    // Darker shade fills the entire bar (overage)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(darkOverageColor)
                        .frame(width: fillWidth)

                    // Normal red on top for the booked portion
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: fillWidth * bookedFraction)

                    // Tick mark at the booked boundary
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 1.5, height: 8)
                        .offset(x: fillWidth * bookedFraction - 0.75)
                } else {
                    // Under or at budget: normal fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * max(progress, 0))
                }
            }
        }
        .frame(height: 8)
    }
}

struct TimeEntryRowView: View {
    let entry: TimeEntryInfo
    var onToggleTimer: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if entry.isRunning {
                Circle()
                    .fill(Color(red: 0.55, green: 0.75, blue: 0.50))
                    .frame(width: 5, height: 5)
            }

            Text(entryLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(formatHours(entry.hours))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(formatDate(entry.date))
                .font(.system(.caption2))
                .foregroundStyle(.tertiary)

            Button(action: { onToggleTimer?() }) {
                Image(systemName: entry.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(entry.isRunning ? "Stop timer" : "Start timer")
        }
    }

    private var entryLabel: String {
        let parts = [entry.taskName, entry.notes].compactMap { $0?.isEmpty == false ? $0 : nil }
        if parts.isEmpty { return "No description" }
        return parts.joined(separator: ": ")
    }

    private func formatHours(_ hours: Double) -> String {
        if hours == 0 { return "0h" }
        if hours == hours.rounded() { return String(format: "%.0fh", hours) }
        return String(format: "%.1fh", hours)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = "EEE"
        return display.string(from: date)
    }
}
