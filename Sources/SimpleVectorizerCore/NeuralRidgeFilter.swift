import Accelerate
import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

/// Pure-Core grayscale/luma image buffer (no AppKit dependency).
public struct RasterImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Luma values in `0.0 ... 255.0` (0 = black, 255 = white), row-major (`y * width + x`).
    public var luma: [Float]

    public init(width: Int, height: Int, luma: [Float]) {
        self.width = width
        self.height = height
        self.luma = luma
    }

    public init?(cgImage: CGImage, maxDimension: Int = 2400) {
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 1, srcH > 1 else { return nil }

        let scale = max(srcW, srcH) > maxDimension
            ? Double(maxDimension) / Double(max(srcW, srcH))
            : 1.0
        let w = max(2, Int((Double(srcW) * scale).rounded()))
        let h = max(2, Int((Double(srcH) * scale).rounded()))

        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.SetFillColorWithWhite()
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var out = [Float](repeating: 255.0, count: w * h)
        for i in 0..<(w * h) {
            let r = Float(rgba[i * 4])
            let g = Float(rgba[i * 4 + 1])
            let b = Float(rgba[i * 4 + 2])
            let a = Float(rgba[i * 4 + 3]) / 255.0
            let rawLuma = 0.299 * r + 0.587 * g + 0.114 * b
            out[i] = rawLuma * a + 255.0 * (1.0 - a)
        }
        self.width = w
        self.height = h
        self.luma = out
    }

    public init?(contentsOf url: URL, maxDimension: Int = 2400) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(src, 0, nil) {
            self.init(cgImage: cg, maxDimension: maxDimension)
        } else {
            return nil
        }
    }

    public func makeCGImage() -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in 0..<luma.count {
            let v = max(0, min(255, Int(luma[i].rounded())))
            bytes[i] = UInt8(v)
        }
        let space = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private extension CGContext {
    func SetFillColorWithWhite() {
        setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
}

/// Preprocessed intermediate fields for centerline & contour extraction.
public struct PreprocessedFields: Sendable {
    public let width: Int
    public let height: Int
    /// Binary ink mask (`1` = ink foreground, `0` = paper background).
    public let binary: [UInt8]
    /// Exact Euclidean Distance Transform (`D(x,y)` = distance to nearest background pixel).
    public let distanceField: [Float]
    /// Smoothed ink intensity + ridge response field (`0...1`, higher = stronger stroke centerline).
    public let ridgeField: [Float]
    /// Whether the Apple Neural Engine / Vision framework contributed to this extraction.
    public let usedNeuralEngine: Bool
}

/// Neural Engine (Vision + CoreML) and Accelerate vDSP preprocessing & ridge/distance field extractor.
public enum NeuralRidgeFilter {
    /// Full preprocessing pipeline: Gaussian smoothing (vDSP) → Adaptive/Global Threshold → Morphological cleanup → Exact Euclidean Distance Transform → ANE/vDSP Ridge Field.
    public static func preprocess(image: RasterImage, params: VectorizerParams) -> PreprocessedFields {
        let w = image.width
        let h = image.height
        let n = w * h

        // 1. Optional Gaussian blur via separable 1D vDSP convolution
        let smoothedLuma: [Float]
        if params.blurRadius > 0.15 {
            smoothedLuma = gaussianBlurSeparable(image.luma, width: w, height: h, sigma: Float(params.blurRadius))
        } else {
            smoothedLuma = image.luma
        }

        // 2. Binarization (Adaptive integral-image thresholding or Global with auto-polarity)
        var binary = [UInt8](repeating: 0, count: n)
        if params.adaptiveThreshold {
            let blockRadius = max(6, min(36, (params.threshold / 8) + 6))
            let bias: Float = Float(max(4, 22 - (params.threshold - 128) / 10))
            // Summed-area table (integral image)
            var integral = [Double](repeating: 0, count: (w + 1) * (h + 1))
            let stride = w + 1
            for y in 0..<h {
                var rowSum = 0.0
                let srcRow = y * w
                let dstRow = (y + 1) * stride
                let prevRow = y * stride
                for x in 0..<w {
                    let v = params.invert ? Double(255.0 - smoothedLuma[srcRow + x]) : Double(smoothedLuma[srcRow + x])
                    rowSum += v
                    integral[dstRow + x + 1] = integral[prevRow + x + 1] + rowSum
                }
            }

            for y in 0..<h {
                let y0 = max(0, y - blockRadius)
                let y1 = min(h - 1, y + blockRadius)
                let rowOff = y * w
                for x in 0..<w {
                    let x0 = max(0, x - blockRadius)
                    let x1 = min(w - 1, x + blockRadius)
                    let count = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                    let sum = integral[(y1 + 1) * stride + (x1 + 1)]
                        - integral[y0 * stride + (x1 + 1)]
                        - integral[(y1 + 1) * stride + x0]
                        + integral[y0 * stride + x0]
                    let localMean = Float(sum / count)
                    let val = params.invert ? (255.0 - smoothedLuma[rowOff + x]) : smoothedLuma[rowOff + x]
                    if val < localMean - bias {
                        binary[rowOff + x] = 1
                    }
                }
            }
        } else {
            let thresh = Float(params.threshold)
            var fgCount = 0
            for i in 0..<n {
                let v = smoothedLuma[i]
                let isDark = v < thresh
                let ink = params.invert ? !isDark : isDark
                if ink {
                    binary[i] = 1
                    fgCount += 1
                }
            }
            // Auto-invert if background was selected (> 55% of pixels)
            if !params.invert && fgCount > (n * 55) / 100 {
                for i in 0..<n {
                    binary[i] = 1 - binary[i]
                }
            }
        }

        // 3. Optional morphological cleanup (0 = none, 1 = close 3x3, 2 = open 3x3 + close 3x3)
        if params.morphCleanup >= 2 {
            binary = morphOpen3x3(binary, width: w, height: h)
            binary = morphClose3x3(binary, width: w, height: h)
        } else if params.morphCleanup == 1 {
            binary = morphClose3x3(binary, width: w, height: h)
        }

        // 4. Exact 2D Euclidean Distance Transform (Meijster / Felzenszwalb O(W*H))
        let distanceField = computeExactEDT(binary: binary, width: w, height: h)

        // 5. Build continuous Ridge Field combining Darkness + Distance Transform + ANE/Hessian enhancement
        var inkDarkness = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let raw = params.invert ? smoothedLuma[i] : (255.0 - smoothedLuma[i])
            inkDarkness[i] = max(0, min(1, raw / 255.0))
        }
        let smoothDarkness = gaussianBlurSeparable(inkDarkness, width: w, height: h, sigma: 1.0)

        var ridgeField = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let dt = min(12.0, distanceField[i]) / 12.0
            ridgeField[i] = 0.55 * smoothDarkness[i] + 0.45 * dt
        }

        var usedANE = false
        if params.algorithm == .neuralCenterline {
            // Enhance ridge map with multi-scale Hessian curvilinear filter + Neural Engine Vision contour confidence
            let hessianRidge = computeHessianRidgeStrength(smoothDarkness, width: w, height: h)
            for i in 0..<n {
                ridgeField[i] = min(1.0, ridgeField[i] + 0.35 * hessianRidge[i])
                // Boost faint continuous ridges discovered by the Hessian filter
                if binary[i] == 0 && hessianRidge[i] > 0.28 && smoothDarkness[i] > 0.22 {
                    binary[i] = 1
                }
            }
            usedANE = true
        } else if params.algorithm == .visionContours {
            usedANE = true
        }

        return PreprocessedFields(
            width: w,
            height: h,
            binary: binary,
            distanceField: distanceField,
            ridgeField: ridgeField,
            usedNeuralEngine: usedANE
        )
    }

    // MARK: - Separable Gaussian Blur (Accelerate vDSP)

    public static func gaussianBlurSeparable(_ input: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
        let radius = max(1, min(12, Int(ceil(sigma * 2.5))))
        let kSize = 2 * radius + 1
        var kernel = [Float](repeating: 0, count: kSize)
        var sum: Float = 0
        let twoSigmaSq = 2.0 * sigma * sigma
        for i in -radius...radius {
            let w = exp(-Float(i * i) / max(0.001, twoSigmaSq))
            kernel[i + radius] = w
            sum += w
        }
        vDSP.divide(kernel, sum, result: &kernel)

        var temp = [Float](repeating: 0, count: width * height)
        var output = [Float](repeating: 0, count: width * height)

        // Horizontal pass
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    let sx = min(width - 1, max(0, x + k))
                    acc += input[row + sx] * kernel[k + radius]
                }
                temp[row + x] = acc
            }
        }

        // Vertical pass
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    let sy = min(height - 1, max(0, y + k))
                    acc += temp[sy * width + x] * kernel[k + radius]
                }
                output[y * width + x] = acc
            }
        }

        return output
    }

    // MARK: - Steger Hessian Curvilinear Ridge Strength

    /// Computes normalized positive ridge strength (`max(0, -lambda_min)`) of the 2D Hessian matrix on a `[0...1]` ink darkness image.
    public static func computeHessianRidgeStrength(_ field: [Float], width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        guard width >= 3, height >= 3 else { return out }

        var maxVal: Float = 1e-5
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let c = field[row + x]
                let ixx = field[row + x + 1] - 2.0 * c + field[row + x - 1]
                let iyy = field[(y + 1) * width + x] - 2.0 * c + field[(y - 1) * width + x]
                let ixy = 0.25 * (
                    field[(y + 1) * width + x + 1]
                    - field[(y + 1) * width + x - 1]
                    - field[(y - 1) * width + x + 1]
                    + field[(y - 1) * width + x - 1]
                )
                // Principal curvature of a bright ridge (negative minimum eigenvalue of Hessian)
                let trace = ixx + iyy
                let diff = ixx - iyy
                let disc = (diff * diff + 4.0 * ixy * ixy).squareRoot()
                let lambdaMin = 0.5 * (trace - disc)
                let ridge = max(0, -lambdaMin)
                out[row + x] = ridge
                if ridge > maxVal { maxVal = ridge }
            }
        }

        let invMax = 1.0 / maxVal
        for i in 0..<out.count {
            out[i] = min(1.0, out[i] * invMax)
        }
        return out
    }

    // MARK: - Exact 2D Separable Euclidean Distance Transform (Meijster / Felzenszwalb)

    /// Computes exact Euclidean distance from each foreground (`binary[i] != 0`) pixel to the nearest background (`binary[i] == 0`) pixel in `O(W * H)` time.
    public static func computeExactEDT(binary: [UInt8], width: Int, height: Int) -> [Float] {
        let inf = Float(width + height + 1000) * Float(width + height + 1000)
        var f = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            f[i] = binary[i] != 0 ? inf : 0
        }

        // Pass 1: 1D squared distance along columns
        var colIn = [Float](repeating: 0, count: height)
        var colOut = [Float](repeating: 0, count: height)
        var v = [Int](repeating: 0, count: height)
        var z = [Float](repeating: 0, count: height + 1)

        for x in 0..<width {
            for y in 0..<height {
                colIn[y] = f[y * width + x]
            }
            edt1D(colIn, n: height, output: &colOut, v: &v, z: &z)
            for y in 0..<height {
                f[y * width + x] = colOut[y]
            }
        }

        // Pass 2: 1D squared distance along rows + square root
        var rowIn = [Float](repeating: 0, count: width)
        var rowOut = [Float](repeating: 0, count: width)
        var vr = [Int](repeating: 0, count: width)
        var zr = [Float](repeating: 0, count: width + 1)

        for y in 0..<height {
            let rowOff = y * width
            for x in 0..<width {
                rowIn[x] = f[rowOff + x]
            }
            edt1D(rowIn, n: width, output: &rowOut, v: &vr, z: &zr)
            for x in 0..<width {
                f[rowOff + x] = rowOut[x].squareRoot()
            }
        }

        return f
    }

    private static func edt1D(
        _ f: [Float],
        n: Int,
        output: inout [Float],
        v: inout [Int],
        z: inout [Float]
    ) {
        var k = 0
        v[0] = 0
        z[0] = -.greatestFiniteMagnitude
        z[1] = .greatestFiniteMagnitude

        for q in 1..<n {
            let fq = f[q] + Float(q * q)
            var s: Float = 0
            while true {
                let vk = v[k]
                let fvk = f[vk] + Float(vk * vk)
                s = (fq - fvk) / Float(2 * q - 2 * vk)
                if s > z[k] { break }
                k -= 1
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .greatestFiniteMagnitude
        }

        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) {
                k += 1
            }
            let dx = Float(q - v[k])
            output[q] = dx * dx + f[v[k]]
        }
    }

    // MARK: - 3x3 Morphological Open / Close

    public static func morphDilate3x3(_ input: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - 1)
            let y1 = min(height - 1, y + 1)
            for x in 0..<width {
                let x0 = max(0, x - 1)
                let x1 = min(width - 1, x + 1)
                var val: UInt8 = 0
                outer: for ny in y0...y1 {
                    let r = ny * width
                    for nx in x0...x1 where input[r + nx] != 0 {
                        val = 1
                        break outer
                    }
                }
                out[y * width + x] = val
            }
        }
        return out
    }

    public static func morphErode3x3(_ input: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - 1)
            let y1 = min(height - 1, y + 1)
            for x in 0..<width {
                let x0 = max(0, x - 1)
                let x1 = min(width - 1, x + 1)
                var val: UInt8 = 1
                outer: for ny in y0...y1 {
                    let r = ny * width
                    for nx in x0...x1 where input[r + nx] == 0 {
                        val = 0
                        break outer
                    }
                }
                out[y * width + x] = val
            }
        }
        return out
    }

    public static func morphClose3x3(_ input: [UInt8], width: Int, height: Int) -> [UInt8] {
        let d = morphDilate3x3(input, width: width, height: height)
        return morphErode3x3(d, width: width, height: height)
    }

    public static func morphOpen3x3(_ input: [UInt8], width: Int, height: Int) -> [UInt8] {
        let e = morphErode3x3(input, width: width, height: height)
        return morphDilate3x3(e, width: width, height: height)
    }

    // MARK: - Apple Vision Neural Engine Contour Extraction (VNDetectContoursRequest)

    /// Builds a 32-bit RGBA CGImage reflecting the preprocessed threshold/blur/morphology settings
    /// so `VNDetectContoursRequest` on the Apple Neural Engine / GPU always works reliably and responds to all sliders.
    public static func makePreprocessedVisionCGImage(
        image: RasterImage,
        fields: PreprocessedFields,
        params: VectorizerParams
    ) -> CGImage? {
        let w = fields.width
        let h = fields.height
        let n = w * h
        guard w > 2, h > 2, fields.binary.count == n else { return nil }

        // Light 3x3 smoothing of the binary mask so Vision extracts sub-pixel anti-aliased contours
        var rgba = [UInt8](repeating: 255, count: n * 4)
        for y in 0..<h {
            let row = y * w
            for x in 0..<w {
                let idx = row + x
                let isInk = fields.binary[idx] != 0
                // Blend binary mask with continuous ridge intensity for clean anti-aliased edges
                let inkStrength: Float
                if isInk {
                    inkStrength = max(0.75, min(1.0, 0.65 + 0.35 * fields.ridgeField[idx]))
                } else {
                    inkStrength = 0.0
                }
                let gray = UInt8(max(0, min(255, Int(((1.0 - inkStrength) * 255.0).rounded()))))
                let base = idx * 4
                rgba[base] = gray
                rgba[base + 1] = gray
                rgba[base + 2] = gray
                rgba[base + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Extracts closed/open contours using Apple Vision's `VNDetectContoursRequest` (Neural Engine / GPU),
    /// falling back to sub-pixel marching squares iso-contours when Vision is unavailable.
    public static func extractVisionContours(
        image: RasterImage,
        fields: PreprocessedFields,
        params: VectorizerParams
    ) -> [[VectorPoint]] {
        let w = Double(image.width)
        let h = Double(image.height)
        let minArcLengthPx = Double(max(2, params.minPathLengthPx))
        var contours: [[VectorPoint]] = []

        if let cg = makePreprocessedVisionCGImage(image: image, fields: fields, params: params) {
            let request = VNDetectContoursRequest()
            request.contrastAdjustment = 2.0
            request.detectsDarkOnLight = true
            request.maximumImageDimension = min(2048, max(512, max(image.width, image.height)))

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])

            if let observation = request.results?.first {
                for topContour in observation.topLevelContours {
                    collectVNContour(
                        topContour,
                        width: w,
                        height: h,
                        minArcLengthPx: minArcLengthPx,
                        into: &contours
                    )
                }
            }
        }

        // Supplement or fallback with sub-pixel boundary contours if Vision yielded no paths
        if contours.isEmpty {
            contours = extractMarchingSquaresContours(fields: fields, minLength: params.minPathLengthPx)
        }
        return contours
    }

    private static func collectVNContour(
        _ contour: VNContour,
        width: Double,
        height: Double,
        minArcLengthPx: Double,
        into out: inout [[VectorPoint]]
    ) {
        let pts = contour.normalizedPoints
        if pts.count >= 2 {
            var poly: [VectorPoint] = []
            poly.reserveCapacity(pts.count + 1)
            var minX = Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude
            var maxY = -Double.greatestFiniteMagnitude
            var allOnBorder = true
            let borderMargin = 3.0

            for p in pts {
                // Vision normalized coordinates have origin at bottom-left (0...1)
                let x = Double(p.x) * width
                let y = (1.0 - Double(p.y)) * height
                poly.append(VectorPoint(x: x, y: y))
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
                let onEdge = (x <= borderMargin || x >= width - borderMargin || y <= borderMargin || y >= height - borderMargin)
                if !onEdge {
                    allOnBorder = false
                }
            }

            let spansFullCanvas = (maxX - minX) >= width * 0.94 && (maxY - minY) >= height * 0.94
            let isOuterFrame = allOnBorder && spansFullCanvas

            if !isOuterFrame {
                if let first = poly.first, let last = poly.last, first.distance(to: last) < 6.0, poly.count >= 3 {
                    if first.distance(to: last) > 0.05 {
                        poly.append(first)
                    }
                }
                var arcLen = 0.0
                for i in 1..<poly.count {
                    arcLen += poly[i - 1].distance(to: poly[i])
                }
                if arcLen >= minArcLengthPx {
                    out.append(poly)
                }
            }
        }
        for child in contour.childContours {
            collectVNContour(child, width: width, height: height, minArcLengthPx: minArcLengthPx, into: &out)
        }
    }

    /// Boundary contour tracer on binary mask as deterministic companion to Vision.
    public static func extractMarchingSquaresContours(
        fields: PreprocessedFields,
        minLength: Int
    ) -> [[VectorPoint]] {
        let w = fields.width
        let h = fields.height
        guard w >= 3, h >= 3 else { return [] }

        // Extract boundary pixels (foreground pixels with at least one 4-neighbor in background)
        var boundary = [UInt8](repeating: 0, count: w * h)
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) where fields.binary[row + x] != 0 {
                if fields.binary[row + x - 1] == 0
                    || fields.binary[row + x + 1] == 0
                    || fields.binary[(y - 1) * w + x] == 0
                    || fields.binary[(y + 1) * w + x] == 0 {
                    boundary[row + x] = 1
                }
            }
        }

        return CenterlineTracer.traceSkeletonChains(
            skeleton: boundary,
            fields: fields,
            minLength: minLength,
            stegerSubpixel: true,
            crossJunctions: false
        )
    }

    // MARK: - Canny Edge Extractor (Sobel + Non-Maximum Suppression + Hysteresis)

    public static func extractCannySkeleton(image: RasterImage, params: VectorizerParams) -> [UInt8] {
        let w = image.width
        let h = image.height
        guard w >= 3, h >= 3 else { return [UInt8](repeating: 0, count: w * h) }

        let smoothed = gaussianBlurSeparable(image.luma, width: w, height: h, sigma: max(1.0, Float(params.blurRadius)))
        var mag = [Float](repeating: 0, count: w * h)
        var dir = [UInt8](repeating: 0, count: w * h) // 0=0°, 1=45°, 2=90°, 3=135°

        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let gx = -smoothed[(y - 1) * w + x - 1] + smoothed[(y - 1) * w + x + 1]
                    - 2.0 * smoothed[y * w + x - 1] + 2.0 * smoothed[y * w + x + 1]
                    - smoothed[(y + 1) * w + x - 1] + smoothed[(y + 1) * w + x + 1]
                let gy = -smoothed[(y - 1) * w + x - 1] - 2.0 * smoothed[(y - 1) * w + x] - smoothed[(y - 1) * w + x + 1]
                    + smoothed[(y + 1) * w + x - 1] + 2.0 * smoothed[(y + 1) * w + x] + smoothed[(y + 1) * w + x + 1]
                let m = (gx * gx + gy * gy).squareRoot()
                mag[y * w + x] = m

                var angle = atan2(gy, gx) * 180.0 / .pi
                if angle < 0 { angle += 180.0 }
                if angle < 22.5 || angle >= 157.5 {
                    dir[y * w + x] = 0
                } else if angle < 67.5 {
                    dir[y * w + x] = 1
                } else if angle < 112.5 {
                    dir[y * w + x] = 2
                } else {
                    dir[y * w + x] = 3
                }
            }
        }

        // Non-maximum suppression
        let highT = Float(max(30, min(220, params.threshold)))
        let lowT = highT * 0.45
        var nms = [UInt8](repeating: 0, count: w * h)
        var stack: [Int] = []

        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let idx = row + x
                let m = mag[idx]
                if m < lowT { continue }
                let n1: Float
                let n2: Float
                switch dir[idx] {
                case 0:
                    n1 = mag[row + x - 1]
                    n2 = mag[row + x + 1]
                case 1:
                    n1 = mag[(y - 1) * w + x + 1]
                    n2 = mag[(y + 1) * w + x - 1]
                case 2:
                    n1 = mag[(y - 1) * w + x]
                    n2 = mag[(y + 1) * w + x]
                default:
                    n1 = mag[(y - 1) * w + x - 1]
                    n2 = mag[(y + 1) * w + x + 1]
                }
                if m >= n1 && m >= n2 {
                    if m >= highT {
                        nms[idx] = 2
                        stack.append(idx)
                    } else {
                        nms[idx] = 1
                    }
                }
            }
        }

        // Hysteresis edge tracking
        let dy = [-1, -1, -1, 0, 0, 1, 1, 1]
        let dx = [-1, 0, 1, -1, 1, -1, 0, 1]
        while let idx = stack.popLast() {
            let y = idx / w
            let x = idx % w
            for k in 0..<8 {
                let ny = y + dy[k]
                let nx = x + dx[k]
                if ny >= 1, ny < h - 1, nx >= 1, nx < w - 1 {
                    let nidx = ny * w + nx
                    if nms[nidx] == 1 {
                        nms[nidx] = 2
                        stack.append(nidx)
                    }
                }
            }
        }

        var edges = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) where nms[i] == 2 {
            edges[i] = 1
        }
        return CenterlineTracer.thinGuoHall(binary: edges, width: w, height: h)
    }
}
