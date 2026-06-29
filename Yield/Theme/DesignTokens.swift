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

enum YieldColors {
    /// Panel background. Dark mode is the original `#1A1B1C`; light mode
    /// is a slightly cool off-white that mirrors that brightness without
    /// the harshness of pure white.
    static let background = dynamicColor(
        light: NSColor(red: 0.961, green: 0.961, blue: 0.965, alpha: 1.0),  // #F5F5F6
        dark:  NSColor(red: 0.102, green: 0.106, blue: 0.110, alpha: 1.0)   // #1A1B1C
    )

    // Brand accents flip between a bright dark-mode value and a darker
    // light-mode value tuned for WCAG AA (≥ 4.5:1) against the panel
    // background. The opacity-derived variants below inherit from these
    // dynamic accents, so e.g. `greenFaint` becomes a soft pale-green
    // wash in light mode and the original 4% white-tinted glow in dark.
    static let greenAccent = dynamicColor(
        light: NSColor(red: 0.043, green: 0.439, blue: 0.282, alpha: 1.0),  // #0B7048 — 5.6:1 on light bg
        dark:  NSColor(red: 0.082, green: 0.855, blue: 0.576, alpha: 1.0)   // #15DA93 — 9.95:1 on dark bg
    )
    static let greenDim = greenAccent.opacity(0.3)
    static let greenSubtle = greenAccent.opacity(0.15)
    static let greenFaint = greenAccent.opacity(0.04)

    static let yellowAccent = dynamicColor(
        light: NSColor(red: 0.580, green: 0.380, blue: 0.0,   alpha: 1.0),  // #946100 — 4.9:1 on light bg
        dark:  NSColor(red: 1.0,   green: 0.831, blue: 0.286, alpha: 1.0)   // #FFD449 — 12.7:1 on dark bg
    )
    static let yellowDim = yellowAccent.opacity(0.3)
    static let yellowFaint = yellowAccent.opacity(0.1)

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
    static let greenBorder = greenAccent.opacity(0.15)
    static let greenBorderActive = greenAccent.opacity(0.3)

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

    /// Generic foreground that should always contrast the panel
    /// background — `Color.white` in dark mode, dark gray in light. Use
    /// for status lines, dot fills, and any place a literal white was
    /// previously hard-coded against the dark bg.
    static let onBackground = dynamicColor(
        light: NSColor(red: 0.102, green: 0.106, blue: 0.110, alpha: 1.0),
        dark:  .white
    )
}

// MARK: - Fonts

enum YieldFonts {
    // Newsreader — titles, dates, project names
    static func newsreader(_ size: CGFloat) -> Font {
        .custom("Newsreader-Regular", size: size)
    }

    static func newsreaderItalic(_ size: CGFloat) -> Font {
        .custom("Newsreader-Italic", size: size)
    }

    // DM Sans — labels, descriptions
    static func dmSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium:
            return .custom("DMSans-Medium", size: size)
        case .semibold:
            return .custom("DMSans-SemiBold", size: size)
        default:
            return .custom("DMSans-Regular", size: size)
        }
    }

    static func dmSansItalic(_ size: CGFloat) -> Font {
        .custom("DMSans-Italic", size: size)
    }

    // JetBrains Mono — times, numbers
    static func jetBrainsMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium:
            return .custom("JetBrainsMono-Medium", size: size)
        default:
            return .custom("JetBrainsMono-Regular", size: size)
        }
    }
}

// MARK: - Typography Presets

extension YieldFonts {
    /// 14px Newsreader — week dates, project names
    static let titleMedium = newsreader(14)

    /// 12px Newsreader — task names, form fields
    static let titleSmall = newsreader(12)

    /// 9px DM Sans Medium uppercase — client names, field labels
    static let labelProject = dmSans(9, weight: .medium)

    /// 9px DM Sans — remaining time labels
    static let labelTimeRemaining = dmSans(9)

    /// 9px DM Sans Italic — notes, descriptions
    static let labelNote = dmSansItalic(9)

    /// 10px DM Sans SemiBold — button labels
    static let labelButton = dmSans(10, weight: .semibold)

    /// 11px JetBrains Mono — project time totals
    static let monoSmall = jetBrainsMono(11)

    /// 10px JetBrains Mono — task time values
    static let monoXS = jetBrainsMono(10)

    /// 12px JetBrains Mono Medium — timer display
    static let monoMedium = jetBrainsMono(12, weight: .medium)
}

// MARK: - Corner Radii

// MARK: - Status Colors

enum YieldStatusColors {
    static let under = YieldColors.greenAccent
    static let over = dynamicColor(
        light: NSColor(red: 0.757, green: 0.243, blue: 0.055, alpha: 1.0),  // #C13E0E — 4.8:1 on light bg
        dark:  NSColor(red: 0.941, green: 0.365, blue: 0.157, alpha: 1.0)   // #F05D28 — 5.5:1 on dark bg
    )
    static let unbooked = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.3),
        dark:  NSColor.white.withAlphaComponent(0.3)
    )
    /// Prospective / proposal-stage Forecast projects — booked but not
    /// yet linked to a Harvest project. Used as the 2px status line.
    static let prospective = dynamicColor(
        light: NSColor(red: 0.722, green: 0.153, blue: 0.435, alpha: 1.0),  // #B8276F — 5.4:1 on light bg
        dark:  NSColor(red: 0.941, green: 0.365, blue: 0.627, alpha: 1.0)   // #F05DA0 — 5.0:1 on dark bg
    )
    /// Warning amber — a real, actionable problem that isn't an error:
    /// a project booked in Forecast the user isn't a member of in
    /// Harvest. Status line + the row's unassigned badge. WCAG-checked
    /// against both backgrounds.
    static let warning = dynamicColor(
        light: NSColor(red: 0.580, green: 0.380, blue: 0.0,   alpha: 1.0),  // #946100 — 4.6:1 on light bg
        dark:  NSColor(red: 1.0,   green: 0.831, blue: 0.286, alpha: 1.0)   // #FFD449 — 11.9:1 on dark bg
    )
}

enum YieldRadius {
    static let panel: CGFloat = 14
    static let card: CGFloat = 8
    static let button: CGFloat = 4
    static let dropdown: CGFloat = 6
    static let progressBar: CGFloat = 4
}

// MARK: - Dimensions

enum YieldDimensions {
    static let panelWidth: CGFloat = 540
    static let progressBarWidth: CGFloat = 104
    static let progressBarHeight: CGFloat = 4
    static let timerButtonSize: CGFloat = 24
    /// Standard control height for inline form inputs — pickers,
    /// favorite-list buttons. Matches the dropdown's intrinsic 32pt
    /// hit target.
    static let controlHeight: CGFloat = 32
    /// Notes field + time-input field tracked together so they read
    /// as a paired row in the new/edit timer form.
    static let inputFieldHeight: CGFloat = 52
    /// Settings row dropdown width — same value used for every
    /// `enumPickerRow` so all rows align.
    static let settingsRowControlWidth: CGFloat = 160
    /// Project row heights — taller when the row carries a progress
    /// bar (forecasted), shorter when it doesn't.
    static let projectRowForecastedHeight: CGFloat = 74
    static let projectRowDefaultHeight: CGFloat = 56
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
