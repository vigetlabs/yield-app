import SwiftUI

/// Muted meeting titles ("Don't prompt for meetings like this" on the
/// meeting prompt bar), surfaced as a removable list so a permanent
/// mute is always undoable. Mirrors `FavoritesCard`'s shape. Hidden
/// entirely when Google Calendar isn't connected — without it there
/// are no prompts, so managing their mutes is an irrelevant control.
struct MutedMeetingsCard: View {
    /// Read directly so a mute/unmute elsewhere only invalidates
    /// this card.
    private let store: MutedMeetingsStore = MutedMeetingsStore.shared
    private let googleAuth: GoogleAuthService = AppState.shared.googleAuthService

    var body: some View {
        if googleAuth.isAuthenticated {
            let muted = store.sortedMuted
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardSectionHeader(
                    "Muted Meetings",
                    info: "Meetings you've told Yield not to prompt timers for. Remove one to start getting prompts for it again."
                )

                if muted.isEmpty {
                    Text("No muted meetings. Mute one from a meeting prompt's \u{201C}Don't prompt for meetings like this.\u{201D}")
                        .font(YieldFonts.settingsLabel())
                        .foregroundStyle(YieldColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRowPadding(vertical: 10)
                } else {
                    // Same scroll treatment as the favorites list: size
                    // to content when short, cap with scrolling when the
                    // list grows.
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(muted.enumerated()), id: \.element.key) { index, entry in
                                mutedRow(entry)
                                if index < muted.count - 1 {
                                    SettingsRowDivider()
                                }
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsCard()
        }
    }

    private func mutedRow(_ entry: (key: String, title: String)) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "bell.slash")
                .settingsRowIcon()

            Text(entry.title)
                .font(YieldFonts.settingsLabel(weight: .medium))
                .foregroundStyle(YieldColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                store.unmute(normalizedTitle: entry.key)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(YieldColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Prompt for this meeting again")
        }
        .settingsRowPadding()
    }
}
