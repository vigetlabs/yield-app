import AppKit
import SwiftUI

/// Build a Color that resolves to `light` under the `aqua` system
/// appearance and `dark` under `darkAqua`. Used by `YieldColors` so the
/// whole palette flips automatically when `NSApp.appearance` changes.
private func dynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(NSColor(name: nil, dynamicProvider: { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua: return dark
        default:        return light
        }
    }))
}

// MARK: - Colors

/// The palette, resolved through the active theme like every other
/// token. Each theme is a complete set below; the public names pick
/// from whichever is active, so views never know which palette they
/// are drawing with.
///
/// Editorial's values are the app's original ones, unchanged. System's
/// are macOS's semantic colors — see `System` below.
enum YieldColors {
    private static var theme: YieldTheme { ThemeStore.shared.theme }

    static var background: Color      { theme == .editorial ? Editorial.background : System.background }
    static var greenAccent: Color     { theme == .editorial ? Editorial.greenAccent : System.greenAccent }
    static var greenDim: Color        { greenAccent.opacity(0.3) }
    static var greenSubtle: Color     { greenAccent.opacity(0.15) }
    static var greenFaint: Color      { greenAccent.opacity(0.04) }
    static var yellowAccent: Color    { theme == .editorial ? Editorial.yellowAccent : System.yellowAccent }
    static var yellowDim: Color       { yellowAccent.opacity(0.3) }
    static var yellowFaint: Color     { yellowAccent.opacity(0.1) }
    static var border: Color          { theme == .editorial ? Editorial.border : System.border }
    static var buttonBorder: Color    { theme == .editorial ? Editorial.buttonBorder : System.buttonBorder }
    static var greenBorder: Color     { greenAccent.opacity(0.15) }
    static var greenBorderActive: Color { greenAccent.opacity(0.3) }
    /// The color of things you click: filled and tinted buttons, text
    /// links, selectable calendar events. Distinct from `greenAccent`,
    /// which means "running / on track". Editorial has one green for
    /// both, so the two resolve to the same color there; System gives
    /// controls the kit's blue and keeps status on a fixed green, so
    /// a healthy project never borrows the color of a button.
    static var controlAccent: Color   { theme == .editorial ? Editorial.greenAccent : System.controlAccent }
    /// A filled ("contained") button: its fill, its hover fill and the
    /// label on it. Editorial's filled button is its green with the
    /// label knocked out to the panel colour, as it always was.
    static var controlFill: Color      { theme == .editorial ? Editorial.greenAccent : System.controlFill }
    static var controlFillHover: Color { theme == .editorial ? Editorial.greenAccent : System.controlFillHover }
    static var onControlFill: Color    { theme == .editorial ? Editorial.background : System.onControlFill }
    /// A surface lifted off the panel (System). Editorial has no raised
    /// surfaces; it resolves to the panel colour there.
    static var raised: Color           { theme == .editorial ? Editorial.background : System.raised }
    /// Shadow colour for raised surfaces (System).
    static var shadow: Color           { theme == .editorial ? Color.black : System.shadow }
    /// The band behind a client header (System). Editorial has no
    /// client headers; it resolves to its ordinary surface there.
    static var sectionBand: Color      { theme == .editorial ? Editorial.surfaceDefault : System.sectionBand }
    /// Hover wash on a System list row.
    static var rowHover: Color         { controlAccent.opacity(0.06) }
    static var controlAccentSubtle: Color { controlAccent.opacity(0.15) }
    static var controlAccentFaint: Color  { controlAccent.opacity(0.04) }
    static var controlAccentBorder: Color { controlAccent.opacity(0.15) }
    static var controlAccentBorderActive: Color { controlAccent.opacity(0.3) }
    /// Progress fill for a booked project nobody is timing right now.
    /// Editorial fills every bar green, as it always has. System keeps
    /// color for the running project and for over-budget, so the row
    /// you're on is the one that stands out.
    static var idleFill: Color        { theme == .editorial ? Editorial.greenAccent : System.idleFill }
    static var textPrimary: Color     { theme == .editorial ? Editorial.textPrimary : System.textPrimary }
    static var textSecondary: Color   { theme == .editorial ? Editorial.textSecondary : System.textSecondary }
    static var surfaceDefault: Color  { theme == .editorial ? Editorial.surfaceDefault : System.surfaceDefault }
    static var surfaceActive: Color   { theme == .editorial ? Editorial.surfaceActive : System.surfaceActive }
    static var progressTrack: Color   { theme == .editorial ? Editorial.progressTrack : System.progressTrack }
    static var onBackground: Color    { theme == .editorial ? Editorial.onBackground : System.onBackground }

