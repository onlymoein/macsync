// Draws the app icon. Usage: swift scripts/make-icon.swift <output.png> <pixel size>
import AppKit

let output = CommandLine.arguments[1]
let size = CGFloat(Int(CommandLine.arguments[2]) ?? 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let inset = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
NSGradient(colors: [NSColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1), NSColor(red: 0.05, green: 0.22, blue: 0.62, alpha: 1)])!
    .draw(in: tile, angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.52, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let box = symbol.size
symbol.draw(in: NSRect(x: (size - box.width) / 2, y: (size - box.height) / 2, width: box.width, height: box.height))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
