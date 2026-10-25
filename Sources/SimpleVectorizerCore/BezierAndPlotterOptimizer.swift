import Foundation

/// Cached output of Stage A (image preprocessing, ANE/vDSP ridge/skeleton extraction, tracing, stitching, pen clustering).
public struct RawExtractionStage: Sendable {
    public let imageWidth: Int
    public let imageHeight: Int
    public let extractionCacheKey: String
    public let usedNeuralEngine: Bool
    public let pathsByPen: [[(points: [VectorPoint], radiusPx: Double, pointRadiiPx: [Double], isHatch: Bool)]]
    public let breakpointsPx: [Double]
}

/// Ramer-Douglas-Peucker simplification, Philip Schneider's least-squares cubic Bézier curve fitting,
/// variable-width stroke ribbon construction, cross-hatching fill generator, and reversible Nearest-Neighbor + 2-Opt AxiDraw travel optimizer.
public enum BezierAndPlotterOptimizer {

    // MARK: - Ramer-Douglas-Peucker Simplification

    public static func simplifyRDP(_ points: [VectorPoint], epsilon: Double) -> [VectorPoint] {
        simplifyRDPWithRadii(points, radii: [], epsilon: epsilon).points
    }

    public static func simplifyRDPWithRadii(
        _ points: [VectorPoint],
        radii: [Double],
        epsilon: Double
    ) -> (points: [VectorPoint], radii: [Double]) {
        guard points.count >= 3, epsilon > 0.01 else {
            return (points, radii.count == points.count ? radii : [])
        }
        let hasRadii = (radii.count == points.count)
        let isClosed = points.count > 4 && points.first!.distance(to: points.last!) < 1.5
        if isClosed {
            let mid = points.count / 2
            let firstIdx = simplifyRDPOpenIndices(Array(points[0...mid]), epsilon: epsilon)
            let secondIdx = simplifyRDPOpenIndices(Array(points[mid..<points.count]), epsilon: epsilon).map { $0 + mid }
            let allIdx = firstIdx + secondIdx.dropFirst()
            let outPts = allIdx.map { points[$0] }
            let outRad = hasRadii ? allIdx.map { radii[$0] } : []
            return (outPts, outRad)
        }
        let keptIdx = simplifyRDPOpenIndices(points, epsilon: epsilon)
        let outPts = keptIdx.map { points[$0] }
        let outRad = hasRadii ? keptIdx.map { radii[$0] } : []
        return (outPts, outRad)
    }

    private static func simplifyRDPOpenIndices(_ points: [VectorPoint], epsilon: Double) -> [Int] {
        guard points.count >= 3 else { return Array(0..<points.count) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        let epsSq = epsilon * epsilon

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end - start > 1 else { continue }
            let a = points[start]
            let b = points[end]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy

            var maxDistSq = -1.0
            var maxIdx = start

            for i in (start + 1)..<end {
                let p = points[i]
                let dSq: Double
                if lenSq < 1e-10 {
                    dSq = p.distanceSquared(to: a)
                } else {
                    let t = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
                    let projX = a.x + t * dx
                    let projY = a.y + t * dy
                    let ex = p.x - projX
                    let ey = p.y - projY
                    dSq = ex * ex + ey * ey
                }
                if dSq > maxDistSq {
                    maxDistSq = dSq
                    maxIdx = i
                }
            }

            if maxDistSq > epsSq {
                keep[maxIdx] = true
                stack.append((start, maxIdx))
                stack.append((maxIdx, end))
            }
        }

        var result: [Int] = []
        result.reserveCapacity(points.count)
        for i in 0..<points.count where keep[i] {
            result.append(i)
        }
        return result
    }

    // MARK: - Sharp Corner Detection & Path Splitting

    public static func splitAtCorners(_ points: [VectorPoint], cornerAngleDeg: Int) -> [[VectorPoint]] {
        guard points.count >= 3, cornerAngleDeg > 0 else { return [points] }
        let cosThreshold = cos(Double(180 - cornerAngleDeg) * .pi / 180.0)
        var splits: [Int] = []

        for i in 1..<(points.count - 1) {
            let ax = points[i].x - points[i - 1].x
            let ay = points[i].y - points[i - 1].y
            let bx = points[i + 1].x - points[i].x
            let by = points[i + 1].y - points[i].y
            let na = (ax * ax + ay * ay).squareRoot()
            let nb = (bx * bx + by * by).squareRoot()
            guard na > 1e-6, nb > 1e-6 else { continue }
            let cosVal = (ax * bx + ay * by) / (na * nb)
            if cosVal < cosThreshold {
                splits.append(i)
            }
        }

        guard !splits.isEmpty else { return [points] }
        var segments: [[VectorPoint]] = []
        var prev = 0
        for s in splits {
            let seg = Array(points[prev...s])
            if seg.count >= 2 { segments.append(seg) }
            prev = s
        }
        let tail = Array(points[prev..<points.count])
        if tail.count >= 2 { segments.append(tail) }
        return segments
    }

    // MARK: - Schneider Least-Squares + Catmull-Rom Cubic Bézier Fitting

    /// Fits smooth cubic Bézier curves to a simplified polyline, preserving sharp corners.
    public static func fitCubicBeziers(
        points: [VectorPoint],
        smoothing: Double,
        cornerAngleDeg: Int
    ) -> [CubicBezierSegment] {
        guard points.count >= 2, smoothing > 0.02 else { return [] }

        let subpaths = splitAtCorners(points, cornerAngleDeg: cornerAngleDeg)
        var allBeziers: [CubicBezierSegment] = []
        let alpha = max(0.0, min(1.0, smoothing))
        // Maximum allowed fitting error in pixels (scales with smoothing slider)
        let fitError = max(0.35, alpha * 2.2)

        for seg in subpaths {
            if seg.count == 2 {
                let p0 = seg[0]
                let p3 = seg[1]
                let c1 = VectorPoint(x: p0.x + (p3.x - p0.x) / 3.0, y: p0.y + (p3.y - p0.y) / 3.0)
                let c2 = VectorPoint(x: p0.x + 2.0 * (p3.x - p0.x) / 3.0, y: p0.y + 2.0 * (p3.y - p0.y) / 3.0)
                allBeziers.append(CubicBezierSegment(p0: p0, c1: c1, c2: c2, p3: p3))
            } else if seg.count >= 6 && alpha >= 0.35 {
                // Philip Schneider least-squares cubic Bézier fitting for multi-point smooth chains
                let tHat1 = unitVector(from: seg[0], to: seg[1])
                let tHat2 = unitVector(from: seg[seg.count - 1], to: seg[seg.count - 2])
                let fitted = fitSchneiderCubic(seg, leftTangent: tHat1, rightTangent: tHat2, error: fitError)
                allBeziers.append(contentsOf: fitted)
            } else {
                // Tension-scaled Catmull-Rom to Cubic Bézier conversion
                let n = seg.count
                for i in 0..<(n - 1) {
                    let p0 = seg[max(0, i - 1)]
                    let p1 = seg[i]
                    let p2 = seg[min(n - 1, i + 1)]
                    let p3 = seg[min(n - 1, i + 2)]

                    let c1 = VectorPoint(
                        x: p1.x + alpha * (p2.x - p0.x) / 6.0,
                        y: p1.y + alpha * (p2.y - p0.y) / 6.0
                    )
                    let c2 = VectorPoint(
                        x: p2.x - alpha * (p3.x - p1.x) / 6.0,
                        y: p2.y - alpha * (p3.y - p1.y) / 6.0
                    )
                    allBeziers.append(CubicBezierSegment(p0: p1, c1: c1, c2: c2, p3: p2))
                }
            }
        }

        return allBeziers
    }

