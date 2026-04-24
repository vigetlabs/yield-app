import SwiftUI

/// Leading-edge icon that surfaces a project's Forecast assignment notes
/// for the current week. Hover reveals the full concatenated text via
/// the native `.help()` tooltip. Used at the start of both
/// `ProjectRowView` and `LookAheadRowView`.
struct ForecastNotesIcon: View {
    let notes: String

    var body: some View {
        Image(systemName: "text.page")
            .font(.system(size: 14))
            .foregroundStyle(YieldColors.textSecondary)
            .help(notes)
    }
}
