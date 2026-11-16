import AppKit

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "background.png"

// 660x448 points at 2x = 1320x896 pixels at 144 DPI. The visible window is
// 660x420 points; icon centers sit at y=180 and the arrow between them.
let width: CGFloat = 660
let height: CGFloat = 448
let scale: CGFloat = 2
let pixelWidth = Int(width * scale)
let pixelHeight = Int(height * scale)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: pixelWidth,
                                 pixelsHigh: pixelHeight,
                                 bitsPerSample: 8,
                                 samplesPerPixel: 4,
                                 hasAlpha: true,
                                 isPlanar: false,
                                 colorSpaceName: .calibratedRGB,
                                 bytesPerRow: 0,
                                 bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("cannot create bitmap\n".utf8))
    exit(1)
}
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let cg = context.cgContext
cg.scaleBy(x: scale, y: scale)

// AppKit bitmap contexts use bottom-left coordinates.
let top: (CGFloat) -> CGFloat = { height - $0 }

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colors as CFArray,
               locations: locations)!
}

func radialGlow(center: CGPoint, radius: CGFloat,
                color: NSColor, alpha: CGFloat) {
    let colors = [
        color.withAlphaComponent(alpha).cgColor,
        color.withAlphaComponent(0).cgColor
    ]
    cg.drawRadialGradient(gradient(colors, [0, 1]),
                          startCenter: center, startRadius: 0,
                          endCenter: center, endRadius: radius,
                          options: [.drawsAfterEndLocation])
}

// Bright, airy canvas.
let background = gradient([
    NSColor(calibratedRed: 0.995, green: 0.998, blue: 1.000, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.890, green: 0.930, blue: 0.990, alpha: 1).cgColor
], [0, 1])
cg.drawLinearGradient(background,
                      start: CGPoint(x: 0, y: height),
                      end: CGPoint(x: width, y: 0),
                      options: [])

// Pastel auras: mint on the left, lavender on the right.
radialGlow(center: CGPoint(x: 260, y: top(145)), radius: 270,
           color: NSColor(calibratedRed: 0.45, green: 0.85, blue: 1.0, alpha: 1),
           alpha: 0.38)
radialGlow(center: CGPoint(x: 440, y: top(205)), radius: 230,
           color: NSColor(calibratedRed: 0.78, green: 0.66, blue: 1.0, alpha: 1),
           alpha: 0.34)

// Soft edge tint for depth.
let edge = gradient([
    NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.92, alpha: 0).cgColor,
    NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.92, alpha: 0.20).cgColor
], [0, 1])
cg.drawRadialGradient(edge,
                      startCenter: CGPoint(x: width / 2, y: top(190)),
                      startRadius: 150,
                      endCenter: CGPoint(x: width / 2, y: top(190)),
                      endRadius: 560,
                      options: [.drawsAfterEndLocation])

// One smooth arc between the icon centers (y=180), ending horizontally.
let start = CGPoint(x: 238, y: top(196))
let control1 = CGPoint(x: 295, y: top(112))
let control2 = CGPoint(x: 360, y: top(180))
let end = CGPoint(x: 400, y: top(180))

let arc = CGMutablePath()
arc.move(to: start)
arc.addCurve(to: end, control1: control1, control2: control2)

let cyan = NSColor(calibratedRed: 0.05, green: 0.72, blue: 0.82, alpha: 1)
let blue = NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.96, alpha: 1)
let violet = NSColor(calibratedRed: 0.55, green: 0.25, blue: 0.96, alpha: 1)
let pink = NSColor(calibratedRed: 0.90, green: 0.25, blue: 0.65, alpha: 1)

