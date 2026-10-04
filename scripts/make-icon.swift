import AppKit
// Regenerates the app icon: swift scripts/make-icon.swift QuickCapture/Assets.xcassets/AppIcon.appiconset/AppIcon.png

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// Background: diagonal blue → indigo gradient (iOS applies the rounded mask).
let full = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: rgb(10, 132, 255), ending: rgb(88, 86, 214))!.draw(in: full, angle: -60)

// Note card with a soft shadow.
let card = NSRect(x: 212, y: 180, width: 600, height: 664)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0, 0, 40, 0.35)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()
rgb(255, 255, 255).setFill()
NSBezierPath(roundedRect: card, xRadius: 72, yRadius: 72).fill()
NSGraphicsContext.restoreGraphicsState()

// Text lines on the card.
rgb(200, 205, 220).setFill()
let lineWidths: [CGFloat] = [440, 400, 440, 260]
for (i, w) in lineWidths.enumerated() {
    let y = 690 - CGFloat(i) * 100
    NSBezierPath(roundedRect: NSRect(x: 292, y: y, width: w, height: 40), xRadius: 20, yRadius: 20).fill()
}

// Lightning-bolt badge, bottom-right of the card.
let badgeCenter = NSPoint(x: 752, y: 252)
let badgeRadius: CGFloat = 150
NSGraphicsContext.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowColor = rgb(0, 0, 40, 0.3)
badgeShadow.shadowBlurRadius = 30
badgeShadow.shadowOffset = NSSize(width: 0, height: -10)
badgeShadow.set()
rgb(255, 204, 0).setFill()
NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                            width: badgeRadius * 2, height: badgeRadius * 2)).fill()
NSGraphicsContext.restoreGraphicsState()

let bolt = NSBezierPath()
let pts: [(CGFloat, CGFloat)] = [(20, 100), (-62, -10), (-8, -10), (-24, -100), (62, 14), (8, 14)]
bolt.move(to: NSPoint(x: badgeCenter.x + pts[0].0, y: badgeCenter.y + pts[0].1))
for p in pts.dropFirst() { bolt.line(to: NSPoint(x: badgeCenter.x + p.0, y: badgeCenter.y + p.1)) }
bolt.close()
bolt.lineJoinStyle = .round
rgb(255, 255, 255).setFill()
bolt.fill()

NSGraphicsContext.restoreGraphicsState()
// Flatten to an opaque RGB image: App Store icons must not have an alpha channel.
let opaque = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
CGImageDestinationFinalize(destination)
