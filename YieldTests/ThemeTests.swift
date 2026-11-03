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
    /// store rather than caching the first value they saw.
    func test_tokensFollowTheActiveTheme() {
        ThemeStore.shared.select(.editorial)
        let editorialRow = YieldDimensions.projectRowForecastedHeight
        let editorialCard = YieldRadius.card

        ThemeStore.shared.select(.system)
        XCTAssertGreaterThan(YieldDimensions.projectRowForecastedHeight, editorialRow)
        XCTAssertGreaterThan(YieldRadius.card, editorialCard)
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

    func test_renderProjectRowsInEachTheme() throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set YIELD_SNAPSHOT_DIR to write theme snapshots")
        }
        let outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.select(original) }

        for theme in YieldTheme.allCases {
            ThemeStore.shared.select(theme)
            for (appearance, scheme) in [(NSAppearance.Name.darkAqua, ColorScheme.dark), (.aqua, .light)] {
                // `YieldColors` resolve via NSAppearance, so set it
                // app-wide for the render, not just the environment.
                NSApp.appearance = NSAppearance(named: appearance)

                let renderer = ImageRenderer(content: Self.sampleList().environment(\.colorScheme, scheme))
                renderer.scale = 2
                guard let cg = renderer.cgImage else {
                    XCTFail("no image for \(theme) \(appearance.rawValue)"); continue
                }
                let rep = NSBitmapImageRep(cgImage: cg)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    XCTFail("no png for \(theme)"); continue
                }
                let suffix = scheme == .dark ? "dark" : "light"
                try png.write(to: outDir.appendingPathComponent("rows-\(theme.rawValue)-\(suffix).png"))
            }
        }
        NSApp.appearance = nil
    }

    // MARK: - Fixtures

    /// Three rows that exercise the type hierarchy: a tracked booked
    /// project, a prospective one (pink line, link badge, no timer),
    /// and an unbooked logged-only one.
    private static func sampleList() -> some View {
        VStack(spacing: 0) {
            ProjectRowView(
                project: status(
                    client: "GEICO [GCO]", name: "Development Extension", code: "03",
                    booked: 18, logged: 4.02, tracking: true, harvestId: 1
                ),
                effectiveLoggedHours: 4.02,
                visibleEntries: []
            )
            ProjectRowView(
                project: status(
                    client: "GEICO [GCO]", name: "BOATUS.com Redesign", code: "04",
                    booked: 18, logged: 0, tracking: false, harvestId: nil, link: .prospective
                ),
                effectiveLoggedHours: 0,
                visibleEntries: []
            )
            ProjectRowView(
                project: status(
                    client: "Viget Labs", name: "Professional Development", code: nil,
                    booked: 0, logged: 3.83, tracking: false, harvestId: 2
                ),
                effectiveLoggedHours: 3.83,
                visibleEntries: []
            )
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
