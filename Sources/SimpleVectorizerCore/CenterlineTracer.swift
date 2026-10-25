import Foundation

/// Topological thinning (LUT-accelerated Guo-Hall), Steger Hessian sub-pixel centerline refinement,
/// collinear junction crossing, multi-pass tangent stitching, and Distance-Transform k-means pen classification.
public enum CenterlineTracer {

    // MARK: - 256-Entry Precomputed Lookup Tables for Guo-Hall Thinning

    /// Neighbor bit order (clockwise from top):
    /// `p2(0,-1)=bit0, p3(1,-1)=bit1, p4(1,0)=bit2, p5(1,1)=bit3, p6(0,1)=bit4, p7(-1,1)=bit5, p8(-1,0)=bit6, p9(-1,-1)=bit7`
    private static let lutSub0: [Bool] = buildGuoHallLUT(subiteration: 0)
    private static let lutSub1: [Bool] = buildGuoHallLUT(subiteration: 1)

    private static func buildGuoHallLUT(subiteration: Int) -> [Bool] {
        var table = [Bool](repeating: false, count: 256)
        for mask in 0..<256 {
            let p2 = (mask >> 0) & 1
            let p3 = (mask >> 1) & 1
            let p4 = (mask >> 2) & 1
            let p5 = (mask >> 3) & 1
            let p6 = (mask >> 4) & 1
            let p7 = (mask >> 5) & 1
            let p8 = (mask >> 6) & 1
            let p9 = (mask >> 7) & 1

            let c = ((~p2 & (p3 | p4))
                + (~p4 & (p5 | p6))
                + (~p6 & (p7 | p8))
                + (~p8 & (p9 | p2))) & 0xFF

            guard c == 1 else { continue }

            let n1 = (p9 | p2) + (p3 | p4) + (p5 | p6) + (p7 | p8)
            let n2 = (p2 | p3) + (p4 | p5) + (p6 | p7) + (p8 | p9)
            let n = min(n1, n2)
            guard n >= 2 && n <= 3 else { continue }

            let m: Int
            if subiteration == 0 {
                m = (p2 | p3 | (~p5 & 1)) & p4
            } else {
                m = (p6 | p7 | (~p9 & 1)) & p8
            }
            if m == 0 {
                table[mask] = true
            }
        }
        return table
    }

