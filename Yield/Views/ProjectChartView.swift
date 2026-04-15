import Charts
import SwiftUI

/// Weekly time chart: one colored line per project, hours on Y, weekdays on X.
/// Only projects with logged time this week are included.
struct ProjectChartView: View {
    let viewModel: TimeComparisonViewModel

    /// Assign colors by dividing the color wheel into N equal slices (where N is
    /// the number of projects in the chart). Every pair of projects ends up the
    /// same 360°/N apart — maximum possible separation. Sat/bright alternates so
    /// even a small N has brightness variation too.
    private func color(for projectId: Int) -> Color {
        let projects = projectList
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else {
            return YieldColors.greenAccent  // shouldn't happen
        }
        let n = max(projects.count, 1)
        let hue = Double(idx) / Double(n)
        // Muted, dark-theme-friendly tones. Alternate sat/bright between two
        // low-saturation levels so neighbors differ on a second axis.
        let even = idx.isMultiple(of: 2)
        let sat: Double = even ? 0.50 : 0.35
        let bright: Double = even ? 0.82 : 0.72
        return Color(hue: hue, saturation: sat, brightness: bright)
    }

    private struct ProjectRef: Identifiable {
        let id: Int
        let name: String
    }

    /// Unique projects in the series, in display order (alphabetical by name).
    private var projectList: [ProjectRef] {
        let points = viewModel.chartSeries
        var seen = Set<Int>()
        var out: [ProjectRef] = []
        for p in points where !seen.contains(p.projectId) {
            seen.insert(p.projectId)
            out.append(ProjectRef(id: p.projectId, name: p.projectName))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let points = viewModel.chartSeries
        let projects = projectList

        if points.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                chart(points: points)
                    .frame(height: 200)

                legend(projects: projects)
            }
            .padding(16)
        }
    }

    /// Y-axis upper bound: 8h minimum, grown in 2h increments so long days still
    /// land on a labeled tick instead of cutting off mid-interval.
    private func yMax(for points: [TimeComparisonViewModel.ChartPoint]) -> Double {
        var totals: [String: Double] = [:]
        for p in points { totals[p.date, default: 0] += p.hours }
        let peak = totals.values.max() ?? 0
        let rounded = ceil(peak / 2) * 2
        return max(8, rounded)
    }

    private func yTicks(upTo upper: Double) -> [Double] {
        stride(from: 0, through: upper, by: 2).map { $0 }
    }

    @ViewBuilder
    private func chart(points: [TimeComparisonViewModel.ChartPoint]) -> some View {
        let upper = yMax(for: points)

        let projects = projectList

        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", point.dayLabel),
                    y: .value("Hours", point.hours),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("Project", point.projectName))
                .interpolationMethod(.monotone)
            }

            // 8-hour reference line (a workday)
            RuleMark(y: .value("Target", 8))
                .foregroundStyle(YieldColors.textSecondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .topTrailing, alignment: .trailing, spacing: 2) {
                    Text("8h")
                        .font(YieldFonts.dmSans(9, weight: .medium))
                        .foregroundStyle(YieldColors.textSecondary)
                }
        }
        .chartForegroundStyleScale(
            domain: projects.map(\.name),
            range: projects.map { color(for: $0.id) }
        )
        .chartYScale(domain: 0...upper)
        .chartLegend(.hidden)  // custom legend below
        .chartXAxis {
            AxisMarks(values: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]) { _ in
                AxisValueLabel()
                    .font(YieldFonts.dmSans(9, weight: .medium))
                    .foregroundStyle(YieldColors.textSecondary)
                AxisGridLine()
                    .foregroundStyle(YieldColors.border)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks(upTo: upper)) { value in
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(formatHours(h))
                            .font(YieldFonts.jetBrainsMono(9))
                            .foregroundStyle(YieldColors.textSecondary)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(YieldColors.border)
            }
        }
    }

    private func legend(projects: [ProjectRef]) -> some View {
        // Two-column flow so long project lists don't overflow the panel width.
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(projects) { project in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: project.id))
                        .frame(width: 7, height: 7)
                    Text(project.name)
                        .font(YieldFonts.dmSans(10))
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(YieldColors.textSecondary)
            Text("No time logged this week yet.")
                .foregroundStyle(YieldColors.textSecondary)
                .font(YieldFonts.dmSans(11))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func formatHours(_ hours: Double) -> String {
        if hours == floor(hours) {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }
}
