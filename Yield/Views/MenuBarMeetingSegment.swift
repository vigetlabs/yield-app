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
    private static let glyphGap: CGFloat = 4
    private static let font = MenuBarGraphicRenderer.font

    /// A template base (the classic style) stays a template: the
    /// countdown is drawn in black, macOS colors it, and the tones
    /// then differ only by the glyph's shape.
    ///
    /// - Parameter isDark: which ink the bar needs. Ignored for a
    ///   template.
    static func append(
        _ status: MenuBarMeetingStatus,
        to base: NSImage,
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

        let symbolName = status.tone == .overrun ? "calendar.badge.exclamationmark" : "calendar"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
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