    /// LUT-accelerated Guo-Hall morphological skeletonization + staircase diagonal pruning.
    public static func thinGuoHall(binary: [UInt8], width: Int, height: Int, maxIterations: Int = 120) -> [UInt8] {
        guard width >= 3, height >= 3 else { return binary }
        var img = binary

        // Clear 1px border so inner loop never needs bounds checks
        for x in 0..<width {
            img[x] = 0
            img[(height - 1) * width + x] = 0
        }
        for y in 0..<height {
            img[y * width] = 0
            img[y * width + (width - 1)] = 0
        }

        // Collect initial foreground coordinates to iterate only over active ink pixels
        var active: [Int] = []
        active.reserveCapacity(width * height / 8)
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) where img[row + x] != 0 {
                active.append(row + x)
            }
        }

        var toDelete: [Int] = []
        toDelete.reserveCapacity(4096)

        for _ in 0..<maxIterations {
            var changed = false
            for sub in 0...1 {
                let lut = (sub == 0) ? lutSub0 : lutSub1
                toDelete.removeAll(keepingCapacity: true)

                for idx in active where img[idx] != 0 {
                    let p2 = Int(img[idx - width])
                    let p3 = Int(img[idx - width + 1])
                    let p4 = Int(img[idx + 1])
                    let p5 = Int(img[idx + width + 1])
                    let p6 = Int(img[idx + width])
                    let p7 = Int(img[idx + width - 1])
                    let p8 = Int(img[idx - 1])
                    let p9 = Int(img[idx - width - 1])

                    let mask = p2 | (p3 << 1) | (p4 << 2) | (p5 << 3)
                        | (p6 << 4) | (p7 << 5) | (p8 << 6) | (p9 << 7)
                    if lut[mask] {
                        toDelete.append(idx)
                    }
                }

                if !toDelete.isEmpty {
                    changed = true
                    for idx in toDelete {
                        img[idx] = 0
                    }
                }
            }
            if !changed { break }
            active.removeAll { img[$0] == 0 }
        }

        // Staircase / L-elbow cleanup pass: removes redundant 4-connected corner pixels when diagonal neighbor exists
        toDelete.removeAll(keepingCapacity: true)
        for idx in active where img[idx] != 0 {
            let n = img[idx - width] != 0
            let s = img[idx + width] != 0
            let e = img[idx + 1] != 0
            let w = img[idx - 1] != 0
            let ne = img[idx - width + 1] != 0
            let nw = img[idx - width - 1] != 0
            let se = img[idx + width + 1] != 0
            let sw = img[idx + width - 1] != 0

            let isStairNE = n && e && !sw && !w && !s && !nw && !se && !ne
            let isStairNW = n && w && !se && !e && !s && !ne && !sw && !nw
            let isStairSE = s && e && !nw && !w && !n && !ne && !sw && !se
            let isStairSW = s && w && !ne && !e && !n && !nw && !se && !sw
            if isStairNE || isStairNW || isStairSE || isStairSW {
                toDelete.append(idx)
            }
        }
        for idx in toDelete {
            img[idx] = 0
        }

        return img
    }

    // MARK: - Steger Hessian Sub-Pixel Centerline Refinement

    /// Shifts integer skeleton coordinates `(x, y)` to sub-pixel ridge centers using 2nd-order Taylor expansion of `fields.ridgeField`.
    public static func refinePointSubpixel(
        x: Int,
        y: Int,
        fields: PreprocessedFields
    ) -> VectorPoint {
        let w = fields.width
        let h = fields.height
        guard x >= 1, x < w - 1, y >= 1, y < h - 1 else {
            return VectorPoint(x: Double(x), y: Double(y))
        }

        let r = fields.ridgeField
        let row = y * w
        let c = Double(r[row + x])
        let rx = 0.5 * Double(r[row + x + 1] - r[row + x - 1])
        let ry = 0.5 * Double(r[(y + 1) * w + x] - r[(y - 1) * w + x])
        let rxx = Double(r[row + x + 1]) - 2.0 * c + Double(r[row + x - 1])
        let ryy = Double(r[(y + 1) * w + x]) - 2.0 * c + Double(r[(y - 1) * w + x])
        let rxy = 0.25 * Double(
            r[(y + 1) * w + x + 1]
            - r[(y + 1) * w + x - 1]
            - r[(y - 1) * w + x + 1]
            + r[(y - 1) * w + x - 1]
        )

        // Eigenvector corresponding to minimum (most negative) eigenvalue of Hessian
        let diff = rxx - ryy
        let disc = (diff * diff + 4.0 * rxy * rxy).squareRoot()
        let lambdaMin = 0.5 * (rxx + ryy - disc)

        var nx: Double
        var ny: Double
        if abs(rxy) > 1e-6 {
            nx = lambdaMin - ryy
            ny = rxy
        } else if rxx < ryy {
            nx = 1.0
            ny = 0.0
        } else {
            nx = 0.0
            ny = 1.0
        }
        let norm = (nx * nx + ny * ny).squareRoot()
        guard norm > 1e-8 else {
            return VectorPoint(x: Double(x), y: Double(y))
        }
        nx /= norm
        ny /= norm

        let denom = rxx * nx * nx + 2.0 * rxy * nx * ny + ryy * ny * ny
        guard denom < -1e-5 else {
            return VectorPoint(x: Double(x), y: Double(y))
        }

        let t = max(-0.55, min(0.55, -(rx * nx + ry * ny) / denom))
        return VectorPoint(x: Double(x) + t * nx, y: Double(y) + t * ny)
    }

    // MARK: - Graph Chain Tracing + Collinear Junction Crossing

    public static func traceSkeletonChains(
        skeleton: [UInt8],
        fields: PreprocessedFields,
        minLength: Int,
        stegerSubpixel: Bool,
        crossJunctions: Bool
    ) -> [[VectorPoint]] {
        let w = fields.width
        let h = fields.height
        guard w >= 3, h >= 3 else { return [] }

        var work = skeleton
        let dy = [-1, -1, -1, 0, 0, 1, 1, 1]
        let dx = [-1, 0, 1, -1, 1, -1, 0, 1]
        let offsets = dy.enumerated().map { $1 * w + dx[$0] }

        // Compute 8-neighbor degree for each skeleton pixel
        var degree = [UInt8](repeating: 0, count: w * h)
        var endpoints: [Int] = []
        var junctions: [Int] = []
        var allPixels: [Int] = []

        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) where work[row + x] != 0 {
                let idx = row + x
                var d: UInt8 = 0
                for off in offsets where work[idx + off] != 0 {
                    d += 1
                }
                degree[idx] = d
                allPixels.append(idx)
                if d == 1 {
                    endpoints.append(idx)
                } else if d >= 3 {
                    junctions.append(idx)
                }
            }
        }

        var rawChains: [[Int]] = []

        @inline(__always)
        func traceFrom(_ startIdx: Int) -> [Int] {
            guard work[startIdx] != 0 else { return [] }
            work[startIdx] = 0
            var chain = [startIdx]
            var curr = startIdx
            var prevDirX = 0
            var prevDirY = 0

            while true {
                var bestNext = -1
                var bestScore = -1000
                let cy = curr / w
                let cx = curr % w

                for k in 0..<8 {
                    let nidx = curr + offsets[k]
                    if work[nidx] != 0 {
                        // Prefer 4-neighbors slightly or continuation of previous direction
                        let ndx = dx[k]
                        let ndy = dy[k]
                        let dirDot = ndx * prevDirX + ndy * prevDirY
                        let orthoBonus = (ndx == 0 || ndy == 0) ? 2 : 1
                        let score = dirDot * 4 + orthoBonus
                        if score > bestScore {
                            bestScore = score
                            bestNext = nidx
                        }
                    }
                }

                guard bestNext >= 0 else { break }
                let ny = bestNext / w
                let nx = bestNext % w
                prevDirX = nx - cx
                prevDirY = ny - cy
                work[bestNext] = 0
                chain.append(bestNext)
                curr = bestNext

                // Stop at junctions so branches stay clean and can be paired by collinear angle
                if degree[curr] >= 3 {
                    break
                }
            }
            return chain
        }

        // Phase 1: trace from degree-1 endpoints
        for ep in endpoints where work[ep] != 0 {
            let c = traceFrom(ep)
            if c.count >= 2 { rawChains.append(c) }
        }

        // Phase 2: trace branches from junction neighbors
        for jIdx in junctions {
            work[jIdx] = 0
            for off in offsets {
                let nIdx = jIdx + off
                if work[nIdx] != 0 {
                    var c = traceFrom(nIdx)
                    c.insert(jIdx, at: 0)
                    if c.count >= 2 { rawChains.append(c) }
                }
            }
        }

        // Phase 3: trace any remaining closed loops
        for idx in allPixels where work[idx] != 0 {
            var c = traceFrom(idx)
            if c.count >= 3 {
                // Close the loop if end is adjacent to start
                let sy = c[0] / w, sx = c[0] % w
                let ey = c.last! / w, ex = c.last! % w
                if abs(sx - ex) <= 1 && abs(sy - ey) <= 1 {
                    c.append(c[0])
                }
                rawChains.append(c)
            }
        }

        // Convert integer pixel indices to sub-pixel VectorPoints
        var pointPaths: [[VectorPoint]] = []
        pointPaths.reserveCapacity(rawChains.count)

        for chain in rawChains {
            guard chain.count >= max(2, minLength) || (chain.count >= 2 && crossJunctions) else { continue }
            var pts = [VectorPoint]()
            pts.reserveCapacity(chain.count)
            for idx in chain {
                let y = idx / w
                let x = idx % w
                if stegerSubpixel {
                    pts.append(refinePointSubpixel(x: x, y: y, fields: fields))
                } else {
                    pts.append(VectorPoint(x: Double(x), y: Double(y)))
                }
            }
            // Gentle endpoint-preserving 3-tap coordinate smoothing
            if stegerSubpixel && pts.count >= 4 {
                var smoothed = pts
                for i in 1..<(pts.count - 1) {
                    smoothed[i] = VectorPoint(
                        x: 0.25 * pts[i - 1].x + 0.5 * pts[i].x + 0.25 * pts[i + 1].x,
                        y: 0.25 * pts[i - 1].y + 0.5 * pts[i].y + 0.25 * pts[i + 1].y
                    )
                }
                pts = smoothed
            }
            pointPaths.append(pts)
        }

        // Optional Collinear Junction Crossing: merge branches that meet at a junction with near-180° collinear tangents
        if crossJunctions && pointPaths.count > 1 {
            pointPaths = mergeCollinearJunctions(pointPaths, maxJunctionGap: 3.2)
        }

        // Filter by minimum path length
        let minLen = max(2, minLength)
        return pointPaths.filter { $0.count >= minLen }
    }

    // MARK: - Collinear X / T Junction Crossing

    /// Pairs chains whose endpoints meet within `maxJunctionGap` and whose outward tangents point in opposite directions (`cos < -0.60`),
    /// allowing crossing strokes in line drawings to stay continuous through intersections.
    public static func mergeCollinearJunctions(_ paths: [[VectorPoint]], maxJunctionGap: Double) -> [[VectorPoint]] {
        let current = paths
        let gapSq = maxJunctionGap * maxJunctionGap
        var mergedFlags = [Bool](repeating: false, count: current.count)
        var output: [[VectorPoint]] = []
        output.reserveCapacity(current.count)

        let order = current.indices.sorted { current[$0].count > current[$1].count }

        for seedIdx in order {
            if mergedFlags[seedIdx] { continue }
            mergedFlags[seedIdx] = true
            var chain = current[seedIdx]

            var keepGrowing = true
            while keepGrowing {
                keepGrowing = false
                for atEnd in [true, false] {
                    let probe = atEnd ? chain.last! : chain.first!
                    let lookback = min(5, chain.count - 1)
                    guard lookback >= 1 else { continue }
                    let refPt = atEnd ? chain[chain.count - 1 - lookback] : chain[lookback]
                    let tx = probe.x - refPt.x
                    let ty = probe.y - refPt.y
                    let tNorm = (tx * tx + ty * ty).squareRoot()
                    guard tNorm > 1e-5 else { continue }
                    let ux = tx / tNorm
                    let uy = ty / tNorm

                    var bestIdx = -1
                    var bestEnd = false
                    var bestCos = 0.55 // require forward alignment > ~56°

                    for candIdx in 0..<current.count where !mergedFlags[candIdx] {
                        let cand = current[candIdx]
                        guard cand.count >= 2 else { continue }
                        let lb2 = min(5, cand.count - 1)

                        let dStartSq = probe.distanceSquared(to: cand.first!)
                        if dStartSq <= gapSq {
                            let dx2 = cand[lb2].x - cand[0].x
                            let dy2 = cand[lb2].y - cand[0].y
                            let n2 = (dx2 * dx2 + dy2 * dy2).squareRoot()
                            if n2 > 1e-5 {
                                let cosVal = (ux * dx2 + uy * dy2) / n2
                                if cosVal > bestCos {
                                    bestCos = cosVal
                                    bestIdx = candIdx
                                    bestEnd = false
                                }
                            }
                        }

                        let dEndSq = probe.distanceSquared(to: cand.last!)
                        if dEndSq <= gapSq {
                            let dx2 = cand[cand.count - 1 - lb2].x - cand.last!.x
                            let dy2 = cand[cand.count - 1 - lb2].y - cand.last!.y
                            let n2 = (dx2 * dx2 + dy2 * dy2).squareRoot()
                            if n2 > 1e-5 {
                                let cosVal = (ux * dx2 + uy * dy2) / n2
                                if cosVal > bestCos {
                                    bestCos = cosVal
                                    bestIdx = candIdx
                                    bestEnd = true
                                }
                            }
                        }
                    }

                    if bestIdx >= 0 {
                        mergedFlags[bestIdx] = true
                        let cand = current[bestIdx]
                        let oriented = bestEnd ? Array(cand.reversed()) : cand
                        if atEnd {
                            let dropFirst = probe.distanceSquared(to: oriented[0]) < 1.1 ? 1 : 0
                            chain.append(contentsOf: oriented.dropFirst(dropFirst))
                        } else {
                            let rev = Array(oriented.reversed())
                            let dropLast = probe.distanceSquared(to: rev.last!) < 1.1 ? 1 : 0
                            chain = Array(rev.dropLast(dropLast)) + chain
                        }
                        keepGrowing = true
                        break
                    }
                }
            }
            output.append(chain)
        }

        return output
    }

    // MARK: - Multi-Pass Spatial-Grid Path Stitching

    public static func stitchPaths(
        _ paths: [[VectorPoint]],
        maxGap: Double,
        continuity: Double
    ) -> [[VectorPoint]] {
        guard paths.count > 1, maxGap > 0.5 else { return paths }

        let c = max(0.0, min(1.0, continuity / 100.0))
        let nPasses = 1 + Int(c * 2.0)
        let multipliers = [1.0, 1.4 + c * 0.8, 1.8 + c * 1.4].prefix(nPasses)
        let cosReject = -0.25 - c * 0.65

        var currentPaths = paths

        for mult in multipliers {
            let gap = maxGap * mult
            let gapSq = gap * gap
            if currentPaths.count <= 1 { break }

            let cellSize = max(4.0, gap)
            struct EndpointEntry {
                let pt: VectorPoint
                let pathIdx: Int
                let isEnd: Bool
            }

            var grid: [Int64: [EndpointEntry]] = [:]
            @inline(__always)
            func cellKey(_ x: Int, _ y: Int) -> Int64 {
                (Int64(x) << 32) ^ Int64(UInt32(bitPattern: Int32(y)))
            }

            for (i, p) in currentPaths.enumerated() where p.count >= 2 {
                // Never stitch closed loops to other paths
                if p.count > 4 && p.first!.distance(to: p.last!) < 2.5 { continue }
                let s = p.first!
                let e = p.last!
                let sx = Int(floor(s.x / cellSize))
                let sy = Int(floor(s.y / cellSize))
                grid[cellKey(sx, sy), default: []].append(EndpointEntry(pt: s, pathIdx: i, isEnd: false))

                let ex = Int(floor(e.x / cellSize))
                let ey = Int(floor(e.y / cellSize))
                grid[cellKey(ex, ey), default: []].append(EndpointEntry(pt: e, pathIdx: i, isEnd: true))
            }

            var merged = [Bool](repeating: false, count: currentPaths.count)
            var result: [[VectorPoint]] = []
            result.reserveCapacity(currentPaths.count)

            let order = currentPaths.indices.sorted { currentPaths[$0].count > currentPaths[$1].count }

            for idx in order {
                if merged[idx] { continue }
                merged[idx] = true
                var cur = currentPaths[idx]
                if cur.count > 4 && cur.first!.distance(to: cur.last!) < 2.5 {
                    result.append(cur)
                    continue
                }

                var changed = true
                while changed {
                    changed = false
                    for tryEnd in [true, false] {
                        guard cur.count >= 2 else { continue }
                        let probe = tryEnd ? cur.last! : cur.first!
                        let lb = min(4, cur.count - 1)
                        let refPt = tryEnd ? cur[cur.count - 1 - lb] : cur[lb]
                        let tx = probe.x - refPt.x
                        let ty = probe.y - refPt.y
                        let tNorm = (tx * tx + ty * ty).squareRoot()

                        let cx = Int(floor(probe.x / cellSize))
                        let cy = Int(floor(probe.y / cellSize))

                        var bestCandIdx = -1
                        var bestIsEnd = false
                        var bestScore = Double.greatestFiniteMagnitude

                        for dyCell in -1...1 {
                            for dxCell in -1...1 {
                                guard let bucket = grid[cellKey(cx + dxCell, cy + dyCell)] else { continue }
                                for entry in bucket {
                                    if merged[entry.pathIdx] || entry.pathIdx == idx { continue }
                                    let dSq = probe.distanceSquared(to: entry.pt)
                                    if dSq > gapSq { continue }
                                    let d = dSq.squareRoot()

                                    let cand = currentPaths[entry.pathIdx]
                                    var cosVal = 1.0
                                    if tNorm > 1e-5 && cand.count >= 2 {
                                        let lb2 = min(4, cand.count - 1)
                                        let d2x: Double
                                        let d2y: Double
                                        if entry.isEnd {
                                            d2x = cand[cand.count - 1 - lb2].x - cand.last!.x
                                            d2y = cand[cand.count - 1 - lb2].y - cand.last!.y
                                        } else {
                                            d2x = cand[lb2].x - cand[0].x
                                            d2y = cand[lb2].y - cand[0].y
                                        }
                                        let n2 = (d2x * d2x + d2y * d2y).squareRoot()
                                        if n2 > 1e-5 {
                                            cosVal = (tx * d2x + ty * d2y) / (tNorm * n2)
                                            if cosVal < cosReject { continue }
                                        }
                                    }

                                    let score = d * (1.5 - max(0.0, cosVal))
                                    if score < bestScore {
                                        bestScore = score
                                        bestCandIdx = entry.pathIdx
                                        bestIsEnd = entry.isEnd
                                    }
                                }
                            }
                        }

                        if bestCandIdx >= 0 {
                            merged[bestCandIdx] = true
                            let cand = currentPaths[bestCandIdx]
                            let ordered = bestIsEnd ? Array(cand.reversed()) : cand
                            if tryEnd {
                                cur.append(contentsOf: ordered)
                            } else {
                                cur = Array(ordered.reversed()) + cur
                            }
                            changed = true
                            break
                        }
                    }
                }
                result.append(cur)
            }
            currentPaths = result
        }

        return currentPaths
    }

    // MARK: - Stroke Width Measurement & 1D K-Means Multi-Pen Classification

    public static func measureAndClassifyPens(
        rawPaths: [[VectorPoint]],
        fields: PreprocessedFields,
        params: VectorizerParams
    ) -> (pathsByPen: [[(points: [VectorPoint], radiusPx: Double, pointRadiiPx: [Double])]], breakpoints: [Double]) {
        let penCount = max(1, min(4, params.penCount))
        let w = fields.width
        let h = fields.height

        let searchWin = (params.algorithm == .visionContours || params.algorithm == .cannyEdges) ? 2 : 1
        @inline(__always)
        func sampleRadius(at pt: VectorPoint) -> Float {
            let px = Int(pt.x.rounded())
            let py = Int(pt.y.rounded())
            guard px >= 0, px < w, py >= 0, py < h else { return 0.6 }
            var best: Float = fields.distanceField[py * w + px]
            let y0 = max(0, py - searchWin)
            let y1 = min(h - 1, py + searchWin)
            let x0 = max(0, px - searchWin)
            let x1 = min(w - 1, px + searchWin)
            for ny in y0...y1 {
                let row = ny * w
                for nx in x0...x1 {
                    let v = fields.distanceField[row + nx]
                    if v > best { best = v }
                }
            }
            return max(0.5, best)
        }

        func measurePathProfile(_ path: [VectorPoint]) -> (radiusPx: Double, pointRadiiPx: [Double]) {
            guard !path.isEmpty else { return (1.0, []) }
            var raw = [Double](repeating: 1.0, count: path.count)
            for i in 0..<path.count {
                raw[i] = Double(sampleRadius(at: path[i]))
            }
            // Smooth 1D radius profile along the stroke (3 passes of [0.25, 0.5, 0.25]) to remove pixel quantization
            if raw.count >= 3 {
                var tmp = raw
                for _ in 0..<3 {
                    tmp[0] = 0.7 * raw[0] + 0.3 * raw[1]
                    for i in 1..<(raw.count - 1) {
                        tmp[i] = 0.25 * raw[i - 1] + 0.5 * raw[i] + 0.25 * raw[i + 1]
                    }
                    tmp[raw.count - 1] = 0.3 * raw[raw.count - 2] + 0.7 * raw[raw.count - 1]
                    raw = tmp
                }
            }
            let sorted = raw.sorted()
            let p75 = sorted[min(sorted.count - 1, (sorted.count * 3) / 4)]
            return (max(0.5, p75), raw)
        }

        // Measure 75th-percentile Distance Transform stroke half-width along each raw path
        var radii = [Double](repeating: 1.0, count: rawPaths.count)
        for (idx, path) in rawPaths.enumerated() {
            let step = max(1, path.count / 48)
            var samples: [Float] = []
            samples.reserveCapacity(min(64, path.count))
            var j = 0
            while j < path.count {
                let d = sampleRadius(at: path[j])
                if d > 0 { samples.append(d) }
                j += step
            }
            if samples.count >= 3 {
                samples.sort()
                let p75Idx = min(samples.count - 1, (samples.count * 3) / 4)
                radii[idx] = Double(samples[p75Idx])
            } else if let first = samples.first {
                radii[idx] = Double(first)
            }
        }

        if penCount <= 1 || rawPaths.isEmpty {
            let stitched = stitchPaths(rawPaths, maxGap: params.maxStitchGapPx, continuity: params.continuity)
            let single = stitched.map { path -> (points: [VectorPoint], radiusPx: Double, pointRadiiPx: [Double]) in
                let prof = measurePathProfile(path)
                return (path, prof.radiusPx, prof.pointRadiiPx)
            }
            return ([single], [])
        }

        let validRadii = radii.filter { $0 > 0 }
        let breakpoints = kmeans1DBreakpoints(values: validRadii, k: penCount)

        var buckets = Array(repeating: [[VectorPoint]](), count: penCount)
        for (path, r) in zip(rawPaths, radii) {
            var pen = 0
            for (k, bp) in breakpoints.enumerated() where r > bp {
                pen = k + 1
            }
            buckets[min(pen, penCount - 1)].append(path)
        }

        // Stitch within each pen layer and measure full stroke radius profile
        var finalBuckets = Array(repeating: [(points: [VectorPoint], radiusPx: Double, pointRadiiPx: [Double])](), count: penCount)
        for penIdx in 0..<penCount {
            let stitched = stitchPaths(buckets[penIdx], maxGap: params.maxStitchGapPx, continuity: params.continuity)
            finalBuckets[penIdx] = stitched.map { path in
                let prof = measurePathProfile(path)
                return (path, prof.radiusPx, prof.pointRadiiPx)
            }
        }

        return (finalBuckets, breakpoints)
    }

    public static func kmeans1DBreakpoints(values: [Double], k: Int, maxIterations: Int = 25) -> [Double] {
        guard values.count >= k, k > 1 else { return [] }
        let sorted = values.sorted()
        var centroids = (1...k).map { i -> Double in
            let q = Double(i) / Double(k + 1)
            let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * q)))
            return sorted[idx]
        }

        for _ in 0..<maxIterations {
            var sums = [Double](repeating: 0, count: k)
            var counts = [Int](repeating: 0, count: k)

            for v in sorted {
                var bestC = 0
                var bestDist = abs(v - centroids[0])
                for cIdx in 1..<k {
                    let d = abs(v - centroids[cIdx])
                    if d < bestDist {
                        bestDist = d
                        bestC = cIdx
                    }
                }
                sums[bestC] += v
                counts[bestC] += 1
            }

            var maxShift = 0.0
            for cIdx in 0..<k where counts[cIdx] > 0 {
                let newC = sums[cIdx] / Double(counts[cIdx])
                maxShift = max(maxShift, abs(newC - centroids[cIdx]))
                centroids[cIdx] = newC
            }
            if maxShift < 0.01 { break }
        }

        centroids.sort()
        return (0..<(k - 1)).map { (centroids[$0] + centroids[$0 + 1]) * 0.5 }
    }
}
