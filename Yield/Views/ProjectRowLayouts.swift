import SwiftUI

/// What a row layout needs to draw the two header columns.
struct ProjectRowHeaderContext {
    let project: ProjectStatus
    let effectiveLoggedHours: Double
    let dayFilteredHours: Double?
    let hasEntries: Bool
    let isExpanded: Bool
}

/// The header layout of a `ProjectRowView`, chosen by the *parent* as a
/// type parameter.
///
/// The two columns of the header are the only part of the row that
/// differs between themes; the drawer, hover actions, menus and
/// gestures are shared. Keeping each layout as a pair of static
/// functions here — rather than a runtime branch inside the row —
/// keeps the row free of theme logic and puts the two looks side by
/// side where they can be compared. `MenuBarContentView` picks
/// `EditorialRowLayout` or `GroupedRowLayout` where it builds the
/// list, next to the grouping decision that goes with it.
///
/// Editorial must stay pixel-identical to the app as it shipped, and
/// is verified against a render of the pre-fork commit (see
/// `ThemeSnapshotTests`). Its functions return exactly the `VStack`s
/// the row used to build inline.
protocol ProjectRowLayout {
    associatedtype LeftColumn: View
    associatedtype TimeColumn: View

    /// Name side.
    @ViewBuilder static func leftColumn(_ ctx: ProjectRowHeaderContext) -> LeftColumn
    /// Time / progress side; the row wraps it in the hover-action zone.
    @ViewBuilder static func timeColumn(_ ctx: ProjectRowHeaderContext) -> TimeColumn
    /// Color of the 3pt line on the row's leading edge. `.clear` keeps
    /// the slot (and the row's alignment) without drawing anything.
    static func statusLineColor(_ project: ProjectStatus) -> Color
    /// Whether the expanded drawer is drawn as a tinted band with
    /// one-line entries (System) rather than as full-width rows on the
    /// list's own background (Editorial).
    static var usesBandDrawer: Bool { get }
    /// Fill behind the row's header for its hover and open states.
    static func headerBackground(isHovered: Bool, isExpanded: Bool) -> Color
}

// MARK: - Editorial (the original layout)

/// Client name in small caps, project name, remaining label; time
/// label and progress bar on the right. Byte-for-byte the row's
/// original header columns, moved here unchanged.
enum EditorialRowLayout: ProjectRowLayout {

    static var usesBandDrawer: Bool { false }

    static func headerBackground(isHovered: Bool, isExpanded: Bool) -> Color {
        isHovered ? YieldColors.surfaceDefault : Color.clear
    }

    /// - Clear: project has no booking (Harvest-only tracked time)
    /// - Pink: prospective / proposal-stage (booked but no Harvest link)
    /// - Amber: booked but the user isn't a member of the Harvest
    ///   project (the warning badge by the name carries the detail)
    /// - White: normal booked project
    static func statusLineColor(_ project: ProjectStatus) -> Color {
        guard project.isForecasted else { return .clear }
        switch project.harvestLinkState {
        case .prospective: return YieldStatusColors.prospective
        case .unassigned:  return YieldStatusColors.warning
        case .linked:      return YieldColors.onBackground.opacity(0.7)
        }
    }

    static func leftColumn(_ ctx: ProjectRowHeaderContext) -> some View {
        // Left: client, name, remaining
        VStack(alignment: .leading, spacing: 6) {
            // Client name
            if let clientName = ctx.project.clientName {
                Text(clientName.uppercased())
                    .font(YieldFonts.labelProject)
                    .foregroundStyle(YieldColors.textSecondary)
                    .lineLimit(1)
            }

            // Project name + chevron. `displayName` adds the
            // "[code]" prefix when the Forecast project has
            // a code set.
            HStack(spacing: 10) {
                Text(ctx.project.displayName)
                    .font(YieldFonts.titleMedium)
                    .foregroundStyle(YieldColors.textPrimary)
                    .lineLimit(1)

                // Booked in Forecast, but the Harvest side
                // can't take time — either the user isn't a
                // member of the project, or the project was
                // never linked to Harvest at all. Booked hours
                // still show in full; this just names the gap
                // (self-hides when the link is healthy).
                HarvestLinkIcon(
                    state: ctx.project.harvestLinkState,
                    projectName: ctx.project.displayName
                )

                if ctx.hasEntries {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(YieldColors.textPrimary)
                        .rotationEffect(.degrees(ctx.isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.15), value: ctx.isExpanded)
                }
            }

            // Remaining / over label (forecasted only)
            if ctx.project.isForecasted {
                let remaining = ctx.project.bookedHours - ctx.effectiveLoggedHours
                if remaining != 0 {
                    Text(RowFormat.remainingLabel(remaining))
                        .font(YieldFonts.labelTimeRemaining)
                        .foregroundStyle(remaining < 0 ? YieldStatusColors.over : YieldColors.greenAccent)
                        .tracking(0.18)
                }
            }
        }
    }