    private static func unitVector(from a: VectorPoint, to b: VectorPoint) -> VectorPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-8 else { return VectorPoint(x: 1, y: 0) }
        return VectorPoint(x: dx / len, y: dy / len)
    }

    private static func fitSchneiderCubic(
        _ pts: [VectorPoint],
        leftTangent: VectorPoint,
        rightTangent: VectorPoint,
        error: Double,
        depth: Int = 0
    ) -> [CubicBezierSegment] {
        let n = pts.count
        if n == 2 {
            let dist = pts[0].distance(to: pts[1]) / 3.0
            let c1 = VectorPoint(x: pts[0].x + leftTangent.x * dist, y: pts[0].y + leftTangent.y * dist)
            let c2 = VectorPoint(x: pts[1].x + rightTangent.x * dist, y: pts[1].y + rightTangent.y * dist)
            return [CubicBezierSegment(p0: pts[0], c1: c1, c2: c2, p3: pts[1])]
        }

        var u = chordLengthParameterize(pts)
        var bez = generateBezier(pts, u: u, leftTangent: leftTangent, rightTangent: rightTangent)
        var (maxErr, splitPoint) = computeMaxError(pts, bez: bez, u: u)

        if maxErr <= error {
            return [bez]
        }

        // Newton-Raphson reparameterization when error is close
        if maxErr <= error * 4.0 && depth < 6 {
            for _ in 0..<4 {
                u = reparameterize(pts, u: u, bez: bez)
                bez = generateBezier(pts, u: u, leftTangent: leftTangent, rightTangent: rightTangent)
                (maxErr, splitPoint) = computeMaxError(pts, bez: bez, u: u)
                if maxErr <= error {
                    return [bez]
                }
            }
        }

        if depth >= 8 || splitPoint <= 0 || splitPoint >= n - 1 {
            return [bez]
        }

        // Split at point of maximum error
        let centerDX = pts[splitPoint - 1].x - pts[splitPoint + 1].x
        let centerDY = pts[splitPoint - 1].y - pts[splitPoint + 1].y
        let centerLen = (centerDX * centerDX + centerDY * centerDY).squareRoot()
        let tCenterLeft: VectorPoint
        let tCenterRight: VectorPoint
        if centerLen > 1e-8 {
            tCenterLeft = VectorPoint(x: centerDX / centerLen, y: centerDY / centerLen)
            tCenterRight = VectorPoint(x: -tCenterLeft.x, y: -tCenterLeft.y)
        } else {
            tCenterLeft = unitVector(from: pts[splitPoint], to: pts[splitPoint - 1])
            tCenterRight = unitVector(from: pts[splitPoint], to: pts[splitPoint + 1])
        }

        let leftPts = Array(pts[0...splitPoint])
        let rightPts = Array(pts[splitPoint..<n])
        return fitSchneiderCubic(leftPts, leftTangent: leftTangent, rightTangent: tCenterLeft, error: error, depth: depth + 1)
            + fitSchneiderCubic(rightPts, leftTangent: tCenterRight, rightTangent: rightTangent, error: error, depth: depth + 1)
    }

    private static func chordLengthParameterize(_ pts: [VectorPoint]) -> [Double] {
        var u = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            u[i] = u[i - 1] + pts[i].distance(to: pts[i - 1])
        }
        let total = u.last ?? 1.0
        if total > 1e-9 {
            for i in 1..<pts.count { u[i] /= total }
        }
        return u
    }

    private static func generateBezier(
        _ pts: [VectorPoint],
        u: [Double],
        leftTangent: VectorPoint,
        rightTangent: VectorPoint
    ) -> CubicBezierSegment {
        let p0 = pts.first!
        let p3 = pts.last!
        var c00 = 0.0, c01 = 0.0, c11 = 0.0
        var x0 = 0.0, x1 = 0.0

        for i in 0..<pts.count {
            let ti = u[i]
            let mt = 1.0 - ti
            let b0 = mt * mt * mt
            let b1 = 3.0 * ti * mt * mt
            let b2 = 3.0 * ti * ti * mt
            let b3 = ti * ti * ti

            let a1x = leftTangent.x * b1
            let a1y = leftTangent.y * b1
            let a2x = rightTangent.x * b2
            let a2y = rightTangent.y * b2

            c00 += a1x * a1x + a1y * a1y
            c01 += a1x * a2x + a1y * a2y
            c11 += a2x * a2x + a2y * a2y

            let tmpX = pts[i].x - (p0.x * (b0 + b1) + p3.x * (b2 + b3))
            let tmpY = pts[i].y - (p0.y * (b0 + b1) + p3.y * (b2 + b3))

            x0 += a1x * tmpX + a1y * tmpY
            x1 += a2x * tmpX + a2y * tmpY
        }

        let detC0C1 = c00 * c11 - c01 * c01
        let detC0X = c00 * x1 - c01 * x0
        let detXC1 = x0 * c11 - x1 * c01

        var alphaL = abs(detC0C1) > 1e-9 ? detXC1 / detC0C1 : 0.0
        var alphaR = abs(detC0C1) > 1e-9 ? detC0X / detC0C1 : 0.0

        let segLength = p0.distance(to: p3)
        let epsilon = 1e-6 * segLength
        // Guard against ill-conditioned C matrix producing negative or runaway control handles (Graphics Gems I, p. 618)
        if alphaL < epsilon || alphaR < epsilon || alphaL > segLength * 0.85 || alphaR > segLength * 0.85 {
            alphaL = segLength / 3.0
            alphaR = segLength / 3.0
        }

        let c1 = VectorPoint(x: p0.x + leftTangent.x * alphaL, y: p0.y + leftTangent.y * alphaL)
        let c2 = VectorPoint(x: p3.x + rightTangent.x * alphaR, y: p3.y + rightTangent.y * alphaR)
        return CubicBezierSegment(p0: p0, c1: c1, c2: c2, p3: p3)
    }

    private static func evaluateBezier(_ bez: CubicBezierSegment, t: Double) -> VectorPoint {
        let mt = 1.0 - t
        let b0 = mt * mt * mt
        let b1 = 3.0 * t * mt * mt
        let b2 = 3.0 * t * t * mt
        let b3 = t * t * t
        return VectorPoint(
            x: b0 * bez.p0.x + b1 * bez.c1.x + b2 * bez.c2.x + b3 * bez.p3.x,
            y: b0 * bez.p0.y + b1 * bez.c1.y + b2 * bez.c2.y + b3 * bez.p3.y
        )
    }

    private static func computeMaxError(
        _ pts: [VectorPoint],
        bez: CubicBezierSegment,
        u: [Double]
    ) -> (Double, Int) {
        var maxDist = 0.0
        var splitPoint = pts.count / 2
        for i in 1..<(pts.count - 1) {
            let p = evaluateBezier(bez, t: u[i])
            let d = p.distance(to: pts[i])
            if d >= maxDist {
                maxDist = d
                splitPoint = i
            }
        }
        return (maxDist, splitPoint)
    }

    private static func reparameterize(
        _ pts: [VectorPoint],
        u: [Double],
        bez: CubicBezierSegment
    ) -> [Double] {
        var out = u
        for i in 1..<(pts.count - 1) {
            let t = u[i]
            let mt = 1.0 - t
            let q = evaluateBezier(bez, t: t)
            // First derivative Q'(t)
            let q1x = 3.0 * mt * mt * (bez.c1.x - bez.p0.x)
                + 6.0 * mt * t * (bez.c2.x - bez.c1.x)
                + 3.0 * t * t * (bez.p3.x - bez.c2.x)
            let q1y = 3.0 * mt * mt * (bez.c1.y - bez.p0.y)
                + 6.0 * mt * t * (bez.c2.y - bez.c1.y)
                + 3.0 * t * t * (bez.p3.y - bez.c2.y)
            // Second derivative Q''(t)
            let q2x = 6.0 * mt * (bez.c2.x - 2.0 * bez.c1.x + bez.p0.x)
                + 6.0 * t * (bez.p3.x - 2.0 * bez.c2.x + bez.c1.x)
            let q2y = 6.0 * mt * (bez.c2.y - 2.0 * bez.c1.y + bez.p0.y)
                + 6.0 * t * (bez.p3.y - 2.0 * bez.c2.y + bez.c1.y)

            let dx = q.x - pts[i].x
            let dy = q.y - pts[i].y
            let num = dx * q1x + dy * q1y
            let den = q1x * q1x + q1y * q1y + dx * q2x + dy * q2y
            if abs(den) > 1e-9 {
                out[i] = max(0.0, min(1.0, t - num / den))
            }
        }
        return out
    }

    // MARK: - Variable-Width Stroke Ribbon Builder (Illustration SVG Mode)

    /// Builds a closed cubic Bézier variable-width outline ribbon around a stroke centerline
    /// using the per-vertex local radius profile `pointRadiiPx` and a user thickness multiplier `scale`.
    public static func buildVariableWidthRibbon(
        points: [VectorPoint],
        pointRadiiPx: [Double],
        beziers: [CubicBezierSegment],
        defaultRadiusPx: Double,
        scale: Double,
        isClosed: Bool
    ) -> [CubicBezierSegment] {
        guard points.count >= 2 else { return [] }
        let widthScale = max(0.15, min(4.0, scale))

        // Base centerline cubic segments (convert polyline segments to linear cubics if smoothing is off)
        let baseSegments: [CubicBezierSegment]
        if !beziers.isEmpty {
            baseSegments = beziers
        } else {
            var segs: [CubicBezierSegment] = []
            segs.reserveCapacity(points.count - 1)
            for i in 0..<(points.count - 1) {
                let p0 = points[i]
                let p3 = points[i + 1]
                let c1 = VectorPoint(x: p0.x + (p3.x - p0.x) / 3.0, y: p0.y + (p3.y - p0.y) / 3.0)
                let c2 = VectorPoint(x: p0.x + 2.0 * (p3.x - p0.x) / 3.0, y: p0.y + 2.0 * (p3.y - p0.y) / 3.0)
                segs.append(CubicBezierSegment(p0: p0, c1: c1, c2: c2, p3: p3))
            }
            baseSegments = segs
        }
        guard !baseSegments.isEmpty else { return [] }

        // Subdivide long cubic Bézier segments via de Casteljau so mid-segment thickness swells are faithfully captured
        var refinedSegments: [CubicBezierSegment] = []
        refinedSegments.reserveCapacity(baseSegments.count * 2)
        for seg in baseSegments {
            if seg.p0.distance(to: seg.p3) > 16.0 {
                let (left, right) = splitCubicAtMidpoint(seg)
                refinedSegments.append(left)
                refinedSegments.append(right)
            } else {
                refinedSegments.append(seg)
            }
        }

        // Precompute cumulative arc-length along `points` to interpolate local radius at any point on the refined curve
        let hasPointRadii = (pointRadiiPx.count == points.count && !pointRadiiPx.isEmpty)
        func sampleRadius(at pt: VectorPoint) -> Double {
            guard hasPointRadii else {
                return max(0.35, defaultRadiusPx * widthScale)
            }
            var bestDistSq = Double.greatestFiniteMagnitude
            var bestR = defaultRadiusPx
            for i in 0..<(points.count - 1) {
                let a = points[i]
                let b = points[i + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let lenSq = dx * dx + dy * dy
                let t: Double
                if lenSq < 1e-10 {
                    t = 0.0
                } else {
                    t = max(0.0, min(1.0, ((pt.x - a.x) * dx + (pt.y - a.y) * dy) / lenSq))
                }
                let px = a.x + t * dx
                let py = a.y + t * dy
                let dSq = (pt.x - px) * (pt.x - px) + (pt.y - py) * (pt.y - py)
                if dSq < bestDistSq {
                    bestDistSq = dSq
                    bestR = pointRadiiPx[i] * (1.0 - t) + pointRadiiPx[i + 1] * t
                }
            }
            return max(0.35, bestR * widthScale)
        }

        let m = refinedSegments.count
        var knotRadii = [Double](repeating: defaultRadiusPx * widthScale, count: m + 1)
        for i in 0..<m {
            knotRadii[i] = sampleRadius(at: refinedSegments[i].p0)
        }
        knotRadii[m] = isClosed ? knotRadii[0] : sampleRadius(at: refinedSegments[m - 1].p3)

        // Smooth knot radii slightly for C1 visual continuity of the ribbon envelope
        if knotRadii.count >= 3 {
            var smoothed = knotRadii
            for i in 1..<(knotRadii.count - 1) {
                smoothed[i] = 0.25 * knotRadii[i - 1] + 0.50 * knotRadii[i] + 0.25 * knotRadii[i + 1]
            }
            knotRadii = smoothed
        }

        // Compute unit left-hand normals at each knot between refined cubic segments
        func startTangent(_ seg: CubicBezierSegment) -> VectorPoint {
            let d1 = seg.p0.distance(to: seg.c1)
            if d1 > 1e-5 { return unitVector(from: seg.p0, to: seg.c1) }
            let d2 = seg.p0.distance(to: seg.c2)
            if d2 > 1e-5 { return unitVector(from: seg.p0, to: seg.c2) }
            return unitVector(from: seg.p0, to: seg.p3)
        }

        func endTangent(_ seg: CubicBezierSegment) -> VectorPoint {
            let d1 = seg.c2.distance(to: seg.p3)
            if d1 > 1e-5 { return unitVector(from: seg.c2, to: seg.p3) }
            let d2 = seg.c1.distance(to: seg.p3)
            if d2 > 1e-5 { return unitVector(from: seg.c1, to: seg.p3) }
            return unitVector(from: seg.p0, to: seg.p3)
        }

        func leftNormal(_ tangent: VectorPoint) -> VectorPoint {
            VectorPoint(x: -tangent.y, y: tangent.x)
        }

        var knotNormals = [VectorPoint](repeating: VectorPoint(x: 0, y: 1), count: m + 1)
        for i in 0...m {
            let tVec: VectorPoint
            if i == 0 {
                if isClosed {
                    let tIn = endTangent(refinedSegments[m - 1])
                    let tOut = startTangent(refinedSegments[0])
                    let sx = tIn.x + tOut.x
                    let sy = tIn.y + tOut.y
                    let sl = (sx * sx + sy * sy).squareRoot()
                    tVec = sl > 1e-5 ? VectorPoint(x: sx / sl, y: sy / sl) : tOut
                } else {
                    tVec = startTangent(refinedSegments[0])
                }
            } else if i == m {
                if isClosed {
                    tVec = VectorPoint(x: knotNormals[0].y, y: -knotNormals[0].x)
                } else {
                    tVec = endTangent(refinedSegments[m - 1])
                }
            } else {
                let tIn = endTangent(refinedSegments[i - 1])
                let tOut = startTangent(refinedSegments[i])
                let sx = tIn.x + tOut.x
                let sy = tIn.y + tOut.y
                let sl = (sx * sx + sy * sy).squareRoot()
                tVec = sl > 1e-5 ? VectorPoint(x: sx / sl, y: sy / sl) : tOut
            }
            knotNormals[i] = (i == m && isClosed) ? knotNormals[0] : leftNormal(tVec)
        }

        // Build left-side offset segments (forward: 0 ..< m) and right-side offset segments (backward: m-1 down to 0)
        var leftChain: [CubicBezierSegment] = []
        var rightChainReversed: [CubicBezierSegment] = []
        leftChain.reserveCapacity(m)
        rightChainReversed.reserveCapacity(m)

        for i in 0..<m {
            let seg = refinedSegments[i]
            let n0 = knotNormals[i]
            let n3 = knotNormals[i + 1]
            let r0 = knotRadii[i]
            let r3 = knotRadii[i + 1]
            let r1 = (2.0 * r0 + r3) / 3.0
            let r2 = (r0 + 2.0 * r3) / 3.0

            // Interpolated unit normals at t=1/3 and t=2/3
            let n1x = 2.0 * n0.x + n3.x
            let n1y = 2.0 * n0.y + n3.y
            let n1l = max(1e-6, (n1x * n1x + n1y * n1y).squareRoot())
            let n1 = VectorPoint(x: n1x / n1l, y: n1y / n1l)

            let n2x = n0.x + 2.0 * n3.x
            let n2y = n0.y + 2.0 * n3.y
            let n2l = max(1e-6, (n2x * n2x + n2y * n2y).squareRoot())
            let n2 = VectorPoint(x: n2x / n2l, y: n2y / n2l)

            // Left offset curve (+n)
            let lp0 = VectorPoint(x: seg.p0.x + n0.x * r0, y: seg.p0.y + n0.y * r0)
            let lc1 = VectorPoint(x: seg.c1.x + n1.x * r1, y: seg.c1.y + n1.y * r1)
            let lc2 = VectorPoint(x: seg.c2.x + n2.x * r2, y: seg.c2.y + n2.y * r2)
            let lp3 = VectorPoint(x: seg.p3.x + n3.x * r3, y: seg.p3.y + n3.y * r3)
            leftChain.append(CubicBezierSegment(p0: lp0, c1: lc1, c2: lc2, p3: lp3))

            // Right offset curve (-n), stored reversed (p3 -> p0) so it forms a continuous loop back to start
            let rp0 = VectorPoint(x: seg.p3.x - n3.x * r3, y: seg.p3.y - n3.y * r3)
            let rc1 = VectorPoint(x: seg.c2.x - n2.x * r2, y: seg.c2.y - n2.y * r2)
            let rc2 = VectorPoint(x: seg.c1.x - n1.x * r1, y: seg.c1.y - n1.y * r1)
            let rp3 = VectorPoint(x: seg.p0.x - n0.x * r0, y: seg.p0.y - n0.y * r0)
            rightChainReversed.append(CubicBezierSegment(p0: rp0, c1: rc1, c2: rc2, p3: rp3))
        }

        // Semicircular round cap helper using two 90-degree cubic Bézier arcs (kappa = 0.5522847498)
        let kappa = 0.5522847498307936
        func makeRoundCap(
            center: VectorPoint,
            fromPt: VectorPoint,
            toPt: VectorPoint,
            outwardDir: VectorPoint,
            radius: Double
        ) -> [CubicBezierSegment] {
            let apex = VectorPoint(x: center.x + outwardDir.x * radius, y: center.y + outwardDir.y * radius)
            let fromVec = VectorPoint(x: fromPt.x - center.x, y: fromPt.y - center.y)
            let toVec = VectorPoint(x: toPt.x - center.x, y: toPt.y - center.y)

            let arc1 = CubicBezierSegment(
                p0: fromPt,
                c1: VectorPoint(x: fromPt.x + outwardDir.x * radius * kappa, y: fromPt.y + outwardDir.y * radius * kappa),
                c2: VectorPoint(x: apex.x + fromVec.x * kappa, y: apex.y + fromVec.y * kappa),
                p3: apex
            )
            let arc2 = CubicBezierSegment(
                p0: apex,
                c1: VectorPoint(x: apex.x + toVec.x * kappa, y: apex.y + toVec.y * kappa),
                c2: VectorPoint(x: toPt.x + outwardDir.x * radius * kappa, y: toPt.y + outwardDir.y * radius * kappa),
                p3: toPt
            )
            return [arc1, arc2]
        }

        var outline: [CubicBezierSegment] = []
        outline.reserveCapacity(m * 2 + 4)
        outline.append(contentsOf: leftChain)

        // End round cap (connects leftChain.last.p3 to rightChainReversed.last.p0 around refinedSegments.last.p3)
        let endCenter = refinedSegments[m - 1].p3
        let endTan = endTangent(refinedSegments[m - 1])
        let endFrom = leftChain[m - 1].p3
        let endTo = rightChainReversed[m - 1].p0
        outline.append(contentsOf: makeRoundCap(
            center: endCenter,
            fromPt: endFrom,
            toPt: endTo,
            outwardDir: endTan,
            radius: knotRadii[m]
        ))

        // Traverse right chain back to start
        for seg in rightChainReversed.reversed() {
            outline.append(seg)
        }

        // Start round cap (connects rightChainReversed[0].p3 back to leftChain[0].p0 around refinedSegments[0].p0)
        let startCenter = refinedSegments[0].p0
        let startTan = startTangent(refinedSegments[0])
        let backwardDir = VectorPoint(x: -startTan.x, y: -startTan.y)
        let startFrom = rightChainReversed[0].p3
        let startTo = leftChain[0].p0
        outline.append(contentsOf: makeRoundCap(
            center: startCenter,
            fromPt: startFrom,
            toPt: startTo,
            outwardDir: backwardDir,
            radius: knotRadii[0]
        ))

        return outline
    }

    private static func splitCubicAtMidpoint(_ s: CubicBezierSegment) -> (CubicBezierSegment, CubicBezierSegment) {
        let m01 = VectorPoint(x: 0.5 * (s.p0.x + s.c1.x), y: 0.5 * (s.p0.y + s.c1.y))
        let m12 = VectorPoint(x: 0.5 * (s.c1.x + s.c2.x), y: 0.5 * (s.c1.y + s.c2.y))
        let m23 = VectorPoint(x: 0.5 * (s.c2.x + s.p3.x), y: 0.5 * (s.c2.y + s.p3.y))
        let m012 = VectorPoint(x: 0.5 * (m01.x + m12.x), y: 0.5 * (m01.y + m12.y))
        let m123 = VectorPoint(x: 0.5 * (m12.x + m23.x), y: 0.5 * (m12.y + m23.y))
        let mid = VectorPoint(x: 0.5 * (m012.x + m123.x), y: 0.5 * (m012.y + m123.y))
        let left = CubicBezierSegment(p0: s.p0, c1: m01, c2: m012, p3: mid)
        let right = CubicBezierSegment(p0: mid, c1: m123, c2: m23, p3: s.p3)
        return (left, right)
    }

    // MARK: - Parallel & Cross-Hatching Fill Generator for Dark Regions

    public static func generateHatchPaths(
        fields: PreprocessedFields,
        spacingPx: Double,
        angleDeg: Double,
        crossHatch: Bool
    ) -> [[VectorPoint]] {
        let w = fields.width
        let h = fields.height
        let step = max(2.5, spacingPx)
        let angles = crossHatch ? [angleDeg, angleDeg + 90.0] : [angleDeg]
        var hatchLines: [[VectorPoint]] = []

        let cx = Double(w) * 0.5
        let cy = Double(h) * 0.5
        let diag = (Double(w * w + h * h)).squareRoot() * 0.55

        for aDeg in angles {
            let rad = aDeg * .pi / 180.0
            let cosA = cos(rad)
            let sinA = sin(rad)
            // Normal to hatch lines
            let nx = -sinA
            let ny = cosA

            var offset = -diag
            var lineToggle = false
            while offset <= diag {
                defer {
                    offset += step
                    lineToggle.toggle()
                }
                let ox = cx + offset * nx
                let oy = cy + offset * ny

                var insideRun: [VectorPoint] = []
                var s = -diag
                while s <= diag {
                    let px = ox + s * cosA
                    let py = oy + s * sinA
                    let ix = Int(px.rounded())
                    let iy = Int(py.rounded())
                    let isDeepInk: Bool
                    if ix >= 1, ix < w - 1, iy >= 1, iy < h - 1 {
                        // Only hatch dark interior regions (stroke half-width >= 2.8 px)
                        isDeepInk = fields.distanceField[iy * w + ix] >= 2.8
                    } else {
                        isDeepInk = false
                    }

                    if isDeepInk {
                        if insideRun.isEmpty {
                            insideRun.append(VectorPoint(x: px, y: py))
                        } else {
                            insideRun[insideRun.count - 1] = VectorPoint(x: px, y: py)
                            if insideRun.count == 1 {
                                insideRun.append(VectorPoint(x: px, y: py))
                            }
                        }
                    } else if insideRun.count >= 2 {
                        if insideRun.first!.distance(to: insideRun.last!) >= 4.0 {
                            let seg = lineToggle ? Array(insideRun.reversed()) : insideRun
                            hatchLines.append(seg)
                        }
                        insideRun.removeAll(keepingCapacity: true)
                    } else {
                        insideRun.removeAll(keepingCapacity: true)
                    }
                    s += 1.5
                }
                if insideRun.count >= 2 && insideRun.first!.distance(to: insideRun.last!) >= 4.0 {
                    let seg = lineToggle ? Array(insideRun.reversed()) : insideRun
                    hatchLines.append(seg)
                }
            }
        }

        return hatchLines
    }

    // MARK: - Reversible Nearest-Neighbor + 2-Opt Plotter Travel Optimizer

    /// Reorders and reverses paths to minimize pen-up rapid travel distance on AxiDraw.
    /// Returns `(optimizedPaths, rawTravelPx, optimizedTravelPx)`.
    public static func optimizePlotterTour(
        paths: [VectorPath],
        enable2Opt: Bool
    ) -> (paths: [VectorPath], rawTravelPx: Double, optimizedTravelPx: Double) {
        guard paths.count > 1 else {
            return (paths, 0.0, 0.0)
        }

        // Measure initial unoptimized travel distance (starting from top-left home 0,0)
        let rawTravel = computeTravelDistance(paths)

        // Step 1: Bidirectional Greedy Nearest-Neighbor starting from path closest to (0,0)
        let n = paths.count
        var working = paths
        var used = [Bool](repeating: false, count: n)
        var orderedIndices: [Int] = []
        orderedIndices.reserveCapacity(n)

        let origin = VectorPoint(x: 0, y: 0)
        var firstIdx = 0
        var firstReverse = false
        var bestOriginDist = Double.greatestFiniteMagnitude
        for i in 0..<n {
            let ds = origin.distanceSquared(to: working[i].startPoint)
            if ds < bestOriginDist {
                bestOriginDist = ds
                firstIdx = i
                firstReverse = false
            }
            let de = origin.distanceSquared(to: working[i].endPoint)
            if de < bestOriginDist {
                bestOriginDist = de
                firstIdx = i
                firstReverse = true
            }
        }

        if firstReverse {
            working[firstIdx] = working[firstIdx].reversedPath()
        }
        used[firstIdx] = true
        orderedIndices.append(firstIdx)
        var currentEnd = working[firstIdx].endPoint

        for _ in 1..<n {
            var bestIdx = -1
            var bestRev = false
            var bestDistSq = Double.greatestFiniteMagnitude

            for cand in 0..<n where !used[cand] {
                let ds = currentEnd.distanceSquared(to: working[cand].startPoint)
                if ds < bestDistSq {
                    bestDistSq = ds
                    bestIdx = cand
                    bestRev = false
                }
                let de = currentEnd.distanceSquared(to: working[cand].endPoint)
                if de < bestDistSq {
                    bestDistSq = de
                    bestIdx = cand
                    bestRev = true
                }
            }

            guard bestIdx >= 0 else { break }
            if bestRev {
                working[bestIdx] = working[bestIdx].reversedPath()
            }
            used[bestIdx] = true
            orderedIndices.append(bestIdx)
            currentEnd = working[bestIdx].endPoint
        }

        var tour = orderedIndices.map { working[$0] }

        // Step 2: 2-Opt local search pass (untangles crossing rapid pen-up travels)
        if enable2Opt && tour.count >= 4 {
            let maxWindow = min(tour.count, 140)
            let maxPasses = tour.count <= 400 ? 3 : 1
            for _ in 0..<maxPasses {
                var improved = false
                for i in 0..<(tour.count - 2) {
                    let prevEnd = (i == 0) ? origin : tour[i - 1].endPoint
                    let jLimit = min(tour.count - 1, i + maxWindow)
                    for j in (i + 1)...jLimit {
                        let nextStart: VectorPoint? = (j + 1 < tour.count) ? tour[j + 1].startPoint : nil

                        // Current edges: prevEnd -> tour[i].start AND tour[j].end -> nextStart
                        var oldCost = prevEnd.distance(to: tour[i].startPoint)
                        if let ns = nextStart {
                            oldCost += tour[j].endPoint.distance(to: ns)
                        }

                        // Reversed segment [i...j] flips tour[j].endPoint to become the new start at i,
                        // and tour[i].startPoint to become the new end at j
                        var newCost = prevEnd.distance(to: tour[j].endPoint)
                        if let ns = nextStart {
                            newCost += tour[i].startPoint.distance(to: ns)
                        }

                        if newCost + 0.5 < oldCost {
                            // Reverse slice i...j and flip each path inside so internal transitions stay identical
                            var sub = Array(tour[i...j].reversed())
                            for k in 0..<sub.count {
                                sub[k] = sub[k].reversedPath()
                            }
                            tour.replaceSubrange(i...j, with: sub)
                            improved = true
                        }
                    }
                }
                if !improved { break }
            }
        }

        let optTravel = computeTravelDistance(tour)
        return (tour, rawTravel, min(rawTravel, optTravel))
    }

    public static func computeTravelDistance(_ paths: [VectorPath]) -> Double {
        guard !paths.isEmpty else { return 0 }
        var total = VectorPoint(x: 0, y: 0).distance(to: paths[0].startPoint)
        for i in 1..<paths.count {
            total += paths[i - 1].endPoint.distance(to: paths[i].startPoint)
        }
        return total
    }
}

