import SwiftUI

/// The pieces every Settings card is built from, in one place so the
/// two themes fork once rather than in each card.
///
/// Editorial: each section is a bordered, tinted card with rows at
/// 12pt margins — unchanged from how Settings shipped. System: no
/// cards. Each section is a band, like a client's in the project list,
/// and its rows sit on the panel's own background at the list's
/// margins (19pt in, 16pt in) with inset rules between them and
/// larger type.
enum SettingsStyle {
    static var refreshed: Bool { ThemeStore.shared.theme.usesRefreshedLayout }

    /// Left and right margins of a row's content.
    static var leading: CGFloat { refreshed ? 16 + 3 : 12 }
    static var trailing: CGFloat { refreshed ? 16 : 12 }

    /// Sign Out, Disconnect.
    static var destructive: Color { YieldStatusColors.errorText(editorialOpacity: 0.8) }
}

/// The rule between two rows of a section.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(YieldColors.border)
            .frame(height: 1)
            .padding(.leading, SettingsStyle.refreshed ? SettingsStyle.leading : 0)
            .padding(.trailing, SettingsStyle.refreshed ? SettingsStyle.trailing : 0)
    }
}

extension View {
    /// A section's container: Editorial's card, or nothing in System.
    @ViewBuilder
    func settingsCard() -> some View {
        if SettingsStyle.refreshed {
            self
        } else {
            yieldCard()
        }
    }

    /// Padding for a single-line row. `vertical` is Editorial's value;
    /// System adds a little, for its larger type.
    func settingsRowPadding(vertical: CGFloat = 8) -> some View {
        self
            .padding(.leading, SettingsStyle.leading)
            .padding(.trailing, SettingsStyle.trailing)
            .padding(.vertical, SettingsStyle.refreshed ? vertical + 3 : vertical)
    }

    /// Padding for a taller block: an identity row, a confirmation,
    /// a sign-in prompt.
    func settingsBlockPadding() -> some View {
        self
            .padding(.leading, SettingsStyle.leading)
            .padding(.trailing, SettingsStyle.trailing)
            .padding(.vertical, 12)
    }

    /// The glyph that leads a row, in secondary ink in a fixed slot so
    /// labels line up.
    @ViewBuilder
    func settingsRowIcon(size: CGFloat = 10) -> some View {
        if SettingsStyle.refreshed {
            self
                .font(.system(size: 13))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 20)
        } else {
            self
                .font(.system(size: size))
                .foregroundStyle(YieldColors.textSecondary)
                .frame(width: 16)
        }
    }

    /// A row's leading glyph that takes its color from the row (the
    /// destructive rows).
    @ViewBuilder
    func settingsInlineIcon() -> some View {
        if SettingsStyle.refreshed {
            self
                .font(.system(size: 13))
                .frame(width: 20)
        } else {
            self.font(.system(size: 10))
        }
    }

    /// A row's on/off switch. System's is a size up and takes the
    /// theme's control color rather than the macOS accent.
    @ViewBuilder
    func settingsSwitch() -> some View {
        if SettingsStyle.refreshed {
            self
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(YieldColors.controlFill)
                .labelsHidden()
        } else {
            self
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}
