// Draws the arrows layer of Resources/AppIcon.icon (macOS 26 and later): swift scripts/make-icon-layer.swift <out.png>
import AppKit
// The arrows layer: white, on a clear 1024 canvas, centred.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let config = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .bold).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let s = symbol.size
symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