// MARK: - High-Level Vectorization Engine

public enum VectorizationEngine {
    /// Stage A: Preprocess image, extract skeleton/contours via ANE/Vision/vDSP, trace & stitch paths, and classify by pen width.
    public static func extractStageA(
        image: RasterImage,
        params: VectorizerParams,
        progress: (@Sendable (String, Double) -> Void)? = nil
    ) -> RawExtractionStage {
        progress?(L("Prétraitement & transformée en distance…", "Preprocessing & distance transform…"), 0.12)
        let fields = NeuralRidgeFilter.preprocess(image: image, params: params)

        let rawPolylines: [[VectorPoint]]
        switch params.algorithm {
        case .neuralCenterline:
            progress?(L("Extraction crêtes ANE + squelette Guo-Hall…", "ANE ridge extraction + Guo-Hall skeleton…"), 0.28)
            let skel = CenterlineTracer.thinGuoHall(binary: fields.binary, width: fields.width, height: fields.height)
            progress?(L("Traçage sub-pixel de Steger & croisements…", "Steger sub-pixel tracing & junctions…"), 0.45)
            let traced = CenterlineTracer.traceSkeletonChains(
                skeleton: skel,
                fields: fields,
                minLength: params.minPathLengthPx,
                stegerSubpixel: params.stegerSubpixel,
                crossJunctions: params.crossJunctions
            )
            // Conservative pre-stitch before width measurement
            rawPolylines = CenterlineTracer.stitchPaths(traced, maxGap: min(4.0, params.maxStitchGapPx), continuity: 15.0)

        case .visionContours:
            progress?(L("Détection de contours Apple Vision (ANE)…", "Apple Vision contour detection (ANE)…"), 0.35)
            rawPolylines = NeuralRidgeFilter.extractVisionContours(image: image, fields: fields, params: params)

        case .skeletonize:
            progress?(L("Squelettisation morphologique Guo-Hall…", "Guo-Hall morphological skeletonization…"), 0.30)
            let skel = CenterlineTracer.thinGuoHall(binary: fields.binary, width: fields.width, height: fields.height)
            progress?(L("Traçage des chaînes connexes…", "Connected chain tracing…"), 0.45)
            let traced = CenterlineTracer.traceSkeletonChains(
                skeleton: skel,
                fields: fields,
                minLength: params.minPathLengthPx,
                stegerSubpixel: params.stegerSubpixel,
                crossJunctions: params.crossJunctions
            )
            rawPolylines = CenterlineTracer.stitchPaths(traced, maxGap: min(4.0, params.maxStitchGapPx), continuity: 10.0)

        case .cannyEdges:
            progress?(L("Filtre Canny double seuil + amincissement…", "Dual-threshold Canny + thinning…"), 0.32)
            let skel = NeuralRidgeFilter.extractCannySkeleton(image: image, params: params)
            rawPolylines = CenterlineTracer.traceSkeletonChains(
                skeleton: skel,
                fields: fields,
                minLength: params.minPathLengthPx,
                stegerSubpixel: params.stegerSubpixel,
                crossJunctions: false
            )
        }

        progress?(L("Classification multi-stylos & fusion…", "Multi-pen classification & stitching…"), 0.58)
        let (classified, breakpoints) = CenterlineTracer.measureAndClassifyPens(
            rawPaths: rawPolylines,
            fields: fields,
            params: params
        )

        var pathsByPen: [[(points: [VectorPoint], radiusPx: Double, pointRadiiPx: [Double], isHatch: Bool)]] = classified.map { bucket in
            bucket.map { ($0.points, $0.radiusPx, $0.pointRadiiPx, false) }
        }

        if params.hatchEnabled {
            progress?(L("Génération des hachures AxiDraw…", "Generating AxiDraw hatching…"), 0.65)
            let hatches = BezierAndPlotterOptimizer.generateHatchPaths(
                fields: fields,
                spacingPx: params.hatchSpacingPx,
                angleDeg: params.hatchAngleDeg,
                crossHatch: params.crossHatch
            )
            if !pathsByPen.isEmpty {
                pathsByPen[0].append(contentsOf: hatches.map { ($0, 0.6, [Double](repeating: 0.6, count: $0.count), true) })
            }
        }

        return RawExtractionStage(
            imageWidth: image.width,
            imageHeight: image.height,
            extractionCacheKey: params.extractionCacheKey,
            usedNeuralEngine: fields.usedNeuralEngine,
            pathsByPen: pathsByPen,
            breakpointsPx: breakpoints
        )
    }

