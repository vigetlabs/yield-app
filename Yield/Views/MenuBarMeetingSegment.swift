import AppKit

/// Draws the meeting countdown onto the end of the menu bar image: a
/// calendar glyph and a line of text, after whatever the chosen style
/// drew. Appended to the finished image rather than woven into each
/// style's renderer, so the styles themselves are untouched and a
/// countdown that is off costs nothing.
enum MenuBarMeetingSegment {
    /// Space between the timer graphic and the countdown — wider than
    /// the gaps inside either, so they read as two things.
    private static let leadingGap: CGFloat = 9
    private static let glyphGap: CGFloat = 5
    private static let glyphPointSize: CGFloat = 15
    private static let font = MenuBarGraphicRenderer.font

    /// A template base (the classic style) stays a template: the
    /// countdown is drawn in black, macOS colors it, and the tones
    /// then differ only by the glyph's shape.
    ///
    /// - Parameters:
    ///   - day: today's day of the month, shown in the calendar glyph.
    ///   - isDark: which ink the bar needs. Ignored for a template.
    static func append(
        _ status: MenuBarMeetingStatus,
        to base: NSImage,
        day: Int,
        isDark: Bool
    ) -> NSImage {
        let template = base.isTemplate
        // The words are always in the bar's ordinary ink: tinted text
        // on a translucent menu bar is hard to read. The tone colours
        // the glyph only.
        let textColor: NSColor
        let glyphColor: NSColor
        if template {
            textColor = .black
            glyphColor = .black
        } else {
            let palette = MenuBarGraphicRenderer.Palette(isDark: isDark)
            textColor = palette.ink
            switch status.tone {
            case .plain:    glyphColor = palette.ink
            case .imminent: glyphColor = palette.meeting
            case .overrun:  glyphColor = palette.nearLimit
            }
        }

        // A calendar page showing today's date — the numbered symbols
        // run 1 to 31 — or the plain calendar where one isn't
        // available. An overrun keeps its exclamation badge: on a
        // template image the shape is all that sets it apart.
        // Drawn larger than the text beside it: at the text's own 12pt
        // the date inside the page is too small to read. 15pt puts the
        // page at about 16pt tall, the most the 18pt canvas of the
        // ring and classic styles allows.
        let config = NSImage.SymbolConfiguration(pointSize: Self.glyphPointSize, weight: .regular)
        let symbol = status.tone == .overrun
            ? NSImage(systemSymbolName: "calendar.badge.exclamationmark", accessibilityDescription: nil)
            : NSImage(systemSymbolName: "\(day).calendar", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        let glyph = symbol?.withSymbolConfiguration(config)
        let glyphSize = glyph?.size ?? .zero

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (status.text as NSString).size(withAttributes: attrs)

        let baseSize = base.size
        let height = baseSize.height
        let width = ceil(baseSize.width + leadingGap + glyphSize.width + glyphGap + textSize.width)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: baseSize))
            var x = baseSize.width + leadingGap

            if let glyph {
                let rect = NSRect(
                    x: x, y: (height - glyphSize.height) / 2,
                    width: glyphSize.width, height: glyphSize.height
                )
                glyph.tinted(with: glyphColor).draw(in: rect)
                x += glyphSize.width + glyphGap
            }

            (status.text as NSString).draw(
                at: NSPoint(x: x, y: (height - textSize.height) / 2),
                withAttributes: attrs
            )
            return true
        }
        image.isTemplate = template
        return image
    }
}
