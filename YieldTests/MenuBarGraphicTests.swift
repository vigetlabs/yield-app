import XCTest
@testable import Yield

/// The ring, capsule and week-bars menu bar styles: the state the view
/// model hands the renderer, and the renderer's layout guarantees.
@MainActor
final class MenuBarGraphicTests: XCTestCase {

    // MARK: - Fixtures

    private func entry(id: Int, hours: Double, date: String, isRunning: Bool = false) -> TimeEntryInfo {
        TimeEntryInfo(
            id: id, harvestProjectId: 500, taskId: 100, taskName: "Task",
            hours: hours, date: date, isRunning: isRunning, notes: nil, timerStartedAt: nil
        )
    }

    private func project(
        booked: Double,
        logged: Double,
        isTracking: Bool = false,
        entries: [TimeEntryInfo] = []
    ) -> ProjectStatus {
        ProjectStatus(
            id: "p", clientName: nil, projectName: "Project", projectCode: nil,
            bookedHours: booked, loggedHours: logged, todayHours: 0,
            isTracking: isTracking, harvestProjectId: 500, todayEntryId: nil,
            lastTaskId: nil, timeEntries: entries, forecastNotes: nil
        )
    }

    private func loadedVM(_ statuses: [ProjectStatus]) -> TimeComparisonViewModel {
        let vm = TimeComparisonViewModel()
        vm._setStateForTesting(projectStatuses: statuses, lastUpdated: Date())
        return vm
    }

    private var today: String { DateHelpers.dateFormatter.string(from: Date()) }

    // MARK: - Tone

    func test_tone_thresholds() {
        XCTAssertEqual(MenuBarGraphicState.tone(logged: 4, booked: 16), .onPace)
        XCTAssertEqual(MenuBarGraphicState.tone(logged: 13.5, booked: 16), .onPace)
        XCTAssertEqual(MenuBarGraphicState.tone(logged: 13.6, booked: 16), .nearLimit)
        XCTAssertEqual(MenuBarGraphicState.tone(logged: 16, booked: 16), .nearLimit, "exactly at the booking is not over")
        XCTAssertEqual(MenuBarGraphicState.tone(logged: 16.01, booked: 16), .over)
        XCTAssertEqual(MenuBarGraphicState.tone(logged: 3, booked: 0), .neutral, "no booking, nothing to judge")
    }

    func test_quantize_clampsAndSnaps() {
        XCTAssertEqual(MenuBarGraphicState.quantize(-0.2), 0)
        XCTAssertEqual(MenuBarGraphicState.quantize(1.7), 1)
        XCTAssertEqual(MenuBarGraphicState.quantize(0.3333), 0.335, accuracy: 0.0001)
        XCTAssertEqual(MenuBarGraphicState.quantize(0.3334), MenuBarGraphicState.quantize(0.3341),
                       "sub-pixel drift must not change the cache key")
    }

    // MARK: - View model state

    func test_state_beforeFirstLoad_isEmpty() {
        let state = TimeComparisonViewModel().menuBarGraphicState
        XCTAssertEqual(state.timer, .none)
        XCTAssertNil(state.progress)
        XCTAssertTrue(state.weekFractions.isEmpty)
    }

    func test_state_runningBookedTimer_reportsToneAndProgress() {
        let vm = loadedVM([project(booked: 16, logged: 4, isTracking: true,
                                   entries: [entry(id: 1, hours: 4, date: today, isRunning: true)])])
        let state = vm.menuBarGraphicState
        XCTAssertEqual(state.timer, .running)
        XCTAssertEqual(state.tone, .onPace)
        XCTAssertEqual(state.progress, 0.25)
    }

    func test_state_localTicksCountTowardTone() {
        let vm = loadedVM([project(booked: 16, logged: 15.9, isTracking: true,
                                   entries: [entry(id: 1, hours: 15.9, date: today, isRunning: true)])])
        XCTAssertEqual(vm.menuBarGraphicState.tone, .nearLimit)
        vm._setStateForTesting(elapsedOffset: 0.5)
        let state = vm.menuBarGraphicState
        XCTAssertEqual(state.tone, .over, "minutes ticked locally since the last refresh push it over")
        XCTAssertEqual(state.progress, 1, "progress never draws past a full ring")
    }

    func test_state_unbookedTimer_hasNothingToMeasure() {
        let vm = loadedVM([project(booked: 0, logged: 2, isTracking: true,
                                   entries: [entry(id: 1, hours: 2, date: today, isRunning: true)])])
        let state = vm.menuBarGraphicState
        XCTAssertEqual(state.timer, .running)
        XCTAssertEqual(state.tone, .neutral)
        XCTAssertNil(state.progress)
    }