// Soft drop shadow under the ribbon.
var shadowTransform = CGAffineTransform(translationX: 0, y: -4)
let shadow = arc.copy(using: &shadowTransform)!
cg.saveGState()
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.setStrokeColor(NSColor(calibratedWhite: 0.12, alpha: 0.07).cgColor)
cg.setLineWidth(26)
cg.addPath(shadow)
cg.strokePath()
cg.setStrokeColor(NSColor(calibratedWhite: 0.12, alpha: 0.11).cgColor)
cg.setLineWidth(20)
cg.addPath(shadow)
cg.strokePath()
cg.restoreGState()

// White lift so the ribbon separates from the pastel background.
cg.saveGState()
cg.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.40).cgColor)
cg.setLineWidth(13)
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.addPath(arc)
cg.strokePath()
cg.restoreGState()

// Glossy gradient core: teal -> blue -> violet -> pink.
let core = gradient([
    cyan.cgColor, blue.cgColor, violet.cgColor, pink.cgColor
], [0, 0.36, 0.70, 1])
let coreOutline = arc.copy(strokingWithWidth: 9,
                            lineCap: .round,
                            lineJoin: .round,
                            miterLimit: 10)
cg.saveGState()
cg.addPath(coreOutline)
cg.clip()
cg.drawLinearGradient(core, start: start, end: end, options: [])
cg.restoreGState()

// Top highlight along the ribbon.
var highlightTransform = CGAffineTransform(translationX: 0, y: 2.2)
let highlight = arc.copy(using: &highlightTransform)!
cg.saveGState()
cg.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.70).cgColor)
cg.setLineWidth(2.2)
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.addPath(highlight)
cg.strokePath()
cg.restoreGState()

// Arrowhead pointing at the Applications folder.
let headLength: CGFloat = 27
let headHalfWidth: CGFloat = 16
let tip = CGPoint(x: end.x + headLength, y: end.y)
let head = CGMutablePath()
head.move(to: tip)
head.addLine(to: CGPoint(x: end.x, y: end.y + headHalfWidth))
head.addLine(to: CGPoint(x: end.x, y: end.y - headHalfWidth))
head.closeSubpath()

// Head shadow.
var headShadowTransform = CGAffineTransform(translationX: 0, y: -4)
let headShadow = head.copy(using: &headShadowTransform)!
cg.saveGState()
cg.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.10).cgColor)
cg.addPath(headShadow)
cg.fillPath()
cg.restoreGState()

// Head fill.
let headGradient = gradient([
    blue.cgColor, violet.cgColor, pink.cgColor
], [0, 0.55, 1])
cg.saveGState()
cg.addPath(head)
cg.clip()
cg.drawLinearGradient(headGradient, start: end, end: tip, options: [])
cg.restoreGState()

// Crisp head outline and a small glossy highlight.
cg.saveGState()
cg.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.55).cgColor)
cg.setLineWidth(1.2)
cg.setLineJoin(.round)
cg.addPath(head)
cg.strokePath()
cg.restoreGState()

// A few glints along the arc.
func pointOnArc(_ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let x = u * u * u * start.x
        + 3 * u * u * t * control1.x
        + 3 * u * t * t * control2.x
        + t * t * t * end.x
    let y = u * u * u * start.y
        + 3 * u * u * t * control1.y
        + 3 * u * t * t * control2.y
        + t * t * t * end.y
    return CGPoint(x: x, y: y)
}

for index in 0..<22 {
    let t = (CGFloat(index) + 0.5) / 22
    let base = pointOnArc(t)
    let offset = sin(CGFloat(index) * 2.399) * 12
    let point = CGPoint(x: base.x, y: base.y + offset)
    let radius = 0.6 + CGFloat((index * 7) % 5) / 5 * 1.5
    let alpha = 0.18 + CGFloat((index * 11) % 7) / 7 * 0.34
    let color = index % 4 == 0 ? pink : (index % 3 == 0 ? violet : blue)
    cg.setFillColor(color.withAlphaComponent(alpha).cgColor)
    cg.fillEllipse(in: CGRect(x: point.x - radius,
                              y: point.y - radius,
                              width: radius * 2,
                              height: radius * 2))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("cannot encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