    /// The original palette. Dark mode is the original `#1A1B1C`-era
    /// scheme on `#151617`; light mode is a slightly cool off-white that
    /// mirrors that brightness without the harshness of pure white.
    /// Brand accents flip between a bright dark-mode value and a darker
    /// light-mode value tuned for WCAG AA against the panel background.
    enum Editorial {
        static let background = dynamicColor(
            light: NSColor(red: 0.961, green: 0.961, blue: 0.965, alpha: 1.0),  // #F5F5F6
            dark:  NSColor(red: 0.082, green: 0.086, blue: 0.090, alpha: 1.0)   // #151617
        )
        static let greenAccent = dynamicColor(
            light: NSColor(red: 0.043, green: 0.439, blue: 0.282, alpha: 1.0),  // #0B7048 — 5.6:1
            dark:  NSColor(red: 0.082, green: 0.855, blue: 0.576, alpha: 1.0)   // #15DA93 — 9.95:1
        )
        static let yellowAccent = dynamicColor(
            light: NSColor(red: 0.580, green: 0.380, blue: 0.0,   alpha: 1.0),  // #946100 — 4.9:1
            dark:  NSColor(red: 1.0,   green: 0.831, blue: 0.286, alpha: 1.0)   // #FFD449 — 12.7:1
        )
        /// Hairlines and dividers — invert the alpha overlay color between
        /// modes so the same opacity values continue to work.
        static let border = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.1),
            dark:  NSColor.white.withAlphaComponent(0.1)
        )
        static let buttonBorder = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.25),
            dark:  NSColor.white.withAlphaComponent(0.3)
        )
        static let textPrimary = dynamicColor(
            light: NSColor(red: 0.102, green: 0.106, blue: 0.110, alpha: 1.0),  // mirror of dark bg
            dark:  .white
        )
        static let textSecondary = dynamicColor(
            light: NSColor(red: 0.102, green: 0.106, blue: 0.110, alpha: 0.7),
            dark:  NSColor.white.withAlphaComponent(0.7)
        )
        /// Hover / pressed surfaces over the panel background. Light mode
        /// uses lighter overlays (0.04 / 0.06) since dark-on-light at 0.10
        /// reads heavier than white-on-dark at 0.10.
        static let surfaceDefault = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.04),
            dark:  NSColor.white.withAlphaComponent(0.04)
        )
        static let surfaceActive = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.06),
            dark:  NSColor.white.withAlphaComponent(0.1)
        )
        /// Unfilled track behind progress bars and the day-segment slots.
        /// Stronger than `surfaceActive` so an empty track reads as
        /// distinct from the panel background.
        static let progressTrack = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.10),
            dark:  NSColor.white.withAlphaComponent(0.13)
        )
        /// Generic foreground that always contrasts the panel background.
        static let onBackground = dynamicColor(
            light: NSColor(red: 0.102, green: 0.106, blue: 0.110, alpha: 1.0),
            dark:  .white
        )
    }

    /// The System theme's palette: the Material-X kit's colour styles.
    ///
    /// Light values are the kit's own, named beside each one. The kit
    /// is light-only, so the dark column is derived from the same
    /// ramps — a step or two lighter on a near-black surface — and is
    /// this app's, not the kit's.
    enum System {
        private static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                    green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
        }

        static let background = dynamicColor(light: hex(0xFFFFFF), dark: hex(0x121212))        // White
        /// "Running / on track". Fixed, as before: status colours don't
        /// follow the control colour.
        static let greenAccent = dynamicColor(light: hex(0x1F8B24), dark: hex(0x52D858))       // Green / 05 · 03
        /// Text and glyphs on controls, links, selected marks.
        static let controlAccent = dynamicColor(light: hex(0x0F56B3), dark: hex(0x8AB9F6))     // Blue / 05 · 02
        /// A contained button's fill, and the label that sits on it.
        static let controlFill = dynamicColor(light: hex(0x0F56B3), dark: hex(0x1672EC))       // Blue / 05 · 04
        static let controlFillHover = dynamicColor(light: hex(0x1672EC), dark: hex(0x5096F1))  // Blue / 04 · 03
        static let onControlFill = dynamicColor(light: hex(0xC5DCFA), dark: hex(0xFFFFFF))     // Blue / 01
        static let idleFill = dynamicColor(light: hex(0xA1A1A1), dark: hex(0x818181))          // Grey / 03 · 04
        /// Paused / warning.
        static let yellowAccent = dynamicColor(light: hex(0xBF710F), dark: hex(0xF2B05C))      // Orange / 05 · 03
        /// The meeting bars' button: the bar's own orange at full
        /// strength, with a dark label — the pairing the menu bar's
        /// "nearly out" capsule uses. White on this orange is too faint.
        static let attentionFill = dynamicColor(light: hex(0xED9526), dark: hex(0xF2B05C))       // Orange / 04 · 03
        static let attentionFillHover = dynamicColor(light: hex(0xF2B05C), dark: hex(0xF6CA92))  // Orange / 03 · 02
        static let onAttentionFill = dynamicColor(light: hex(0x3D2800), dark: hex(0x3D2800))
        static let over = dynamicColor(light: hex(0xDA100B), dark: hex(0xF7716E))              // Red / 05 · 03
        static let prospective = dynamicColor(light: hex(0xE1125E), dark: hex(0xF584AD))       // Pink / 04 · 02
        static let unbooked = dynamicColor(light: hex(0xA1A1A1), dark: hex(0x616161))          // Grey / 03 · 05
        static let border = dynamicColor(light: hex(0xE0E0E0), dark: hex(0xFFFFFF, 0.12))      // Grey / 01
        static let buttonBorder = dynamicColor(light: hex(0xC0C0C0), dark: hex(0x616161))      // Grey / 02 · 05
        static let textPrimary = dynamicColor(light: hex(0x000000), dark: hex(0xFFFFFF))       // Black
        static let textSecondary = dynamicColor(light: hex(0x616161), dark: hex(0xC0C0C0))     // Grey / 05 · 02
        /// The kit's "Light / Grey": Grey at half strength, the fill
        /// behind shaded buttons, segment troughs and open projects.
        static let surfaceDefault = dynamicColor(light: hex(0xE5E5E5, 0.5), dark: hex(0xFFFFFF, 0.07))
        static let surfaceActive = dynamicColor(light: hex(0xE0E0E0), dark: hex(0xFFFFFF, 0.14))  // Grey / 01
        /// Behind a client header: the same grey as `surfaceDefault`
        /// at a little over half its strength, so an open project
        /// under a header is still the darker of the two.
        static let sectionBand = dynamicColor(light: hex(0xE5E5E5, 0.28), dark: hex(0xFFFFFF, 0.04))
        static let progressTrack = dynamicColor(light: hex(0xE0E0E0), dark: hex(0xFFFFFF, 0.14))  // Grey / 01
        static let onBackground = textPrimary
        /// A surface lifted off the panel: the selected segment, a
        /// raised card. White in the kit.
        static let raised = dynamicColor(light: hex(0xFFFFFF), dark: hex(0x3A3A3A))
        /// The kit's grey shadow colour (Grey / 05). Dark surfaces get
        /// plain black; a grey shadow on near-black is invisible.
        static let shadow = dynamicColor(light: hex(0x616161), dark: hex(0x000000))
    }
}