    static func timeColumn(_ ctx: ProjectRowHeaderContext) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            timeLabel(ctx)

            if ctx.project.isForecasted {
                ProgressBarView(
                    logged: ctx.effectiveLoggedHours,
                    booked: ctx.project.bookedHours,
                    dayLogged: ctx.dayFilteredHours
                )
            }
        }
    }

    private static func timeLabel(_ ctx: ProjectRowHeaderContext) -> some View {
        Group {
            if let dayHours = ctx.dayFilteredHours {
                // Day filter active: show "day total / week-so-far" so the
                // filtered day's contribution is framed against the week.
                HStack(spacing: 0) {
                    Text(RowFormat.hoursMinutes(dayHours) + " / ")
                        .foregroundStyle(YieldColors.textPrimary)
                    Text(RowFormat.hoursMinutes(ctx.effectiveLoggedHours))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .font(YieldFonts.monoSmall)
            } else if ctx.project.isForecasted {
                HStack(spacing: 0) {
                    Text(RowFormat.hoursMinutes(ctx.effectiveLoggedHours) + " / ")
                        .foregroundStyle(YieldColors.textPrimary)
                    Text(RowFormat.hoursOnly(ctx.project.bookedHours))
                        .foregroundStyle(YieldColors.textSecondary)
                }
                .font(YieldFonts.monoSmall)
            } else {
                Text(RowFormat.hoursMinutes(ctx.effectiveLoggedHours))
                    .font(YieldFonts.monoSmall)
                    .foregroundStyle(YieldColors.textPrimary)
            }
        }
        .fixedSize()
    }
}

// MARK: - Grouped (System theme)

/// The client name lives in a `ClientSectionHeader` above the group, so
/// the row is two lines each side: name + subtitle on the left, figure
/// + bar on the right.
enum GroupedRowLayout: ProjectRowLayout {

    /// An open project is one block: its header and its entries share
    /// a grey band that runs the full width of the panel. Nothing is
    /// inset, so there is no box inside the list — the block's own
    /// edges say where the project's entries start and stop.
    static var usesBandDrawer: Bool { true }

    /// Open: the band's grey, hovered or not, so the header and the
    /// drawer never show a seam. Closed and hovered: a wash of the
    /// control colour — deliberately not that grey, so a hovered row
    /// next to an open project doesn't read as part of it.
    static func headerBackground(isHovered: Bool, isExpanded: Bool) -> Color {
        if isExpanded { return YieldColors.surfaceDefault }
        return isHovered ? YieldColors.rowHover : Color.clear
    }

    /// The edge line means exactly one thing here: this is the project
    /// the clock is running on. "Booked" is already said by the
    /// "/ 10:00" beside the figure, and the unlinked states by their
    /// icon and subtitle, so those no longer get a line — a grey stripe
    /// on nearly every row was decoration. Marking the running row on
    /// the edge, rather than with a dot before its name, also keeps
    /// every project name on the same left margin.
    static func statusLineColor(_ project: ProjectStatus) -> Color {
        project.isTracking ? YieldStatusColors.under : .clear
    }

    static func leftColumn(_ ctx: ProjectRowHeaderContext) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                title(ctx.project)
                    .font(YieldFonts.titleMedium)
                    .lineLimit(1)

                HarvestLinkIcon(
                    state: ctx.project.harvestLinkState,
                    projectName: ctx.project.displayName
                )

