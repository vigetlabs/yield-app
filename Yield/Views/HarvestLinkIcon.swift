import SwiftUI

/// Badge for a Forecast booking whose Harvest side isn't usable — sits
/// next to the project name on the row and explains, in words, why the
/// row can't be tracked against.
///
/// Covers both non-`.linked` states, which look similar (booked hours
/// with no way to log against them) but have different causes and
/// different people to go ask:
///
/// - `.unassigned` — the Harvest project exists, the user just isn't a
///   member of it. Fixed in Harvest.
/// - `.prospective` — the Forecast project has no `harvest_id` at all,
///   so there's no Harvest project to be a member of. Either genuinely
///   proposal-stage work, or a project nobody linked. Fixed in Forecast.
///
/// Renders nothing for `.linked`, so call sites can use it
/// unconditionally.
///
/// Mirrors `ForecastNotesIcon`'s hover-popover pattern (the native
/// `.help()` tooltip has an untunable ~1s delay, and an inline overlay
/// draws behind sibling row text inside MenuBarExtra panels; a popover
/// renders in its own floating window so it's always on top).
struct HarvestLinkIcon: View {
    let state: ProjectStatus.HarvestLinkState
    /// The project's display name, woven into the explanation so the
    /// tooltip reads as a specific, actionable sentence.
    let projectName: String

    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        if state != .linked {
            Image(systemName: symbolName)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .onHover { hovering in
                    hoverTask?.cancel()
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(hovering ? 100 : 150))
                        if !Task.isCancelled {
                            showTooltip = hovering
                        }
                    }
                }
                .popover(
                    isPresented: $showTooltip,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .trailing
                ) {
                    tooltipText
                }
        }
    }

    /// Matches the row's leading status-line color so the badge reads as
    /// a label for the stripe rather than an unrelated warning.
    private var tint: Color {
        switch state {
        case .prospective: return YieldStatusColors.prospective
        case .unassigned:  return YieldStatusColors.warning
        case .linked:      return .clear
        }
    }

    private var symbolName: String {
        switch state {
        case .prospective: return "link.badge.plus"
        case .unassigned:  return "person.crop.circle.badge.exclamationmark"
        case .linked:      return ""
        }
    }

    private var explanation: String {
        switch state {
        case .prospective:
            return "\(projectName) is booked in Forecast but isn't linked to a Harvest project, so there's nothing to log time against. That's expected for proposal-stage work — otherwise a project admin can link it from Forecast."
        case .unassigned:
            return "You're booked on \(projectName) in Forecast but aren't a member of it in Harvest, so you can't log time against it yet. Ask a project admin to add you in Harvest."
        case .linked:
            return ""
        }
    }

    private var tooltipText: some View {
        Text(explanation)
            .font(YieldFonts.dmSans(13))
            .foregroundStyle(YieldColors.textPrimary)
            .lineLimit(nil)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .frame(width: 260, alignment: .leading)
            .padding(20)
    }
}
