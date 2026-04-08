import SwiftUI

// MARK: - Green Filled Button (+ Timer, Start Timer)

struct GreenFilledButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YieldFonts.labelButton)
            .foregroundStyle(YieldColors.background)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(YieldColors.greenAccent)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
            .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : 0.8)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            }
    }
}

// MARK: - Green Outlined Button (Start Timer outline variant)

struct GreenOutlinedButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YieldFonts.labelButton)
            .foregroundStyle(YieldColors.greenAccent)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(isHovered ? YieldColors.greenSubtle : YieldColors.greenFaint)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: YieldRadius.button)
                    .strokeBorder(isHovered ? YieldColors.greenBorderActive : YieldColors.greenBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : 0.8)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            }
    }
}

// MARK: - Bordered Button (Cancel, Log Time, Stop)

struct BorderedButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YieldFonts.labelButton)
            .foregroundStyle(YieldColors.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(isHovered ? YieldColors.surfaceActive : YieldColors.surfaceDefault)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: YieldRadius.button)
                    .strokeBorder(YieldColors.buttonBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : 0.8)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            }
    }
}

// MARK: - Timer Control Button (Play/Pause/Stop icons, 24x24)

struct TimerControlButtonStyle: ButtonStyle {
    var borderColor: Color = YieldColors.buttonBorder
    var foregroundColor: Color = YieldColors.textSecondary
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10))
            .foregroundStyle(foregroundColor)
            .frame(width: YieldDimensions.timerButtonSize, height: YieldDimensions.timerButtonSize)
            .contentShape(Rectangle())
            .background(isHovered ? YieldColors.surfaceActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: YieldRadius.button)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : isHovered ? 1.0 : 0.8)
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

extension ButtonStyle where Self == BorderedButtonStyle {
    static var yieldBordered: BorderedButtonStyle { BorderedButtonStyle() }
}