    /// Stage B: RDP simplification, Schneider cubic Bézier fitting, variable-width ribbon envelope (in Illustration mode), 2-Opt AxiDraw tour optimization, metrics, and SVG output.
    public static func finalizeStageB(
        stageA: RawExtractionStage,
        params: VectorizerParams,
        existingVisibility: [Int: Bool] = [:],
        computeStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        progress: (@Sendable (String, Double) -> Void)? = nil
    ) -> VectorizationResult {
        progress?(L("Simplification RDP & courbes de Bézier (Schneider)…", "RDP simplification & Schneider Bézier fitting…"), 0.75)

        let penCount = max(1, min(4, params.penCount))
        var layers: [PenLayer] = []
        layers.reserveCapacity(penCount)

        var nextPathID = 1
        var totalRawTravelPx = 0.0
        var totalOptTravelPx = 0.0
        var totalDrawPx = 0.0
        var totalPoints = 0
        var totalBeziers = 0
        var totalLifts = 0

        let buildRibbons = (params.outputMode == .illustration && params.illustrationStrokeStyle == .variableRibbon)

        for penIdx in 0..<penCount {
            let rawItems = penIdx < stageA.pathsByPen.count ? stageA.pathsByPen[penIdx] : []
            var fittedPaths: [VectorPath] = []
            fittedPaths.reserveCapacity(rawItems.count)

            for item in rawItems {
                let (simplified, simplifiedRadii) = BezierAndPlotterOptimizer.simplifyRDPWithRadii(
                    item.points,
                    radii: item.pointRadiiPx,
                    epsilon: params.rdpTolerance
                )
                guard simplified.count >= 2 else { continue }
                let isClosed = simplified.count > 4 && simplified.first!.distance(to: simplified.last!) < 1.5
                let beziers: [CubicBezierSegment]
                if item.isHatch || params.curveSmoothing <= 0.02 {
                    beziers = []
                } else {
                    beziers = BezierAndPlotterOptimizer.fitCubicBeziers(
                        points: simplified,
                        smoothing: params.curveSmoothing,
                        cornerAngleDeg: params.cornerAngleDeg
                    )
                }

                let outlineBeziers: [CubicBezierSegment]
                if buildRibbons && !item.isHatch {
                    outlineBeziers = BezierAndPlotterOptimizer.buildVariableWidthRibbon(
                        points: simplified,
                        pointRadiiPx: simplifiedRadii,
                        beziers: beziers,
                        defaultRadiusPx: item.radiusPx,
                        scale: params.strokeWidthScale,
                        isClosed: isClosed
                    )
                } else {
                    outlineBeziers = []
                }

                let vp = VectorPath(
                    id: nextPathID,
                    penIndex: penIdx,
                    points: simplified,
                    beziers: beziers,
                    strokeRadiusPx: item.radiusPx,
                    pointRadiiPx: simplifiedRadii,
                    outlineBeziers: outlineBeziers,
                    isClosed: isClosed,
                    isHatch: item.isHatch
                )
                nextPathID += 1
                fittedPaths.append(vp)
            }

            progress?(L("Optimisation du parcours AxiDraw (2-opt)…", "Optimizing AxiDraw toolpath (2-opt)…"), 0.88)
            let (optimizedPaths, rawTravel, optTravel) = BezierAndPlotterOptimizer.optimizePlotterTour(
                paths: fittedPaths,
                enable2Opt: params.optimize2Opt
            )

            totalRawTravelPx += rawTravel
            totalOptTravelPx += optTravel
            for p in optimizedPaths {
                totalDrawPx += p.lengthPx
                totalPoints += p.points.count
                totalBeziers += p.beziers.count
            }
            if !optimizedPaths.isEmpty {
                totalLifts += optimizedPaths.count
            }

            let widthMM = penIdx < params.penWidthsMM.count
                ? params.penWidthsMM[penIdx]
                : kDefaultPenWidthsMM[penIdx % kDefaultPenWidthsMM.count]
            let isVis = existingVisibility[penIdx] ?? true
            layers.append(
                PenLayer(
                    index: penIdx,
                    widthMM: widthMM,
                    visible: isVis,
                    paths: optimizedPaths
                )
            )
        }

        let transform = PageTransform(
            imageWidth: stageA.imageWidth,
            imageHeight: stageA.imageHeight,
            params: params
        )

        let drawMM = totalDrawPx * transform.scalePxToMM
        let rawTravelMM = totalRawTravelPx * transform.scalePxToMM
        let optTravelMM = totalOptTravelPx * transform.scalePxToMM
        let savingsPct = rawTravelMM > 1e-3 ? max(0.0, ((rawTravelMM - optTravelMM) / rawTravelMM) * 100.0) : 0.0

        // Realistic AxiDraw V3 speed model:
        // Pen-down average speed ~ 38 mm/s, Pen-up rapid speed ~ 110 mm/s, Servo lift+drop cycle ~ 0.14 s
        let plotSeconds = (drawMM / 38.0) + (optTravelMM / 110.0) + Double(totalLifts) * 0.14
        let elapsedMs = max(0.1, (CFAbsoluteTimeGetCurrent() - computeStartTime) * 1000.0)

        var metrics = PlotterMetrics()
        metrics.imageWidth = stageA.imageWidth
        metrics.imageHeight = stageA.imageHeight
        metrics.pageWidthMM = transform.pageWidthMM
        metrics.pageHeightMM = transform.pageHeightMM
        metrics.pathCount = layers.reduce(0) { $0 + $1.paths.count }
        metrics.pointCount = totalPoints
        metrics.bezierSegmentCount = totalBeziers
        metrics.drawDistancePx = totalDrawPx
        metrics.drawDistanceMM = drawMM
        metrics.travelDistanceRawMM = rawTravelMM
        metrics.travelDistanceOptimizedMM = optTravelMM
        metrics.travelSavingsPercent = savingsPct
        metrics.penLifts = totalLifts
        metrics.estimatedPlotSeconds = plotSeconds
        metrics.computeMilliseconds = elapsedMs
        metrics.usedNeuralEngine = stageA.usedNeuralEngine
        metrics.penPathCounts = layers.map(\.paths.count)
        metrics.penBreakpointsPx = stageA.breakpointsPx

        progress?(L("Génération SVG AxiDraw…", "Generating AxiDraw SVG…"), 0.96)
        let svgPreview = SVGExporter.generateSVG(
            layers: layers,
            transform: transform,
            metrics: metrics,
            params: params,
            forPreview: true
        )
        let svgAxiDraw = SVGExporter.generateSVG(
            layers: layers,
            transform: transform,
            metrics: metrics,
            params: params,
            forPreview: false
        )
        progress?(L("Terminé", "Complete"), 1.0)

        return VectorizationResult(
            layers: layers,
            pageTransform: transform,
            metrics: metrics,
            svgPreview: svgPreview,
            svgAxiDraw: svgAxiDraw
        )
    }

