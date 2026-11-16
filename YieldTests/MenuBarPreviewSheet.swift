import AppKit
import XCTest
@testable import Yield

/// Writes a contact sheet of menu bar images — one row per case, one
/// cell per style on a light and a dark bar — for looking at, not
/// asserting on. Opt in with
/// `TEST_RUNNER_YIELD_MENUBAR_PREVIEW_DIR=/some/dir xcodebuild test …`;
/// without it the calling test is skipped.
enum MenuBarPreviewSheet {
    static func write(
        named fileName: String,
        rowNames: [String],
        styles: [MenuBarStyle],
        labelWidth: CGFloat,
        cellWidth: CGFloat,
        image: (_ row: Int, _ style: MenuBarStyle, _ dark: Bool) -> NSImage
    ) throws {
        guard let dir = ProcessInfo.processInfo.environment["YIELD_MENUBAR_PREVIEW_DIR"] else {
            throw XCTSkip("Set YIELD_MENUBAR_PREVIEW_DIR to write the preview sheet")
        }
        let rowHeight: CGFloat = 30, scale: CGFloat = 3
        let size = NSSize(
            width: labelWidth + cellWidth * CGFloat(styles.count * 2),
            height: rowHeight * CGFloat(rowNames.count)
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (r, name) in rowNames.enumerated() {
            let y = size.height - rowHeight * CGFloat(r + 1)
            (name as NSString).draw(
                at: NSPoint(x: 6, y: y + 8),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black]
            )
            for (s, style) in styles.enumerated() {
                for (d, dark) in [false, true].enumerated() {
                    let x = labelWidth + cellWidth * CGFloat(s * 2 + d)
                    let cell = NSRect(x: x + 1, y: y + 1, width: cellWidth - 2, height: rowHeight - 2)
                    (dark ? MenuBarGraphicRenderer.Palette.hex(0x2A2A2E) : MenuBarGraphicRenderer.Palette.hex(0xE7E4DD)).setFill()
                    cell.fill()
                    let cellImage = image(r, style, dark)
                    cellImage.draw(in: NSRect(
                        x: cell.minX + 8, y: cell.midY - cellImage.size.height / 2,
                        width: cellImage.size.width, height: cellImage.size.height
                    ))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: dir).appendingPathComponent(fileName)
        try png.write(to: url)
        print("Wrote menu bar preview sheet to \(url.path)")
    }
}