// MARK: - Chart colors

/// Categorical palette for the weekly chart's series (System theme).
///
/// Eight hues in a fixed order, each stepped separately for the light
/// and dark surfaces. The order is load-bearing: it was validated for
/// colorblind separation and a normal-vision floor on *adjacent* pairs
/// — which is what stacked segments are — against Yield's own surfaces
/// (#F5F5F6 light, #151617 dark). Slots are assigned to projects in
/// sequence and never cycled; a ninth project folds into `other`.
///
/// Four light-mode slots sit below 3:1 on the light surface, which the
/// validator flags as needing a relief channel. The chart's hover
/// tooltip, with the day's per-project hours, is that channel.
enum YieldChartColors {
    private static func hex(_ light: UInt32, _ dark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                    green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return dynamicColor(light: ns(light), dark: ns(dark))
    }

    static let slots: [Color] = [
        hex(0x2A78D6, 0x3987E5),  // blue
        hex(0xEB6834, 0xD95926),  // orange
        hex(0x1BAF7A, 0x199E70),  // aqua
        hex(0xEDA100, 0xC98500),  // yellow
        hex(0xE87BA4, 0xD55181),  // magenta
        hex(0x008300, 0x008300),  // green
        hex(0x6250D6, 0x9085E9),  // violet
        hex(0xE34948, 0xE66767),  // red
    ]

