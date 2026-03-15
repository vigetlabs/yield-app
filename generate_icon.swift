#!/usr/bin/env swift

import Cocoa

func generateIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let s = CGFloat(size)
    let ctx = NSGraphicsContext.current!.cgContext

    // --- Background: rounded rect with warm golden gradient ---
    let cornerRadius = s * 0.22
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    // Golden gradient background
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        NSColor(red: 0.96, green: 0.76, blue: 0.28, alpha: 1.0).cgColor,  // warm gold top
        NSColor(red: 0.85, green: 0.55, blue: 0.15, alpha: 1.0).cgColor,  // deeper amber bottom
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])

    // --- Wheat stalk ---
    let stalkColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)
    stalkColor.setStroke()
    stalkColor.setFill()

    // Main stem - gentle curve from bottom center to top
    let stem = NSBezierPath()
    let stemWidth = s * 0.025
    stem.lineWidth = stemWidth
    stem.lineCapStyle = .round

    let bottomX = s * 0.48
    let bottomY = s * 0.12
    let topX = s * 0.50
    let topY = s * 0.88

    stem.move(to: NSPoint(x: bottomX, y: bottomY))
    stem.curve(to: NSPoint(x: topX, y: topY),
               controlPoint1: NSPoint(x: s * 0.45, y: s * 0.4),
               controlPoint2: NSPoint(x: s * 0.52, y: s * 0.65))
    stem.stroke()

    // --- Wheat grains (leaves/kernels alternating left and right) ---
    func drawGrain(baseX: CGFloat, baseY: CGFloat, angle: CGFloat, grainLength: CGFloat) {
        let grain = NSBezierPath()
        grain.lineWidth = stemWidth * 0.6

        // Elongated teardrop/leaf shape
        let tipX = baseX + cos(angle) * grainLength
        let tipY = baseY + sin(angle) * grainLength

        let width = grainLength * 0.3
        let perpAngle = angle + .pi / 2

        let ctrl1X = baseX + cos(angle) * grainLength * 0.5 + cos(perpAngle) * width
        let ctrl1Y = baseY + sin(angle) * grainLength * 0.5 + sin(perpAngle) * width
        let ctrl2X = baseX + cos(angle) * grainLength * 0.5 - cos(perpAngle) * width
        let ctrl2Y = baseY + sin(angle) * grainLength * 0.5 - sin(perpAngle) * width

        grain.move(to: NSPoint(x: baseX, y: baseY))
        grain.curve(to: NSPoint(x: tipX, y: tipY),
                    controlPoint1: NSPoint(x: ctrl1X, y: ctrl1Y),
                    controlPoint2: NSPoint(x: tipX + cos(perpAngle) * width * 0.3,
                                           y: tipY + sin(perpAngle) * width * 0.3))
        grain.curve(to: NSPoint(x: baseX, y: baseY),
                    controlPoint1: NSPoint(x: tipX - cos(perpAngle) * width * 0.3,
                                           y: tipY - sin(perpAngle) * width * 0.3),
                    controlPoint2: NSPoint(x: ctrl2X, y: ctrl2Y))

        stalkColor.setFill()
        grain.fill()
    }

    // Position grains along the stem
    let grainSize = s * 0.10
    let grainPairs: [(t: CGFloat, leftAngle: CGFloat, rightAngle: CGFloat)] = [
        (0.78, .pi * 0.65, .pi * 0.35),   // top pair
        (0.70, .pi * 0.70, .pi * 0.30),
        (0.62, .pi * 0.72, .pi * 0.28),
        (0.54, .pi * 0.75, .pi * 0.25),
        (0.46, .pi * 0.78, .pi * 0.22),
        (0.38, .pi * 0.80, .pi * 0.20),   // bottom pair
    ]

    for pair in grainPairs {
        // Interpolate position along the stem curve
        let t = pair.t
        // Approximate cubic bezier position
        let mt = 1.0 - t
        let px = mt*mt*mt * bottomX + 3*mt*mt*t * (s*0.45) + 3*mt*t*t * (s*0.52) + t*t*t * topX
        let py = mt*mt*mt * bottomY + 3*mt*mt*t * (s*0.4) + 3*mt*t*t * (s*0.65) + t*t*t * topY

        // Scale grain size — smaller at top
        let scale = 0.7 + (1.0 - t) * 0.5
        drawGrain(baseX: px, baseY: py, angle: pair.leftAngle, grainLength: grainSize * scale)
        drawGrain(baseX: px, baseY: py, angle: pair.rightAngle, grainLength: grainSize * scale)
    }

    // Top grain (single, pointing up)
    let topGrainT: CGFloat = 0.85
    let mt2 = 1.0 - topGrainT
    let topGrainX = mt2*mt2*mt2 * bottomX + 3*mt2*mt2*topGrainT * (s*0.45) + 3*mt2*topGrainT*topGrainT * (s*0.52) + topGrainT*topGrainT*topGrainT * topX
    let topGrainY = mt2*mt2*mt2 * bottomY + 3*mt2*mt2*topGrainT * (s*0.4) + 3*mt2*topGrainT*topGrainT * (s*0.65) + topGrainT*topGrainT*topGrainT * topY
    drawGrain(baseX: topGrainX, baseY: topGrainY, angle: .pi * 0.50, grainLength: grainSize * 0.65)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String, pixelSize: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path) (\(pixelSize)x\(pixelSize))")
}

// Generate all required sizes
let basePath = "/Users/jeremyfields/Sites/wheres-my-time-app/WheresMyTime/Yield/Assets.xcassets/AppIcon.appiconset"

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for size in sizes {
    let icon = generateIcon(size: size.pixels)
    savePNG(icon, to: "\(basePath)/\(size.name).png", pixelSize: size.pixels)
}

print("Done! All icon sizes generated.")
