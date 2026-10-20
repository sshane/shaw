// Renders the app icon as a 1024 px PNG. Run: swift scripts/make-icon.swift icon.png
// Then turn it into Resources/AppIcon.icns with sips and iconutil (see the comment at the bottom).
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// The macOS icon grid: an 824 px rounded square with a soft shadow under it.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
bg.fill()
ctx.restoreGState()
NSGradient(colors: [NSColor(calibratedRed: 0.085, green: 0.09, blue: 0.11, alpha: 1),
                    NSColor(calibratedRed: 0.15, green: 0.155, blue: 0.19, alpha: 1)])!.draw(in: bg, angle: -90)

// A geometric S: two stacked circles, the top one drawn counterclockwise from its upper right,
// the bottom one clockwise, ending at its lower left.
let r: CGFloat = 140, open: CGFloat = 0.45
let s = CGMutablePath()
s.addArc(center: CGPoint(x: body.midX, y: body.midY + r), radius: r, startAngle: open, endAngle: -.pi / 2, clockwise: false)
s.addArc(center: CGPoint(x: body.midX, y: body.midY - r), radius: r, startAngle: .pi / 2, endAngle: .pi + open, clockwise: true)

// Stroked with Shaw's blue, running from cyan at the top to violet at the bottom.
ctx.saveGState()
ctx.addPath(s)
ctx.setLineWidth(104)
ctx.setLineCap(.round)
ctx.replacePathWithStrokedPath()
ctx.clip()
let colors = [NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.0, alpha: 1),
              NSColor(calibratedRed: 0.25, green: 0.56, blue: 1.0, alpha: 1),
              NSColor(calibratedRed: 0.62, green: 0.45, blue: 1.0, alpha: 1)]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.midY + 330), end: CGPoint(x: body.midX, y: body.midY - 330),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()
img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

// mkdir Icon.iconset
// for s in 16 32 128 256 512; do
//   sips -z $s $s icon.png --out Icon.iconset/icon_${s}x${s}.png
//   sips -z $((s*2)) $((s*2)) icon.png --out Icon.iconset/icon_${s}x${s}@2x.png
// done
// iconutil -c icns Icon.iconset -o Resources/AppIcon.icns
