// Draws the app icon: a glowing sync ring above a glass Dock.
// Usage: swift scripts/make-icon.swift <output.png> <pixel size>
import AppKit

let output = CommandLine.arguments[1]
let size = CGFloat(Int(CommandLine.arguments[2]) ?? 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = size * 0.1
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let u = tile.width / 100
let corner = tile.width * 0.225

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
func shadowed(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur * u
    s.shadowOffset = NSSize(width: 0, height: -dy * u)
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// Tile shadow, as macOS icons have.
shadowed(blur: 3, dy: 1.6, alpha: 0.35) { color(40, 30, 160).setFill(); rounded(tile, corner).fill() }

NSGraphicsContext.saveGraphicsState()
rounded(tile, corner).addClip()

// Background: midnight to electric indigo to blue.
NSGradient(colors: [color(14, 16, 52), color(58, 44, 214), color(30, 124, 255)], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
    .draw(in: tile, angle: -62)
// A soft bloom behind the ring.
NSGradient(colors: [color(150, 190, 255, 0.34), color(150, 190, 255, 0)])!
    .draw(fromCenter: NSPoint(x: tile.midX, y: tile.minY + 62 * u), radius: 0,
          toCenter: NSPoint(x: tile.midX, y: tile.minY + 62 * u), radius: 46 * u, options: [])
// Light from the top edge.
NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: tile.minX, y: tile.midY + 8 * u, width: tile.width, height: tile.height / 2 - 8 * u), angle: -90)

// The sync ring: two arrows chasing each other.
let center = NSPoint(x: tile.midX, y: tile.minY + 62 * u)
let radius = 22 * u
func point(_ degrees: CGFloat) -> NSPoint {
    let r = degrees * .pi / 180
    return NSPoint(x: center.x + radius * cos(r), y: center.y + radius * sin(r))
}
func arrowPieces(from start: CGFloat, to end: CGFloat) -> [NSBezierPath] {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
    let body = arc.bezierPath(strokedWidth: 9 * u)
    let r = end * .pi / 180
    let tangent = NSPoint(x: -sin(r), y: cos(r)), radial = NSPoint(x: cos(r), y: sin(r))
    let base = point(end), half = 11 * u, length = 14 * u
    let head = NSBezierPath()
    head.move(to: NSPoint(x: base.x + radial.x * half, y: base.y + radial.y * half))
    head.line(to: NSPoint(x: base.x + tangent.x * length, y: base.y + tangent.y * length))
    head.line(to: NSPoint(x: base.x - radial.x * half, y: base.y - radial.y * half))
    head.close()
    return [body, head]
}
extension NSBezierPath {
    func bezierPath(strokedWidth w: CGFloat) -> NSBezierPath {
        let cg = self.cgPath.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4)
        return NSBezierPath(cgPath: cg)
    }
    var cgPath: CGPath {
        let p = CGMutablePath(); var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo: p.move(to: pts[0])
            case .lineTo: p.addLine(to: pts[0])
            case .curveTo, .cubicCurveTo: p.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .closePath: p.closeSubpath()
            default: break
            }
        }
        return p
    }
}
let pieces = arrowPieces(from: 32, to: 146) + arrowPieces(from: 212, to: 326)
let ringFill = NSGradient(colors: [color(255, 255, 255), color(210, 225, 255)])!
// One shadow for the whole ring: draw every piece into a group so overlaps stay solid.
shadowed(blur: 5, dy: 2.2, alpha: 0.38) {
    NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    for piece in pieces { ringFill.draw(in: piece, angle: -90) }
    NSGraphicsContext.current?.cgContext.endTransparencyLayer()
}

// The Dock: a glass capsule with four small apps.
let bar = NSRect(x: tile.minX + 17 * u, y: tile.minY + 9 * u, width: 66 * u, height: 21 * u)
shadowed(blur: 4, dy: 1.5, alpha: 0.30) { NSColor(white: 1, alpha: 0.30).setFill(); rounded(bar, 8 * u).fill() }
NSGradient(colors: [NSColor(white: 1, alpha: 0.40), NSColor(white: 1, alpha: 0.16)])!.draw(in: rounded(bar, 8 * u), angle: -90)
NSColor(white: 1, alpha: 0.5).setStroke()
let edge = rounded(bar.insetBy(dx: 0.25 * u, dy: 0.25 * u), 7.8 * u); edge.lineWidth = 0.6 * u; edge.stroke()

let apps: [(NSColor, NSColor)] = [
    (color(255, 176, 64), color(255, 110, 40)),
    (color(88, 224, 140), color(24, 170, 96)),
    (color(255, 112, 170), color(226, 52, 120)),
    (color(96, 214, 255), color(40, 138, 255)),
]
let cell = 13.5 * u, gap = 3.6 * u
let startX = bar.midX - (cell * 4 + gap * 3) / 2
for (i, pair) in apps.enumerated() {
    let r = NSRect(x: startX + CGFloat(i) * (cell + gap), y: bar.midY - cell / 2, width: cell, height: cell)
    shadowed(blur: 1.2, dy: 0.6, alpha: 0.28) { pair.1.setFill(); rounded(r, 4 * u).fill() }
    NSGradient(colors: [pair.0, pair.1])!.draw(in: rounded(r, 4 * u), angle: -90)
}

NSGraphicsContext.restoreGraphicsState()

// A hairline inside the tile edge keeps the shape crisp on any wallpaper.
NSColor(white: 1, alpha: 0.22).setStroke()
let rim = rounded(tile.insetBy(dx: 0.3 * u, dy: 0.3 * u), corner); rim.lineWidth = 0.7 * u; rim.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
