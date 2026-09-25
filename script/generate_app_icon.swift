import AppKit
import Foundation

// Minimal icon: a blue macOS rounded square, one white arrow ferrying across one wave.

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("dist/DiskFerry.iconset", isDirectory: true)
let output = root.appendingPathComponent("dist/DiskFerry.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let unit = size / 1024
    // Apple's macOS grid: 824pt body centred in 1024, corner radius ≈ 185.
    let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit)

    if size >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 18 * unit
        shadow.shadowOffset = NSSize(width: 0, height: -8 * unit)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.56, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.30, blue: 0.82, alpha: 1)
    ])?.draw(in: shape, angle: -90)

    // Small sizes get thicker strokes so the glyph stays legible.
    let weight: CGFloat = size <= 32 ? 1.35 : 1
    NSColor.white.setStroke()

    // Arrow: shaft plus open chevron head, rounded ends.
    let arrowY = 560 * unit
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 290 * unit, y: arrowY))
    arrow.line(to: NSPoint(x: 720 * unit, y: arrowY))
    arrow.move(to: NSPoint(x: 580 * unit, y: arrowY + 140 * unit))
    arrow.line(to: NSPoint(x: 724 * unit, y: arrowY))
    arrow.line(to: NSPoint(x: 580 * unit, y: arrowY - 140 * unit))
    arrow.lineWidth = 84 * unit * weight
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()

    // One gentle wave underneath.
    if size >= 32 {
        let waveY = 330 * unit
        let amplitude = 34 * unit
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 290 * unit, y: waveY))
        let segments = 3
        let span = (734 - 290) * unit / CGFloat(segments)
        for index in 0..<segments {
            let startX = 290 * unit + CGFloat(index) * span
            wave.curve(
                to: NSPoint(x: startX + span, y: waveY),
                controlPoint1: NSPoint(x: startX + span * 0.35, y: waveY + amplitude * (index.isMultiple(of: 2) ? 1 : -1)),
                controlPoint2: NSPoint(x: startX + span * 0.65, y: waveY + amplitude * (index.isMultiple(of: 2) ? 1 : -1))
            )
        }
        wave.lineWidth = 44 * unit * weight
        wave.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.55).setStroke()
        wave.stroke()
    }

    return rep
}

for (name, size) in sizes {
    let rep = drawIcon(size: size)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
