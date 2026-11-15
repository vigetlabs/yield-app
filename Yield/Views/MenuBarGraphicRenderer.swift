import AppKit

/// Draws the ring, capsule and week-bars menu bar styles.
///
/// Unlike the classic style these are *not* template images — they
/// carry color — so every pixel's color is chosen here, from an
/// explicit `isDark` (see `MenuBarAppearance`). Being a pure function
/// of its arguments also means the output can be rendered off screen
/// and inspected, which is how the preview sheet in the tests is made.
enum MenuBarGraphicRenderer {
    static let barHeight: CGFloat = 18
    /// The capsule is taller than the other styles' canvas: it is a
    /// filled shape, and at 18pt it sat small in a 24pt menu bar. 21pt
    /// fills more of the bar while staying inside the 22pt status
    /// items are given.
    static let capsuleHeight: CGFloat = 21
    private static let spacing: CGFloat = 4
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    /// Colors tuned for the menu bar rather than borrowed from the
    /// app's theme: theme colors resolve against the app's appearance,
    /// while these have to hold contrast on a translucent bar that is
    /// light or dark independently of it.
    struct Palette {
        /// Ordinary menu bar ink — what the clock is drawn in.
        let ink: NSColor
        /// The opposite of `ink`, for text on an ink-filled capsule.
        let inverse: NSColor
        /// Secondary ink: paused and stale content.
        let mid: NSColor
        /// Faint ink: tracks and empty bars.
        let dim: NSColor
        let onPace: NSColor
        let nearLimit: NSColor
        let over: NSColor
        let meeting: NSColor

        init(isDark: Bool) {
            let base: NSColor = isDark ? .white : .black
            ink = base.withAlphaComponent(isDark ? 0.95 : 0.85)
            inverse = isDark ? NSColor.black.withAlphaComponent(0.85) : .white
            mid = base.withAlphaComponent(0.58)
            dim = base.withAlphaComponent(0.26)
            onPace = Palette.hex(isDark ? 0x5BD68A : 0x12804A)
            nearLimit = Palette.hex(isDark ? 0xF5B544 : 0xA86200)
            over = Palette.hex(isDark ? 0xFF6F66 : 0xC8322B)
            meeting = Palette.hex(isDark ? 0x6CB2FF : 0x1C68C4)
        }

        /// Line/glyph color for a tone. Neutral is plain ink: color
        /// only ever appears for a running, booked timer.
        func color(for tone: MenuBarGraphicState.Tone) -> NSColor {
            switch tone {
            case .neutral:   return ink
            case .onPace:    return onPace
            case .nearLimit: return nearLimit
            case .over:      return over
            }
        }

        /// Capsule fills carry their own background, so one set works
        /// on light and dark bars alike.
        static let pillOnPace = hex(0x1F9D57)
        static let pillNearLimit = hex(0xF0B030)
        static let pillNearLimitText = hex(0x3D2800)
        static let pillOver = hex(0xD8423B)
        static let pillMeeting = hex(0x2F7DE1)

