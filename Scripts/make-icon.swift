// Draws the SimpleVectorizer app icon and writes Resources/AppIcon.icns. Usage: swift Scripts/make-icon.swift
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt rounded square centred in 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.48))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x14171C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x222731), color(0x0E1014)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    // Subtle plotter coordinate grid
    ctx.setStrokeColor(color(0xFFFFFF, 0.04))
    ctx.setLineWidth(4)
    for g in stride(from: 200.0, through: 824.0, by: 104.0) {
        ctx.move(to: CGPoint(x: g, y: 140))
        ctx.addLine(to: CGPoint(x: g, y: 884))
        ctx.move(to: CGPoint(x: 140, y: g))
        ctx.addLine(to: CGPoint(x: 884, y: g))
    }
    ctx.strokePath()

    // Pixel staircase blocks on the bottom-left (representing bitmap input)
    let blocks: [(CGFloat, CGFloat)] = [
        (190, 230), (242, 272), (294, 314), (346, 356), (242, 230), (294, 272),
    ]
    for (bx, by) in blocks {
        let r = CGRect(x: bx, y: by, width: 46, height: 46)
        let bp = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(bp)
        ctx.setFillColor(color(0x565D6A, 0.42))
        ctx.fillPath()
    }

    // Bézier control tangent lines (cyan 5CE1E6)
    let p0 = CGPoint(x: 230, y: 270)
    let c1 = CGPoint(x: 340, y: 780)
    let c2 = CGPoint(x: 690, y: 240)
    let p3 = CGPoint(x: 790, y: 740)

    ctx.saveGState()
    ctx.setStrokeColor(color(0x5CE1E6, 0.78))
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [18, 16])
    ctx.move(to: p0)
    ctx.addLine(to: c1)
    ctx.move(to: p3)
    ctx.addLine(to: c2)
    ctx.strokePath()
    ctx.restoreGState()

    // Secondary multi-pen companion curve (cyan 5CE1E6)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18 * s, color: color(0x5CE1E6, 0.55))
    ctx.setStrokeColor(color(0x5CE1E6, 0.85))
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 250, y: 225))
    ctx.addCurve(
        to: CGPoint(x: 810, y: 675),
        control1: CGPoint(x: 380, y: 700),
        control2: CGPoint(x: 710, y: 180)
    )
    ctx.strokePath()
    ctx.restoreGState()

    // Primary luminous cubic Bézier curve (amber FFB454)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28 * s, color: color(0xFFB454, 0.85))
    ctx.setStrokeColor(color(0xFFB454))
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    ctx.move(to: p0)
    ctx.addCurve(to: p3, control1: c1, control2: c2)
    ctx.strokePath()
    ctx.restoreGState()

    // Control handle nodes (cyan circles)
    for pt in [c1, c2] {
        ctx.saveGState()
        ctx.setFillColor(color(0x14171C))
        ctx.fillEllipse(in: CGRect(x: pt.x - 22, y: pt.y - 22, width: 44, height: 44))
        ctx.setStrokeColor(color(0x5CE1E6))
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: pt.x - 22, y: pt.y - 22, width: 44, height: 44))
        ctx.restoreGState()
    }

    // Anchor point squares (red FF5C57 & green 9ECE6A)
    for (pt, hex) in [(p0, 0xFF5C57), (p3, 0x9ECE6A)] {
        let rect = CGRect(x: pt.x - 22, y: pt.y - 22, width: 44, height: 44)
        let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16 * s, color: color(hex, 0.8))
        ctx.addPath(path)
        ctx.setFillColor(color(hex))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.restoreGState()
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = fm.temporaryDirectory.appendingPathComponent("SimpleVectorizer-\(UUID().uuidString).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try! fm.createDirectory(at: resources, withIntermediateDirectories: true)
for (name, size) in [
    ("16x16", 16), ("16x16@2x", 32),
    ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
] {
    try! drawIcon(size: size).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! drawIcon(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(resources.path)/AppIcon.icns" : "iconutil failed")
exit(task.terminationStatus)
