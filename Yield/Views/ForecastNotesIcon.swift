import SwiftUI

/// Leading-edge icon that surfaces a project's Forecast assignment notes
/// for the current week. Hover reveals the full text in a popover — the
/// native `.help()` tooltip has a ~1s delay we can't tune, and an inline
/// `.overlay` gets drawn behind sibling row text inside MenuBarExtra
/// panels. A popover renders in its own floating window, so it's always
/// on top and sizes to content automatically.
/// Used at the start of both `ProjectRowView` and `LookAheadRowView`.
struct ForecastNotesIcon: View {
    let notes: String

    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 14))
            .foregroundStyle(YieldColors.textSecondary)
            .onHover { hovering in
                hoverTask?.cancel()
                // 100ms show delay (avoid flicker when skimming past the
                // icon) and 150ms hide delay (so a brief hover gap while
                // the popover is materializing doesn't dismiss it).
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

    /// Sequoia (macOS 15) and later get fluid sizing — the popover hugs
    /// short content and wraps long content at 260pt. Sonoma (14) gets a
    /// deterministic fixed-width frame: at least one beta tester on
    /// 14.6.1 saw the `maxWidth + fixedSize` combo render absurdly tall
    /// popovers regardless of content (no special characters in the
    /// note, repro on every project's tooltip), which points at a
    /// SwiftUI popover-sizing bug specific to that OS.
    @ViewBuilder
    private var tooltipText: some View {
        if #available(macOS 15.0, *) {
            Text(notes)
                .font(YieldFonts.dmSans(13))
                .foregroundStyle(YieldColors.textPrimary)
                .lineLimit(nil)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(20)
        } else {
            Text(notes)
                .font(YieldFonts.dmSans(13))
                .foregroundStyle(YieldColors.textPrimary)
                .lineLimit(nil)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(width: 260, alignment: .leading)
                .padding(20)
        }
    }
}