    /// Projects past the eighth are merged into one neutral series.
    static let other = hex(0x9A9A9A, 0x6E6E6E)
}

// MARK: - Fonts

/// Every font resolves through the active theme (`YieldTheme`). Call
/// sites name a *role* — title, label, mono — never a family, so a
/// theme can swap families and sizes without touching a view. These
/// are `static var`s reading an `@Observable` store, which is what
/// makes a theme change re-render every view that uses one.
enum YieldFonts {
    private static var theme: YieldTheme { ThemeStore.shared.theme }

    /// Titles — week dates, project names, task names, form fields.
    static func title(_ size: CGFloat) -> Font { theme.title(size) }
    static func titleItalic(_ size: CGFloat) -> Font { theme.titleItalic(size) }

    /// Labels — client names, descriptions, buttons, settings rows.
    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        theme.label(size, weight: weight)
    }
    static func labelItalic(_ size: CGFloat) -> Font { theme.labelItalic(size) }

    /// Numbers — times, totals, the timer display.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        theme.mono(size, weight: weight)
    }

    /// AppKit equivalents for the NSPopUpButton / NSAttributedString
    /// sites that can't take a SwiftUI `Font`.
    static func nsTitle(_ size: CGFloat) -> NSFont { theme.nsTitle(size) }
    static func nsLabel(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        theme.nsLabel(size, weight: weight)
    }
}

// MARK: - Typography Presets

extension YieldFonts {
    /// Week dates, project names.
    static var titleMedium: Font { theme.titleMedium }

    /// Task names, form fields.
    static var titleSmall: Font { theme.titleSmall }

    /// Uppercase client names, field labels.
    static var labelProject: Font { theme.labelProject }

    /// Remaining time labels.
    static var labelTimeRemaining: Font { theme.labelTimeRemaining }

    /// Notes, descriptions.
    static var labelNote: Font { theme.labelNote }

    /// Button labels.
    static var labelButton: Font { theme.labelButton }

    /// Project time totals.
    static var monoSmall: Font { theme.monoSmall }

    /// Task time values.
    static var monoXS: Font { theme.monoXS }

    /// Timer display.
    static var monoMedium: Font { theme.monoMedium }

    // Grouped-layout presets (System theme's list).

    /// The row's headline number.
    static var figureLarge: Font { theme.figureLarge }
    /// "/ 18h" beside it.
    static var figureDenominator: Font { theme.figureDenominator }
    /// Remaining / over / not-linked line under the name.
    static var rowSubtitle: Font { theme.rowSubtitle }
    /// Client name above a group of rows.
    static var sectionHeader: Font { theme.sectionHeader }
    /// The timer banner's elapsed figure.
    static var heroFigure: Font { theme.heroFigure }
}

// MARK: - Corner Radii

// MARK: - Status Colors

enum YieldStatusColors {
    private static var theme: YieldTheme { ThemeStore.shared.theme }

    static var under: Color { YieldColors.greenAccent }

    /// Over budget.
    static var over: Color {
        theme == .editorial ? Editorial.over : YieldColors.System.over
    }
    /// Unbooked status line.
    static var unbooked: Color {
        theme == .editorial ? Editorial.unbooked : YieldColors.System.unbooked
    }
    /// Prospective / proposal-stage Forecast projects — booked but not
    /// yet linked to a Harvest project.
    static var prospective: Color {
        theme == .editorial ? Editorial.prospective : YieldColors.System.prospective
    }
    /// Warning amber — booked in Forecast, not a member in Harvest. The
    /// theme's yellow accent, so it matches the bars and the paused
    /// timer.
    static var warning: Color { YieldColors.yellowAccent }

