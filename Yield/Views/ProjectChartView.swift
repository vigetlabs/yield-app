import AppKit
import Charts
import SwiftUI

/// Weekly time chart: one colored line per project, hours on Y, weekdays on X.
/// Only projects with logged time this week are included.
struct ProjectChartView: View {
    let viewModel: TimeComparisonViewModel

    /// When non-nil, the chart shows only this project's data and dims the
    /// other rows in the legend. Click a legend row to isolate; click the same
    /// row again to reset back to "all."
    @State private var isolatedProjectId: Int?

    /// Assign colors by dividing the color wheel into N equal slices (where N is
    /// the number of projects in the chart). Every pair of projects ends up the
    /// same 360°/N apart — maximum possible separation. Sat/bright alternates so
    /// even a small N has brightness variation too.
    private func color(for projectId: Int, in projects: [ProjectRef]) -> Color {
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

    /// Returns the active isolation id (or nil if nothing is isolated, or the
    /// isolated project no longer has data this week).
    private func activeIsolation(projects: [ProjectRef]) -> Int? {
        guard let id = isolatedProjectId,
              projects.contains(where: { $0.id == id })
        else { return nil }
        return id
    }

    /// Chart points with non-isolated projects' hours zeroed out. Returning the
    /// full dataset (rather than filtering) keeps every ChartPoint's id stable
    /// across isolation toggles, so Swift Charts can smoothly animate the
    /// non-isolated areas collapsing to zero and the Y-axis rescaling, instead
    /// of unmounting/remounting marks abruptly.
    private func visiblePoints(
        allPoints: [TimeComparisonViewModel.ChartPoint],
        isolatedId: Int?
    ) -> [TimeComparisonViewModel.ChartPoint] {
        guard let id = isolatedId else { return allPoints }
        return allPoints.map { point in
            point.projectId == id
                ? point
                : TimeComparisonViewModel.ChartPoint(
                    id: point.id,
                    projectId: point.projectId,
                    projectName: point.projectName,
                    date: point.date,
                    dayLabel: point.dayLabel,
                    hours: 0
                )
        }
    }

    var body: some View {
        let allPoints = viewModel.chartSeries
        let projects = projectList
        let isolated = activeIsolation(projects: projects)
        let points = visiblePoints(allPoints: allPoints, isolatedId: isolated)

        if allPoints.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    chart(points: points, allPoints: allPoints, projects: projects)
                        .frame(height: 200)

                    Button {
                        exportChartAsPNG(
                            allPoints: allPoints,
                            projects: projects
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(YieldColors.textSecondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Save chart as PNG")
                }

                legend(projects: projects, isolatedId: isolated)
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

    /// Anchor for X-axis day labels. Edge labels are anchored so they hang
    /// inward from the tick (avoiding clipping at the plot boundary); middle
    /// labels stay centered under their tick.
    private static func xLabelAnchor(value: AxisValue, dayCount: Int) -> UnitPoint {
        guard let d = value.as(Double.self),
              let idx = Int(exactly: d.rounded())
        else {
            return .top
        }
        if idx == 0 { return .topLeading }
        if idx == dayCount - 1 { return .topTrailing }
        return .top
    }

    @ViewBuilder
    private func chart(
        points: [TimeComparisonViewModel.ChartPoint],
        allPoints: [TimeComparisonViewModel.ChartPoint],
        projects: [ProjectRef]
    ) -> some View {
        // Use the full (unfiltered) series to set the Y-axis upper bound so the
        // chart's vertical scale stays constant when a project is isolated —
        // otherwise zeroed-out non-isolated points shrink the total per-day
        // peak and the axis rescales downward.
        let upper = yMax(for: allPoints)
        let days = viewModel.chartDays

        // Use numeric x-values (day indices) rather than String categories so the
        // first/last points land on the plot edges instead of being centered in a
        // "band" that leaves half-a-band of gutter on each side.
        let dayIndex: [String: Double] = Dictionary(
            uniqueKeysWithValues: days.enumerated().map { ($1, Double($0)) }
        )
        let upperX = Double(max(days.count - 1, 1))

        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", dayIndex[point.dayLabel] ?? 0),
                    y: .value("Hours", point.hours),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("Project", point.projectName))
                .interpolationMethod(.monotone)
            }

            // 8-hour reference line (a workday). The label is rendered as a
            // trailing Y-axis tick (below) so it sits outside the plot area to the
            // right, mirroring how the leading tick labels sit outside on the left.
            RuleMark(y: .value("Target", 8))
                .foregroundStyle(YieldColors.textSecondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartForegroundStyleScale(
            domain: projects.map(\.name),
            range: projects.map { color(for: $0.id, in: projects) }
        )
        .chartYScale(domain: 0...upper)
        .chartXScale(domain: 0...upperX)
        .chartLegend(.hidden)  // custom legend below
        .chartXAxis {
            AxisMarks(values: days.indices.map { Double($0) }) { value in
                // Anchor the edge labels so they don't get clipped: the leftmost
                // label hangs from the tick rightward, the rightmost hangs
                // leftward, and middle labels stay centered under their tick.
                AxisValueLabel(anchor: Self.xLabelAnchor(value: value, dayCount: days.count)) {
                    if let d = value.as(Double.self),
                       let idx = Int(exactly: d.rounded()),
                       idx >= 0, idx < days.count {
                        Text(days[idx])
                            .font(YieldFonts.dmSans(9, weight: .medium))
                            .foregroundStyle(YieldColors.textSecondary)
                    }
                }
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
            // Trailing-axis "8h" label for the workday reference rule — sits in
            // the right-side axis gutter, outside the plot, mirroring the leading
            // tick labels on the left.
            AxisMarks(position: .trailing, values: [8]) { _ in
                AxisValueLabel {
                    Text("8h")
                        .font(YieldFonts.dmSans(9, weight: .medium))
                        .foregroundStyle(YieldColors.textSecondary)
                }
            }
        }
        // Explicit animation hook so Swift Charts interpolates its internal
        // layout (y-axis rescale, mark shapes) when the isolation toggles.
        .animation(.easeInOut(duration: 0.25), value: isolatedProjectId)
    }

    private func legend(projects: [ProjectRef], isolatedId: Int?) -> some View {
        // Two-column flow so long project lists don't overflow the panel width.
        // Clicking a row isolates that project; clicking the already-isolated
        // row toggles back to "all" — no separate reset button needed.
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(projects) { project in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isolatedProjectId == project.id {
                            isolatedProjectId = nil  // toggle off
                        } else {
                            isolatedProjectId = project.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: project.id, in: projects))
                            .frame(width: 7, height: 7)
                        Text(project.name)
                            .font(YieldFonts.dmSans(10))
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isolatedId == nil || isolatedId == project.id ? 1.0 : 0.35)
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

    // MARK: - PNG Export

    /// Builds a standalone version of the chart suitable for ImageRenderer.
    /// Explicit dark background, week title, and wider layout for a clean PNG.
    private func exportableView(
        allPoints: [TimeComparisonViewModel.ChartPoint],
        projects: [ProjectRef]
    ) -> some View {
        let upper = yMax(for: allPoints)
        let days = viewModel.chartDays
        let dayIndex: [String: Double] = Dictionary(
            uniqueKeysWithValues: days.enumerated().map { ($1, Double($0)) }
        )
        let upperX = Double(max(days.count - 1, 1))

        return VStack(alignment: .leading, spacing: 16) {
            // Week title
            Text(viewModel.weekLabel)
                .font(YieldFonts.newsreader(16))
                .foregroundStyle(YieldColors.textPrimary)

            // Chart
            Chart {
                ForEach(allPoints) { point in
                    AreaMark(
                        x: .value("Day", dayIndex[point.dayLabel] ?? 0),
                        y: .value("Hours", point.hours),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Project", point.projectName))
                    .interpolationMethod(.monotone)
                }

                RuleMark(y: .value("Target", 8))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartForegroundStyleScale(
                domain: projects.map(\.name),
                range: projects.map { color(for: $0.id, in: projects) }
            )
            .chartYScale(domain: 0...upper)
            .chartXScale(domain: 0...upperX)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: days.indices.map { Double($0) }) { value in
                    AxisValueLabel(anchor: Self.xLabelAnchor(value: value, dayCount: days.count)) {
                        if let d = value.as(Double.self),
                           let idx = Int(exactly: d.rounded()),
                           idx >= 0, idx < days.count {
                            Text(days[idx])
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.1))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yTicks(upTo: upper)) { value in
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text(formatHours(h))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.1))
                }
                AxisMarks(position: .trailing, values: [8]) { _ in
                    AxisValueLabel {
                        Text("8h")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
            }
            .frame(width: 560, height: 260)

            // Legend
            let columns = [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(projects) { project in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: project.id, in: projects))
                            .frame(width: 8, height: 8)
                        Text(project.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(24)
        .background(YieldColors.background)
    }

    @MainActor
    private func exportChartAsPNG(
        allPoints: [TimeComparisonViewModel.ChartPoint],
        projects: [ProjectRef]
    ) {
        let view = exportableView(allPoints: allPoints, projects: projects)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // Retina

        guard let cgImage = renderer.cgImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "yield-chart-\(DateHelpers.weekDateStrings().start).png"
        panel.canCreateDirectories = true

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil
            ) else { return }
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}
