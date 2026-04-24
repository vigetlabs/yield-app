import SwiftUI

// MARK: - Colors

enum YieldColors {
    static let background = Color(red: 0.102, green: 0.106, blue: 0.110)         // #1A1B1C
    static let greenAccent = Color(red: 0.082, green: 0.855, blue: 0.576)        // #15DA93
    static let greenDim = Color(red: 0.082, green: 0.855, blue: 0.576).opacity(0.3)
    static let greenSubtle = Color(red: 0.082, green: 0.855, blue: 0.576).opacity(0.15)
    static let greenFaint = Color(red: 0.082, green: 0.855, blue: 0.576).opacity(0.04)

    static let yellowAccent = Color(red: 1.0, green: 0.831, blue: 0.286)            // #FFD449
    static let yellowDim = Color(red: 1.0, green: 0.831, blue: 0.286).opacity(0.3)
    static let yellowFaint = Color(red: 1.0, green: 0.831, blue: 0.286).opacity(0.1)

    static let border = Color.white.opacity(0.1)
    static let buttonBorder = Color.white.opacity(0.3)
    static let greenBorder = Color(red: 0.082, green: 0.855, blue: 0.576).opacity(0.15)
    static let greenBorderActive = Color(red: 0.082, green: 0.855, blue: 0.576).opacity(0.3)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)

    static let surfaceDefault = Color.white.opacity(0.04)
    static let surfaceActive = Color.white.opacity(0.1)
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
    static let over = Color(red: 0.941, green: 0.365, blue: 0.157)       // #F05D28
    static let unbooked = Color.white.opacity(0.3)
    /// Prospective / proposal-stage Forecast projects — booked but not
    /// yet linked to a Harvest project. Used as the status line color.
    static let prospective = Color(red: 0.941, green: 0.365, blue: 0.627) // #F05DA0
}

enum YieldRadius {
    static let panel: CGFloat = 14
    static let card: CGFloat = 8
    static let button: CGFloat = 4
    static let dropdown: CGFloat = 6
    static let dropdownOverlay: CGFloat = 8
    static let progressBar: CGFloat = 4
}

// MARK: - Dimensions

enum YieldDimensions {
    static let panelWidth: CGFloat = 540
    static let progressBarWidth: CGFloat = 104
    static let progressBarHeight: CGFloat = 4
    static let timerButtonSize: CGFloat = 24
}

// MARK: - Domain constants

enum YieldConstants {
    /// The Forecast project name used to represent all time-off bookings
    /// (vacation, sick, holiday, PTO). This is a single undeletable project
    /// maintained by Forecast itself — we match on name to identify it.
    static let timeOffProjectName = "Time Off"

    /// Standard workday length in hours. Used to:
    /// - render the 8h dashed reference line on the weekly chart
    /// - convert a full-day PTO block (allocation == 0) into an hours total
    /// - compute the "days" portion of time-off summaries (8h = 1d)
    static let workdayHours: Double = 8
}
