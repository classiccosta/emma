// Renders the Emma app icon (1024x1024 PNG): a cyan orb on a dark rounded square.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// macOS icon grid: 824pt body centered in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1),
    CGColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

let center = CGPoint(x: 512, y: 512)

// Soft glow behind the orb.
let glow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.45),
    CGColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 360, options: [])

// Outer rings.
for (radius, alpha, width) in [(300.0, 0.25, 6.0), (250.0, 0.5, 10.0)] {
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.90, blue: 1.0, alpha: alpha))
    ctx.setLineWidth(width)
    ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

// Core orb.
let orbRadius: CGFloat = 190
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - orbRadius, y: center.y - orbRadius, width: orbRadius * 2, height: orbRadius * 2))
ctx.clip()
let orb = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.85, green: 0.98, blue: 1.0, alpha: 1),
    CGColor(red: 0.20, green: 0.80, blue: 1.0, alpha: 1),
    CGColor(red: 0.05, green: 0.35, blue: 0.75, alpha: 1),
] as CFArray, locations: [0, 0.45, 1])!
let highlight = CGPoint(x: center.x - 60, y: center.y + 70)
ctx.drawRadialGradient(orb, startCenter: highlight, startRadius: 0, endCenter: center, endRadius: orbRadius, options: [.drawsAfterEndLocation])
ctx.restoreGState()

ctx.restoreGState()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
