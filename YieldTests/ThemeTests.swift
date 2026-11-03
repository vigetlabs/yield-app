import AppKit
import SwiftUI
import XCTest
@testable import Yield

/// `YieldTheme` / `ThemeStore` behavior: the default, persistence, and
/// that the two looks actually differ where they claim to.
@MainActor
final class ThemeTests: XCTestCase {

    private var original: YieldTheme!

    override func setUp() {
        super.setUp()
        original = ThemeStore.shared.theme
    }

    override func tearDown() {
        // The test host shares the real app's UserDefaults domain —
        // never leave the user's choice changed.
        ThemeStore.shared.select(original)
        super.tearDown()
    }

    func test_defaultIsEditorial() {
        XCTAssertEqual(YieldTheme.default, .editorial)
    }

    func test_selectPersistsAndUpdatesLiveValue() {
        ThemeStore.shared.select(.system)
        XCTAssertEqual(ThemeStore.shared.theme, .system)
        XCTAssertEqual(UserDefaults.standard.string(forKey: DefaultsKey.uiTheme), "system")

        ThemeStore.shared.select(.editorial)
        XCTAssertEqual(ThemeStore.shared.theme, .editorial)
        XCTAssertEqual(UserDefaults.standard.string(forKey: DefaultsKey.uiTheme), "editorial")
    }

    /// The tokens are `static var`s — confirm they actually follow the
    /// store rather than caching the first value they saw. Direction is
    /// deliberately not asserted: System rows went *shorter* when the
    /// grouped layout landed, and the invariant is "follows", not
    /// "bigger".
    func test_tokensFollowTheActiveTheme() {
        ThemeStore.shared.select(.editorial)
        let editorialRow = YieldDimensions.projectRowForecastedHeight
        let editorialCard = YieldRadius.card
        let editorialBar = YieldDimensions.progressBarWidth

        ThemeStore.shared.select(.system)
        XCTAssertNotEqual(YieldDimensions.projectRowForecastedHeight, editorialRow)
        XCTAssertNotEqual(YieldRadius.card, editorialCard)
        XCTAssertNotEqual(YieldDimensions.progressBarWidth, editorialBar)

        ThemeStore.shared.select(.editorial)
        XCTAssertEqual(YieldDimensions.projectRowForecastedHeight, editorialRow)
    }

    /// The layout fork is gated on one flag; pin which theme owns it.
    func test_onlySystemUsesGroupedLayout() {
        XCTAssertFalse(YieldTheme.editorial.usesGroupedLayout)
        XCTAssertTrue(YieldTheme.system.usesGroupedLayout)
    }

    /// The System theme's whole point is dropping the serif; make sure
    /// no AppKit site can still hand one back.
    func test_systemThemeUsesNoBundledFonts() {
        ThemeStore.shared.select(.system)
        for size: CGFloat in [10, 12, 14] {
            XCTAssertFalse(YieldFonts.nsTitle(size).fontName.contains("Newsreader"))
            XCTAssertFalse(YieldFonts.nsLabel(size, weight: .semibold).fontName.contains("DMSans"))
        }
    }

    func test_editorialThemeKeepsBundledFonts() {
        ThemeStore.shared.select(.editorial)
        XCTAssertEqual(YieldFonts.nsTitle(12).fontName, "Newsreader-Regular")
        XCTAssertEqual(YieldFonts.nsLabel(10, weight: .semibold).fontName, "DMSans-SemiBold")
    }
}

/// Renders the project list in each theme to PNG so the two looks can
/// be compared side by side. Opt-in: set `YIELD_SNAPSHOT_DIR` to an
/// output directory (via `TEST_RUNNER_YIELD_SNAPSHOT_DIR` on
/// `xcodebuild test`); otherwise this skips, so the normal suite stays
/// fast and file-free.
@MainActor
final class ThemeSnapshotTests: XCTestCase {

