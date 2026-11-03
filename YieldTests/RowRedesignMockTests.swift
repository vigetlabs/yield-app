import AppKit
import SwiftUI
import XCTest
@testable import Yield

/// Design exploration, not a regression test. Renders the current
/// System-theme project rows above a *proposed* row design — client
/// grouping, number-first right column, status-tinted bars — so the
/// two can be compared as pixels before any production view changes.
///
/// The proposed row lives entirely in this file. Opt-in like
/// `ThemeSnapshotTests`: set `YIELD_SNAPSHOT_DIR`, otherwise skips.
@MainActor
final class RowRedesignMockTests: XCTestCase {

    func test_renderCurrentVersusProposedRows() throws {
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
            let renderer = ImageRenderer(content: Self.comparison().environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                XCTFail("render failed for \(appearance.rawValue)"); continue
            }
            let suffix = scheme == .dark ? "dark" : "light"
            try png.write(to: outDir.appendingPathComponent("row-redesign-\(suffix).png"))
        }
        NSApp.appearance = nil
    }

    // MARK: - Composition

    private static func comparison() -> some View {
        VStack(spacing: 0) {
            caption("CURRENT — System theme")
            ForEach(Fixture.all) { f in
                ProjectRowView(project: f.status, effectiveLoggedHours: f.logged, visibleEntries: [])
            }

            Rectangle().fill(Color.clear).frame(height: 28)
            caption("PROPOSED — grouped by client, number-first")
            ProposedList(fixtures: Fixture.all)
            Rectangle().fill(Color.clear).frame(height: 8)
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
    }

    private static func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(YieldColors.textSecondary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    // MARK: - Fixtures

    struct Fixture: Identifiable {
        let id: String
        let client: String
        let name: String
        let code: String?
        let booked: Double
        let logged: Double
        let tracking: Bool
        let link: ProjectStatus.HarvestLinkState

        var status: ProjectStatus {
            ProjectStatus(
                id: id, clientName: client, projectName: name, projectCode: code,
                bookedHours: booked, loggedHours: logged, todayHours: 0, isTracking: tracking,
                harvestProjectId: link == .prospective ? nil : 1, todayEntryId: nil, lastTaskId: nil,
                timeEntries: [], forecastNotes: nil, harvestLinkState: link
            )
        }

        static let all: [Fixture] = [
            .init(id: "1", client: "GEICO [GCO]", name: "Development Extension", code: "03",
                  booked: 18, logged: 4.02, tracking: true, link: .linked),
            .init(id: "2", client: "GEICO [GCO]", name: "BOATUS.com Redesign", code: "04",
                  booked: 18, logged: 0, tracking: false, link: .prospective),
            .init(id: "3", client: "Viget Labs", name: "Professional Development", code: nil,
                  booked: 0, logged: 3.83, tracking: false, link: .linked),
            .init(id: "4", client: "Viget Labs", name: "Viget.com Redesign 2025–26", code: nil,
                  booked: 8, logged: 9.5, tracking: false, link: .linked),
        ]
    }
}

// MARK: - Proposed design (mock only)

/// Rows grouped under one client header each; the per-row uppercase
/// client label is gone, so the project name is the row's first and
/// largest line.
private struct ProposedList: View {
    let fixtures: [RowRedesignMockTests.Fixture]

    var body: some View {
        let groups = Dictionary(grouping: fixtures, by: \.client)
        let order = fixtures.map(\.client).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        VStack(spacing: 0) {
            ForEach(order, id: \.self) { client in
                ClientHeader(name: client)
                ForEach(groups[client] ?? []) { f in
                    ProposedRow(fixture: f)
                }
            }
        }
    }
}

private struct ClientHeader: View {
    let name: String
    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(YieldColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 19)   // stripe (3) + content inset (16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

private struct ProposedRow: View {
    let fixture: RowRedesignMockTests.Fixture

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
        case .unbooked:    return YieldStatusColors.unbooked
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Status stripe stays, but it's no longer the only carrier.
            Rectangle().fill(tint).frame(width: 3)

            HStack(alignment: .center, spacing: 12) {
                // Name — now the first line of the row.
                HStack(spacing: 8) {
                    if fixture.tracking {
                        Circle().fill(YieldColors.greenAccent).frame(width: 6, height: 6)
                    }
                    Text(ProjectStatus.displayName(code: fixture.code, project: fixture.name))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(YieldColors.textPrimary)
                        .lineLimit(1)
                    HarvestLinkIcon(state: fixture.link, projectName: fixture.name)
                }

                Spacer(minLength: 12)

                rightColumn
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(YieldColors.border).frame(height: 1)
        }
    }

    /// The number is the headline. Booked is the denominator, the bar
    /// sits beneath at full column width, and the remaining label lives
    /// under the bar in the status tint instead of competing with the
    /// name on the left.
    @ViewBuilder
    private var rightColumn: some View {
        switch status {
        case .unbooked:
            Text(hm(fixture.logged))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(YieldColors.textPrimary)

        case .prospective:
            VStack(alignment: .trailing, spacing: 6) {
                Text("Not linked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
                DashedTrack(tint: tint).frame(width: 150, height: 5)
                Text("\(hm(fixture.booked)) booked")
                    .font(.system(size: 10))
                    .foregroundStyle(YieldColors.textSecondary)
            }

        case .onTrack, .over:
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hm(fixture.logged))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(YieldColors.textPrimary)
                    Text("/ \(hm(fixture.booked, short: true))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                ProgressTrack(fraction: min(fixture.logged / fixture.booked, 1), tint: tint)
                    .frame(width: 150, height: 5)
                Text(remainingLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
            }
        }
    }

    private var remainingLabel: String {
        let delta = fixture.booked - fixture.logged
        return delta >= 0 ? "\(hm(delta)) remaining this week" : "\(hm(-delta)) over this week"
    }

    private func hm(_ hours: Double, short: Bool = false) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60, m = total % 60
        if short && m == 0 { return "\(h)h" }
        return String(format: "%dh %02dm", h, m)
    }
}

private struct ProgressTrack: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(YieldColors.progressTrack)
                Capsule().fill(tint).frame(width: geo.size.width * fraction)
            }
        }
    }
}

private struct DashedTrack: View {
    let tint: Color
    var body: some View {
        Capsule()
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(tint.opacity(0.6))
    }
}
