import AppKit
import Observation
import SwiftUI

/// The app's selectable look. Settings → Display → Theme.
///
/// A theme owns the *typography and metrics* — font families, the
/// sizes behind each preset, row heights, corner radii. The color
/// palette is shared: the greens and ambers are status semantics tuned
/// for WCAG against both appearances, and they read the same under
/// either theme. Light/dark is a separate axis (`AppearanceMode`) and
/// composes with this one.
///
/// Every token in `DesignTokens.swift` resolves through
/// `ThemeStore.shared.theme`, so a view asks for a role —
/// `YieldFonts.title(14)`, `YieldDimensions.projectRowDefaultHeight` —
/// and gets the active theme's answer. Views never name a family.
enum YieldTheme: String, CaseIterable {
    /// The original look: Newsreader serif for titles and project
    /// names, DM Sans for labels, JetBrains Mono for times. Compact.
    case editorial
    /// The alternative look, drawn with the Material-X kit: Manrope
    /// throughout (tabular figures for times), the kit's blue for
    /// controls, its grey tints for surfaces, 8pt buttons, round icon
    /// buttons, a segmented control with a raised selection, and
    /// uppercase tracked overlines and badges. The name is historical —
    /// it began as a system-font theme.
    case system

    /// Single source of truth for the default, referenced by the
    /// AppDelegate's UserDefaults registration and `ThemeStore`'s
    /// fallback. The original look stays the default; the new one is
    /// opt-in.
    static let `default`: YieldTheme = .editorial

    var label: String {
        switch self {
        case .editorial: return "Editorial"
        case .system:    return "System"
        }
    }

    /// Whether the panel uses the refreshed layout: the grouped list
    /// with client section headers and name + figure rows, the band-
    /// style calendar bars and timer banner, taller buttons. This is a
    /// *layout* fork, not a typographic one — it's gated here rather
    /// than derived from fonts so Editorial stays pixel-identical to the
    /// app as it shipped, by decision.
    var usesRefreshedLayout: Bool { self == .system }

    /// Whether the weekly chart uses the refreshed styling — validated
    /// series palette, hover breakdown, square legend swatches (System).
    /// Same form as Editorial's stacked area; same fork discipline as
    /// `usesRefreshedLayout`: Editorial keeps the chart exactly as it
    /// shipped.
    var usesRefreshedChart: Bool { self == .system }

    // MARK: - Size scale

    /// Multiplier applied to sizes passed to the family functions
    /// (`title(_:)`, `label(_:)`, `mono(_:)`) — the ~80 call sites that
    /// pass a literal size rather than using a preset. The presets
    /// below set their sizes explicitly and don't go through this.
    private var scale: CGFloat {
        switch self {
        case .editorial: return 1.0
        // Manrope runs wide and tall for its point size; the kit's own
        // sizes are used as given rather than scaled up.
        case .system:    return 1.0
        }
    }

    /// The size a family function draws at. System has a floor of
    /// 11pt: the ~80 call sites that pass a literal were written for
    /// Editorial, whose 9pt and 10pt captions are too small to read
    /// comfortably in this theme's wider type. Deliberately smaller
    /// text (the badge's tracked capitals) asks for Manrope directly.
    private func scaled(_ size: CGFloat) -> CGFloat {
        let size = scale == 1 ? size : (size * scale).rounded()
        return self == .system ? max(size, Self.systemMinimumSize) : size
    }

    static let systemMinimumSize: CGFloat = 11

    // MARK: - Font families (SwiftUI)

    /// Titles: week dates, project names, task names, form fields.
    func title(_ size: CGFloat) -> Font {
        switch self {
        case .editorial: return .custom("Newsreader-Regular", size: size)
        case .system:    return Self.manrope(scaled(size), .semibold)
        }
    }

    func titleItalic(_ size: CGFloat) -> Font {
        switch self {
        case .editorial: return .custom("Newsreader-Italic", size: size)
        // The kit has no italic; emphasis is weight and color.
        case .system:    return Self.manrope(scaled(size), .semibold)
        }
    }

