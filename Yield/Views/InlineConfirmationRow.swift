import SwiftUI

/// Single-row inline confirmation prompt: a short message on the
/// left, Cancel + a destructive action button trailing.
///
/// Used in place of `.confirmationDialog` everywhere inside the
/// MenuBarExtra panel — system dialogs presented from the panel
/// make it resign key, which auto-dismisses the panel and cancels
/// the dialog before the action fires. Inline keeps everything
/// within the panel so the action lands.
struct InlineConfirmationRow: View {
    /// Short prompt shown to the left of the buttons (e.g.
    /// "Are you sure?" or "Delete this entry?"). Single line.
    let message: String
    /// Label for the destructive confirm button (e.g. "Sign Out",
    /// "Disconnect", "Delete").
    let confirmLabel: String
    /// SF Symbol name to show alongside `confirmLabel`. Optional —
    /// pass nil for buttons that read fine as plain text.
    var confirmSystemImage: String? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(YieldFonts.dmSans(11))
                .foregroundStyle(YieldColors.textSecondary)

            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.yieldBordered)

            Button(action: onConfirm) {
                if let confirmSystemImage {
                    Label(confirmLabel, systemImage: confirmSystemImage)
                } else {
                    Text(confirmLabel)
                }
            }
            .buttonStyle(.redOutlined)
        }
    }
}
