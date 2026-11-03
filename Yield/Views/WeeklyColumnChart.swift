import Charts
import SwiftUI

/// The System theme's weekly chart: one stacked column per weekday,
/// one segment per project.
///
/// The original chart is a smoothed stacked area, which draws hours
/// *between* days — a Wednesday peak reads as time ramping up through
/// Tuesday afternoon. Logged time is a per-day quantity, so the form
/// here is a column: each day's total is its height, its composition
/// is the stack, and nothing is interpolated.
///
/// Marks follow the chart conventions the palette was validated for:
/// a 2pt surface gap between stacked segments (so neighbors read as
/// distinct even where hues are close), a rounded cap on the top
/// segment only, the day total as a direct label on each cap, solid
/// hairline gridlines, and a hover layer that highlights a day and
/// shows its per-project breakdown. Text never wears a series color.
struct WeeklyColumnChart: View {
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
    /// Hover + highlight. Off for the PNG export.
    var interactive: Bool = true

    @State private var hoveredDay: Int? = nil

    private static let columnWidth: CGFloat = 24
    private static let plotHeight: CGFloat = 200
    private static let capRadius: CGFloat = 4
    /// 2pt gap between stacked segments, expressed in hours. The plot
    /// area is the frame minus the axis label row, so this is a close
    /// approximation rather than exact — a 1.8pt gap reads the same.
    private var gapHours: Double { 2 * upper / (Self.plotHeight - 24) }
    /// The cap sliver's radius in hours, same approximation.
    private var capHours: Double { Self.capRadius * upper / (Self.plotHeight - 24) }

    // MARK: - Derived data

    private struct Segment: Identifiable {
        let id: String
        let day: Int
        let start: Double
        let end: Double
        let color: Color
        let isTop: Bool
    }

    private struct DayTotal: Identifiable {
        var id: Int { day }
        let day: Int
        let total: Double
    }

    /// Hours per (series, day) in series order; days index into `days`.
    private var hoursBySeriesDay: [Int: [Int: Double]] {
        var out: [Int: [Int: Double]] = [:]
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        for p in points {
            guard let d = dayIndex[p.dayLabel] else { continue }
            out[p.projectId, default: [:]][d, default: 0] += p.hours
        }
        return out
    }

    private var segments: [Segment] {
        let hours = hoursBySeriesDay
        var out: [Segment] = []
        for day in days.indices {
            var cursor = 0.0
            let present = series.filter { (hours[$0.id]?[day] ?? 0) > 0 }
            for (i, s) in present.enumerated() {
                let h = hours[s.id]?[day] ?? 0
                let isTop = i == present.count - 1
                // Trim the gap off the top of every segment but the
                // last, so the stack's total height stays honest.
                let end = cursor + h - (isTop ? 0 : min(gapHours, h * 0.5))
                out.append(Segment(id: "\(s.id)-\(day)", day: day, start: cursor, end: end, color: s.color, isTop: isTop))
                cursor += h
            }
        }
        return out
    }

    private var dayTotals: [DayTotal] {
        let hours = hoursBySeriesDay
        return days.indices.map { day in
            DayTotal(day: day, total: series.reduce(0) { $0 + (hours[$1.id]?[day] ?? 0) })
        }
    }

    /// Y upper bound: at least the daily target, then 2h steps past the
    /// unfiltered peak with room for the cap label above the tallest
    /// column.
    private var upper: Double {
        var totals: [String: Double] = [:]
        for p in allPoints { totals[p.date, default: 0] += p.hours }
        let peak = totals.values.max() ?? 0
        let withHeadroom = ceil((peak + 1.0) / 2) * 2
        let targetCeiling = ceil(dailyTarget / 2) * 2
        return max(targetCeiling, withHeadroom, 2)
    }

    private var yTicks: [Double] { stride(from: 0, through: upper, by: 2).map { $0 } }

    // MARK: - Body

