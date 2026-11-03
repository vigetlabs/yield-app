import Charts
import SwiftUI

/// The System theme's weekly chart: the stacked area the app has always
/// had, dressed in the validated palette with a hover layer.
///
/// Form is the original — smoothed, stacked, edge-to-edge — kept by
/// choice for how it looks. What's new is around it: eight fixed,
/// validated series hues (see `YieldChartColors`), solid hairline
/// gridlines, a hover rule that shows the day's per-project breakdown
/// in a tooltip inside the chart frame, and 8pt square legend swatches.
/// Text never wears a series color.
struct WeeklyAreaChart: View {
    struct Series: Identifiable {
        let id: Int
        let name: String
        let color: Color
    }

    /// Points with any isolation already applied (non-isolated series
    /// zeroed), so the chart just draws what it's given.
    let points: [TimeComparisonViewModel.ChartPoint]
    /// The unfiltered series, used for the Y scale so isolating a
    /// project doesn't rescale the axis.
    let allPoints: [TimeComparisonViewModel.ChartPoint]
    /// Fixed order; colors already assigned.
    let series: [Series]
    let days: [String]
    let dailyTarget: Double
    /// Hover layer. Off for the PNG export.
    var interactive: Bool = true

    @State private var hoveredDay: Int? = nil

    private static let plotHeight: CGFloat = 200

    // MARK: - Derived data