                if ctx.hasEntries {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(YieldColors.textPrimary)
                        .rotationEffect(.degrees(ctx.isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.15), value: ctx.isExpanded)
                }
            }

            if ctx.project.isForecasted {
                let subtitle = subtitle(ctx)
                Text(subtitle.text)
                    .font(YieldFonts.rowSubtitle)
                    .foregroundStyle(subtitle.color)
                    .lineLimit(1)
            } else {
                unbookedTag
            }
        }
    }

    /// The project name, with its Forecast code — "[12]" — in secondary
    /// ink. Same text as `displayName`; the code is a reference number,
    /// and at full weight it competed with the name it's attached to.
    static func title(_ project: ProjectStatus) -> Text {
        let name = Text(project.projectName).foregroundStyle(YieldColors.textPrimary)
        guard let code = project.projectCode, !code.isEmpty else { return name }
        return Text("[\(code)] ").foregroundStyle(YieldColors.textSecondary) + name
    }

    /// What tells booked from unbooked in the "All" list. Booked is the
    /// norm, so the mark goes on the exception: time tracked against a
    /// project with no booking this week. It sits on the subtitle line,
    /// at the left margin, so the tags line up and can be picked out by
    /// running an eye down the edge — the job the old stripe did,
    /// without a line on every booked row. A filled shape rather than
    /// more grey text, so it reads as a mark, not a sentence.
    private static var unbookedTag: some View {
        YieldBadge(text: "Unbooked", neutral: true)
            .help("Not booked in Forecast this week")
    }

    static func timeColumn(_ ctx: ProjectRowHeaderContext) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            figure(ctx)

            if ctx.project.isForecasted {
                if ctx.project.harvestLinkState == .prospective {
                    // Nothing can be logged against it, so an empty
                    // fill would be a lie. A dashed outline reads as
                    // "placeholder". Neutral, not pink: the icon and
                    // the subtitle already say what's wrong, and this
                    // only has to hold the column's rhythm.
                    Capsule()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(YieldColors.buttonBorder)
                        .frame(width: YieldDimensions.progressBarWidth, height: YieldDimensions.progressBarHeight)
                } else {
                    ProgressBarView(
                        logged: ctx.effectiveLoggedHours,
                        booked: ctx.project.bookedHours,
                        dayLogged: ctx.dayFilteredHours
                    )
                }
            }
        }
    }

    /// The line under the name. Says what the row *is* when there's
    /// nothing to count down — the states that used to be a bare
    /// colored stripe.
    private static func subtitle(_ ctx: ProjectRowHeaderContext) -> (text: String, color: Color) {
        // Unbooked rows show `unbookedTag` instead and never reach here.
        guard ctx.project.isForecasted else {
            return ("Unbooked", YieldColors.textSecondary)
        }
        switch ctx.project.harvestLinkState {
        case .prospective:
            return ("Not linked to a Harvest project", YieldStatusColors.prospective)
        case .unassigned:
            return ("Not a member of the Harvest project", YieldStatusColors.warning)
        case .linked:
            // Over budget is a signal and keeps its color. On track is
            // the normal case on every booked row, so it reads in
            // secondary ink.
            let remaining = ctx.project.bookedHours - ctx.effectiveLoggedHours
            return (RowFormat.remainingShort(remaining),
                    remaining < 0 ? YieldStatusColors.over : YieldColors.textSecondary)
        }
    }

    /// Headline figure: logged hours large, booked as the denominator.
    /// Under a day filter the figure is the day and the denominator the
    /// week so far, mirroring the Editorial time label.
    private static func figure(_ ctx: ProjectRowHeaderContext) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let dayHours = ctx.dayFilteredHours {
                Text(RowFormat.colon(dayHours))
                    .font(YieldFonts.figureLarge)
                    .foregroundStyle(YieldColors.textPrimary)
                Text("/ " + RowFormat.colon(ctx.effectiveLoggedHours))
                    .font(YieldFonts.figureDenominator)
                    .foregroundStyle(YieldColors.textSecondary)
            } else if ctx.project.isForecasted && ctx.project.harvestLinkState == .prospective {
                Text("—")
                    .font(YieldFonts.figureLarge)
                    .foregroundStyle(YieldColors.textSecondary)
                Text("/ " + RowFormat.colon(ctx.project.bookedHours))
                    .font(YieldFonts.figureDenominator)
                    .foregroundStyle(YieldColors.textSecondary)
            } else if ctx.project.isForecasted {
                Text(RowFormat.colon(ctx.effectiveLoggedHours))
                    .font(YieldFonts.figureLarge)
                    .foregroundStyle(YieldColors.textPrimary)
                Text("/ " + RowFormat.colon(ctx.project.bookedHours))
                    .font(YieldFonts.figureDenominator)
                    .foregroundStyle(YieldColors.textSecondary)
            } else {
                Text(RowFormat.colon(ctx.effectiveLoggedHours))
                    .font(YieldFonts.figureLarge)
                    .foregroundStyle(YieldColors.textPrimary)
            }
        }
        .fixedSize()
    }
}

// MARK: - Shared formatting

enum RowFormat {
    static func hoursMinutes(_ hours: Double) -> String {
        Swift.abs(hours).formattedHoursMinutes
    }

    static func hoursOnly(_ hours: Double) -> String {
        "\(Int(hours))h"
    }

    /// System theme: "6:30", matching the menu bar and the day strip.
    static func colon(_ hours: Double) -> String {
        Swift.abs(hours).formattedColon
    }

    /// System theme: "3:30 left" / "1:30 over". No "this week" — every
    /// row in the list is this week — and the same wording as the menu
    /// bar's "Time left" text.
    static func remainingShort(_ remaining: Double) -> String {
        TimeComparisonViewModel.formatLeft(remaining)
    }

    static func remainingLabel(_ remaining: Double) -> String {
        let suffix = remaining < 0 ? "over this week" : "remaining this week"
        return "\(Swift.abs(remaining).formattedHoursMinutes) \(suffix)"
    }
}
