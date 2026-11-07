// Draws the app icon: a neon-green Pro Click Mini outline, with tilt arrows by the wheel,
// on a black rounded square. Usage: swift scripts/make-icon.swift <out.png>  (1024×1024)
import AppKit

let size: CGFloat = 1024
let green = NSColor(srgbRed: 0x44 / 255, green: 0xD6 / 255, blue: 0x2C / 255, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    // macOS icon grid: 824 pt body centred in 1024, corner radius ~185.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))!
        .draw(in: tile, angle: 90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    tile.lineWidth = 4
    tile.stroke()

    // Mouse body: egg shape, narrower at the front (top).
    let cx: CGFloat = 512, top: CGFloat = 215, bottom: CGFloat = 815, w: CGFloat = 330
    let mouse = NSBezierPath()
    mouse.move(to: NSPoint(x: cx, y: top))
    mouse.curve(to: NSPoint(x: cx + w / 2, y: 470), controlPoint1: NSPoint(x: cx + w * 0.42, y: top),
                controlPoint2: NSPoint(x: cx + w / 2, y: 330))
    mouse.curve(to: NSPoint(x: cx, y: bottom), controlPoint1: NSPoint(x: cx + w / 2, y: 700),
                controlPoint2: NSPoint(x: cx + w * 0.36, y: bottom))
    mouse.curve(to: NSPoint(x: cx - w / 2, y: 470), controlPoint1: NSPoint(x: cx - w * 0.36, y: bottom),
                controlPoint2: NSPoint(x: cx - w / 2, y: 700))
    mouse.curve(to: NSPoint(x: cx, y: top), controlPoint1: NSPoint(x: cx - w / 2, y: 330),
                controlPoint2: NSPoint(x: cx - w * 0.42, y: top))
    mouse.close()

    // Glow, then the crisp outline.
    let glow = NSShadow()
    glow.shadowColor = green.withAlphaComponent(0.9)
    glow.shadowBlurRadius = 40
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    green.setStroke()
    mouse.lineWidth = 26
    mouse.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0.06, alpha: 1).setFill()
    mouse.fill()
    green.setStroke()
    mouse.lineWidth = 22
    mouse.stroke()

    // Split between the buttons, and the scroll wheel.
    let split = NSBezierPath()
    split.move(to: NSPoint(x: cx, y: top + 10))
    split.line(to: NSPoint(x: cx, y: 470))
    split.lineWidth = 12
    green.withAlphaComponent(0.7).setStroke()
    split.stroke()
    let wheel = NSBezierPath(roundedRect: NSRect(x: cx - 24, y: 285, width: 48, height: 110), xRadius: 24, yRadius: 24)
    NSColor(white: 0.06, alpha: 1).setFill()
    wheel.fill()
    green.setFill()
    NSBezierPath(roundedRect: NSRect(x: cx - 15, y: 296, width: 30, height: 88), xRadius: 15, yRadius: 15).fill()

    // Tilt arrows: the app's headline feature.
    for side: CGFloat in [-1, 1] {
        let chevron = NSBezierPath()
        let x = cx + side * 75
        chevron.move(to: NSPoint(x: x, y: 302))
        chevron.line(to: NSPoint(x: x + side * 34, y: 340))
        chevron.line(to: NSPoint(x: x, y: 378))
        chevron.lineWidth = 16
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        green.setStroke()
        chevron.stroke()
    }

    // Side buttons on the left edge.
    for y: CGFloat in [520, 600] {
        green.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: NSRect(x: cx - w / 2 - 22, y: y, width: 18, height: 58), xRadius: 9, yRadius: 9).fill()
    }
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