    func test_state_noTimer_reportsWeekProgressWithoutColor() {
        let vm = loadedVM([project(booked: 16, logged: 4)])
        let state = vm.menuBarGraphicState
        XCTAssertEqual(state.timer, .none)
        XCTAssertEqual(state.tone, .neutral, "color is reserved for a running timer")
        XCTAssertNotNil(state.progress)
    }

    func test_state_weekFractions_coverMondayToFriday() {
        let days = DateHelpers.weekDays(starting: DateHelpers.currentWeekBounds().start)
        let monday = days[0].str
        let saturday = days[5].str
        let vm = loadedVM([project(booked: 40, logged: 12, entries: [
            entry(id: 1, hours: 100, date: monday),
            entry(id: 2, hours: 5, date: saturday),
        ])])
        let state = vm.menuBarGraphicState
        XCTAssertEqual(state.weekFractions.count, 5)
        XCTAssertEqual(state.weekFractions[0], 1, "a day past its target fills the bar and stops")
        XCTAssertEqual(state.weekFractions[1], 0)
        if let index = state.todayIndex {
            XCTAssertEqual(days[index].str, today)
        } else {
            XCTAssertFalse(days.prefix(5).contains { $0.str == today }, "todayIndex is nil only on weekends")
        }
    }

    // MARK: - Time-left label

    func test_formatLeft() {
        XCTAssertEqual(TimeComparisonViewModel.formatLeft(10.8), "10:48 left")
        XCTAssertEqual(TimeComparisonViewModel.formatLeft(-2.0 / 3.0), "0:40 over")
        XCTAssertEqual(TimeComparisonViewModel.formatLeft(0), "0:00 left")
        XCTAssertEqual(TimeComparisonViewModel.formatLeft(-0.001), "0:00 left", "a few seconds over still rounds to zero left")
    }

    // MARK: - Renderer

    private func render(
        _ style: MenuBarStyle,
        _ label: String,
        _ state: MenuBarGraphicState = MenuBarGraphicState(),
        mode: MenuBarLabelMode = .timeLeft,
        dark: Bool = false
    ) -> NSImage {
        MenuBarGraphicRenderer.render(style: style, label: label, state: state, labelMode: mode, isDark: dark)
    }

    func test_render_isColoredNotTemplate() {
        for style in [MenuBarStyle.ring, .capsule, .weekBars] {
            XCTAssertFalse(render(style, "1:20 left").isTemplate, "\(style) carries its own colors")
        }
    }

    func test_render_widthHoldsAsTheLabelTicks() {
        for style in [MenuBarStyle.ring, .capsule, .weekBars] {
            let narrow = render(style, "1:11 left").size
            let wide = render(style, "18:48 left").size
            XCTAssertEqual(narrow.width, wide.width, "\(style) must not shove its neighbors as digits change")
            XCTAssertEqual(narrow.height, style == .capsule
                ? MenuBarGraphicRenderer.capsuleHeight : MenuBarGraphicRenderer.barHeight)
            XCTAssertLessThanOrEqual(narrow.height, 22, "a status item's image is given 22pt")
        }
    }

    func test_render_growsRatherThanClipsAnOverlongLabel() {
        let normal = render(.ring, "9:59 / 16:00", mode: .projectTime).size.width
        let long = render(.ring, "100:17 / 120:00", mode: .projectTime).size.width
        XCTAssertGreaterThan(long, normal)
    }

    // MARK: - Capsule battery

    /// Alpha and color of one pixel, a given fraction across the
    /// capsule at mid-height. An empty label keeps text out of the way.
    private func capsulePixel(_ state: MenuBarGraphicState, at fraction: CGFloat) -> NSColor? {
        let image = render(.capsule, "", state)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.colorAt(x: Int(CGFloat(rep.pixelsWide) * fraction), y: rep.pixelsHigh / 2)
    }

    func test_capsule_usedShareIsSolid_restIsEmpty() throws {
        for tone in [MenuBarGraphicState.Tone.onPace, .nearLimit] {
            var state = MenuBarGraphicState()
            state.timer = .running
            state.tone = tone
            state.progress = 0.5
            let used = try XCTUnwrap(capsulePixel(state, at: 0.25))
            let unused = try XCTUnwrap(capsulePixel(state, at: 0.75))
            XCTAssertEqual(used.alphaComponent, 1, accuracy: 0.01, "\(tone): the used half is filled")
            XCTAssertEqual(unused.alphaComponent, 0, accuracy: 0.01, "\(tone): the unused half is outline only")
        }
    }

    func test_capsule_overAndUnbookedStaySolid() throws {
        var over = MenuBarGraphicState()
        over.timer = .running
        over.tone = .over
        over.progress = 1
        XCTAssertEqual(try XCTUnwrap(capsulePixel(over, at: 0.75)).alphaComponent, 1, accuracy: 0.01)

        // Unbooked is filled with bar ink, which is itself translucent.
        var unbooked = MenuBarGraphicState()
        unbooked.timer = .running
        XCTAssertGreaterThan(try XCTUnwrap(capsulePixel(unbooked, at: 0.75)).alphaComponent, 0.8)
    }

