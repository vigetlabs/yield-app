import SwiftUI

/// The selected day's meetings as a thin timeline: a pill per meeting,
/// placed by the clock, and — today — a line marking now. It is the
/// panel of the weekday bar's selected tab: the same fill, butted up
/// against the tab above it.
struct ScheduleStripView: View {
    let strip: ScheduleStrip
    /// Space between the panel's edge and the timeline, each side.
    var horizontalInset: CGFloat = 12
    /// The top-leading corner, when it isn't the panel's usual one: a
    /// first tab sits just inside that corner, and the curve has to be
    /// over before the tab's edge for the two to join.
    var topLeadingRadius: CGFloat?
    /// Opens the day's schedule. Nil where there is none to open.
    var onOpen: (() -> Void)?

    private static let labelHeight: CGFloat = 11
    private static let labelGap: CGFloat = 3
    /// The band the pills sit in, whatever the number of lanes: one
    /// 5pt pill, or two of 4pt.
    private static let laneAreaHeight: CGFloat = 10
    private static let laneGap: CGFloat = 2
    private static let maxLaneHeight: CGFloat = 5
    /// Narrowest a pill is drawn, so a five-minute event is still seen.
    private static let minBlockWidth: CGFloat = 3
    /// Below this an hour column can't hold its own label; every other
    /// one is dropped.
    private static let minLabelledColumnWidth: CGFloat = 30

    private var laneHeight: CGFloat {
        let lanes = CGFloat(strip.laneCount)
        return min(Self.maxLaneHeight, (Self.laneAreaHeight - Self.laneGap * (lanes - 1)) / lanes)
    }

    /// Top of lane 0: the lanes are centred in their band.
    private var lanesTop: CGFloat {
        let lanes = CGFloat(strip.laneCount)
        let used = lanes * laneHeight + (lanes - 1) * Self.laneGap
        return Self.labelHeight + Self.labelGap + (Self.laneAreaHeight - used) / 2
    }

    private var panelShape: UnevenRoundedRectangle {
        let radius = YieldRadius.button
        return UnevenRoundedRectangle(
            topLeadingRadius: topLeadingRadius ?? radius, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: radius
        )
    }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) { panel.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Meetings")
                .accessibilityHint("Opens the day's schedule")
        } else {
            panel
        }
    }

    private var panel: some View {
        GeometryReader { geo in
            // An empty day is said in words, in place of the hours: at
            // this height a caption under the hour labels only crowds
            // them, and an empty scale says nothing on its own.
            if strip.blocks.isEmpty, strip.isLoaded {
                Text("No meetings")
                    .font(YieldFonts.label(10))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                timeline(width: geo.size.width)
            }
        }
        .frame(height: Self.labelHeight + Self.labelGap + Self.laneAreaHeight)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .background(panelShape.fill(WeekDayBarView.selectedFill))
    }

    /// Hour labels and lines, the pills over them, and the now-line.
    private func timeline(width: CGFloat) -> some View {
        let columnWidth = width / CGFloat(max(strip.hourMarks.count, 1))
        let labelStride = columnWidth < Self.minLabelledColumnWidth ? 2 : 1

        return ZStack(alignment: .topLeading) {
            ForEach(Array(strip.hourMarks.enumerated()), id: \.offset) { index, mark in
                let x = CGFloat(mark.fraction) * width
                if index % labelStride == 0 {
                    Text(mark.label)
                        .font(YieldFonts.label(9, weight: .medium))
                        .foregroundStyle(YieldColors.textSecondary)
                        .fixedSize()
                        .frame(height: Self.labelHeight, alignment: .top)
                        .offset(x: x)
                }
                // Fainter text rather than the border colour, which
                // all but disappears on the panel's tint.
                Rectangle()
                    .fill(YieldColors.textSecondary.opacity(0.22))
                    .frame(width: 1, height: Self.laneAreaHeight)
                    .offset(x: x, y: Self.labelHeight + Self.labelGap)
            }

            ForEach(strip.blocks) { block in
                // A 1pt seam, so back-to-back meetings read as two.
                let blockWidth = max(Self.minBlockWidth, CGFloat(block.width) * width - 1)
                let pill = RoundedRectangle(cornerRadius: min(3, laneHeight / 2))
                pill.fill(Self.fill(for: block.phase))
                    // The panel's own colour underneath, so an hour
                    // line doesn't show through the lighter fills.
                    .modifier(PanelUnderlay(shape: pill))
                    .frame(width: blockWidth, height: laneHeight)
                    .help(block.event.tooltip)
                    .offset(
                        x: min(CGFloat(block.start) * width + 1, width - blockWidth),
                        y: lanesTop + CGFloat(block.lane) * (laneHeight + Self.laneGap)
                    )
            }

            if let now = strip.nowFraction {
                // The day view's red now-line, stood on end. The
                // margin of panel colour either side cuts it out of
                // a pill it crosses, where red on the accent would
                // be lost.
                Capsule()
                    .fill(YieldStatusColors.over)
                    .frame(width: 2, height: Self.laneAreaHeight + 4)
                    .padding(.horizontal, 1)
                    .modifier(PanelUnderlay(shape: Rectangle()))
                    .offset(x: CGFloat(now) * width - 2, y: Self.labelHeight + Self.labelGap - 2)
            }
        }
    }

    /// Only today tells what's on (solid) from what's coming (lighter)
    /// and what's over (fainter still); other days are all "coming".
    private static func fill(for phase: ScheduleStrip.Phase) -> Color {
        switch phase {
        case .past:     return YieldColors.controlAccent.opacity(0.3)
        case .current:  return YieldColors.controlAccent
        case .upcoming: return YieldColors.controlAccent.opacity(0.55)
        }
    }
}

/// The panel's colour — its tint over the window's — behind something
/// drawn on the panel that has to hide what is under it.
private struct PanelUnderlay<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(shape.fill(WeekDayBarView.selectedFill))
            .background(shape.fill(YieldColors.background))
    }
}