    private var dayIndex: [String: Double] {
        Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, Double($0)) })
    }

    private var upperX: Double { Double(max(days.count - 1, 1)) }

    /// Y upper bound: at least the daily target, grown in 2h steps past
    /// the unfiltered peak so long days land on a labeled tick.
    private var upper: Double {
        var totals: [String: Double] = [:]
        for p in allPoints { totals[p.date, default: 0] += p.hours }
        let peak = totals.values.max() ?? 0
        let rounded = ceil(peak / 2) * 2
        let targetCeiling = ceil(dailyTarget / 2) * 2
        return max(targetCeiling, rounded, 2)
    }

    private var yTicks: [Double] { stride(from: 0, through: upper, by: 2).map { $0 } }

    /// Hours per (series, day index) from the visible points.
    private var hoursBySeriesDay: [Int: [Int: Double]] {
        var out: [Int: [Int: Double]] = [:]
        let idx = dayIndex
        for p in points {
            guard let d = idx[p.dayLabel] else { continue }
            out[p.projectId, default: [:]][Int(d), default: 0] += p.hours
        }
        return out
    }

    private func dayTotal(_ day: Int) -> Double {
        let hours = hoursBySeriesDay
        return series.reduce(0) { $0 + (hours[$1.id]?[day] ?? 0) }
    }

    /// Anchor for X-axis day labels: edge labels hang inward from the
    /// tick so they don't clip at the plot boundary.
    private static func xLabelAnchor(_ idx: Int, dayCount: Int) -> UnitPoint {
        if idx == 0 { return .topLeading }
        if idx == dayCount - 1 { return .topTrailing }
        return .top
    }

    // MARK: - Body

    var body: some View {
        let idx = dayIndex
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", idx[point.dayLabel] ?? 0),
                    y: .value("Hours", point.hours),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("Project", point.projectName))
                .interpolationMethod(.monotone)
            }

            // Workday reference. Dashed on purpose — it's a reference
            // line, not a gridline, and the dash is what tells them apart.
            RuleMark(y: .value("Target", dailyTarget))
                .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            if let day = hoveredDay {
                RuleMark(x: .value("Day", Double(day)))
                    .foregroundStyle(YieldColors.onBackground.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartForegroundStyleScale(
            domain: series.map(\.name),
            range: series.map(\.color)
        )
        .chartYScale(domain: 0...upper)
        .chartXScale(domain: 0...upperX)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: days.indices.map { Double($0) }) { value in
                if let d = value.as(Double.self), let i = Int(exactly: d.rounded()), i >= 0, i < days.count {
                    AxisValueLabel(anchor: Self.xLabelAnchor(i, dayCount: days.count)) {
                        Text(days[i])
                            .font(YieldFonts.label(10, weight: .medium))
                            .foregroundStyle(hoveredDay == i ? YieldColors.textPrimary : YieldColors.textSecondary)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(YieldColors.border)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { value in
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(Self.formatHours(h))
                            .font(YieldFonts.mono(10))
                            .foregroundStyle(YieldColors.textSecondary)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(YieldColors.border)
            }
            AxisMarks(position: .trailing, values: [dailyTarget]) { _ in
                AxisValueLabel {
                    Text(Self.formatHours(dailyTarget))
                        .font(YieldFonts.label(10, weight: .medium))
                        .foregroundStyle(YieldColors.textSecondary)
                }
            }
        }
        .chartOverlay { proxy in
            if interactive {
                GeometryReader { geo in
                    hoverLayer(proxy: proxy, geo: geo)
                }
            }
        }
        .frame(height: Self.plotHeight)
        .animation(.easeInOut(duration: 0.12), value: hoveredDay)
    }

    // MARK: - Hover

    /// Transparent hit layer over the plot. Hovering snaps to the nearest
    /// day; the tooltip sits beside that day's rule, clamped to the plot.
    @ViewBuilder
    private func hoverLayer(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        let plot = geo[proxy.plotFrame!]
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let x = location.x - plot.minX
                        if plot.contains(location),
                           let v: Double = proxy.value(atX: x, as: Double.self) {
                            let day = Int(v.rounded())
                            hoveredDay = (0..<days.count).contains(day) ? day : nil
                        } else {
                            hoveredDay = nil
                        }
                    case .ended:
                        hoveredDay = nil
                    }
                }

            if let day = hoveredDay, dayTotal(day) > 0,
               let ruleX = proxy.position(forX: Double(day)) {
                tooltip(day: day)
                    .fixedSize()
                    .modifier(TooltipPlacement(ruleX: plot.minX + ruleX, plot: plot))
            }
        }
    }

    private func tooltip(day: Int) -> some View {
        let hours = hoursBySeriesDay
        let rows = series.compactMap { s -> (Series, Double)? in
            let h = hours[s.id]?[day] ?? 0
            return h > 0 ? (s, h) : nil
        }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(days[day])
                    .font(YieldFonts.label(10, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)
                Spacer(minLength: 12)
                Text(dayTotal(day).formattedHoursMinutes)
                    .font(YieldFonts.mono(10, weight: .medium))
                    .foregroundStyle(YieldColors.textPrimary)
            }
            ForEach(rows, id: \.0.id) { s, h in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 8, height: 8)
                    Text(s.name)
                        .font(YieldFonts.label(10))
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(h.formattedHoursMinutes)
                        .font(YieldFonts.mono(10))
                        .foregroundStyle(YieldColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220)
        .background(YieldColors.background)
        .background(YieldColors.surfaceActive)
        .yieldBorder(radius: YieldRadius.card)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .allowsHitTesting(false)
    }

    /// Places the tooltip to the right of the hovered day's rule, or to
    /// the left when it would run past the plot's edge.
    private struct TooltipPlacement: ViewModifier {
        let ruleX: CGFloat
        let plot: CGRect
        @State private var size: CGSize = .zero

        func body(content: Content) -> some View {
            let gap: CGFloat = 10
            let fitsRight = ruleX + gap + size.width <= plot.maxX
            let x = fitsRight ? ruleX + gap + size.width / 2 : ruleX - gap - size.width / 2
            content
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
                .position(x: x, y: plot.minY + size.height / 2 + 4)
        }
    }

    // MARK: - Formatting

    static func formatHours(_ hours: Double) -> String {
        if hours == floor(hours) { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }
}

/// Legend for the System chart: an 8pt square swatch and the name in
/// text tokens. Clicking isolates a series; clicking it again clears.
struct WeeklyChartLegend: View {
    let series: [WeeklyAreaChart.Series]
    let isolatedId: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(series) { s in
                Button { onSelect(s.id) } label: {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(s.color)
                            .frame(width: 8, height: 8)
                        Text(s.name)
                            .font(YieldFonts.label(10))
                            .foregroundStyle(YieldColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isolatedId == nil || isolatedId == s.id ? 1.0 : 0.35)
            }
        }
    }
}
