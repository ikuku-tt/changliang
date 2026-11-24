import CoreGraphics
import Foundation
import ImageIO

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let cream = CGColor(srgbRed: 1, green: 0.945, blue: 0.815, alpha: 1)
let amber = CGColor(srgbRed: 1, green: 0.765, blue: 0.422, alpha: 1)
let gradient = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(srgbRed: 0.075, green: 0.212, blue: 0.206, alpha: 1),
    CGColor(srgbRed: 0.19, green: 0.404, blue: 0.353, alpha: 1)
] as CFArray, locations: [0, 1])!

func drawIcon(size: Int, url: URL) throws {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGPath(roundedRect: CGRect(x: 84, y: 84, width: 856, height: 856), cornerWidth: 182, cornerHeight: 182, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -11), blur: 22, color: CGColor(gray: 0, alpha: 0.24))
    c.addPath(tile)
    c.fillPath()
    c.restoreGState()
    c.addPath(tile)
    c.clip()
    c.drawLinearGradient(gradient, start: CGPoint(x: 760, y: 84), end: CGPoint(x: 290, y: 940), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.setStrokeColor(amber)
    c.setLineWidth(29)
    for (shift, lift) in [(0, 0), (102, 33)] {
        let x = CGFloat(shift), y = CGFloat(lift)
        c.move(to: CGPoint(x: 409+x, y: 585))
        c.addCurve(to: CGPoint(x: 405+x, y: 714+y), control1: CGPoint(x: 362+x, y: 640), control2: CGPoint(x: 450+x, y: 663+y))
        c.strokePath()
    }
    c.setStrokeColor(cream)
    c.setLineWidth(37)
    c.move(to: CGPoint(x: 630, y: 502))
    c.addCurve(to: CGPoint(x: 627, y: 366), control1: CGPoint(x: 814, y: 555), control2: CGPoint(x: 782, y: 348))
    c.strokePath()
    c.setFillColor(cream)
    c.move(to: CGPoint(x: 280, y: 531))
    c.addLine(to: CGPoint(x: 649, y: 531))
    c.addQuadCurve(to: CGPoint(x: 655, y: 519), control: CGPoint(x: 658, y: 531))
    c.addLine(to: CGPoint(x: 637, y: 418))
    c.addCurve(to: CGPoint(x: 548, y: 328), control1: CGPoint(x: 630, y: 375), control2: CGPoint(x: 595, y: 328))
    c.addLine(to: CGPoint(x: 385, y: 328))
    c.addCurve(to: CGPoint(x: 296, y: 418), control1: CGPoint(x: 339, y: 328), control2: CGPoint(x: 305, y: 375))
    c.addLine(to: CGPoint(x: 273, y: 520))
    c.addQuadCurve(to: CGPoint(x: 280, y: 531), control: CGPoint(x: 271, y: 531))
    c.closePath()
    c.fillPath()
    c.setLineWidth(28)
    c.move(to: CGPoint(x: 266, y: 282))
    c.addQuadCurve(to: CGPoint(x: 718, y: 282), control: CGPoint(x: 487, y: 263))
    c.strokePath()

    let output = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(output, c.makeImage()!, nil)
    guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
}

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Cup.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for dimension in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        try drawIcon(size: dimension * scale, url: folder.appendingPathComponent("icon_\(dimension)x\(dimension)\(suffix).png"))
    }
}