    /// Full one-shot vectorization pipeline.
    public static func vectorize(
        image: RasterImage,
        params: VectorizerParams,
        progress: (@Sendable (String, Double) -> Void)? = nil
    ) -> (stageA: RawExtractionStage, result: VectorizationResult) {
        let start = CFAbsoluteTimeGetCurrent()
        let stageA = extractStageA(image: image, params: params, progress: progress)
        let result = finalizeStageB(stageA: stageA, params: params, computeStartTime: start, progress: progress)
        return (stageA, result)
    }

    /// Recomputes cubic Bézier segments for a modified path (e.g. after dragging vertices, simplifying, or freehand drawing).
    public static func refitPath(_ path: VectorPath, params: VectorizerParams) -> VectorPath {
        guard path.points.count >= 2 else { return path }
        let isClosed = path.points.count > 4 && path.points.first!.distance(to: path.points.last!) < 1.5
        let beziers: [CubicBezierSegment]
        if path.isHatch || params.curveSmoothing <= 0.02 {
            beziers = []
        } else {
            beziers = BezierAndPlotterOptimizer.fitCubicBeziers(
                points: path.points,
                smoothing: params.curveSmoothing,
                cornerAngleDeg: params.cornerAngleDeg
            )
        }
        let radii: [Double]
        if path.pointRadiiPx.count == path.points.count {
            radii = path.pointRadiiPx
        } else {
            radii = [Double](repeating: path.strokeRadiusPx, count: path.points.count)
        }
        let outlineBeziers: [CubicBezierSegment]
        if params.outputMode == .illustration && params.illustrationStrokeStyle == .variableRibbon && !path.isHatch {
            outlineBeziers = BezierAndPlotterOptimizer.buildVariableWidthRibbon(
                points: path.points,
                pointRadiiPx: radii,
                beziers: beziers,
                defaultRadiusPx: path.strokeRadiusPx,
                scale: params.strokeWidthScale,
                isClosed: isClosed
            )
        } else {
            outlineBeziers = []
        }
        return VectorPath(
            id: path.id,
            penIndex: path.penIndex,
            points: path.points,
            beziers: beziers,
            strokeRadiusPx: path.strokeRadiusPx,
            pointRadiiPx: radii,
            outlineBeziers: outlineBeziers,
            isClosed: isClosed,
            isHatch: path.isHatch
        )
    }

