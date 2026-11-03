import AppKit
import SwiftUI
import XCTest
@testable import Yield

/// Design exploration: the grouped row with the remaining label on the
/// *right*, under the bar — the first row comp's arrangement — instead
/// of under the name. Renders through the real `ProjectRowView` with
/// an alternate `ProjectRowLayout` that lives only in this test, so
/// production is untouched until a layout is chosen.
///
/// Opt-in via `YIELD_SNAPSHOT_DIR`, like the other renders.
@MainActor
final class RightLabelRowMockTests: XCTestCase {

    func test_renderRightLabelGroupedList() throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set YIELD_SNAPSHOT_DIR to write mock renders")
        }
        let outDir = URL(fileURLWithPath: dir, isDirectory: true)
        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.select(original); NSApp.appearance = nil }
        ThemeStore.shared.select(.system)

        let statuses = Self.fixtures.sorted(by: TimeComparisonViewModel.projectSortOrder)
        for (appearance, scheme, suffix) in [(NSAppearance.Name.darkAqua, ColorScheme.dark, "dark"), (.aqua, .light, "light")] {
            NSApp.appearance = NSAppearance(named: appearance)
            let list = VStack(spacing: 0) {
                ForEach(ProjectGrouping.grouped(statuses)) { group in
                    ClientSectionHeader(client: group.client)
                    ForEach(group.projects) { project in
                        ProjectRowView<RightLabelRowLayout>(project: project, effectiveLoggedHours: project.loggedHours, visibleEntries: [])
                    }
                }
            }
            .frame(width: YieldDimensions.panelWidth)
            .background(YieldColors.background)
            .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: list); r.scale = 2
            let png = NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!
            try png.write(to: outDir.appendingPathComponent("grouped-rightlabel-\(suffix).png"))
        }
    }

    private static let fixtures: [ProjectStatus] = [
        s("GEICO [GCO]", "Development Extension", "03", 18, 4.02, true, 1, .linked),
        s("GEICO [GCO]", "BOATUS.com Redesign", "04", 18, 0, false, nil, .prospective),
        s("Viget Labs", "Professional Development", nil, 0, 3.83, false, 2, .linked),
        s("Viget Labs", "Viget.com Redesign 2025–26", nil, 8, 9.5, false, 3, .linked),
        s("Alaska Airlines", "Loyalty App", "12", 10, 6.5, false, 4, .linked),
    ]

    private static func s(_ c: String, _ n: String, _ code: String?, _ b: Double, _ l: Double, _ t: Bool, _ h: Int?, _ link: ProjectStatus.HarvestLinkState) -> ProjectStatus {
        ProjectStatus(id: "snap-\(n)", clientName: c, projectName: n, projectCode: code, bookedHours: b, loggedHours: l, todayHours: 0, isTracking: t, harvestProjectId: h, todayEntryId: nil, lastTaskId: nil, timeEntries: [], forecastNotes: nil, harvestLinkState: link)
    }
}

/// Name only on the left; figure, bar and the state/remaining label
/// stacked on the right.
enum RightLabelRowLayout: ProjectRowLayout {
    static func leftColumn(_ ctx: ProjectRowHeaderContext) -> some View {
        HStack(spacing: 7) {
            if ctx.project.isTracking {
                Circle().fill(YieldColors.greenAccent).frame(width: 6, height: 6)
            }
            Text(ctx.project.displayName)
                .font(YieldFonts.titleMedium)
                .foregroundStyle(YieldColors.textPrimary)
                .lineLimit(1)
            HarvestLinkIcon(state: ctx.project.harvestLinkState, projectName: ctx.project.displayName)
            if ctx.hasEntries {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(YieldColors.textPrimary)
                    .rotationEffect(.degrees(ctx.isExpanded ? 180 : 0))
            }
        }
    }

    static func timeColumn(_ ctx: ProjectRowHeaderContext) -> some View {
        let p = ctx.project
        let label: (text: String, color: Color) = {
            guard p.isForecasted else { return ("Not booked in Forecast", YieldColors.textSecondary) }
            switch p.harvestLinkState {
            case .prospective: return ("Not linked to a Harvest project", YieldStatusColors.prospective)
            case .unassigned:  return ("Not a member of the Harvest project", YieldStatusColors.warning)
            case .linked:
                let remaining = p.bookedHours - ctx.effectiveLoggedHours
                return (RowFormat.remainingLabel(remaining), remaining < 0 ? YieldStatusColors.over : YieldColors.textSecondary)
            }
        }()
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if p.isForecasted && p.harvestLinkState == .prospective {
                    Text("—").font(YieldFonts.figureLarge).foregroundStyle(YieldColors.textSecondary)
                    Text("/ " + RowFormat.hoursOnly(p.bookedHours)).font(YieldFonts.figureDenominator).foregroundStyle(YieldColors.textSecondary)
                } else if p.isForecasted {
                    Text(RowFormat.hoursMinutes(ctx.effectiveLoggedHours)).font(YieldFonts.figureLarge).foregroundStyle(YieldColors.textPrimary)
                    Text("/ " + RowFormat.hoursOnly(p.bookedHours)).font(YieldFonts.figureDenominator).foregroundStyle(YieldColors.textSecondary)
                } else {
                    Text(RowFormat.hoursMinutes(ctx.effectiveLoggedHours)).font(YieldFonts.figureLarge).foregroundStyle(YieldColors.textPrimary)
                }
            }
            .fixedSize()
            if p.isForecasted {
                if p.harvestLinkState == .prospective {
                    Capsule()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(YieldStatusColors.prospective.opacity(0.6))
                        .frame(width: YieldDimensions.progressBarWidth, height: YieldDimensions.progressBarHeight)
                } else {
                    ProgressBarView(logged: ctx.effectiveLoggedHours, booked: p.bookedHours, dayLogged: ctx.dayFilteredHours)
                }
            }
            Text(label.text)
                .font(YieldFonts.rowSubtitle)
                .foregroundStyle(label.color)
                .lineLimit(1)
        }
    }
}