        static func hex(_ value: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    /// Render one of the non-classic styles. `style == .classic` is the
    /// caller's job (it's a template image with its own renderer);
    /// asking for it here draws the ring.
    static func render(
        style: MenuBarStyle,
        label: String,
        state: MenuBarGraphicState,
        labelMode: MenuBarLabelMode,
        isDark: Bool
    ) -> NSImage {
        let palette = Palette(isDark: isDark)
        let measure: [NSAttributedString.Key: Any] = [.font: font]
        // Reserve the widest realistic label so the item doesn't change
        // width as the numbers tick; grow rather than clip when the
        // real label is wider still.
        let reserved = (labelMode.widestLabel as NSString).size(withAttributes: measure).width
        let textSize: CGSize = label.isEmpty ? .zero : (label as NSString).size(withAttributes: measure)
        let textSlot = max(reserved, textSize.width)

        let image: NSImage
        switch style {
        case .capsule:
            let width = label.isEmpty ? capsuleEmptyWidth : ceil(textSlot + capsulePadding * 2)
            image = NSImage(size: NSSize(width: width, height: capsuleHeight), flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                drawCapsule(ctx, width: width, label: label, textSize: textSize, state: state, palette: palette)
                return true
            }
        case .weekBars, .ring, .classic:
            let graphicWidth = style == .weekBars ? weekBarsWidth : ringWidth
            let width = ceil(graphicWidth + (label.isEmpty ? 0 : spacing + textSlot))
            image = NSImage(size: NSSize(width: width, height: barHeight), flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                if style == .weekBars {
                    drawWeekBars(ctx, state: state, palette: palette)
                } else {
                    drawRing(ctx, state: state, palette: palette)
                }
                if !label.isEmpty {
                    let dimmed = state.isStale || state.timer == .paused
                    drawText(
                        label,
                        at: CGPoint(x: graphicWidth + spacing, y: (barHeight - textSize.height) / 2),
                        color: dimmed ? palette.mid : palette.ink
                    )
                }
                return true
            }
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Ring

    private static let ringWidth: CGFloat = 18

    private static func drawRing(_ ctx: CGContext, state: MenuBarGraphicState, palette: Palette) {
        let center = CGPoint(x: ringWidth / 2, y: barHeight / 2)
        let radius: CGFloat = 6.5

        if state.isStale {
            strokeCircle(ctx, center: center, radius: radius, color: palette.dim, width: 2, dashed: true)
            drawTimerGlyph(ctx, center: center, timer: state.timer, color: palette.mid)
        } else if state.timer == .running, state.tone == .over {
            // Over is a different shape, not just a different color: a
            // solid disc with an exclamation mark.
            ctx.setFillColor(palette.over.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.addPath(CGPath(
                roundedRect: CGRect(x: center.x - 1, y: center.y - 1.6, width: 2, height: 6.2),
                cornerWidth: 1, cornerHeight: 1, transform: nil
            ))
            ctx.fillPath()
            ctx.fillEllipse(in: CGRect(x: center.x - 1.2, y: center.y - 5.2, width: 2.4, height: 2.4))
        } else {
            if let progress = state.progress {
                strokeCircle(ctx, center: center, radius: radius, color: palette.dim, width: 2.5, dashed: false)
                let arcColor: NSColor
                switch state.timer {
                case .running: arcColor = palette.color(for: state.tone)
                case .paused:  arcColor = palette.mid
                case .none:    arcColor = palette.ink
                }
                strokeArc(ctx, center: center, radius: radius, progress: progress, color: arcColor, width: 2.5)
            } else {
                // Nothing to measure against (unbooked timer, or no
                // data yet): a dashed ring instead of an empty track.
                strokeCircle(ctx, center: center, radius: radius, color: palette.mid, width: 2, dashed: true)
            }
            let glyphColor = state.timer == .running ? palette.color(for: state.tone) : palette.ink
            drawTimerGlyph(ctx, center: center, timer: state.timer, color: glyphColor)
        }

        if state.meetingDue {
            drawBadge(ctx, center: CGPoint(x: ringWidth - 2.5, y: barHeight - 3), color: palette.meeting)
        }
    }

    /// Play triangle while running, pause bars while paused, nothing
    /// otherwise.
    private static func drawTimerGlyph(
        _ ctx: CGContext,
        center: CGPoint,
        timer: MenuBarGraphicState.TimerState,
        color: NSColor
    ) {
        ctx.setFillColor(color.cgColor)
        switch timer {
        case .running:
            ctx.move(to: CGPoint(x: center.x - 1.6, y: center.y + 2.8))
            ctx.addLine(to: CGPoint(x: center.x + 3, y: center.y))
            ctx.addLine(to: CGPoint(x: center.x - 1.6, y: center.y - 2.8))
            ctx.closePath()
            ctx.fillPath()
        case .paused:
            ctx.fill(CGRect(x: center.x - 2.2, y: center.y - 2.5, width: 1.7, height: 5))
            ctx.fill(CGRect(x: center.x + 0.5, y: center.y - 2.5, width: 1.7, height: 5))
        case .none:
            break
        }
    }

    // MARK: - Capsule

    private static let capsulePadding: CGFloat = 10
    private static let capsuleEmptyWidth: CGFloat = 32
    /// Stroke of the battery outline around the unused share.
    private static let capsuleOutline: CGFloat = 1.5
    /// The least fill a started booking shows.
    private static let capsuleMinFill: CGFloat = 4

    private static func drawCapsule(
        _ ctx: CGContext,
        width: CGFloat,
        label: String,
        textSize: CGSize,
        state: MenuBarGraphicState,
        palette: Palette
    ) {
        let rect = CGRect(x: 0, y: 0, width: width, height: capsuleHeight)
        let shape = CGPath(roundedRect: rect, cornerWidth: capsuleHeight / 2, cornerHeight: capsuleHeight / 2, transform: nil)

        var fill: NSColor?
        var textColor = palette.ink
        var outlineDashed = false
        var showsProgress = false
        var badge = state.meetingDue

        if state.isStale {
            outlineDashed = true
            textColor = palette.mid
        } else if state.timer == .running {
            switch state.tone {
            case .neutral:
                fill = palette.ink
                textColor = palette.inverse
            case .onPace:
                fill = Palette.pillOnPace
                textColor = .white
                showsProgress = true
            case .nearLimit:
                fill = Palette.pillNearLimit
                textColor = Palette.pillNearLimitText
                showsProgress = true
            case .over:
                fill = Palette.pillOver
                textColor = .white
            }
        } else if state.meetingDue {
            // Nothing running and a meeting waiting: the whole capsule
            // becomes the cue, so no separate badge.
            fill = Palette.pillMeeting
            textColor = .white
            badge = false
        } else if state.timer == .paused {
            outlineDashed = true
        }

        // Where the used share of the booking ends, for the two toned
        // running states. Nil everywhere else.
        var split: CGFloat?

        if let fill, showsProgress, let progress = state.progress {
            // A battery: the used share of the booking is solid from
            // the leading edge and the rest is an empty outline, so
            // the two parts differ by filled-versus-not rather than by
            // two shades of one color. A sliver stays visible however
            // little is used, so the capsule never reads as unbooked.
            let used = progress > 0 ? max(width * CGFloat(min(progress, 1)), capsuleMinFill) : 0
            split = used
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.setFillColor(fill.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: used, height: capsuleHeight))
            ctx.restoreGState()

            let inset = rect.insetBy(dx: capsuleOutline / 2, dy: capsuleOutline / 2)
            ctx.addPath(CGPath(
                roundedRect: inset,
                cornerWidth: inset.height / 2, cornerHeight: inset.height / 2, transform: nil
            ))
            ctx.setStrokeColor(fill.cgColor)
            ctx.setLineWidth(capsuleOutline)
            ctx.strokePath()
        } else if let fill {
            ctx.addPath(shape)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        } else {
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            ctx.saveGState()
            ctx.addPath(CGPath(
                roundedRect: inset,
                cornerWidth: inset.height / 2, cornerHeight: inset.height / 2, transform: nil
            ))
            ctx.setStrokeColor(palette.mid.cgColor)
            ctx.setLineWidth(1)
            if outlineDashed { ctx.setLineDash(phase: 0, lengths: [3, 2.5]) }
            ctx.strokePath()
            ctx.restoreGState()
        }

        if !label.isEmpty {
            let origin = CGPoint(x: (width - textSize.width) / 2, y: (capsuleHeight - textSize.height) / 2)
            if let split {
                // The label crosses the boundary, so it is drawn twice,
                // each pass clipped to its side: the fill's own text
                // color over the solid part, bar ink over the empty one.
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 0, width: split, height: capsuleHeight))
                drawText(label, at: origin, color: textColor)
                ctx.restoreGState()
                ctx.saveGState()
                ctx.clip(to: CGRect(x: split, y: 0, width: width - split, height: capsuleHeight))
                drawText(label, at: origin, color: palette.ink)
                ctx.restoreGState()
            } else {
                drawText(label, at: origin, color: textColor)
            }
        }

        if badge {
            drawBadge(ctx, center: CGPoint(x: width - 3.5, y: capsuleHeight - 3.5), color: palette.meeting)
        }
    }

    // MARK: - Week bars

    private static let weekBarWidth: CGFloat = 4
    private static let weekBarGap: CGFloat = 1.5
    private static let weekBarHeight: CGFloat = 14
    /// Five bars and their gaps, plus a little room for the meeting
    /// badge to sit clear of Friday.
    private static let weekBarsWidth: CGFloat = 5 * weekBarWidth + 4 * weekBarGap + 2

    private static func drawWeekBars(_ ctx: CGContext, state: MenuBarGraphicState, palette: Palette) {
        let bottom = (barHeight - weekBarHeight) / 2
        for index in 0..<5 {
            let x = CGFloat(index) * (weekBarWidth + weekBarGap)
            fillRounded(ctx, CGRect(x: x, y: bottom, width: weekBarWidth, height: weekBarHeight), color: palette.dim)

            let fraction = index < state.weekFractions.count ? state.weekFractions[index] : 0
            guard fraction > 0 else { continue }

            let color: NSColor
            if state.isStale {
                color = palette.mid
            } else if index == state.todayIndex {
                switch state.timer {
                case .running:
                    // These bars don't show the project's booking, so
                    // color here is the only "the clock is running"
                    // cue — an unbooked timer still earns the on-pace
                    // color rather than disappearing into plain ink.
                    color = state.tone == .neutral ? palette.onPace : palette.color(for: state.tone)
                case .paused:
                    color = palette.mid
                case .none:
                    color = palette.ink
                }
            } else {
                color = palette.ink
            }
            let height = max(1.5, weekBarHeight * CGFloat(fraction))
            fillRounded(ctx, CGRect(x: x, y: bottom, width: weekBarWidth, height: height), color: color)
        }

        if state.meetingDue {
            drawBadge(ctx, center: CGPoint(x: weekBarsWidth - 2.5, y: barHeight - 3), color: palette.meeting)
        }
    }

    // MARK: - Primitives

    private static func drawText(_ text: String, at point: CGPoint, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func fillRounded(_ ctx: CGContext, _ rect: CGRect, color: NSColor) {
        let radius = min(1, rect.height / 2)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    private static func strokeCircle(
        _ ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        width: CGFloat,
        dashed: Bool
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        if dashed { ctx.setLineDash(phase: 0, lengths: [2.4, 2.2]) }
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    /// Clockwise from 12 o'clock.
    private static func strokeArc(
        _ ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        progress: Double,
        color: NSColor,
        width: CGFloat
    ) {
        guard progress > 0 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        if progress >= 1 {
            ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        } else {
            let start = CGFloat.pi / 2
            ctx.addArc(
                center: center,
                radius: radius,
                startAngle: start,
                endAngle: start - 2 * .pi * CGFloat(progress),
                clockwise: true
            )
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// The "meeting waiting" dot. Punches a clear halo first so it
    /// reads as sitting on top of whatever is beneath it.
    private static func drawBadge(_ ctx: CGContext, center: CGPoint, color: NSColor) {
        let radius: CGFloat = 2.5
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: center.x - radius - 1.2, y: center.y - radius - 1.2,
            width: (radius + 1.2) * 2, height: (radius + 1.2) * 2
        ))
        ctx.restoreGState()
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
