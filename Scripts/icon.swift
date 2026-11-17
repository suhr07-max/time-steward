import AppKit
let out = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill()
let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
let rounded = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(calibratedRed: 0.35, green: 0.64, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.29, blue: 0.97, alpha: 1))!.draw(in: rounded, angle: -65)
NSColor.white.withAlphaComponent(0.94).setFill()
NSBezierPath(ovalIn: NSRect(x: 225, y: 225, width: 574, height: 574)).fill()
let hands = NSBezierPath(); hands.lineWidth = 30; hands.lineCapStyle = .round
hands.move(to: NSPoint(x: 512,y: 690)); hands.line(to: NSPoint(x: 512,y: 512)); hands.line(to: NSPoint(x: 660,y: 512))
NSColor(calibratedRed: 0.18, green: 0.40, blue: 0.98, alpha: 1).setStroke(); hands.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
