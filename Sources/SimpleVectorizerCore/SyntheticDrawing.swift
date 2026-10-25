import CoreGraphics
import Foundation

/// Procedural line-art drawing presets for `--snapshot`, `--self-test`, and interactive AxiDraw testing without external files (G36).
public enum SyntheticPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case portrait = "portrait"
    case stageArch = "stage"
    case hatching = "hatching"
    case rosette = "rosette"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .portrait: return L("Portrait & drapés au trait", "Line-Art Portrait & Drapery")
        case .stageArch: return L("Scénographie & perspective", "Stage Scenography & Perspective")
        case .hatching: return L("Plumes variables & hachures", "Variable Pens & Cross-Hatching")
        case .rosette: return L("Rosace guillochée AxiDraw", "AxiDraw Guilloché Rosette")
        }
    }

    public var icon: String {
        switch self {
        case .portrait: return "scribble.variable"
        case .stageArch: return "cube.transparent"
        case .hatching: return "lines.measurement.horizontal"
        case .rosette: return "hurricane"
        }
    }
}

public enum SyntheticDrawing {
    public static func generate(preset: SyntheticPreset = .portrait, width: Int = 720, height: Int = 960) -> RasterImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return RasterImage(width: width, height: height, luma: [Float](repeating: 255, count: width * height))
        }

        // Paper background (warm off-white with subtle vignette to exercise adaptive thresholding)
        ctx.setFillColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let w = CGFloat(width)
        let h = CGFloat(height)

        switch preset {
        case .portrait:
            drawCalligraphicPortrait(in: ctx, width: w, height: h)
        case .stageArch:
            drawStagePerspective(in: ctx, width: w, height: h)
        case .hatching:
            drawVariablePensAndHatching(in: ctx, width: w, height: h)
        case .rosette:
            drawGuillocheRosette(in: ctx, width: w, height: h)
        }

        // Convert RGBA to Luma (note: CoreGraphics origin is bottom-left, row 0 in memory is top)
        var luma = [Float](repeating: 255.0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(rgba[i * 4])
            let g = Float(rgba[i * 4 + 1])
            let b = Float(rgba[i * 4 + 2])
            luma[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }
        return RasterImage(width: width, height: height, luma: luma)
    }

    private static func drawCalligraphicPortrait(in ctx: CGContext, width w: CGFloat, height h: CGFloat) {
        let cx = w * 0.50
        let cy = h * 0.54

        // Bold outer contour strokes (Pen 2 — thick ~ 5.5 px)
        ctx.setStrokeColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        ctx.setLineWidth(5.5)

        // Head & jawline silhouette
        let face = CGMutablePath()
        face.move(to: CGPoint(x: cx - w * 0.20, y: cy + h * 0.18))
        face.addCurve(
            to: CGPoint(x: cx, y: cy - h * 0.22),
            control1: CGPoint(x: cx - w * 0.24, y: cy - h * 0.06),
            control2: CGPoint(x: cx - w * 0.12, y: cy - h * 0.21)
        )
        face.addCurve(
            to: CGPoint(x: cx + w * 0.20, y: cy + h * 0.18),
            control1: CGPoint(x: cx + w * 0.12, y: cy - h * 0.21),
            control2: CGPoint(x: cx + w * 0.24, y: cy - h * 0.06)
        )
        face.addCurve(
            to: CGPoint(x: cx - w * 0.20, y: cy + h * 0.18),
            control1: CGPoint(x: cx + w * 0.14, y: cy + h * 0.31),
            control2: CGPoint(x: cx - w * 0.14, y: cy + h * 0.31)
        )
        ctx.addPath(face)
        ctx.strokePath()

        // Shoulders & stage drapery folds (bold)
        ctx.setLineWidth(5.2)
        for k in 0..<4 {
            let kf = CGFloat(k)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: w * 0.12, y: h * (0.14 + kf * 0.05)))
            p.addCurve(
                to: CGPoint(x: w * 0.88, y: h * (0.16 + kf * 0.045)),
                control1: CGPoint(x: w * 0.36, y: h * (0.26 - kf * 0.03)),
                control2: CGPoint(x: w * 0.64, y: h * (0.06 + kf * 0.04))
            )
            ctx.addPath(p)
            ctx.strokePath()
        }

        // Fine expressive features & flowing hair/contours (Pen 1 — thin ~ 1.8 px)
        ctx.setLineWidth(1.8)

        // Nose bridge & eyebrow line (single continuous calligraphic gesture)
        let profile = CGMutablePath()
        profile.move(to: CGPoint(x: cx - w * 0.14, y: cy + h * 0.08))
        profile.addQuadCurve(to: CGPoint(x: cx - w * 0.02, y: cy + h * 0.09), control: CGPoint(x: cx - w * 0.08, y: cy + h * 0.13))
        profile.addLine(to: CGPoint(x: cx - w * 0.04, y: cy - h * 0.04))
        profile.addQuadCurve(to: CGPoint(x: cx + w * 0.03, y: cy - h * 0.05), control: CGPoint(x: cx - w * 0.01, y: cy - h * 0.06))
        ctx.addPath(profile)
        ctx.strokePath()

        // Right eyebrow & eye
        let browR = CGMutablePath()
        browR.move(to: CGPoint(x: cx + w * 0.03, y: cy + h * 0.09))
        browR.addQuadCurve(to: CGPoint(x: cx + w * 0.15, y: cy + h * 0.07), control: CGPoint(x: cx + w * 0.09, y: cy + h * 0.13))
        ctx.addPath(browR)
        ctx.strokePath()

        for side in [-1.0, 1.0] {
            let ex = cx + CGFloat(side) * w * 0.085
            let ey = cy + h * 0.045
            ctx.strokeEllipse(in: CGRect(x: ex - w * 0.04, y: ey - h * 0.016, width: w * 0.08, height: h * 0.032))
            ctx.strokeEllipse(in: CGRect(x: ex - w * 0.012, y: ey - w * 0.012, width: w * 0.024, height: w * 0.024))
        }

        // Mouth line
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: cx - w * 0.065, y: cy - h * 0.11))
        mouth.addCurve(
            to: CGPoint(x: cx + w * 0.065, y: cy - h * 0.11),
            control1: CGPoint(x: cx - w * 0.02, y: cy - h * 0.13),
            control2: CGPoint(x: cx + w * 0.02, y: cy - h * 0.13)
        )
        ctx.addPath(mouth)
        ctx.strokePath()

        // Fine cross-contour shading & flowing hair strands
        for i in 0..<14 {
            let t = CGFloat(i) / 13.0
            let wave = CGMutablePath()
            let startX = cx - w * 0.28 + t * w * 0.56
            let startY = cy + h * 0.20 + sin(t * .pi) * h * 0.12
            wave.move(to: CGPoint(x: startX, y: startY))
            wave.addCurve(
                to: CGPoint(x: startX + (t - 0.5) * w * 0.22, y: cy + h * 0.36),
                control1: CGPoint(x: startX - w * 0.06, y: startY + h * 0.07),
                control2: CGPoint(x: startX + w * 0.08, y: startY + h * 0.12)
            )
            ctx.addPath(wave)
            ctx.strokePath()
        }

        // Fine cheek hatching (tests collinear crossing & fine stroke preservation)
        for i in 0..<8 {
            let off = CGFloat(i) * 8.0
            ctx.move(to: CGPoint(x: cx - w * 0.17, y: cy - h * 0.02 - off))
            ctx.addLine(to: CGPoint(x: cx - w * 0.09, y: cy - h * 0.08 - off * 0.8))
            ctx.strokePath()
        }
    }

    private static func drawStagePerspective(in ctx: CGContext, width w: CGFloat, height h: CGFloat) {
        let vx = w * 0.5
        let vy = h * 0.58

        ctx.setStrokeColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        // Bold proscenium frame
        ctx.setLineWidth(6.0)
        ctx.stroke(CGRect(x: w * 0.10, y: h * 0.12, width: w * 0.80, height: h * 0.76))
        ctx.stroke(CGRect(x: w * 0.24, y: h * 0.32, width: w * 0.52, height: h * 0.42))

        // Fine perspective rays & stage floor grid
        ctx.setLineWidth(1.8)
        for i in 0...8 {
            let tx = w * (0.10 + 0.80 * CGFloat(i) / 8.0)
            ctx.move(to: CGPoint(x: tx, y: h * 0.12))
            ctx.addLine(to: CGPoint(x: vx + (tx - vx) * 0.35, y: h * 0.32))
            ctx.strokePath()
        }
        for j in 1...6 {
            let t = pow(CGFloat(j) / 6.0, 1.4)
            let y = h * 0.32 - t * h * 0.20
            let inset = (1.0 - t) * w * 0.14
            ctx.move(to: CGPoint(x: w * 0.10 + inset, y: y))
            ctx.addLine(to: CGPoint(x: w * 0.90 - inset, y: y))
            ctx.strokePath()
        }
        // Stage arches
        ctx.setLineWidth(3.6)
        for r in [w * 0.14, w * 0.22, w * 0.30] {
            ctx.addArc(center: CGPoint(x: vx, y: vy), radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.strokePath()
        }
    }

    private static func drawVariablePensAndHatching(in ctx: CGContext, width w: CGFloat, height h: CGFloat) {
        ctx.setStrokeColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)
        ctx.setFillColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)

        let widths: [CGFloat] = [1.5, 3.2, 5.5, 8.5]
        for (idx, lw) in widths.enumerated() {
            ctx.setLineWidth(lw)
            let baseY = h * (0.18 + CGFloat(idx) * 0.18)
            for k in 0..<3 {
                let yOff = baseY + CGFloat(k) * 18.0
                let p = CGMutablePath()
                p.move(to: CGPoint(x: w * 0.10, y: yOff))
                p.addCurve(
                    to: CGPoint(x: w * 0.90, y: yOff),
                    control1: CGPoint(x: w * 0.35, y: yOff + 42),
                    control2: CGPoint(x: w * 0.65, y: yOff - 42)
                )
                ctx.addPath(p)
                ctx.strokePath()
            }
        }

        // Filled ink medallion at top for hatching test
        ctx.fillEllipse(in: CGRect(x: w * 0.40, y: h * 0.78, width: w * 0.20, height: w * 0.14))
    }

    private static func drawGuillocheRosette(in ctx: CGContext, width w: CGFloat, height h: CGFloat) {
        let cx = w * 0.5
        let cy = h * 0.5
        let maxR = min(w, h) * 0.40
        ctx.setStrokeColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)

        // Outer bold rings
        ctx.setLineWidth(5.0)
        ctx.strokeEllipse(in: CGRect(x: cx - maxR, y: cy - maxR, width: maxR * 2, height: maxR * 2))
        ctx.strokeEllipse(in: CGRect(x: cx - maxR * 0.52, y: cy - maxR * 0.52, width: maxR * 1.04, height: maxR * 1.04))

        // Fine hypotrochoid rosette
        ctx.setLineWidth(1.6)
        let path = CGMutablePath()
        let steps = 720
        let R = Double(maxR * 0.74)
        let r = R * (3.0 / 11.0)
        let d = R * 0.42
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 6.0 * .pi
            let x = Double(cx) + (R - r) * cos(t) + d * cos(((R - r) / r) * t)
            let y = Double(cy) + (R - r) * sin(t) - d * sin(((R - r) / r) * t)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.addPath(path)
        ctx.strokePath()
    }
}