    enum Editorial {
        static let over = dynamicColor(
            light: NSColor(red: 0.757, green: 0.243, blue: 0.055, alpha: 1.0),  // #C13E0E — 4.8:1 on light bg
            dark:  NSColor(red: 0.941, green: 0.365, blue: 0.157, alpha: 1.0)   // #F05D28 — 5.5:1 on dark bg
        )
        static let unbooked = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.3),
            dark:  NSColor.white.withAlphaComponent(0.3)
        )
        static let prospective = dynamicColor(
            light: NSColor(red: 0.722, green: 0.153, blue: 0.435, alpha: 1.0),  // #B8276F — 5.4:1 on light bg
            dark:  NSColor(red: 0.941, green: 0.365, blue: 0.627, alpha: 1.0)   // #F05DA0 — 5.0:1 on dark bg
        )
    }
}

enum YieldRadius {
    private static var theme: YieldTheme { ThemeStore.shared.theme }

    static var panel: CGFloat { theme.panelRadius }
    static var card: CGFloat { theme.cardRadius }
    static var button: CGFloat { theme.buttonRadius }
    static var dropdown: CGFloat { theme.dropdownRadius }
    static var progressBar: CGFloat { theme.progressBarRadius }
    /// Buttons and header chips. See `YieldTheme.pillRadius`.
    static var pill: CGFloat { theme.pillRadius }
    /// Icon-only buttons. See `YieldTheme.iconButtonRadius`.
    static var iconButton: CGFloat { theme.iconButtonRadius }
}

// MARK: - Dimensions

enum YieldDimensions {
    private static var theme: YieldTheme { ThemeStore.shared.theme }

    static let panelWidth: CGFloat = 540
    /// Themed: the grouped layout carries the figure above the bar, so
    /// the bar is wider there.
    static var progressBarWidth: CGFloat { theme.progressBarWidth }
    static let progressBarHeight: CGFloat = 4
    static let timerButtonSize: CGFloat = 24
    /// Text-button metrics — themed; see `YieldTheme`.
    static var buttonHeight: CGFloat { theme.buttonHeight }
    static var buttonHorizontalPadding: CGFloat { theme.buttonHorizontalPadding }
    /// Not a dimension, but it travels with the two above: the opacity
    /// a text button rests at before hover.
    static var buttonRestingOpacity: Double { theme.buttonRestingOpacity }
    /// Letter-spacing on text-button labels. See `YieldTheme`.
    static var buttonLabelTracking: CGFloat { theme.buttonLabelTracking }
    static var headerIconWidth: CGFloat { theme.headerIconWidth }
    /// Standard control height for inline form inputs — pickers,
    /// favorite-list buttons. Matches the dropdown's intrinsic hit
    /// target. Themed: larger type needs a taller control.
    static var controlHeight: CGFloat { theme.controlHeight }
    /// Notes field + time-input field tracked together so they read
    /// as a paired row in the new/edit timer form.
    static var inputFieldHeight: CGFloat { theme.inputFieldHeight }
    /// Settings row dropdown width — same value used for every
    /// `enumPickerRow` so all rows align.
    static let settingsRowControlWidth: CGFloat = 160
    /// Project row heights — taller when the row carries a progress
    /// bar (forecasted), shorter when it doesn't.
    static var projectRowForecastedHeight: CGFloat { theme.projectRowForecastedHeight }
    static var projectRowDefaultHeight: CGFloat { theme.projectRowDefaultHeight }
}

// MARK: - View modifiers

extension View {
    /// Apply the standard "rounded surface with hairline border"
    /// treatment — used by dropdowns, the favorites button, the notes
    /// and time-input fields, and any other inline form control. The
    /// caller is expected to set its own `.background(...)` (typically
    /// `YieldColors.surfaceDefault`); this modifier just clips and
    /// strokes.
    func yieldBorder(radius: CGFloat = YieldRadius.dropdown) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(YieldColors.border, lineWidth: 1)
            )
    }

    /// The Settings panel's "card" treatment: surface fill plus the
    /// standard rounded border. Used for the Account / Preferences /
    /// Favorites / About sections so their styling stays in sync.
    func yieldCard() -> some View {
        self
            .background(YieldColors.surfaceDefault)
            .yieldBorder(radius: YieldRadius.card)
    }
}

// MARK: - Domain constants

enum YieldConstants {
    /// The Forecast project name used to represent all time-off bookings
    /// (vacation, sick, holiday, PTO). This is a single undeletable project
    /// maintained by Forecast itself — we match on name to identify it.
    static let timeOffProjectName = "Time Off"
}
