import AppKit
import Foundation

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

func renderIcon(size: Int) -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    representation.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high

    let s = CGFloat(size)
    let canvas = NSRect(x: 0, y: 0, width: s, height: s)
    color(0x202329).setFill()
    NSBezierPath(rect: canvas).fill()

    let window = NSRect(x: s * 0.14, y: s * 0.18, width: s * 0.72, height: s * 0.64)
    color(0xF5F6F7).setFill()
    NSBezierPath(roundedRect: window, xRadius: s * 0.055, yRadius: s * 0.055).fill()

    let toolbar = NSRect(x: window.minX, y: window.maxY - s * 0.12, width: window.width, height: s * 0.12)
    color(0xDDE1E5).setFill()
    NSBezierPath(
        roundedRect: toolbar,
        xRadius: s * 0.055,
        yRadius: s * 0.055
    ).fill()
    color(0xDDE1E5).setFill()
    NSBezierPath(rect: NSRect(x: toolbar.minX, y: toolbar.minY, width: toolbar.width, height: toolbar.height * 0.55)).fill()

    let dotY = toolbar.midY
    for (index, value) in [0xF06A5B, 0xE6B94A, 0x4DBD88].enumerated() {
        color(UInt32(value)).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: window.minX + s * (0.055 + CGFloat(index) * 0.065),
            y: dotY - s * 0.018,
            width: s * 0.036,
            height: s * 0.036
        )).fill()
    }

    let tileSize = s * 0.145
    let tileGap = s * 0.045
    let gridX = window.minX + s * 0.09
    let gridY = window.minY + s * 0.09
    let tiles: [(CGFloat, CGFloat, UInt32)] = [
        (gridX, gridY + tileSize + tileGap, 0x4DBD88),
        (gridX + tileSize + tileGap, gridY + tileSize + tileGap, 0x343941),
        (gridX, gridY, 0x343941),
        (gridX + tileSize + tileGap, gridY, 0xF06A5B),
    ]
    for (x, y, value) in tiles {
        color(value).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: tileSize, height: tileSize), xRadius: s * 0.022, yRadius: s * 0.022).fill()
    }

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: s * 0.60, y: s * 0.54))
    cursor.line(to: NSPoint(x: s * 0.80, y: s * 0.38))
    cursor.line(to: NSPoint(x: s * 0.70, y: s * 0.36))
    cursor.line(to: NSPoint(x: s * 0.76, y: s * 0.24))
    cursor.line(to: NSPoint(x: s * 0.69, y: s * 0.205))
    cursor.line(to: NSPoint(x: s * 0.63, y: s * 0.33))
    cursor.line(to: NSPoint(x: s * 0.55, y: s * 0.26))
    cursor.close()
    color(0xFFFFFF).setFill()
    cursor.fill()
    color(0x202329).setStroke()
    cursor.lineWidth = max(1, s * 0.012)
    cursor.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return representation.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: generate-app-icon.swift <AppIcon.icns> [preview.png]\n".data(using: .utf8)!)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset", isDirectory: true)
let manager = FileManager.default
try? manager.removeItem(at: iconset)
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, size) in variants {
    try renderIcon(size: size).write(to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
try? manager.removeItem(at: iconset)

if CommandLine.arguments.count >= 3 {
    let preview = URL(fileURLWithPath: CommandLine.arguments[2])
    try manager.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
    try renderIcon(size: 512).write(to: preview)
}
