import SwiftUI

// MARK: - Material-X button chrome (System theme)

/// The kit's four button styles. Editorial's buttons are drawn by the
/// original code in each style below; these are System's.
enum KitButtonKind {
    /// Filled with the primary colour, raised on a tinted shadow.
    case contained
    /// White with a 1pt grey outline and a primary label.
    case outlined
    /// A flat grey tint with a primary label — the neutral action.
    case shaded
    /// The shaded button in red, for destructive actions.
    case danger
    /// The contained button without its shadow: the action on a
    /// tinted bar, where a shadow would smudge the bar's wash.
    case flat
}

struct KitButtonChrome: ViewModifier {
    let kind: KitButtonKind
    let isPressed: Bool
    let isHovered: Bool

    private var foreground: Color {
        switch kind {
        case .contained, .flat: return YieldColors.onControlFill
        case .outlined, .shaded: return YieldColors.controlAccent
        case .danger: return YieldStatusColors.over
        }
    }

    private var fill: Color {
        switch kind {
        case .contained, .flat: return isHovered ? YieldColors.controlFillHover : YieldColors.controlFill
        case .outlined:  return isHovered ? YieldColors.controlAccent.opacity(0.08) : Color.clear
        case .shaded:    return isHovered ? YieldColors.surfaceActive : YieldColors.surfaceDefault
        case .danger:    return YieldStatusColors.over.opacity(isHovered ? 0.2 : 0.1)
        }
    }

    func body(content: Content) -> some View {
        content
            .font(YieldFonts.labelButton)
            .tracking(YieldDimensions.buttonLabelTracking)
            .foregroundStyle(foreground)
            .padding(.horizontal, YieldDimensions.buttonHorizontalPadding)
            .frame(height: YieldDimensions.buttonHeight)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
            .overlay {
                if kind == .outlined {
                    RoundedRectangle(cornerRadius: YieldRadius.pill)
                        .strokeBorder(YieldColors.buttonBorder, lineWidth: 1)
                }
            }
            .kitShadow(YieldColors.controlFill, dp: kind == .contained ? (isHovered ? 4 : 2) : 0)
            .opacity(isPressed ? 0.7 : 1)
    }
}

extension View {
    /// The kit's two-layer drop shadow at an elevation given in its
    /// "dp": one layer offset by the elevation, one by half of it.
    /// Zero draws nothing.
    func kitShadow(_ color: Color, dp: CGFloat, opacity: Double = 0.2) -> some View {
        self
            .shadow(color: color.opacity(dp > 0 ? opacity : 0), radius: dp, x: 0, y: dp)
            .shadow(color: color.opacity(dp > 0 ? opacity : 0), radius: dp / 2, x: 0, y: dp / 2)
    }
}

// MARK: - Green Filled Button (+ Timer, Start Timer)

struct GreenFilledButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            configuration.label
                .modifier(KitButtonChrome(kind: .contained, isPressed: configuration.isPressed, isHovered: isHovered))
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        } else {
            configuration.label
                .font(YieldFonts.labelButton)
                .foregroundStyle(YieldColors.background)
                .padding(.horizontal, YieldDimensions.buttonHorizontalPadding)
                .padding(.vertical, 4)
                .frame(height: YieldDimensions.buttonHeight)
                .background(YieldColors.controlAccent)
                .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
                .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : YieldDimensions.buttonRestingOpacity)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        }
    }
}

// MARK: - Green Outlined Button (Start Timer outline variant)

struct GreenOutlinedButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            configuration.label
                .modifier(KitButtonChrome(kind: .outlined, isPressed: configuration.isPressed, isHovered: isHovered))
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        } else {
            configuration.label
                .font(YieldFonts.labelButton)
                .foregroundStyle(YieldColors.controlAccent)
                .padding(.horizontal, YieldDimensions.buttonHorizontalPadding)
                .padding(.vertical, 4)
                .frame(height: YieldDimensions.buttonHeight)
                .background(isHovered ? YieldColors.controlAccentSubtle : YieldColors.controlAccentFaint)
                .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
                .overlay(
                    RoundedRectangle(cornerRadius: YieldRadius.pill)
                        .strokeBorder(isHovered ? YieldColors.controlAccentBorderActive : YieldColors.controlAccentBorder, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : YieldDimensions.buttonRestingOpacity)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        }
    }
}

// MARK: - Red Outlined Button (destructive — Delete)