    func test_capsule_aJustStartedBookingStillShowsAFill() throws {
        var state = MenuBarGraphicState()
        state.timer = .running
        state.tone = .onPace
        state.progress = 0.01
        XCTAssertGreaterThan(try XCTUnwrap(capsulePixel(state, at: 0.08)).alphaComponent, 0.5)
    }

    func test_render_emptyLabelStillDrawsSomething() {
        for style in [MenuBarStyle.ring, .capsule, .weekBars] {
            XCTAssertGreaterThan(render(style, "").size.width, 0)
        }
    }

    /// Not an assertion — a contact sheet of every style and state on a
    /// light and a dark bar, for looking at. Opt in with
    /// `TEST_RUNNER_YIELD_MENUBAR_PREVIEW_DIR=/some/dir xcodebuild test …`.
    func test_writePreviewSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_MENUBAR_PREVIEW_DIR"] else {
            throw XCTSkip("Set YIELD_MENUBAR_PREVIEW_DIR to write the preview sheet")
        }
        let week = [1, 0.94, 1, 0.55, 0]
        func state(_ configure: (inout MenuBarGraphicState) -> Void) -> MenuBarGraphicState {
            var s = MenuBarGraphicState()
            s.weekFractions = week
            s.todayIndex = 3
            configure(&s)
            return s
        }
        let rows: [(name: String, label: String, mode: MenuBarLabelMode, state: MenuBarGraphicState)] = [
            ("No timer", "8:40 left", .timeLeft, state { $0.progress = 0.78 }),
            ("On pace", "10:48 left", .timeLeft, state { $0.timer = .running; $0.tone = .onPace; $0.progress = 0.33 }),
            ("On pace, pair", "5:12 / 16:00", .projectTime, state { $0.timer = .running; $0.tone = .onPace; $0.progress = 0.33 }),
            ("Nearly out", "1:20 left", .timeLeft, state { $0.timer = .running; $0.tone = .nearLimit; $0.progress = 0.92 }),
            ("Over", "0:40 over", .timeLeft, state { $0.timer = .running; $0.tone = .over; $0.progress = 1 }),
            ("Unbooked", "0:35", .timeLeft, state { $0.timer = .running }),
            ("Paused", "10:48 left", .timeLeft, state { $0.timer = .paused; $0.progress = 0.33 }),
            ("Meeting, idle", "8:40 left", .timeLeft, state { $0.progress = 0.78; $0.meetingDue = true }),
            ("Meeting, running", "10:48 left", .timeLeft, state { $0.timer = .running; $0.tone = .onPace; $0.progress = 0.33; $0.meetingDue = true }),
            ("Offline", "10:48 left", .timeLeft, state { $0.timer = .running; $0.tone = .onPace; $0.progress = 0.33; $0.isStale = true }),
            ("Current timer", "1:24", .currentTimer, state { $0.timer = .running; $0.tone = .onPace; $0.progress = 0.33 }),
            ("Loading", "", .timeLeft, MenuBarGraphicState()),
        ]
        let styles: [MenuBarStyle] = [.ring, .capsule, .weekBars]
        let labelWidth: CGFloat = 120, cellWidth: CGFloat = 132, rowHeight: CGFloat = 30, scale: CGFloat = 3
        let size = NSSize(width: labelWidth + cellWidth * CGFloat(styles.count * 2), height: rowHeight * CGFloat(rows.count))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (r, row) in rows.enumerated() {
            let y = size.height - rowHeight * CGFloat(r + 1)
            (row.name as NSString).draw(
                at: NSPoint(x: 6, y: y + 8),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black]
            )
            for (s, style) in styles.enumerated() {
                for (d, dark) in [false, true].enumerated() {
                    let x = labelWidth + cellWidth * CGFloat(s * 2 + d)
                    let cell = NSRect(x: x + 1, y: y + 1, width: cellWidth - 2, height: rowHeight - 2)
                    (dark ? MenuBarGraphicRenderer.Palette.hex(0x2A2A2E) : MenuBarGraphicRenderer.Palette.hex(0xE7E4DD)).setFill()
                    cell.fill()
                    let image = render(style, row.label, row.state, mode: row.mode, dark: dark)
                    image.draw(in: NSRect(
                        x: cell.minX + 8, y: cell.midY - image.size.height / 2,
                        width: image.size.width, height: image.size.height
                    ))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: dir).appendingPathComponent("menubar-styles.png")
        try png.write(to: url)
        print("Wrote menu bar preview sheet to \(url.path)")
    }
}
