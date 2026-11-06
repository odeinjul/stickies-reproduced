// Draws the flat app icon after Stickies' own, following Apple's macOS icon
// layout: an 824 pt continuous-corner shape on a 1024 canvas with the standard
// drop shadow (10 down, 10 blur, 30% black) and no other shadows. Inside: a soft
// blue sheet whose pad shows as two deeper bands along the bottom edge, and a
// squiggle, a full line and a short line. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let sheet = color(0xD6EAFF)
let padNear = color(0xB4D6FA)
let padFar = color(0x8DBAEA)
let ink = color(0x93BFEC)

/// Apple's icon shape is a continuous-curvature rounded square, close to a superellipse.
func squircle(_ rect: NSRect, exponent: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let (c, s) = (cos(t), sin(t))
        let x = rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / exponent), c)
        let y = rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / exponent), s)
        step == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.close()
    return path
}

/// On a 1024 grid; AppKit's y axis points up.
func draw() {
    let shape = NSRect(x: 100, y: 100, width: 824, height: 824)
    let outline = squircle(shape)

    // The one drop shadow, under the whole icon.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 10
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    padFar.setFill()
    outline.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The pad: the same shape stacked upwards, clipped to the icon so its edges
    // show as two bands that follow the bottom corners.
    NSGraphicsContext.saveGraphicsState()
    outline.addClip()
    padNear.setFill()
    squircle(shape.offsetBy(dx: 0, dy: 38)).fill()
    sheet.setFill()
    squircle(shape.offsetBy(dx: 0, dy: 76)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Writing: a squiggle, a full line and a short line on the right.
    ink.setStroke()
    func stroke(_ path: NSBezierPath) {
        path.lineWidth = 58
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
    let squiggle = NSBezierPath()
    squiggle.move(to: NSPoint(x: 250, y: 690))
    squiggle.curve(to: NSPoint(x: 450, y: 700), controlPoint1: NSPoint(x: 320, y: 745), controlPoint2: NSPoint(x: 380, y: 745))
    squiggle.curve(to: NSPoint(x: 610, y: 690), controlPoint1: NSPoint(x: 510, y: 660), controlPoint2: NSPoint(x: 560, y: 645))
    squiggle.curve(to: NSPoint(x: 774, y: 790), controlPoint1: NSPoint(x: 660, y: 735), controlPoint2: NSPoint(x: 715, y: 795))
    stroke(squiggle)
    for (from, to, y) in [(250.0, 774.0, 548.0), (560.0, 774.0, 410.0)] {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: from, y: y))
        line.line(to: NSPoint(x: to, y: y))
        stroke(line)
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSAffineTransform(transform: AffineTransform(scale: CGFloat(size) / 1024)).concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
