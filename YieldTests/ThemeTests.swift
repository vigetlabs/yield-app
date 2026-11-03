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
        XCTAssertFalse(YieldTheme.editorial.usesRefreshedLayout)
        XCTAssertTrue(YieldTheme.system.usesRefreshedLayout)
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

    /// Renders, in this order: Editorial rows and chart, System rows,
    /// the System grouped list, the System chart. One method, not
    /// several, because order is load-bearing: rendering the System
    /// theme anywhere earlier in the process shifts Editorial's text
    /// antialiasing by 1/255 on a few hundred glyph-edge pixels
    /// (measured — same code, same harness, only the order differed;
    /// it recurred once already when a separate chart test class
    /// happened to sort first). Everything Editorial renders before
    /// anything System does, so `*-editorial-*.png` stay valid
    /// pixel-identity checks against the pre-fork renders.
    func test_renderThemes() throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set YIELD_SNAPSHOT_DIR to write theme snapshots")
        }
        let outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.select(original); NSApp.appearance = nil }

        let appearances: [(NSAppearance.Name, ColorScheme, String)] = [(.darkAqua, .dark, "dark"), (.aqua, .light, "light")]

        let chartVM = Self.makeChartViewModel()

        // 1: everything Editorial — rows, then chart.
        ThemeStore.shared.select(.editorial)
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.sampleList().environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("rows-editorial-\(suffix).png"))
        }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.chart(chartVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("chart-editorial-\(suffix).png"))
        }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.bars(chartVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("bars-editorial-\(suffix).png"))
        }
        let bannerVM = Self.makeBannerViewModel()
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.banner(bannerVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("banner-editorial-\(suffix).png"))
        }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.header(bannerVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("header-editorial-\(suffix).png"))
        }

        // 2: System rows.
        ThemeStore.shared.select(.system)
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.sampleList().environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("rows-system-\(suffix).png"))
        }

        // 3: the System list as the panel composes it — section
        // headers over grouped rows — all real views.
        ThemeStore.shared.select(.system)
        let statuses = Self.groupedFixtures.sorted(by: TimeComparisonViewModel.projectSortOrder)
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            let list = VStack(spacing: 0) {
                ForEach(ProjectGrouping.grouped(statuses)) { group in
                    ClientSectionHeader(client: group.client)
                    ForEach(group.projects) { project in
                        ProjectRowView<GroupedRowLayout>(project: project, effectiveLoggedHours: project.loggedHours, visibleEntries: [])
                    }
                }
            }
            .frame(width: YieldDimensions.panelWidth)
            .background(YieldColors.background)
            .environment(\.colorScheme, scheme)
            try Self.write(list, to: outDir.appendingPathComponent("grouped-system-\(suffix).png"))
        }

        // 4: the System chart, then the System calendar bars.
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.chart(chartVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("chart-system-\(suffix).png"))
        }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.bars(chartVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("bars-system-\(suffix).png"))
        }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.banner(bannerVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("banner-system-\(suffix).png"))
        }
        for (appearance, scheme, suffix) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            try Self.write(Self.header(bannerVM).environment(\.colorScheme, scheme),
                           to: outDir.appendingPathComponent("header-system-\(suffix).png"))
        }
    }

    /// Pixel-identity probes for the Editorial surfaces. Each renders
    /// exactly one surface and nothing else, because the *first* render
    /// in a process rasterizes text slightly differently from later ones
    /// (1/255 on glyph edges, measured) — so a byte comparison against a
    /// cold-rendered baseline is only valid from a cold render. Run one
    /// at a time with `-only-testing` and `YIELD_IDENTITY_SURFACE` set
    /// to `rows` or `chart`; they skip otherwise.
    func test_identityProbe_editorialRows() throws {
        try Self.identityProbe(surface: "rows") { Self.sampleList() }
    }

    func test_identityProbe_editorialChart() throws {
        let vm = Self.makeChartViewModel()
        try Self.identityProbe(surface: "chart") { Self.chart(vm) }
    }

    /// Clock-dependent: the bars print the event's wall-clock times, so
    /// this only compares byte-for-byte against a baseline rendered in
    /// the same minute. A diff confined to the status-line rows is the
    /// clock, not a layout change.
    func test_identityProbe_editorialBars() throws {
        let vm = Self.makeChartViewModel()
        try Self.identityProbe(surface: "bars") { Self.bars(vm) }
    }

    func test_identityProbe_editorialBanner() throws {
        let vm = Self.makeBannerViewModel()
        try Self.identityProbe(surface: "banner") { Self.banner(vm) }
    }

    func test_identityProbe_editorialHeader() throws {
        let vm = Self.makeBannerViewModel()
        try Self.identityProbe(surface: "header") { Self.header(vm) }
    }

    private static func identityProbe<V: View>(surface: String, _ view: () -> V) throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["YIELD_SNAPSHOT_DIR"], env["YIELD_IDENTITY_SURFACE"] == surface else {
            throw XCTSkip("Set YIELD_SNAPSHOT_DIR and YIELD_IDENTITY_SURFACE=\(surface)")
        }
        let outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let original = ThemeStore.shared.theme
        defer { ThemeStore.shared.select(original); NSApp.appearance = nil }
        ThemeStore.shared.select(.editorial)
        for (appearance, scheme, suffix) in [(NSAppearance.Name.darkAqua, ColorScheme.dark, "dark"), (.aqua, .light, "light")] {
            NSApp.appearance = NSAppearance(named: appearance)
            try write(view().environment(\.colorScheme, scheme),
                      to: outDir.appendingPathComponent("\(surface)-editorial-\(suffix).png"))
        }
    }

    /// The two calendar bars that sit above the timer banner: a meeting
    /// that started six minutes ago, and a meeting timer running twelve
    /// minutes past its end.
    private static func bars(_ vm: TimeComparisonViewModel) -> some View {
        let now = Date()
        let event = CalendarEvent(
            id: "evt-prompt", summary: "Design review — BOATUS",
            start: now.addingTimeInterval(-6 * 60), end: now.addingTimeInterval(24 * 60)
        )
        let reminder = TimeComparisonViewModel.CalendarSourcedTimer(
            eventId: "evt-reminder", eventTitle: "Weekly planning",
            eventStart: now.addingTimeInterval(-50 * 60), eventEnd: now.addingTimeInterval(-12 * 60),
            projectId: 1, taskId: 100
        )
        return VStack(spacing: 0) {
            MeetingPromptBarView(viewModel: vm, event: event, onStartTimer: {})
            PostMeetingReminderBarView(viewModel: vm, reminder: reminder, onMoveTime: {})
        }
        .frame(width: YieldDimensions.panelWidth)
        .background(YieldColors.background)
    }

    /// The panel header: week nav, title, tabs, + Timer. Rendered on
    /// the current week so the tab toggle and the timer button show.
    private static func header(_ vm: TimeComparisonViewModel) -> some View {
        MenuBarHeaderView(viewModel: vm, onToggleNewTimerForm: {})
            .frame(width: YieldDimensions.panelWidth)
            .background(YieldColors.background)
    }

    /// The timer banner with a running timer: task, client — project,
    /// a note, and 1h10m on the clock.
    private static func banner(_ vm: TimeComparisonViewModel) -> some View {
        TimerBannerView(viewModel: vm)
            .frame(width: YieldDimensions.panelWidth)
            .background(YieldColors.background)
    }

    /// A view model with one timer running on today's entry.
    static func makeBannerViewModel() -> TimeComparisonViewModel {
        let vm = TimeComparisonViewModel()
        let startedAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-70 * 60))
        let entry = HarvestTimeEntry(
            id: 1, hours: 1.17, spentDate: DateHelpers.dateFormatter.string(from: Date()), isRunning: true,
            updatedAt: startedAt, notes: "Homepage hero + nav", isLocked: nil, approvalStatus: nil,
            timerStartedAt: startedAt,
            project: HarvestProjectRef(id: 1, name: "BOATUS.com Website Redesign", code: nil),
            client: HarvestClientRef(id: 1, name: "GEICO [GCO]"),
            task: nil,
            taskAssignment: HarvestTaskAssignmentRef(id: 901, task: HarvestTaskRef(id: 100, name: "FED"))
        )
        vm.applyRefreshedData(entries: [entry], bookedByForecastProject: [:], projectMap: [:],
                              clientMap: [:], timeOffBlock: nil, notesByForecastProject: [:])
        return vm
    }

    private static func chart(_ vm: TimeComparisonViewModel) -> some View {
        ProjectChartView(viewModel: vm)
            .frame(width: YieldDimensions.panelWidth)
            .background(YieldColors.background)
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

    /// Five projects with time spread across Mon–Fri of the current
    /// week — enough series to exercise the categorical palette, with
    /// one heavy day so the target rule and the peak both show.
    static func makeChartViewModel() -> TimeComparisonViewModel {
        let vm = TimeComparisonViewModel()
        let monday = DateHelpers.currentWeekBounds().start
        let cal = Calendar.current
        func day(_ offset: Int) -> String {
            DateHelpers.dateFormatter.string(from: cal.date(byAdding: .day, value: offset, to: monday)!)
        }

        // (harvest project id, name, client, [hours Mon..Fri])
        let projects: [(Int, String, String, [Double])] = [
            (1, "Development Extension", "GEICO [GCO]",     [2.0, 3.5, 1.0, 4.0, 2.5]),
            (2, "Loyalty App",           "Alaska Airlines", [3.0, 2.0, 4.5, 1.5, 3.0]),
            (3, "Professional Development", "Viget Labs",   [0.0, 1.0, 0.5, 0.0, 1.5]),
            (4, "Viget.com Redesign 2025–26", "Viget Internal", [2.5, 1.5, 2.0, 3.0, 0.5]),
            (5, "Brand Refresh",         "Acme Co",         [0.5, 0.0, 1.0, 0.5, 1.0]),
        ]

        var entries: [HarvestTimeEntry] = []
        var nextId = 1
        for (pid, name, client, hours) in projects {
            for (offset, h) in hours.enumerated() where h > 0 {
                entries.append(HarvestTimeEntry(
                    id: nextId, hours: h, spentDate: day(offset), isRunning: false,
                    updatedAt: "2026-11-03T00:00:00Z", notes: nil, isLocked: nil, approvalStatus: nil,
                    timerStartedAt: nil,
                    project: HarvestProjectRef(id: pid, name: name, code: nil),
                    client: HarvestClientRef(id: pid, name: client),
                    task: nil,
                    taskAssignment: HarvestTaskAssignmentRef(id: 900 + pid, task: HarvestTaskRef(id: 100, name: "Dev"))
                ))
                nextId += 1
            }
        }

        vm.applyRefreshedData(
            entries: entries,
            bookedByForecastProject: [:],
            projectMap: [:],
            clientMap: [:],
            timeOffBlock: nil,
            notesByForecastProject: [:]
        )
        return vm
    }


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
            if ThemeStore.shared.theme.usesRefreshedLayout {
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
