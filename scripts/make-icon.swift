// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.16, alpha: 1),
                    NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.32, alpha: 1)])!.draw(in: bg, angle: -90)
// Stacked "composition" layers.
let colors: [NSColor] = [
    NSColor(calibratedRed: 0.36, green: 0.55, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.70, green: 0.48, blue: 0.92, alpha: 1),
    NSColor(calibratedRed: 0.93, green: 0.43, blue: 0.40, alpha: 1),
    NSColor(calibratedRed: 0.91, green: 0.74, blue: 0.30, alpha: 1),
]
for (i, c) in colors.enumerated() {
    let y = body.minY + 150 + CGFloat(i) * 120
    let x0 = body.minX + 110 + CGFloat(i % 2) * 70
    let w = body.width - 220 - CGFloat((i * 37) % 120)
    c.setFill()
    NSBezierPath(roundedRect: CGRect(x: x0, y: y, width: w, height: 84), xRadius: 18, yRadius: 18).fill()
}
// Waveform across the top.
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
ctx.setLineWidth(22)
ctx.setLineCap(.round)
let midY = body.minY + 712
for i in 0..<15 {
    let x = body.minX + 130 + CGFloat(i) * 41
    let h = 18 + 60 * abs(sin(Double(i) * 0.75)) * (1 - abs(Double(i) - 7) / 9)
    ctx.move(to: CGPoint(x: x, y: midY - CGFloat(h)))
    ctx.addLine(to: CGPoint(x: x, y: midY + CGFloat(h)))
}
ctx.strokePath()
img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
