import SwiftUI

struct ServiceWarningBanner: View {
    let viewModel: TimeComparisonViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(YieldColors.yellowAccent)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.serviceErrors) { error in
                    ServiceErrorRow(
                        error: error,
                        snapshot: viewModel.statusSnapshot,
                        compact: true
                    )
                }
            }

            Spacer(minLength: 8)

            RetryLoadButton(viewModel: viewModel, compact: true)
        }
        // System: on the list's text margin, like the bars around it.
        .padding(.leading, ThemeStore.shared.theme.usesRefreshedLayout ? 16 + 3 : 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(YieldColors.yellowFaint)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YieldColors.border)
                .frame(height: 1)
        }
    }
}

/// "Try again" on a failed load: re-runs the full refresh. Shown where
/// the failure is reported — the warning banner and the full-panel
/// error — rather than as a standing Refresh in the gear menu, since a
/// retry is only wanted when something has gone wrong.
struct RetryLoadButton: View {
    let viewModel: TimeComparisonViewModel
    /// Compact: a text link, the weight of the banner's "Status page"
    /// link. Otherwise a bordered button for the full-panel error.
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                Button(action: retry) {
                    label(iconSize: 8, spacing: 3)
                        .font(YieldFonts.label(10, weight: .medium))
                        .foregroundStyle(YieldColors.controlAccent)
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reload from Harvest and Forecast")
            } else {
                Button(action: retry) {
                    label(iconSize: 9, spacing: 5)
                }
                .buttonStyle(.yieldBordered)
                .font(ThemeStore.shared.theme.usesRefreshedLayout ? YieldFonts.labelButton : YieldFonts.label(10, weight: .medium))
                .padding(.top, 4)
            }
        }
        .disabled(viewModel.isLoading)
    }

    private func retry() {
        Task { await viewModel.refresh() }
    }

    private func label(iconSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: iconSize, weight: .semibold))
            Text("Try again")
        }
    }
}
