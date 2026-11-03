import AppKit
import SwiftUI
import XCTest
@testable import Yield

/// Third exploration: the full-panel proposal without cards. Client
/// grouping as flat section headers over hairline-separated rows (the
/// row mock's structure), variant-B rows with the status stripe back,
/// and the timer hero and week summary as full-bleed bands.
///
/// Also tries SF Pro with tabular digits for the large numbers in
/// place of SF Mono — proportional type with fixed-width digits keeps
/// columns aligned without the mono space's wide gap in "6h 30m".
///
/// Mock-only, opt-in via `YIELD_SNAPSHOT_DIR`.
@MainActor
final class PanelFlatMockTests: XCTestCase {

    func test_renderFlatPanel() throws {
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
            let renderer = ImageRenderer(content: FlatPanel(fixtures: PanelRedesignMockTests.fixtures).environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                XCTFail("render failed for \(appearance.rawValue)"); continue
            }
            try png.write(to: outDir.appendingPathComponent("panel-flat-\(scheme == .dark ? "dark" : "light").png"))
        }
        NSApp.appearance = nil
    }
}

// MARK: - Flat panel (mock only)

private typealias Fixture = RowRedesignMockTests.Fixture

private enum Flat {
    static let inset: CGFloat = 16
    static let stripe: CGFloat = 3

    static func hm(_ hours: Double, short: Bool = false) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60, m = total % 60
        if short && m == 0 { return "\(h)h" }
        return String(format: "%dh %02dm", h, m)
    }

    /// Large figures: SF Pro, tabular digits.
    static func figure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }
    static func denominator(_ size: CGFloat) -> Font {
        .system(size: size).monospacedDigit()
    }
}

private struct FlatPanel: View {
    let fixtures: [Fixture]

    private var groups: [(client: String, projects: [Fixture])] {
        Dictionary(grouping: fixtures, by: \.client)
            .map { (client: $0.key, projects: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.client.localizedCaseInsensitiveCompare($1.client) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            FlatHeader()
            TimerBand(fixture: fixtures.first { $0.tracking })
            ForEach(groups, id: \.client) { group in
                SectionHeader(client: group.client)
                ForEach(group.projects) { project in
                    FlatRow(fixture: project)
                }
            }
            SummaryBand(fixtures: fixtures)
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
    }
}

private struct FlatHeader: View {
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
        .padding(.horizontal, Flat.inset)
        .padding(.vertical, 12)
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

/// Full-bleed tinted band, hairline above and below — the shape the
/// current banner already has, with the number promoted.
private struct TimerBand: View {
    let fixture: Fixture?

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
                    .font(Flat.figure(22))
                    .foregroundStyle(YieldColors.greenAccent)
                control("pause.fill")
                control("stop.fill")
            }
            .padding(.horizontal, Flat.inset)
            .padding(.vertical, 12)
            .background(YieldColors.greenFaint)
            .overlay(alignment: .top) { Rectangle().fill(YieldColors.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(YieldColors.border).frame(height: 1) }
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

private struct SectionHeader: View {
    let client: String
    var body: some View {
        Text(client)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(YieldColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Flat.stripe + Flat.inset)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}

/// Variant B with the stripe: two lines each side, ~58pt.
private struct FlatRow: View {
    let fixture: Fixture

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

    private var stripe: Color {
        status == .unbooked ? YieldStatusColors.unbooked : tint
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle().fill(stripe).frame(width: Flat.stripe)

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
            .padding(.horizontal, Flat.inset)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(YieldColors.border).frame(height: 1)
        }
    }

    private var subtitle: String {
        switch status {
        case .onTrack:     return "\(Flat.hm(fixture.booked - fixture.logged)) remaining this week"
        case .over:        return "\(Flat.hm(fixture.logged - fixture.booked)) over this week"
        case .prospective: return "Not linked to a Harvest project"
        case .unbooked:    return "Not booked in Forecast"
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        switch status {
        case .unbooked:
            Text(Flat.hm(fixture.logged))
                .font(Flat.figure(16))
                .foregroundStyle(YieldColors.textPrimary)

        case .prospective:
            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("—").font(Flat.figure(16)).foregroundStyle(YieldColors.textSecondary)
                    Text("/ \(Flat.hm(fixture.booked, short: true))")
                        .font(Flat.denominator(12))
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
                    Text(Flat.hm(fixture.logged))
                        .font(Flat.figure(16))
                        .foregroundStyle(YieldColors.textPrimary)
                    Text("/ \(Flat.hm(fixture.booked, short: true))")
                        .font(Flat.denominator(12))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                FlatStatusBar(fraction: fixture.logged / fixture.booked, tint: tint)
                    .frame(width: 140, height: 5)
            }
        }
    }
}

private struct FlatStatusBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(YieldColors.progressTrack)
                Capsule().fill(tint).frame(width: geo.size.width * min(fraction, 1))
                if fraction > 1 {
                    Rectangle()
                        .fill(YieldColors.background)
                        .frame(width: 2)
                        .offset(x: geo.size.width * (1 / fraction) - 1)
                }
            }
        }
    }
}

/// Footer band: hairline above, no fill.
private struct SummaryBand: View {
    let fixtures: [Fixture]

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
                Text("+ \(Flat.hm(unbooked)) unbooked")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
                Text(Flat.hm(logged))
                    .font(Flat.figure(14))
                    .foregroundStyle(YieldColors.textPrimary)
                    .padding(.leading, 8)
                Text("/ \(Flat.hm(total, short: true))")
                    .font(Flat.denominator(11))
                    .foregroundStyle(YieldColors.textSecondary)
            }
            FlatStatusBar(fraction: logged / total, tint: YieldColors.greenAccent)
                .frame(height: 5)
        }
        .padding(.horizontal, Flat.inset + Flat.stripe)
        .padding(.vertical, 12)
        .padding(.top, 4)
    }
}
