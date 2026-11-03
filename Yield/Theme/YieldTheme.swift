import AppKit
import Observation
import SwiftUI

/// The app's selectable look. Settings → Preferences → Theme.
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
    /// System fonts — SF Pro for text, SF Mono for times — at slightly
    /// larger sizes, with a little more room in each row and softer
    /// corners. Built for legibility at the panel's small type sizes:
    /// the serif's thin strokes are what make 14px project names hard
    /// to read, and SF is what macOS rasterizes best at that scale.
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

    /// Whether the panel uses the grouped list layout: client section
    /// headers over rows whose header is name + subtitle on the left
    /// and figure + bar on the right, instead of the per-row client
    /// label. This is a *layout* fork, not a typographic one — it's
    /// gated here rather than derived from fonts so Editorial stays
    /// pixel-identical to the app as it shipped, by decision.
    var usesGroupedLayout: Bool { self == .system }

    /// Whether the weekly chart uses the refreshed styling — validated
    /// series palette, hover breakdown, square legend swatches (System).
    /// Same form as Editorial's stacked area; same fork discipline as
    /// `usesGroupedLayout`: Editorial keeps the chart exactly as it
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
        case .system:    return 1.05
        }
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        scale == 1 ? size : (size * scale).rounded()
    }

    // MARK: - Font families (SwiftUI)

    /// Titles: week dates, project names, task names, form fields.
    func title(_ size: CGFloat) -> Font {
        switch self {
        case .editorial: return .custom("Newsreader-Regular", size: size)
        case .system:    return .system(size: scaled(size), weight: .medium)
        }
    }

    func titleItalic(_ size: CGFloat) -> Font {
        switch self {
        case .editorial: return .custom("Newsreader-Italic", size: size)
        case .system:    return .system(size: scaled(size), weight: .medium).italic()
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
            return .system(size: scaled(size), weight: weight)
        }
    }

    func labelItalic(_ size: CGFloat) -> Font {
        switch self {
        case .editorial: return .custom("DMSans-Italic", size: size)
        case .system:    return .system(size: scaled(size)).italic()
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
            return .system(size: scaled(size), weight: weight).monospacedDigit()
        }
    }

    // MARK: - Font families (AppKit)

    /// For the NSPopUpButton and NSAttributedString sites that can't
    /// take a SwiftUI `Font`. Same role mapping as above.
    func nsTitle(_ size: CGFloat) -> NSFont {
        switch self {
        case .editorial: return NSFont(name: "Newsreader-Regular", size: size) ?? .systemFont(ofSize: size)
        case .system:    return .systemFont(ofSize: scaled(size), weight: .medium)
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
            return .systemFont(ofSize: scaled(size), weight: weight)
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
        case .system:    return .system(size: 14.5, weight: .medium)
        }
    }

    /// Task names, form fields.
    var titleSmall: Font {
        switch self {
        case .editorial: return title(12)
        case .system:    return .system(size: 12.5, weight: .medium)
        }
    }

    /// Uppercase client names and field labels.
    var labelProject: Font {
        switch self {
        case .editorial: return label(9, weight: .medium)
        case .system:    return .system(size: 10, weight: .semibold)
        }
    }

    /// "Xh Ym remaining this week".
    var labelTimeRemaining: Font {
        switch self {
        case .editorial: return label(9)
        case .system:    return .system(size: 10)
        }
    }

    /// Notes and descriptions.
    var labelNote: Font {
        switch self {
        case .editorial: return labelItalic(9)
        case .system:    return .system(size: 10).italic()
        }
    }

    /// Button labels.
    var labelButton: Font {
        switch self {
        case .editorial: return label(10, weight: .semibold)
        case .system:    return .system(size: 10.5, weight: .semibold)
        }
    }

    /// Project time totals.
    var monoSmall: Font {
        switch self {
        case .editorial: return mono(11)
        case .system:    return .system(size: 11.5).monospacedDigit()
        }
    }

    /// Task time values.
    var monoXS: Font {
        switch self {
        case .editorial: return mono(10)
        case .system:    return .system(size: 10.5).monospacedDigit()
        }
    }

    /// The running timer display.
    var monoMedium: Font {
        switch self {
        case .editorial: return mono(12, weight: .medium)
        case .system:    return .system(size: 12.5, weight: .medium).monospacedDigit()
        }
    }

    // MARK: - Grouped-layout presets

    /// The row's headline number — logged hours.
    var figureLarge: Font {
        switch self {
        case .editorial: return mono(11)
        case .system:    return .system(size: 15, weight: .medium).monospacedDigit()
        }
    }

    /// "/ 18h" beside the figure.
    var figureDenominator: Font {
        switch self {
        case .editorial: return mono(11)
        case .system:    return .system(size: 11.5).monospacedDigit()
        }
    }

    /// The line under the project name: remaining / over / not linked.
    var rowSubtitle: Font {
        switch self {
        case .editorial: return label(9)
        case .system:    return .system(size: 10)
        }
    }

    /// Client name above a group of rows.
    var sectionHeader: Font {
        switch self {
        case .editorial: return label(9, weight: .medium)
        case .system:    return .system(size: 10.5, weight: .semibold)
        }
    }

    // MARK: - Corner radii

    var panelRadius: CGFloat       { self == .editorial ? 14 : 16 }
    var cardRadius: CGFloat        { self == .editorial ? 8 : 10 }
    var buttonRadius: CGFloat      { self == .editorial ? 4 : 6 }
    var dropdownRadius: CGFloat    { self == .editorial ? 6 : 8 }
    var progressBarRadius: CGFloat { 4 }

    // MARK: - Buttons

    // Text buttons (+ Timer, Start Timer, Cancel, Delete…). System's are
    // a touch taller and rest at full opacity; Editorial's rest at 80%
    // and brighten on hover, as they always have.
    var buttonHeight: CGFloat            { self == .editorial ? 22 : 26 }
    var buttonHorizontalPadding: CGFloat { self == .editorial ? 11 : 12 }
    var buttonRestingOpacity: Double     { self == .editorial ? 0.8 : 1.0 }

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
