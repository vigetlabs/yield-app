import AppKit
import SwiftUI
import XCTest
@testable import Yield

/// Design exploration — the whole panel this time. Builds on the row
/// mock: variant-B rows (remaining under the name, right column is
/// number + bar), client groups as cards, a "now playing" timer hero,
/// and a week summary footer. Ordering is alphabetical by client, then
/// by project *name* — codes are context, not sort keys.
///
/// Mock-only; nothing here touches production views. Opt-in via
/// `YIELD_SNAPSHOT_DIR` like the other renders.
@MainActor
final class PanelRedesignMockTests: XCTestCase {

    func test_renderProposedPanel() throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set YIELD_SNAPSHOT_DIR to write mock renders")
        }
        let outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.select(original) }
        ThemeStore.shared.select(.system)

        for (appearance, scheme) in [(NSAppearance.Name.darkAqua, ColorScheme.dark), (.aqua, .light)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let renderer = ImageRenderer(content: ProposedPanel(fixtures: Self.fixtures).environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                XCTFail("render failed for \(appearance.rawValue)"); continue
            }
            try png.write(to: outDir.appendingPathComponent("panel-redesign-\(scheme == .dark ? "dark" : "light").png"))
        }
        NSApp.appearance = nil
    }

    typealias Fixture = RowRedesignMockTests.Fixture

    /// A third client so the alphabetical grouping is visible, plus the
    /// four from the row mock. Deliberately out of order here — the
    /// panel sorts.
    static let fixtures: [Fixture] = RowRedesignMockTests.Fixture.all + [
        .init(id: "5", client: "Alaska Airlines", name: "Loyalty App", code: "12",
              booked: 10, logged: 6.5, tracking: false, link: .linked),
    ]
}

// MARK: - Proposed panel (mock only)

private enum Mock {
    static let gutter: CGFloat = 12
    static let cardRadius: CGFloat = 10

    static func hm(_ hours: Double, short: Bool = false) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60, m = total % 60
        if short && m == 0 { return "\(h)h" }
        return String(format: "%dh %02dm", h, m)
    }
}

private struct ProposedPanel: View {
    let fixtures: [PanelRedesignMockTests.Fixture]

    private var groups: [(client: String, projects: [PanelRedesignMockTests.Fixture])] {
        Dictionary(grouping: fixtures, by: \.client)
            .map { (client: $0.key, projects: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.client.localizedCaseInsensitiveCompare($1.client) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: Mock.gutter) {
            MockHeader()
            TimerHero(fixture: fixtures.first { $0.tracking })
            ForEach(groups, id: \.client) { group in
                ClientCard(client: group.client, projects: group.projects)
            }
            WeekSummary(fixtures: fixtures)
        }
        .padding(.vertical, Mock.gutter)
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
    }
}

/// Week nav + title + the two primary actions.
private struct MockHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            navButton("chevron.left")
            Text("Sep 22 – 28")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(YieldColors.textPrimary)
            navButton("chevron.right")
            Spacer()
            pill(icon: "calendar", label: nil)
            pill(icon: "plus", label: "Timer")
        }
        .padding(.horizontal, Mock.gutter + 4)
    }

    private func navButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(YieldColors.textSecondary)
            .frame(width: 24, height: 24)
            .background(YieldColors.surfaceDefault)
            .yieldBorder(radius: 6)
    }

    private func pill(icon: String, label: String?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            if let label { Text(label).font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(YieldColors.textPrimary)
        .padding(.horizontal, label == nil ? 7 : 10)
        .frame(height: 26)
        .background(YieldColors.surfaceDefault)
        .yieldBorder(radius: 6)
    }
}

/// The running timer as the panel's hero: big tabular elapsed time,
/// project and task beside it, circular controls. The faint green wash
/// already exists in the palette — this leans on it.
private struct TimerHero: View {
    let fixture: PanelRedesignMockTests.Fixture?