    var body: some View {
        Chart {
            ForEach(segments) { seg in
                // Every segment is square. `cornerRadius` would round all
                // four corners, so the top segment instead gets a same-
                // color rounded sliver laid over its top edge: its rounded
                // bottom corners sit on the square segment beneath, and
                // only the rounded top shows.
                BarMark(
                    x: .value("Day", seg.day),
                    yStart: .value("Start", seg.start),
                    yEnd: .value("End", seg.end),
                    width: .fixed(Self.columnWidth)
                )
                .foregroundStyle(seg.color)
                .opacity(hoveredDay == nil || hoveredDay == seg.day ? 1 : 0.4)

                if seg.isTop, seg.end - seg.start > capHours * 2 {
                    BarMark(
                        x: .value("Day", seg.day),
                        yStart: .value("Start", seg.end - capHours * 2),
                        yEnd: .value("End", seg.end),
                        width: .fixed(Self.columnWidth)
                    )
                    .foregroundStyle(seg.color)
                    .cornerRadius(Self.capRadius)
                    .opacity(hoveredDay == nil || hoveredDay == seg.day ? 1 : 0.4)
                }
            }

            // Day totals on the caps — the direct-label channel. Hidden
            // for a zero day so there's no "0h" floating on the axis.
            ForEach(dayTotals) { t in
                if t.total > 0 {
                    PointMark(x: .value("Day", t.day), y: .value("Hours", t.total))
                        .symbolSize(0)
                        .annotation(position: .top, spacing: 3) {
                            Text(Self.formatHours(t.total))
                                .font(YieldFonts.label(10, weight: .medium))
                                .foregroundStyle(YieldColors.textSecondary)
                        }
                }
            }

            // Workday reference. Dashed on purpose — it's a reference
            // line, not a gridline, and the dash is what tells them apart.
            RuleMark(y: .value("Target", dailyTarget))
                .foregroundStyle(YieldColors.textSecondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: -0.5...(Double(max(days.count, 1)) - 0.5))
        .chartYScale(domain: 0...upper)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: days.indices.map { $0 }) { value in
                AxisValueLabel(centered: false) {
                    if let idx = value.as(Int.self), idx >= 0, idx < days.count {
                        Text(days[idx])
                            .font(YieldFonts.label(10, weight: .medium))
                            .foregroundStyle(hoveredDay == idx ? YieldColors.textPrimary : YieldColors.textSecondary)
                    }
                }
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
        .animation(.easeInOut(duration: 0.15), value: hoveredDay)
    }

    // MARK: - Hover

    /// Transparent hit layer over the plot. Hovering picks the nearest
    /// day; the tooltip sits above that column, clamped to the plot.
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
                        if let day: Int = proxy.value(atX: x, as: Double.self).map({ Int($0.rounded()) }),
                           day >= 0, day < days.count,
                           plot.contains(location) {
                            hoveredDay = day
                        } else {
                            hoveredDay = nil
                        }
                    case .ended:
                        hoveredDay = nil
                    }
                }

            if let day = hoveredDay, let total = dayTotals.first(where: { $0.day == day }), total.total > 0,
               let columnX = proxy.position(forX: day) {
                tooltip(day: day, total: total.total)
                    .fixedSize()
                    .modifier(TooltipPlacement(columnX: plot.minX + columnX, plot: plot))
            }
        }
    }

    private func tooltip(day: Int, total: Double) -> some View {
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
                Text(total.formattedHoursMinutes)
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

    /// Positions the tooltip centered over a column, pulled inside the
    /// plot's horizontal bounds and sitting just under the top edge.
    private struct TooltipPlacement: ViewModifier {
        let columnX: CGFloat
        let plot: CGRect
        @State private var size: CGSize = .zero

        func body(content: Content) -> some View {
            content
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
                .position(
                    x: min(max(columnX, plot.minX + size.width / 2), plot.maxX - size.width / 2),
                    y: plot.minY + size.height / 2 + 4
                )
        }
    }

    // MARK: - Formatting

    static func formatHours(_ hours: Double) -> String {
        if hours == floor(hours) { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }
}

/// Legend for the column chart: an 8pt square swatch and the name in
/// text tokens. Clicking isolates a series; clicking it again clears.
struct WeeklyChartLegend: View {
    let series: [WeeklyColumnChart.Series]
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
