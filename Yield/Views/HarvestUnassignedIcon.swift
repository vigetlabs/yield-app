import SwiftUI

/// Warning badge for a project booked in Forecast that the current user
/// isn't a member of in Harvest — so they can see what they're meant to
/// work on, but Harvest will reject any time entry until an admin adds
/// them. Sits next to the project name on the row.
///
/// Mirrors `ForecastNotesIcon`'s hover-popover pattern (the native
/// `.help()` tooltip has an untunable ~1s delay, and an inline overlay
/// draws behind sibling row text inside MenuBarExtra panels; a popover
/// renders in its own floating window so it's always on top).
struct HarvestUnassignedIcon: View {
    /// The project's display name, woven into the explanation so the
    /// tooltip reads as a specific, actionable sentence.
    let projectName: String

    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "person.crop.circle.badge.exclamationmark")
            .font(.system(size: 13))
            .foregroundStyle(YieldStatusColors.warning)
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

    private var tooltipText: some View {
        Text("You're booked on \(projectName) in Forecast but aren't a member of it in Harvest, so you can't log time against it yet. Ask a project admin to add you in Harvest.")
            .font(YieldFonts.dmSans(13))
            .foregroundStyle(YieldColors.textPrimary)
            .lineLimit(nil)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .frame(width: 260, alignment: .leading)
            .padding(20)
    }
}
