// Draws the app icon: white sync arrows on a blue tile, the same mark as the menu's corner.
// Usage: swift scripts/make-icon.swift <output.png> <pixel size>
import AppKit

let output = CommandLine.arguments[1]
let size = CGFloat(Int(CommandLine.arguments[2]) ?? 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's grid: the tile is 824 of 1024, with room around it for the shadow.
let inset = size * 0.1
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner = tile.width * 0.225
let shape = NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner)
func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// A soft shadow under the tile.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = size * 0.03
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.set()
color(10, 110, 245).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// The blue, a little lighter at the top, like the system's accent gradient.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [color(82, 168, 255), color(18, 122, 250), color(6, 96, 232)], atLocations: [0, 0.55, 1],
           colorSpace: .deviceRGB)!.draw(in: tile, angle: -90)
// A faint shine along the top edge.
NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// The arrows: the SF Symbol the menu uses, in white.
let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.46, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    let rect = NSRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2, width: s.width, height: s.height)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowBlurRadius = size * 0.02
    glow.shadowOffset = NSSize(width: 0, height: -size * 0.006)
    glow.shadowColor = NSColor(red: 0, green: 0.2, blue: 0.6, alpha: 0.35)
    glow.set()
    symbol.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

// A hairline edge so the tile holds its shape on light backgrounds.
NSColor(white: 1, alpha: 0.18).setStroke()
let edge = NSBezierPath(roundedRect: tile.insetBy(dx: size * 0.002, dy: size * 0.002), xRadius: corner, yRadius: corner)
edge.lineWidth = size * 0.004
edge.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