struct RedOutlinedButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            configuration.label
                .modifier(KitButtonChrome(kind: .danger, isPressed: configuration.isPressed, isHovered: isHovered))
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        } else {
            configuration.label
                .font(YieldFonts.labelButton)
                .foregroundStyle(YieldStatusColors.over)
                .padding(.horizontal, YieldDimensions.buttonHorizontalPadding)
                .padding(.vertical, 4)
                .frame(height: YieldDimensions.buttonHeight)
                .background(YieldStatusColors.over.opacity(isHovered ? 0.15 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
                .overlay(
                    RoundedRectangle(cornerRadius: YieldRadius.pill)
                        .strokeBorder(YieldStatusColors.over.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : YieldDimensions.buttonRestingOpacity)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        }
    }
}

// MARK: - Bordered Button (Cancel, Log Time, Stop)

struct BorderedButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            configuration.label
                .modifier(KitButtonChrome(kind: .shaded, isPressed: configuration.isPressed, isHovered: isHovered))
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        } else {
            configuration.label
                .font(YieldFonts.labelButton)
                .foregroundStyle(YieldColors.textPrimary)
                .padding(.horizontal, YieldDimensions.buttonHorizontalPadding)
                .padding(.vertical, 4)
                .frame(height: YieldDimensions.buttonHeight)
                .background(isHovered ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
                .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
                .overlay(
                    RoundedRectangle(cornerRadius: YieldRadius.pill)
                        .strokeBorder(YieldColors.buttonBorder, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : YieldDimensions.buttonRestingOpacity)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                }
        }
    }
}

// MARK: - Timer Control Button (Play/Pause/Stop icons, 24x24)

struct TimerControlButtonStyle: ButtonStyle {
    var borderColor: Color = YieldColors.buttonBorder
    var foregroundColor: Color = YieldColors.textSecondary
    /// When true, the foreground + border swap to `YieldStatusColors.over`
    /// (destructive red) on hover — used for stop buttons so the user
    /// gets a "you're about to terminate" signal mid-hover. Mirrors the
    /// active-hover state in the Figma design.
    var destructiveOnHover: Bool = false
    /// Hit/visual size. Defaults to the shared 24pt; the System banner
    /// passes 28 for its hero controls.
    var size: CGFloat = YieldDimensions.timerButtonSize
    /// Filled circle (a tint of the foreground color, no border) rather
    /// than the bordered square. Follows the theme, so every play /
    /// pause / stop control in the app changes together.
    var filled: Bool = ThemeStore.shared.theme.usesCircularControls
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let resolvedForeground = (destructiveOnHover && isHovered) ? YieldStatusColors.over : foregroundColor
        let resolvedBorder = (destructiveOnHover && isHovered) ? YieldStatusColors.over : borderColor
        if filled {
            return AnyView(configuration.label
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(resolvedForeground)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .background(resolvedForeground.opacity(isHovered ? 0.28 : 0.16))
                .clipShape(Circle())
                .opacity(configuration.isPressed ? 0.6 : 1.0)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
                })
        }
        return AnyView(configuration.label
            .font(.system(size: 10))
            .foregroundStyle(resolvedForeground)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .background(isHovered ? YieldColors.surfaceActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.pill))
            .overlay(
                RoundedRectangle(cornerRadius: YieldRadius.pill)
                    .strokeBorder(resolvedBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : 0.8)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            })
    }
}

// MARK: - Meeting bar button (System)

struct KitFlatFilledButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(KitButtonChrome(kind: .flat, isPressed: configuration.isPressed, isHovered: isHovered))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            }
    }
}

// MARK: - Convenience Extensions

extension ButtonStyle where Self == GreenFilledButtonStyle {
    static var greenFilled: GreenFilledButtonStyle { GreenFilledButtonStyle() }
}

extension ButtonStyle where Self == GreenOutlinedButtonStyle {
    static var greenOutlined: GreenOutlinedButtonStyle { GreenOutlinedButtonStyle() }
}

extension ButtonStyle where Self == RedOutlinedButtonStyle {
    static var redOutlined: RedOutlinedButtonStyle { RedOutlinedButtonStyle() }
}

extension ButtonStyle where Self == BorderedButtonStyle {
    static var yieldBordered: BorderedButtonStyle { BorderedButtonStyle() }
}

extension View {
    /// The timer form's commit — Start Timer, Save, Move Time.
    /// Editorial: the tinted outline. System: the filled button, so
    /// the form has one obvious primary action.
    @ViewBuilder
    func formCommitButtonStyle() -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            buttonStyle(.greenFilled)
        } else {
            buttonStyle(.greenOutlined)
        }
    }

    /// The "− Timer" that closes the timer form. Editorial fills it to
    /// show the form is open. System leaves the fill to the commit
    /// button below and draws this as the outline "+ Timer" was.
    @ViewBuilder
    func formCloseButtonStyle() -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            buttonStyle(.greenOutlined)
        } else {
            buttonStyle(.greenFilled)
        }
    }

    /// The one action on a meeting bar. Editorial: the tinted outline
    /// it has always been. System: the filled button in the meeting
    /// blue, without its shadow, so the prompt has an obvious answer.
    @ViewBuilder
    func meetingBarButtonStyle() -> some View {
        if ThemeStore.shared.theme.usesRefreshedLayout {
            buttonStyle(KitFlatFilledButtonStyle())
        } else {
            buttonStyle(.greenOutlined)
        }
    }
}
