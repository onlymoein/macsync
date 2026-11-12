// Draws the disk image window's background: the app on the left, Applications on the right,
// an arrow between them and a line telling you what to do.
// Usage: swift scripts/make-dmg-background.swift <output.png>   (1320x800 pixels, shown at 660x400)
import AppKit

let output = CommandLine.arguments[1]
let w: CGFloat = 1320, h: CGFloat = 800
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The app's own backdrop: soft grey with a faint indigo-to-blue wash.
NSColor(white: 0.925, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
NSGradient(colors: [NSColor(red: 59/255, green: 43/255, blue: 214/255, alpha: 0.14),
                    NSColor(red: 31/255, green: 125/255, blue: 255/255, alpha: 0.08),
                    NSColor(white: 1, alpha: 0)])!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -45)

// Icons sit at (165, 200) and (495, 200) in the 660x400 window, y measured from the top.
let iconY = h - 200 * 2
// One path, so the line and the head don't overlap into a darker spot.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 270 * 2, y: iconY))
arrow.line(to: NSPoint(x: 391 * 2, y: iconY))
arrow.move(to: NSPoint(x: 370 * 2, y: iconY + 36))
arrow.line(to: NSPoint(x: 392 * 2, y: iconY))
arrow.line(to: NSPoint(x: 370 * 2, y: iconY - 36))
arrow.lineWidth = 10
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSGraphicsContext.current?.cgContext.setAlpha(0.45)
NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
NSColor(white: 0.25, alpha: 1).setStroke()
arrow.stroke()
NSGraphicsContext.current?.cgContext.endTransparencyLayer()
NSGraphicsContext.current?.cgContext.setAlpha(1)

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                 .foregroundColor: NSColor(white: 0.12, alpha: alpha), .paragraphStyle: style]
    NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 0, y: y, width: w, height: size * 1.4))
}
text("Drag MacSync into Applications", size: 44, weight: .semibold, alpha: 0.9, y: h - 92 * 2)
text("Then open it from Applications. It lives in the menu bar.", size: 28, weight: .regular, alpha: 0.55, y: 58 * 2)

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
