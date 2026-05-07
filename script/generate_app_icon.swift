import AppKit
import Foundation

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

for (name, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.22, yRadius: size * 0.22).fill()

    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.70, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.32, alpha: 1)
    ])
    bg?.draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.09, dy: size * 0.09), xRadius: size * 0.18, yRadius: size * 0.18), angle: 90)

    let hullTop = size * 0.55
    let hullBottom = size * 0.70

    let cabin = NSBezierPath()
    cabin.move(to: NSPoint(x: size * 0.34, y: size * 0.72))
    cabin.line(to: NSPoint(x: size * 0.66, y: size * 0.72))
    cabin.line(to: NSPoint(x: size * 0.73, y: size - hullTop))
    cabin.line(to: NSPoint(x: size * 0.27, y: size - hullTop))
    cabin.close()
    NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.96, alpha: 1).setFill()
    cabin.fill()

    for index in 0..<3 {
        let x = size * (0.39 + CGFloat(index) * 0.11)
        let window = NSRect(x: x, y: size * 0.53, width: size * 0.055, height: size * 0.075)
        NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.58, alpha: 1).setFill()
        NSBezierPath(roundedRect: window, xRadius: size * 0.01, yRadius: size * 0.01).fill()
    }

    let hull = NSBezierPath()
    hull.move(to: NSPoint(x: size * 0.16, y: size - hullTop))
    hull.line(to: NSPoint(x: size * 0.84, y: size - hullTop))
    hull.line(to: NSPoint(x: size * 0.71, y: size - hullBottom))
    hull.line(to: NSPoint(x: size * 0.29, y: size - hullBottom))
    hull.close()
    NSColor(calibratedRed: 0.95, green: 0.38, blue: 0.18, alpha: 1).setFill()
    hull.fill()

    NSColor(calibratedRed: 0.78, green: 0.17, blue: 0.11, alpha: 1).setStroke()
    hull.lineWidth = max(1, size * 0.012)
    hull.stroke()

    for offset in [0.0, 0.10] {
        let y = size * (0.19 + CGFloat(offset))
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: size * 0.18, y: y))
        wave.curve(
            to: NSPoint(x: size * 0.46, y: y),
            controlPoint1: NSPoint(x: size * 0.27, y: y + size * 0.055),
            controlPoint2: NSPoint(x: size * 0.37, y: y - size * 0.055)
        )
        wave.curve(
            to: NSPoint(x: size * 0.74, y: y),
            controlPoint1: NSPoint(x: size * 0.55, y: y + size * 0.055),
            controlPoint2: NSPoint(x: size * 0.65, y: y - size * 0.055)
        )
        NSColor(calibratedRed: 0.70, green: 0.93, blue: 1.00, alpha: 1).setStroke()
        wave.lineWidth = max(1.5, size * 0.026)
        wave.stroke()
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DiskFerryIcon", code: 1)
    }
    try data.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    throw NSError(domain: "DiskFerryIcon", code: Int(process.terminationStatus))
}