    /// Rebuilds a `VectorizationResult` (metrics + SVG preview + AxiDraw SVG) from interactively edited `PenLayer`s.
    public static func rebuildFromEditedLayers(
        layers: [PenLayer],
        imageWidth: Int,
        imageHeight: Int,
        params: VectorizerParams,
        usedNeuralEngine: Bool = true,
        breakpointsPx: [Double] = [],
        reoptimizeTour: Bool = false
    ) -> VectorizationResult {
        var updatedLayers = layers
        var totalRawTravelPx = 0.0
        var totalOptTravelPx = 0.0
        var totalDrawPx = 0.0
        var totalPoints = 0
        var totalBeziers = 0
        var totalLifts = 0

        for idx in updatedLayers.indices {
            let paths = updatedLayers[idx].paths
            let finalPaths: [VectorPath]
            let rawT: Double
            let optT: Double
            if reoptimizeTour {
                (finalPaths, rawT, optT) = BezierAndPlotterOptimizer.optimizePlotterTour(
                    paths: paths,
                    enable2Opt: params.optimize2Opt
                )
                updatedLayers[idx].paths = finalPaths
            } else {
                finalPaths = paths
                let t = BezierAndPlotterOptimizer.computeTravelDistance(paths)
                rawT = t
                optT = t
            }
            totalRawTravelPx += rawT
            totalOptTravelPx += optT
            for p in finalPaths {
                totalDrawPx += p.lengthPx
                totalPoints += p.points.count
                totalBeziers += p.beziers.count
            }
            if !finalPaths.isEmpty {
                totalLifts += finalPaths.count
            }
        }

        let transform = PageTransform(imageWidth: imageWidth, imageHeight: imageHeight, params: params)
        let drawMM = totalDrawPx * transform.scalePxToMM
        let rawTravelMM = totalRawTravelPx * transform.scalePxToMM
        let optTravelMM = totalOptTravelPx * transform.scalePxToMM
        let savingsPct = rawTravelMM > 1e-3 ? max(0.0, ((rawTravelMM - optTravelMM) / rawTravelMM) * 100.0) : 0.0
        let plotSeconds = (drawMM / 38.0) + (optTravelMM / 110.0) + Double(totalLifts) * 0.14

        var metrics = PlotterMetrics()
        metrics.imageWidth = imageWidth
        metrics.imageHeight = imageHeight
        metrics.pageWidthMM = transform.pageWidthMM
        metrics.pageHeightMM = transform.pageHeightMM
        metrics.pathCount = updatedLayers.reduce(0) { $0 + $1.paths.count }
        metrics.pointCount = totalPoints
        metrics.bezierSegmentCount = totalBeziers
        metrics.drawDistancePx = totalDrawPx
        metrics.drawDistanceMM = drawMM
        metrics.travelDistanceRawMM = rawTravelMM
        metrics.travelDistanceOptimizedMM = optTravelMM
        metrics.travelSavingsPercent = savingsPct
        metrics.penLifts = totalLifts
        metrics.estimatedPlotSeconds = plotSeconds
        metrics.computeMilliseconds = 1.0
        metrics.usedNeuralEngine = usedNeuralEngine
        metrics.penPathCounts = updatedLayers.map(\.paths.count)
        metrics.penBreakpointsPx = breakpointsPx

        let svgPreview = SVGExporter.generateSVG(
            layers: updatedLayers,
            transform: transform,
            metrics: metrics,
            params: params,
            forPreview: true
        )
        let svgAxiDraw = SVGExporter.generateSVG(
            layers: updatedLayers,
            transform: transform,
            metrics: metrics,
            params: params,
            forPreview: false
        )
        return VectorizationResult(
            layers: updatedLayers,
            pageTransform: transform,
            metrics: metrics,
            svgPreview: svgPreview,
            svgAxiDraw: svgAxiDraw
        )
    }
}
