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
                Text(notes)
                    .font(YieldFonts.dmSans(13))
                    .foregroundStyle(YieldColors.textPrimary)
                    // Cap at 30 lines so pathological notes (invisible
                    // chars that slip past normalization, extreme
                    // length) can't blow the popover up to fill the
                    // screen. Truncates mid-content past that.
                    .lineLimit(30)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .leading)
                    .padding(20)
            }
    }
}