    /// Renders, in this order: Editorial rows, System rows, then the
    /// System grouped list. One method, not three, because order is
    /// load-bearing: rendering the System theme first in a process
    /// shifts Editorial's text antialiasing by 1/255 on a few hundred
    /// glyph-edge pixels (measured — same code, same harness, only the
    /// order differed). Editorial goes first so `rows-editorial-*.png`
    /// stays a valid pixel-identity check against the pre-fork render.
    func test_renderThemes() throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set YIELD_SNAPSHOT_DIR to write theme snapshots")
        }
        let outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.select(original); NSApp.appearance = nil }

        let appearances: [(NSAppearance.Name, ColorScheme, String)] = [(.darkAqua, .dark, "dark"), (.aqua, .light, "light")]

        // 1 + 2: the three sample rows, Editorial first.
        for theme in [YieldTheme.editorial, .system] {
            ThemeStore.shared.select(theme)
            for (appearance, scheme, suffix) in appearances {
                NSApp.appearance = NSAppearance(named: appearance)
                try Self.write(Self.sampleList().environment(\.colorScheme, scheme),
                               to: outDir.appendingPathComponent("rows-\(theme.rawValue)-\(suffix).png"))
            }
        }

        // 3: the System list as the panel composes it — section
        // headers, grouped rows, week summary band — all real views.
        ThemeStore.shared.select(.system)
        let statuses = Self.groupedFixtures.sorted(by: TimeComparisonViewModel.projectSortOrder)
        let booked = statuses.filter { $0.bookedHours > 0 }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            let list = VStack(spacing: 0) {
                ForEach(ProjectGrouping.grouped(statuses)) { group in
                    ClientSectionHeader(client: group.client)
                    ForEach(group.projects) { project in
                        ProjectRowView<GroupedRowLayout>(project: project, effectiveLoggedHours: project.loggedHours, visibleEntries: [])
                    }
                }
                WeekSummaryBand(
                    logged: booked.reduce(0) { $0 + $1.loggedHours },
                    booked: booked.reduce(0) { $0 + $1.bookedHours },
                    unbooked: statuses.filter { $0.bookedHours == 0 }.reduce(0) { $0 + $1.loggedHours }
                )
            }
            .frame(width: YieldDimensions.panelWidth)
            .background(YieldColors.background)
            .environment(\.colorScheme, scheme)
            try Self.write(list, to: outDir.appendingPathComponent("grouped-system-\(suffix).png"))
        }
    }

    @MainActor
    private static func write<V: View>(_ view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            XCTFail("render failed for \(url.lastPathComponent)"); return
        }
        try png.write(to: url)
    }

    // MARK: - Fixtures

    /// Three clients, five projects, every row state: tracking, on
    /// track, prospective, unbooked, over.
    private static let groupedFixtures: [ProjectStatus] = [
        status(client: "GEICO [GCO]", name: "Development Extension", code: "03",
               booked: 18, logged: 4.02, tracking: true, harvestId: 1),
        status(client: "GEICO [GCO]", name: "BOATUS.com Redesign", code: "04",
               booked: 18, logged: 0, tracking: false, harvestId: nil, link: .prospective),
        status(client: "Viget Labs", name: "Professional Development", code: nil,
               booked: 0, logged: 3.83, tracking: false, harvestId: 2),
        status(client: "Viget Labs", name: "Viget.com Redesign 2025–26", code: nil,
               booked: 8, logged: 9.5, tracking: false, harvestId: 3),
        status(client: "Alaska Airlines", name: "Loyalty App", code: "12",
               booked: 10, logged: 6.5, tracking: false, harvestId: 4),
    ]


    /// Three rows that exercise the type hierarchy: a tracked booked
    /// project, a prospective one (pink line, link badge, no timer),
    /// and an unbooked logged-only one.
    /// Built the way the panel builds its list — the layout switch
    /// above a `ForEach` of rows — so the Editorial render is a fair
    /// stand-in for the app when compared against the pre-fork commit.
    private static func sampleList() -> some View {
        let statuses = [
            status(client: "GEICO [GCO]", name: "Development Extension", code: "03",
                   booked: 18, logged: 4.02, tracking: true, harvestId: 1),
            status(client: "GEICO [GCO]", name: "BOATUS.com Redesign", code: "04",
                   booked: 18, logged: 0, tracking: false, harvestId: nil, link: .prospective),
            status(client: "Viget Labs", name: "Professional Development", code: nil,
                   booked: 0, logged: 3.83, tracking: false, harvestId: 2),
        ]
        return VStack(spacing: 0) {
            // The layout switch sits above the rows, as in the panel.
            if ThemeStore.shared.theme.usesGroupedLayout {
                ForEach(statuses) { project in
                    ProjectRowView<GroupedRowLayout>(project: project, effectiveLoggedHours: project.loggedHours, visibleEntries: [])
                }
            } else {
                ForEach(statuses) { project in
                    ProjectRowView<EditorialRowLayout>(project: project, effectiveLoggedHours: project.loggedHours, visibleEntries: [])
                }
            }
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
    }

    private static func status(
        client: String, name: String, code: String?,
        booked: Double, logged: Double, tracking: Bool, harvestId: Int?,
        link: ProjectStatus.HarvestLinkState = .linked
    ) -> ProjectStatus {
        ProjectStatus(
            id: "snap-\(name)",
            clientName: client,
            projectName: name,
            projectCode: code,
            bookedHours: booked,
            loggedHours: logged,
            todayHours: 0,
            isTracking: tracking,
            harvestProjectId: harvestId,
            todayEntryId: nil,
            lastTaskId: nil,
            timeEntries: [],
            forecastNotes: nil,
            harvestLinkState: link
        )
    }
}
