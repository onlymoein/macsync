// Draws the app icon: two docks, one copy of the other. Usage: swift scripts/make-icon.swift <output.png> <pixel size>
import AppKit

let output = CommandLine.arguments[1]
let size = CGFloat(Int(CommandLine.arguments[2]) ?? 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = size * 0.1
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let u = tile.width / 100

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
func fill(_ path: NSBezierPath, _ color: NSColor) { color.setFill(); path.fill() }

// Background: deep indigo to electric blue.
NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.98, alpha: 1), NSColor(red: 0.07, green: 0.45, blue: 1.0, alpha: 1)])!
    .draw(in: rounded(tile, tile.width * 0.225), angle: -50)

NSGraphicsContext.saveGraphicsState()
rounded(tile, tile.width * 0.225).addClip()
// Soft light from the top.
NSGradient(colors: [NSColor(white: 1, alpha: 0.28), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

func dock(y: CGFloat, alpha: CGFloat) {
    let width = 70 * u, height = 25 * u
    let rect = NSRect(x: tile.minX + 15 * u, y: tile.minY + y * u, width: width, height: height)
    fill(rounded(rect, 8 * u), NSColor(white: 1, alpha: 0.22 * alpha))
    let cell = 15 * u, gap = 3.2 * u
    let total = cell * 4 + gap * 3
    let startX = rect.midX - total / 2
    for i in 0..<4 {
        let r = NSRect(x: startX + CGFloat(i) * (cell + gap), y: rect.midY - cell / 2, width: cell, height: cell)
        fill(rounded(r, 4.2 * u), NSColor(white: 1, alpha: i == 1 ? alpha : 0.9 * alpha))
    }
}
dock(y: 52, alpha: 1)       // the original
dock(y: 23, alpha: 0.55)    // its copy

NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
