#!/usr/bin/env swift
// Draws the app icon at every macOS size into App/Assets.xcassets/AppIcon.appiconset.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

for px in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.18, yRadius: s * 0.18)
    NSColor.white.setFill(); tile.fill()
    NSColor.black.setStroke(); tile.lineWidth = max(1, s * 0.02); tile.stroke()
    let mark = s * 0.28
    NSColor.black.setFill()
    NSRect(x: (s - mark) / 2, y: (s - mark) / 2, width: mark, height: mark).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(px).png"))
}
print("wrote \(sizes.count) sizes to \(dir.path)")
