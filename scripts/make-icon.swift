// Renders the app icon as a .icns. Draws a Darcula-style rounded-rect tile with
// a database "cylinder" mark. Usage: swift scripts/make-icon.swift <out.icns>
import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size

    // Rounded-rect tile with a subtle vertical gradient (macOS icon grid ~ 82%).
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let corner = (s - 2 * inset) * 0.2237   // macOS squircle-ish radius
    let tile = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    tile.addClip()
    let top = CGColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1)
    let bottom = CGColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1)
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Database cylinder, centered.
    let cx = s / 2
    let bodyW = s * 0.42
    let bodyH = s * 0.40
    let ellipseH = s * 0.11
    let left = cx - bodyW / 2
    let topY = s * 0.66
    let botY = topY - bodyH

    let blue = NSColor(red: 0.29, green: 0.55, blue: 0.90, alpha: 1)
    let blueLight = NSColor(red: 0.42, green: 0.66, blue: 0.96, alpha: 1)

    // Body
    let body = NSBezierPath()
    body.move(to: CGPoint(x: left, y: topY))
    body.line(to: CGPoint(x: left, y: botY))
    body.appendArc(withCenter: CGPoint(x: cx, y: botY), radius: bodyW / 2,
                   startAngle: 180, endAngle: 360, clockwise: false)
    // fix aspect for ellipse via transform trick: draw as bezier ellipse instead
    body.removeAllPoints()
    body.move(to: CGPoint(x: left, y: topY))
    body.line(to: CGPoint(x: left, y: botY))
    body.curve(to: CGPoint(x: cx, y: botY - ellipseH / 2),
               controlPoint1: CGPoint(x: left, y: botY - ellipseH * 0.55),
               controlPoint2: CGPoint(x: cx - bodyW * 0.28, y: botY - ellipseH / 2))
    body.curve(to: CGPoint(x: left + bodyW, y: botY),
               controlPoint1: CGPoint(x: cx + bodyW * 0.28, y: botY - ellipseH / 2),
               controlPoint2: CGPoint(x: left + bodyW, y: botY - ellipseH * 0.55))
    body.line(to: CGPoint(x: left + bodyW, y: topY))
    body.close()
    blue.setFill()
    body.fill()

    // Discs (top + two banding ellipses)
    func disc(centerY: CGFloat, color: NSColor) {
        let r = CGRect(x: left, y: centerY - ellipseH / 2, width: bodyW, height: ellipseH)
        let e = NSBezierPath(ovalIn: r)
        color.setFill()
        e.fill()
    }
    disc(centerY: topY - bodyH * 0.02, color: blueLight)   // top rim
    disc(centerY: topY, color: blueLight)                  // top face
    // banding lines
    blue.withAlphaComponent(0.0).setFill()
    let band = NSBezierPath(ovalIn: CGRect(x: left, y: topY - bodyH * 0.5 - ellipseH / 2,
                                           width: bodyW, height: ellipseH))
    NSColor(red: 0.18, green: 0.38, blue: 0.70, alpha: 1).setStroke()
    band.lineWidth = max(1, s * 0.008)
    band.stroke()

    image.unlockFocus()
    return image
}

// Build .iconset then convert with iconutil.
let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: tmp)
try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    let img = drawIcon(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: tmp.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmp.path, "-o", outPath]
try! proc.run()
proc.waitUntilExit()
print(proc.terminationStatus == 0 ? "wrote \(outPath)" : "iconutil failed")