    var body: some View {
        if let fixture {
            HStack(spacing: 14) {
                Circle().fill(YieldColors.greenAccent).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FED")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(YieldColors.textPrimary)
                    Text("\(fixture.client) — \(ProjectStatus.displayName(code: fixture.code, project: fixture.name))")
                        .font(.system(size: 11))
                        .foregroundStyle(YieldColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("1:10:24")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(YieldColors.greenAccent)
                control("pause.fill")
                control("stop.fill")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(YieldColors.greenFaint)
            .background(YieldColors.surfaceDefault)
            .clipShape(RoundedRectangle(cornerRadius: Mock.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Mock.cardRadius).strokeBorder(YieldColors.greenBorder, lineWidth: 1))
            .padding(.horizontal, Mock.gutter)
        }
    }

    private func control(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(YieldColors.greenAccent)
            .frame(width: 28, height: 28)
            .background(YieldColors.greenSubtle)
            .clipShape(Circle())
    }
}

/// One card per client: a quiet header, then the client's projects
/// separated by hairlines. No left status stripe anymore — with rows
/// inside a rounded card the bar and the remaining label carry status.
private struct ClientCard: View {
    let client: String
    let projects: [PanelRedesignMockTests.Fixture]

    var body: some View {
        VStack(spacing: 0) {
            Text(client)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                ProjectRowB(fixture: project)
                if index < projects.count - 1 {
                    Rectangle().fill(YieldColors.border).frame(height: 1).padding(.leading, 14)
                }
            }
        }
        .padding(.bottom, 2)
        .yieldCard()
        .padding(.horizontal, Mock.gutter)
    }
}

/// Variant B: both columns are two lines. Name + remaining on the left,
/// number + bar on the right. ~58pt instead of 80.
private struct ProjectRowB: View {
    let fixture: PanelRedesignMockTests.Fixture

    private enum Status { case onTrack, over, prospective, unbooked }

    private var status: Status {
        if fixture.link == .prospective { return .prospective }
        if fixture.booked == 0 { return .unbooked }
        let tolerance = max(0.5, fixture.booked * 0.1)
        return fixture.logged - fixture.booked > tolerance ? .over : .onTrack
    }

    private var tint: Color {
        switch status {
        case .onTrack:     return YieldColors.greenAccent
        case .over:        return YieldStatusColors.over
        case .prospective: return YieldStatusColors.prospective
        case .unbooked:    return YieldColors.textSecondary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if fixture.tracking {
                        Circle().fill(YieldColors.greenAccent).frame(width: 6, height: 6)
                    }
                    Text(ProjectStatus.displayName(code: fixture.code, project: fixture.name))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                    HarvestLinkIcon(state: fixture.link, projectName: fixture.name)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
            }

            Spacer(minLength: 12)

            rightColumn
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        switch status {
        case .onTrack:     return "\(Mock.hm(fixture.booked - fixture.logged)) remaining this week"
        case .over:        return "\(Mock.hm(fixture.logged - fixture.booked)) over this week"
        case .prospective: return "Not linked to a Harvest project"
        case .unbooked:    return "Not booked in Forecast"
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        switch status {
        case .unbooked:
            Text(Mock.hm(fixture.logged))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(YieldColors.textPrimary)

        case .prospective:
            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("—")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(YieldColors.textSecondary)
                    Text("/ \(Mock.hm(fixture.booked, short: true))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                Capsule()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(tint.opacity(0.6))
                    .frame(width: 140, height: 5)
            }

        case .onTrack, .over:
            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Mock.hm(fixture.logged))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(YieldColors.textPrimary)
                    Text("/ \(Mock.hm(fixture.booked, short: true))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                StatusBar(fraction: fixture.logged / fixture.booked, tint: tint)
                    .frame(width: 140, height: 5)
            }
        }
    }
}

/// Fill tinted by status. Past 100% the fill stays full and a thin
/// tick marks the budget line, so "over" reads as over, not complete.
private struct StatusBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(YieldColors.progressTrack)
                Capsule().fill(tint).frame(width: geo.size.width * min(fraction, 1))
                if fraction > 1 {
                    // Budget line sits at booked ÷ logged of the width.
                    Rectangle()
                        .fill(YieldColors.background)
                        .frame(width: 2)
                        .offset(x: geo.size.width * (1 / fraction) - 1)
                }
            }
        }
    }
}

/// Glanceable week total: logged over booked, one full-width bar.
private struct WeekSummary: View {
    let fixtures: [PanelRedesignMockTests.Fixture]

    var body: some View {
        let booked = fixtures.filter { $0.booked > 0 }
        let logged = booked.reduce(0) { $0 + $1.logged }
        let total = booked.reduce(0) { $0 + $1.booked }
        let unbooked = fixtures.filter { $0.booked == 0 }.reduce(0) { $0 + $1.logged }

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(YieldColors.textSecondary)
                Spacer()
                Text("+ \(Mock.hm(unbooked)) unbooked")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                Text(Mock.hm(logged))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(YieldColors.textPrimary)
                    .padding(.leading, 8)
                Text("/ \(Mock.hm(total, short: true))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            StatusBar(fraction: logged / total, tint: YieldColors.greenAccent)
                .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .yieldCard()
        .padding(.horizontal, Mock.gutter)
    }
}