    /// Labels: client names, descriptions, buttons, settings rows.
    func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .editorial:
            switch weight {
            case .medium:   return .custom("DMSans-Medium", size: size)
            case .semibold: return .custom("DMSans-SemiBold", size: size)
            default:        return .custom("DMSans-Regular", size: size)
            }
        case .system:
            return Self.manrope(scaled(size), weight)
        }
    }

    func labelItalic(_ size: CGFloat) -> Font {
        switch self {
        case .editorial: return .custom("DMSans-Italic", size: size)
        case .system:    return Self.manrope(scaled(size), .regular)
        }
    }

    /// Numbers: times, totals, the timer display.
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .editorial:
            switch weight {
            case .medium: return .custom("JetBrainsMono-Medium", size: size)
            default:      return .custom("JetBrainsMono-Regular", size: size)
            }
        case .system:
            return Self.manrope(scaled(size), weight == .regular ? .medium : weight).monospacedDigit()
        }
    }

    // MARK: - Manrope (System theme)

    /// The Material-X kit's typeface. One variable font file is bundled
    /// (`Manrope-Variable.ttf`); its named instances resolve by
    /// PostScript name, so each weight is asked for the same way the
    /// static Editorial fonts are.
    static func manropeName(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium:              return "Manrope-Medium"
        case .semibold:            return "Manrope-SemiBold"
        case .bold:                return "Manrope-Bold"
        case .heavy, .black:       return "Manrope-ExtraBold"
        default:                   return "Manrope-Regular"
        }
    }

    static func manrope(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom(manropeName(weight), size: size)
    }

    // MARK: - Font families (AppKit)

    /// For the NSPopUpButton and NSAttributedString sites that can't
    /// take a SwiftUI `Font`. Same role mapping as above.
    func nsTitle(_ size: CGFloat) -> NSFont {
        switch self {
        case .editorial: return NSFont(name: "Newsreader-Regular", size: size) ?? .systemFont(ofSize: size)
        case .system:    return NSFont(name: "Manrope-SemiBold", size: scaled(size)) ?? .systemFont(ofSize: scaled(size), weight: .semibold)
        }
    }

    func nsLabel(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch self {
        case .editorial:
            let name: String
            switch weight {
            case .medium:   name = "DMSans-Medium"
            case .semibold: name = "DMSans-SemiBold"
            default:        name = "DMSans-Regular"
            }
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .system:
            let name: String
            switch weight {
            case .medium:   name = "Manrope-Medium"
            case .semibold: name = "Manrope-SemiBold"
            case .bold:     name = "Manrope-Bold"
            default:        name = "Manrope-Regular"
            }
            return NSFont(name: name, size: scaled(size)) ?? .systemFont(ofSize: scaled(size), weight: weight)
        }
    }

    // MARK: - Typography presets

    // Each preset names what it's for; the sizes are per theme and
    // deliberate rather than scaled, so the two looks can be tuned
    // independently. Editorial values are the app's original ones.

    /// Week dates, project names.
    var titleMedium: Font {
        switch self {
        case .editorial: return title(14)
        case .system:    return Self.manrope(14, .semibold)
        }
    }

    /// Task names, form fields.
    var titleSmall: Font {
        switch self {
        case .editorial: return title(12)
        case .system:    return Self.manrope(12, .semibold)
        }
    }

    /// Uppercase client names and field labels.
    var labelProject: Font {
        switch self {
        case .editorial: return label(9, weight: .medium)
        case .system:    return Self.manrope(10, .heavy)
        }
    }

    /// "Xh Ym remaining this week".
    var labelTimeRemaining: Font {
        switch self {
        case .editorial: return label(9)
        // 11pt: macOS's own size for supporting text. 10pt in
        // secondary grey was hard going.
        case .system:    return Self.manrope(11, .medium)
        }
    }

    /// Notes and descriptions.
    var labelNote: Font {
        switch self {
        case .editorial: return labelItalic(9)
        case .system:    return Self.manrope(11, .regular)
        }
    }

    /// Button labels.
    var labelButton: Font {
        switch self {
        case .editorial: return label(10, weight: .semibold)
        case .system:    return Self.manrope(12, .bold)
        }
    }

    /// Project time totals.
    var monoSmall: Font {
        switch self {
        case .editorial: return mono(11)
        case .system:    return Self.manrope(11.5, .medium).monospacedDigit()
        }
    }

    /// Task time values.
    var monoXS: Font {
        switch self {
        case .editorial: return mono(10)
        case .system:    return Self.manrope(11, .medium).monospacedDigit()
        }
    }

    /// The running timer display.
    var monoMedium: Font {
        switch self {
        case .editorial: return mono(12, weight: .medium)
        case .system:    return Self.manrope(12.5, .semibold).monospacedDigit()
        }
    }

    // MARK: - Grouped-layout presets

    /// The row's headline number — logged hours.
    var figureLarge: Font {
        switch self {
        case .editorial: return mono(11)
        case .system:    return Self.manrope(15, .bold).monospacedDigit()
        }
    }

    /// "/ 18h" beside the figure.
    var figureDenominator: Font {
        switch self {
        case .editorial: return mono(11)
        case .system:    return Self.manrope(11.5, .medium).monospacedDigit()
        }
    }

    /// The line under the project name: remaining / over / not linked.
    var rowSubtitle: Font {
        switch self {
        case .editorial: return label(9)
        case .system:    return Self.manrope(11, .medium)
        }
    }

    /// Client name above a group of rows.
    var sectionHeader: Font {
        switch self {
        case .editorial: return label(9, weight: .medium)
        // Medium, not bold: the band behind it does the separating,
        // so the name itself can stay quiet.
        case .system:    return Self.manrope(12, .medium)
        }
    }

    /// The timer banner's elapsed figure — the panel's hero number.
    var heroFigure: Font {
        switch self {
        case .editorial: return monoMedium
        case .system:    return Self.manrope(24, .semibold).monospacedDigit()
        }
    }

    // MARK: - Durations

    /// How a span of hours is written in the panel. Editorial keeps its
    /// "6h 30m"; System uses "6:30", the form the menu bar, the day
    /// strip and Harvest itself already use, so one number doesn't
    /// appear three different ways in the same window.
    func duration(_ hours: Double) -> String {
        switch self {
        case .editorial: return hours.formattedHoursMinutes
        case .system:    return hours.formattedColon
        }
    }

    // MARK: - Corner radii

    var panelRadius: CGFloat       { self == .editorial ? 14 : 16 }
    var cardRadius: CGFloat        { self == .editorial ? 8 : 12 }
    var buttonRadius: CGFloat      { self == .editorial ? 4 : 8 }
    var dropdownRadius: CGFloat    { self == .editorial ? 6 : 8 }
    var progressBarRadius: CGFloat { 4 }

    // MARK: - Buttons

    // Text buttons (+ Timer, Start Timer, Cancel, Delete…). System's are
    // a touch taller and rest at full opacity; Editorial's rest at 80%
    // and brighten on hover, as they always have.
    var buttonHeight: CGFloat            { self == .editorial ? 22 : 32 }
    var buttonHorizontalPadding: CGFloat { self == .editorial ? 11 : 12 }
    var buttonRestingOpacity: Double     { self == .editorial ? 0.8 : 1.0 }
    /// Corner radius for text buttons and header chips specifically —
    /// not the general `buttonRadius`, which other small controls
    /// share. System takes the kit's 8pt button corner.
    var pillRadius: CGFloat              { self == .editorial ? 4 : 8 }
    /// Icon-only buttons. The kit's are circles (its FAB); Editorial's
    /// share the text buttons' corner.
    var iconButtonRadius: CGFloat        { self == .editorial ? 4 : 16 }
    /// Letter-spacing on button labels: the kit tracks them 5%.
    var buttonLabelTracking: CGFloat     { self == .editorial ? 0 : 0.6 }
    /// Header icon chips (week chevrons, calendar). Editorial's are a
    /// 24×22 rectangle; System's are square so the clip makes a circle.
    var headerIconWidth: CGFloat         { self == .editorial ? 24 : 32 }
    /// Whether icon controls (play / pause / stop) are filled circles
    /// rather than bordered squares.
    var usesCircularControls: Bool       { self == .system }

    // MARK: - Dimensions

    // System rows use the grouped layout: two lines on each side, so a
    // booked and an unbooked row are the same height.

    var projectRowForecastedHeight: CGFloat { self == .editorial ? 74 : 58 }
    var projectRowDefaultHeight: CGFloat    { self == .editorial ? 56 : 58 }
    var progressBarWidth: CGFloat           { self == .editorial ? 104 : 140 }
    var controlHeight: CGFloat              { self == .editorial ? 32 : 34 }
    var inputFieldHeight: CGFloat           { self == .editorial ? 52 : 56 }
}

/// Holds the active theme and persists the choice.
///
/// `@Observable` is what makes the whole token layer live: the
/// `static var` tokens in `DesignTokens.swift` read `theme` here, and
/// Observation records that read for any SwiftUI body that's being
/// evaluated at the time — so every view that uses a token re-renders
/// when the theme changes, without a root-level `.id()` that would
/// reset view state (and kick the user out of the Settings panel they
/// just changed the theme from).
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var theme: YieldTheme

    private init() {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.uiTheme)
            ?? YieldTheme.default.rawValue
        theme = YieldTheme(rawValue: raw) ?? .default
    }

    func select(_ theme: YieldTheme) {
        guard theme != self.theme else { return }
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: DefaultsKey.uiTheme)
    }
}
