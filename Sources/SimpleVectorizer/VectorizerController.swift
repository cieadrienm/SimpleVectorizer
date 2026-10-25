import AppKit
import Darwin
import Foundation
import Observation
import SimpleVectorizerCore
import SwiftUI

/// Pre-built image-space `Path`s and 8×8 spatial tile buckets for 120 Hz resolution-independent vector rendering.
struct VectorRenderCache: Sendable {
    struct SpatialBucket: Sendable {
        var gridIndex: Int
        var boundsPx: CGRect
        var pathPx: Path
        var filledRibbonPathPx: Path
        var handlesPx: Path
    }

    struct WidthBandCache: Sendable {
        let radiusPx: CGFloat
        let fullPathPx: Path
        let bucketPathsPx: [Int: Path]
    }

    struct LayerCache: Sendable {
        let index: Int
        let fullPathPx: Path
        let fullFilledRibbonPathPx: Path
        let fullHandlesPx: Path
        let buckets: [SpatialBucket]
        let widthBands: [WidthBandCache]
        let pathByID: [Int: Path]
        let ribbonByID: [Int: Path]
        let handlesByID: [Int: Path]
        let boundsByID: [Int: CGRect]
    }

    let layers: [LayerCache]
    let fullTravelPathPx: Path
    let boundsByPathID: [Int: CGRect]

    static func build(from result: VectorizationResult) -> VectorRenderCache {
        let imgW = max(1.0, CGFloat(result.pageTransform.imageWidth))
        let imgH = max(1.0, CGFloat(result.pageTransform.imageHeight))
        let gridCols = 8
        let gridRows = 8
        let cellW = max(1.0, imgW / CGFloat(gridCols))
        let cellH = max(1.0, imgH / CGFloat(gridRows))

        var layerCaches: [LayerCache] = []
        layerCaches.reserveCapacity(result.layers.count)
        var allBoundsByID: [Int: CGRect] = [:]

        var travelPath = Path()
        var prevEnd = CGPoint.zero

        for layer in result.layers {
            var fullPath = Path()
            var fullFilledRibbonPath = Path()
            var fullHandles = Path()
            var gridPaths = [Path](repeating: Path(), count: gridCols * gridRows)
            var gridRibbonPaths = [Path](repeating: Path(), count: gridCols * gridRows)
            var gridHandles = [Path](repeating: Path(), count: gridCols * gridRows)
            var gridBounds = [CGRect?](repeating: nil, count: gridCols * gridRows)
            var pathByID: [Int: Path] = [:]
            var ribbonByID: [Int: Path] = [:]
            var handlesByID: [Int: Path] = [:]
            var boundsByID: [Int: CGRect] = [:]
            pathByID.reserveCapacity(layer.paths.count)
            boundsByID.reserveCapacity(layer.paths.count)

            // Quantize per-stroke radius into 0.25 px steps for fast batched rendering in `.perStrokeWidth` mode
            var bandFullPaths: [Int: Path] = [:]
            var bandBucketPaths: [Int: [Int: Path]] = [:]

            for vp in layer.paths {
                if layer.visible {
                    let s = CGPoint(x: vp.startPoint.x, y: vp.startPoint.y)
                    travelPath.move(to: prevEnd)
                    travelPath.addLine(to: s)
                    prevEnd = CGPoint(x: vp.endPoint.x, y: vp.endPoint.y)
                }

                var singlePath = Path()
                var singleRibbon = Path()
                var singleHandles = Path()
                var minX = CGFloat.greatestFiniteMagnitude
                var minY = CGFloat.greatestFiniteMagnitude
                var maxX = -CGFloat.greatestFiniteMagnitude
                var maxY = -CGFloat.greatestFiniteMagnitude

                @inline(__always)
                func includePt(_ p: CGPoint) {
                    if p.x < minX { minX = p.x }
                    if p.y < minY { minY = p.y }
                    if p.x > maxX { maxX = p.x }
                    if p.y > maxY { maxY = p.y }
                }

                if !vp.beziers.isEmpty {
                    let p0 = CGPoint(x: vp.beziers[0].p0.x, y: vp.beziers[0].p0.y)
                    singlePath.move(to: p0)
                    includePt(p0)
                    for seg in vp.beziers {
                        let s0 = CGPoint(x: seg.p0.x, y: seg.p0.y)
                        let c1 = CGPoint(x: seg.c1.x, y: seg.c1.y)
                        let c2 = CGPoint(x: seg.c2.x, y: seg.c2.y)
                        let p3 = CGPoint(x: seg.p3.x, y: seg.p3.y)
                        singlePath.addCurve(to: p3, control1: c1, control2: c2)
                        includePt(c1)
                        includePt(c2)
                        includePt(p3)
                        singleHandles.move(to: s0)
                        singleHandles.addLine(to: c1)
                        singleHandles.move(to: p3)
                        singleHandles.addLine(to: c2)
                    }
                    if vp.isClosed { singlePath.closeSubpath() }
                } else if vp.points.count >= 2 {
                    let p0 = CGPoint(x: vp.points[0].x, y: vp.points[0].y)
                    singlePath.move(to: p0)
                    includePt(p0)
                    for i in 1..<vp.points.count {
                        let pi = CGPoint(x: vp.points[i].x, y: vp.points[i].y)
                        singlePath.addLine(to: pi)
                        includePt(pi)
                    }
                    if vp.isClosed { singlePath.closeSubpath() }
                }

                if !vp.outlineBeziers.isEmpty {
                    let rp0 = CGPoint(x: vp.outlineBeziers[0].p0.x, y: vp.outlineBeziers[0].p0.y)
                    singleRibbon.move(to: rp0)
                    includePt(rp0)
                    for seg in vp.outlineBeziers {
                        let c1 = CGPoint(x: seg.c1.x, y: seg.c1.y)
                        let c2 = CGPoint(x: seg.c2.x, y: seg.c2.y)
                        let p3 = CGPoint(x: seg.p3.x, y: seg.p3.y)
                        singleRibbon.addCurve(to: p3, control1: c1, control2: c2)
                        includePt(p3)
                    }
                    singleRibbon.closeSubpath()
                }

                let bbox: CGRect
                if minX <= maxX && minY <= maxY {
                    let pad = CGFloat(max(1.0, vp.strokeRadiusPx * 2.5))
                    bbox = CGRect(x: minX - pad, y: minY - pad, width: max(1.0, (maxX - minX) + pad * 2.0), height: max(1.0, (maxY - minY) + pad * 2.0))
                } else {
                    bbox = .zero
                }

                fullPath.addPath(singlePath)
                if !singleRibbon.isEmpty {
                    fullFilledRibbonPath.addPath(singleRibbon)
                    ribbonByID[vp.id] = singleRibbon
                }
                fullHandles.addPath(singleHandles)
                pathByID[vp.id] = singlePath
                handlesByID[vp.id] = singleHandles
                boundsByID[vp.id] = bbox
                allBoundsByID[vp.id] = bbox

                let col = max(0, min(gridCols - 1, Int(bbox.midX / cellW)))
                let row = max(0, min(gridRows - 1, Int(bbox.midY / cellH)))
                let cellIdx = row * gridCols + col
                gridPaths[cellIdx].addPath(singlePath)
                if !singleRibbon.isEmpty {
                    gridRibbonPaths[cellIdx].addPath(singleRibbon)
                }
                gridHandles[cellIdx].addPath(singleHandles)
                gridBounds[cellIdx] = gridBounds[cellIdx]?.union(bbox) ?? bbox

                // Add to quantized radius band (step = 0.25 px)
                let bandKey = max(1, min(64, Int((vp.strokeRadiusPx * 4.0).rounded())))
                bandFullPaths[bandKey, default: Path()].addPath(singlePath)
                bandBucketPaths[bandKey, default: [:]][cellIdx, default: Path()].addPath(singlePath)
            }

            var buckets: [SpatialBucket] = []
            for idx in 0..<(gridCols * gridRows) {
                if let b = gridBounds[idx] {
                    buckets.append(
                        SpatialBucket(
                            gridIndex: idx,
                            boundsPx: b,
                            pathPx: gridPaths[idx],
                            filledRibbonPathPx: gridRibbonPaths[idx],
                            handlesPx: gridHandles[idx]
                        )
                    )
                }
            }

            let sortedBandKeys = bandFullPaths.keys.sorted()
            let widthBands: [WidthBandCache] = sortedBandKeys.map { key in
                WidthBandCache(
                    radiusPx: CGFloat(key) * 0.25,
                    fullPathPx: bandFullPaths[key] ?? Path(),
                    bucketPathsPx: bandBucketPaths[key] ?? [:]
                )
            }

            layerCaches.append(
                LayerCache(
                    index: layer.index,
                    fullPathPx: fullPath,
                    fullFilledRibbonPathPx: fullFilledRibbonPath,
                    fullHandlesPx: fullHandles,
                    buckets: buckets,
                    widthBands: widthBands,
                    pathByID: pathByID,
                    ribbonByID: ribbonByID,
                    handlesByID: handlesByID,
                    boundsByID: boundsByID
                )
            )
        }

        return VectorRenderCache(
            layers: layerCaches,
            fullTravelPathPx: travelPath,
            boundsByPathID: allBoundsByID
        )
    }
}

/// Thread-safe value box for cross-isolation HTTP responses.
final class LockBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

/// Core controller managing image loading, two-stage cached vectorization, OSC (:9140), and HTTP/MCP (:17940/v1).
@Observable
@MainActor
final class VectorizerController {
    var sourceImage: RasterImage? = nil
    var displayNSImage: NSImage? = nil
    var sourceTitle: String = ""
    var sourceURL: URL? = nil
    var activePreset: SyntheticPreset? = nil

    var params = VectorizerParams()
    var result: VectorizationResult? = nil
    var renderCache: VectorRenderCache? = nil
    var layerVisibility: [Int: Bool] = [0: true, 1: true, 2: true, 3: true]

    var isProcessing: Bool = false
    var progressFraction: Double = 0.0
    var progressStage: String = ""
    var statusMessage: String = L("Prêt — ouvrir une image (⌘O), glisser-déposer un fichier ou coller (⌘V)", "Ready — open an image (⌘O), drop a file, or paste (⌘V)")
    var lastError: String? = nil

    private var cachedStageA: RawExtractionStage? = nil
    private var cachedStageAImageRevision: UInt64 = 0
    private(set) var imageRevision: UInt64 = 0
    private var computeGeneration: UInt64 = 0
    private var pendingTask: Task<Void, Never>? = nil

    // Interactive stroke editing Undo / Redo stacks
    private(set) var undoStack: [[PenLayer]] = []
    private(set) var redoStack: [[PenLayer]] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // Network services (OSC :9140, HTTP :17940)
    weak var plotter: AxiDrawPlotterController? = nil
    private(set) var oscServer: OSCUDPServer? = nil
    private(set) var httpPort: UInt16 = kSimpleVectorizerDefaultHTTPPort
    private var httpListenFD: Int32 = -1

    init(startServices: Bool = true, plotter: AxiDrawPlotterController? = nil) {
        self.plotter = plotter
        if startServices {
            let envOSC = ProcessInfo.processInfo.environment["SIMPLEVECTORIZER_OSC_IN_PORT"].flatMap(UInt16.init)
            startOSCServer(port: envOSC ?? kSimpleVectorizerDefaultOSCInPort)
            startHTTPServer()
        }
    }

    // MARK: - Loading Images & Presets

    func loadPreset(_ preset: SyntheticPreset, runSynchronously: Bool = false) {
        let raster = SyntheticDrawing.generate(preset: preset)
        self.activePreset = preset
        self.sourceURL = nil
        self.sourceTitle = preset.label
        self.setRasterImage(raster, runSynchronously: runSynchronously)
    }

    @discardableResult
    func loadFile(at url: URL, runSynchronously: Bool = false) -> Bool {
        guard let raster = RasterImage(contentsOf: url) else {
            self.lastError = L("Impossible de lire l'image « \(url.lastPathComponent) ».", "Could not load image \"\(url.lastPathComponent)\".")
            self.statusMessage = self.lastError ?? ""
            return false
        }
        self.activePreset = nil
        self.sourceURL = url
        self.sourceTitle = url.lastPathComponent
        self.lastError = nil
        self.setRasterImage(raster, runSynchronously: runSynchronously)
        return true
    }

    @discardableResult
    func loadNSImage(_ nsImage: NSImage, title: String, runSynchronously: Bool = false) -> Bool {
        let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            ?? nsImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.cgImage }
        guard let cg, let raster = RasterImage(cgImage: cg) else {
            self.lastError = L("Format d'image non pris en charge.", "Unsupported image format.")
            self.statusMessage = self.lastError ?? ""
            return false
        }
        self.activePreset = nil
        self.sourceURL = nil
        self.sourceTitle = title
        self.lastError = nil
        self.setRasterImage(raster, runSynchronously: runSynchronously)
        return true
    }

    private func setRasterImage(_ raster: RasterImage, runSynchronously: Bool) {
        pendingTask?.cancel()
        self.imageRevision &+= 1
        self.sourceImage = raster
        self.cachedStageA = nil
        self.cachedStageAImageRevision = 0
        self.result = nil
        self.renderCache = nil
        self.undoStack.removeAll()
        self.redoStack.removeAll()
        if let cg = raster.makeCGImage() {
            self.displayNSImage = NSImage(cgImage: cg, size: NSSize(width: raster.width, height: raster.height))
        }
        if runSynchronously {
            runSynchronousVectorization()
        } else {
            scheduleVectorization(debounceMs: 0, forceFullExtraction: true)
        }
    }

    // MARK: - Synchronous & Asynchronous Vectorization with Two-Stage Cache

    func runSynchronousVectorization() {
        pendingTask?.cancel()
        guard let image = sourceImage else { return }
        let currentParams = params
        let vis = layerVisibility
        let rev = imageRevision
        let start = CFAbsoluteTimeGetCurrent()

        let stageA: RawExtractionStage
        if let cached = cachedStageA,
           cachedStageAImageRevision == rev,
           cached.extractionCacheKey == currentParams.extractionCacheKey {
            stageA = cached
        } else {
            stageA = VectorizationEngine.extractStageA(image: image, params: currentParams)
            self.cachedStageA = stageA
            self.cachedStageAImageRevision = rev
        }

        let res = VectorizationEngine.finalizeStageB(
            stageA: stageA,
            params: currentParams,
            existingVisibility: vis,
            computeStartTime: start
        )
        applyResult(res)
    }

    func scheduleVectorization(debounceMs: UInt64 = 45, forceFullExtraction: Bool = false) {
        pendingTask?.cancel()
        guard let image = sourceImage else { return }
        self.computeGeneration &+= 1
        let capturedGen = self.computeGeneration
        let capturedRev = self.imageRevision
        let currentParams = params
        let vis = layerVisibility
        let existingStageA = forceFullExtraction ? nil : cachedStageA
        let canReuseStageA = !forceFullExtraction
            && cachedStageAImageRevision == capturedRev
            && existingStageA?.extractionCacheKey == currentParams.extractionCacheKey

        self.isProcessing = true
        self.progressFraction = canReuseStageA ? 0.65 : 0.08
        self.progressStage = canReuseStageA
            ? L("Ajustement courbes & 2-opt (cache)…", "Updating curves & 2-opt (cached)…")
            : L("Vectorisation de « \(sourceTitle) »…", "Vectorizing \"\(sourceTitle)\"…")
        self.statusMessage = self.progressStage

        pendingTask = Task { @MainActor [weak self] in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard let self, self.computeGeneration == capturedGen, self.imageRevision == capturedRev else { return }

            let start = CFAbsoluteTimeGetCurrent()
            let computed = await Task.detached(priority: .userInitiated) { () -> (RawExtractionStage, VectorizationResult, VectorRenderCache) in
                let stageA: RawExtractionStage
                if canReuseStageA, let existingStageA {
                    stageA = existingStageA
                } else {
                    stageA = VectorizationEngine.extractStageA(image: image, params: currentParams)
                }
                let finalRes = VectorizationEngine.finalizeStageB(
                    stageA: stageA,
                    params: currentParams,
                    existingVisibility: vis,
                    computeStartTime: start
                )
                let cache = VectorRenderCache.build(from: finalRes)
                return (stageA, finalRes, cache)
            }.value

            guard self.computeGeneration == capturedGen, self.imageRevision == capturedRev else { return }
            self.cachedStageA = computed.0
            self.cachedStageAImageRevision = capturedRev
            self.applyResult(computed.1, prebuiltCache: computed.2)
        }
    }

    private func applyResult(_ res: VectorizationResult, prebuiltCache: VectorRenderCache? = nil) {
        self.result = res
        self.renderCache = prebuiltCache ?? VectorRenderCache.build(from: res)
        self.isProcessing = false
        self.progressFraction = 1.0
        self.progressStage = L("Terminé", "Complete")
        let m = res.metrics
        self.statusMessage = L(
            "\(sourceTitle) — \(m.pathCount) chemins · tracé \(Format.distanceMM(m.drawDistanceMM)) · voyage \(Format.distanceMM(m.travelDistanceOptimizedMM)) (-\(Int(m.travelSavingsPercent.rounded())) %) · \(Format.latency(m.computeMilliseconds))",
            "\(sourceTitle) — \(m.pathCount) paths · draw \(Format.distanceMM(m.drawDistanceMM)) · travel \(Format.distanceMM(m.travelDistanceOptimizedMM)) (-\(Int(m.travelSavingsPercent.rounded()))%) · \(Format.latency(m.computeMilliseconds))"
        )
    }

    func toggleLayerVisibility(_ penIndex: Int) {
        let current = layerVisibility[penIndex] ?? true
        layerVisibility[penIndex] = !current
        if var res = result {
            for i in res.layers.indices where res.layers[i].index == penIndex {
                res.layers[i].visible = !current
            }
            res.svgPreview = SVGExporter.generateSVG(
                layers: res.layers,
                transform: res.pageTransform,
                metrics: res.metrics,
                params: params,
                forPreview: true
            )
            res.svgAxiDraw = SVGExporter.generateSVG(
                layers: res.layers,
                transform: res.pageTransform,
                metrics: res.metrics,
                params: params,
                forPreview: false
            )
            result = res
            renderCache = VectorRenderCache.build(from: res)
        }
    }

    func updatePenWidth(_ penIndex: Int, widthMM: Double) {
        while params.penWidthsMM.count <= penIndex {
            params.penWidthsMM.append(kDefaultPenWidthsMM[params.penWidthsMM.count % kDefaultPenWidthsMM.count])
        }
        params.penWidthsMM[penIndex] = max(0.1, min(5.0, widthMM))
        scheduleVectorization(debounceMs: 15)
    }

    func resetParameters() {
        params = VectorizerParams()
        layerVisibility = [0: true, 1: true, 2: true, 3: true]
        undoStack.removeAll()
        redoStack.removeAll()
        scheduleVectorization(debounceMs: 10)
    }

    // MARK: - Interactive Stroke Editing & Undo / Redo

    func recordUndoSnapshot() {
        guard let currentLayers = result?.layers else { return }
        undoStack.append(currentLayers)
        if undoStack.count > 40 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast(), let current = result?.layers else { return }
        redoStack.append(current)
        commitEditedLayers(previous, reoptimizeTour: false)
    }

    func redo() {
        guard let next = redoStack.popLast(), let current = result?.layers else { return }
        undoStack.append(current)
        commitEditedLayers(next, reoptimizeTour: false)
    }

    func commitEditedLayers(_ layers: [PenLayer], reoptimizeTour: Bool = false) {
        guard let res = result else { return }
        let updated = VectorizationEngine.rebuildFromEditedLayers(
            layers: layers,
            imageWidth: res.pageTransform.imageWidth,
            imageHeight: res.pageTransform.imageHeight,
            params: params,
            usedNeuralEngine: res.metrics.usedNeuralEngine,
            breakpointsPx: res.metrics.penBreakpointsPx,
            reoptimizeTour: reoptimizeTour
        )
        applyResult(updated)
    }

    @discardableResult
    func deletePaths(ids: Set<Int>) -> Int {
        guard !ids.isEmpty, var layers = result?.layers else { return 0 }
        recordUndoSnapshot()
        var removed = 0
        for i in layers.indices {
            let before = layers[i].paths.count
            layers[i].paths.removeAll { ids.contains($0.id) }
            removed += (before - layers[i].paths.count)
        }
        if removed > 0 {
            commitEditedLayers(layers)
        }
        return removed
    }

    func assignPathsToPen(ids: Set<Int>, targetPenIndex: Int) {
        guard !ids.isEmpty, var layers = result?.layers, layers.indices.contains(targetPenIndex) else { return }
        recordUndoSnapshot()
        var moved: [VectorPath] = []
        for i in layers.indices where i != targetPenIndex {
            let matching = layers[i].paths.filter { ids.contains($0.id) }
            if !matching.isEmpty {
                layers[i].paths.removeAll { ids.contains($0.id) }
                for var p in matching {
                    p.penIndex = targetPenIndex
                    moved.append(p)
                }
            }
        }
        guard !moved.isEmpty else { return }
        layers[targetPenIndex].paths.append(contentsOf: moved)
        commitEditedLayers(layers, reoptimizeTour: params.optimize2Opt)
    }

    func simplifySelectedPaths(ids: Set<Int>) {
        guard !ids.isEmpty, var layers = result?.layers else { return }
        recordUndoSnapshot()
        let strongerEps = max(1.5, params.rdpTolerance * 2.2)
        for i in layers.indices {
            for j in layers[i].paths.indices where ids.contains(layers[i].paths[j].id) {
                var p = layers[i].paths[j]
                let simplified = BezierAndPlotterOptimizer.simplifyRDP(p.points, epsilon: strongerEps)
                if simplified.count >= 2 {
                    p.points = simplified
                    layers[i].paths[j] = VectorizationEngine.refitPath(p, params: params)
                }
            }
        }
        commitEditedLayers(layers)
    }

    func reverseSelectedPaths(ids: Set<Int>) {
        guard !ids.isEmpty, var layers = result?.layers else { return }
        recordUndoSnapshot()
        for i in layers.indices {
            for j in layers[i].paths.indices where ids.contains(layers[i].paths[j].id) {
                layers[i].paths[j] = layers[i].paths[j].reversedPath()
            }
        }
        commitEditedLayers(layers)
    }

    /// Joins two or more selected open paths at their closest endpoints into a single continuous path.
    @discardableResult
    func joinSelectedPaths(ids: Set<Int>) -> Int? {
        guard ids.count >= 2, var layers = result?.layers else { return nil }
        var extracted: [(penIdx: Int, path: VectorPath)] = []
        for i in layers.indices {
            for p in layers[i].paths where ids.contains(p.id) {
                extracted.append((i, p))
            }
        }
        guard extracted.count >= 2 else { return nil }
        recordUndoSnapshot()

        let targetPen = extracted[0].penIdx
        for i in layers.indices {
            layers[i].paths.removeAll { ids.contains($0.id) }
        }

        var combinedPts = extracted[0].path.points
        var remaining = Array(extracted.dropFirst().map(\.path))
        while !remaining.isEmpty {
            let curStart = combinedPts.first!
            let curEnd = combinedPts.last!
            var bestIdx = 0
            var bestDist = Double.greatestFiniteMagnitude
            var attachAtEnd = true
            var reverseCandidate = false

            for (k, cand) in remaining.enumerated() {
                let dEndStart = curEnd.distance(to: cand.startPoint)
                if dEndStart < bestDist { bestDist = dEndStart; bestIdx = k; attachAtEnd = true; reverseCandidate = false }
                let dEndEnd = curEnd.distance(to: cand.endPoint)
                if dEndEnd < bestDist { bestDist = dEndEnd; bestIdx = k; attachAtEnd = true; reverseCandidate = true }
                let dStartEnd = curStart.distance(to: cand.endPoint)
                if dStartEnd < bestDist { bestDist = dStartEnd; bestIdx = k; attachAtEnd = false; reverseCandidate = false }
                let dStartStart = curStart.distance(to: cand.startPoint)
                if dStartStart < bestDist { bestDist = dStartStart; bestIdx = k; attachAtEnd = false; reverseCandidate = true }
            }

            let chosen = remaining.remove(at: bestIdx)
            let pts = reverseCandidate ? Array(chosen.points.reversed()) : chosen.points
            if attachAtEnd {
                combinedPts.append(contentsOf: pts)
            } else {
                combinedPts = pts + combinedPts
            }
        }

        let newID = nextAvailablePathID(in: layers)
        let rawJoined = VectorPath(
            id: newID,
            penIndex: targetPen,
            points: combinedPts,
            beziers: [],
            strokeRadiusPx: extracted[0].path.strokeRadiusPx,
            isClosed: false,
            isHatch: false
        )
        let fitted = VectorizationEngine.refitPath(rawJoined, params: params)
        layers[targetPen].paths.append(fitted)
        commitEditedLayers(layers)
        return newID
    }

    /// Splits a path at a specific vertex index into two independent paths.
    @discardableResult
    func splitPath(pathID: Int, atVertexIndex vertexIdx: Int) -> (Int, Int)? {
        guard var layers = result?.layers else { return nil }
        for i in layers.indices {
            if let j = layers[i].paths.firstIndex(where: { $0.id == pathID }) {
                let orig = layers[i].paths[j]
                guard vertexIdx > 0, vertexIdx < orig.points.count - 1 else { return nil }
                recordUndoSnapshot()
                let ptsA = Array(orig.points[0...vertexIdx])
                let ptsB = Array(orig.points[vertexIdx..<orig.points.count])
                let idA = orig.id
                let idB = nextAvailablePathID(in: layers)
                let pathA = VectorizationEngine.refitPath(
                    VectorPath(id: idA, penIndex: i, points: ptsA, strokeRadiusPx: orig.strokeRadiusPx),
                    params: params
                )
                let pathB = VectorizationEngine.refitPath(
                    VectorPath(id: idB, penIndex: i, points: ptsB, strokeRadiusPx: orig.strokeRadiusPx),
                    params: params
                )
                layers[i].paths.replaceSubrange(j...j, with: [pathA, pathB])
                commitEditedLayers(layers)
                return (idA, idB)
            }
        }
        return nil
    }

    func translatePaths(ids: Set<Int>, dxPx: Double, dyPx: Double) {
        guard !ids.isEmpty, var layers = result?.layers else { return }
        for i in layers.indices {
            for j in layers[i].paths.indices where ids.contains(layers[i].paths[j].id) {
                var p = layers[i].paths[j]
                p.points = p.points.map { VectorPoint(x: $0.x + dxPx, y: $0.y + dyPx) }
                p.beziers = p.beziers.map {
                    CubicBezierSegment(
                        p0: VectorPoint(x: $0.p0.x + dxPx, y: $0.p0.y + dyPx),
                        c1: VectorPoint(x: $0.c1.x + dxPx, y: $0.c1.y + dyPx),
                        c2: VectorPoint(x: $0.c2.x + dxPx, y: $0.c2.y + dyPx),
                        p3: VectorPoint(x: $0.p3.x + dxPx, y: $0.p3.y + dyPx)
                    )
                }
                layers[i].paths[j] = p
            }
        }
        commitEditedLayers(layers)
    }

    func movePathVertex(pathID: Int, pointIndex: Int, to newPt: VectorPoint) {
        guard var layers = result?.layers else { return }
        for i in layers.indices {
            if let j = layers[i].paths.firstIndex(where: { $0.id == pathID }) {
                var p = layers[i].paths[j]
                guard p.points.indices.contains(pointIndex) else { return }
                p.points[pointIndex] = newPt
                layers[i].paths[j] = VectorizationEngine.refitPath(p, params: params)
                commitEditedLayers(layers)
                return
            }
        }
    }

    @discardableResult
    func erasePathsNear(pointPx: VectorPoint, radiusPx: Double) -> Int {
        guard var layers = result?.layers else { return 0 }
        let rSq = radiusPx * radiusPx
        var removed = 0
        for i in layers.indices where layers[i].visible {
            let before = layers[i].paths.count
            layers[i].paths.removeAll { vp in
                Self.distanceSquaredToPath(pointPx: pointPx, path: vp) <= rSq
            }
            removed += (before - layers[i].paths.count)
        }
        if removed > 0 {
            commitEditedLayers(layers)
        }
        return removed
    }

    @discardableResult
    func addFreehandPath(points: [VectorPoint], penIndex: Int) -> Int? {
        guard points.count >= 2, var layers = result?.layers else { return nil }
        recordUndoSnapshot()
        let targetPen = max(0, min(layers.count - 1, penIndex))
        let simplified = BezierAndPlotterOptimizer.simplifyRDP(points, epsilon: max(0.6, params.rdpTolerance))
        guard simplified.count >= 2 else { return nil }
        let newID = nextAvailablePathID(in: layers)
        let raw = VectorPath(
            id: newID,
            penIndex: targetPen,
            points: simplified,
            beziers: [],
            strokeRadiusPx: 1.5,
            isClosed: false,
            isHatch: false
        )
        let fitted = VectorizationEngine.refitPath(raw, params: params)
        layers[targetPen].paths.append(fitted)
        commitEditedLayers(layers)
        return newID
    }

    private func nextAvailablePathID(in layers: [PenLayer]) -> Int {
        var maxID = 0
        for l in layers {
            for p in l.paths where p.id > maxID {
                maxID = p.id
            }
        }
        return maxID + 1
    }

    static func distanceSquaredToPath(pointPx: VectorPoint, path: VectorPath) -> Double {
        let pts = path.points
        guard !pts.isEmpty else { return .greatestFiniteMagnitude }
        if pts.count == 1 {
            return pointPx.distanceSquared(to: pts[0])
        }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            let dSq: Double
            if lenSq < 1e-10 {
                dSq = pointPx.distanceSquared(to: a)
            } else {
                let t = max(0.0, min(1.0, ((pointPx.x - a.x) * dx + (pointPx.y - a.y) * dy) / lenSq))
                let proj = VectorPoint(x: a.x + t * dx, y: a.y + t * dy)
                dSq = pointPx.distanceSquared(to: proj)
            }
            if dSq < best { best = dSq }
        }
        return best
    }

    // MARK: - OSC Control (:9140)

    func startOSCServer(port: UInt16 = kSimpleVectorizerDefaultOSCInPort) {
        oscServer?.stop()
        let srv = OSCUDPServer(port: port) { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.handleOSCMessage(msg)
            }
        }
        _ = srv.start()
        self.oscServer = srv
    }

    func handleOSCMessage(_ message: OSCCodec.Message) {
        let addr = message.address.lowercased()
        let first = message.arguments.first

        switch addr {
        case "/simplevectorizer/algorithm":
            if let s = first?.stringValue, let alg = VectorAlgorithm(rawValue: s) {
                params.algorithm = alg
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/threshold":
            if let v = first?.intValue {
                params.threshold = max(0, min(255, v))
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/adaptive":
            if let b = first?.boolValue {
                params.adaptiveThreshold = b
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/invert":
            if let b = first?.boolValue {
                params.invert = b
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/blur":
            if let v = first?.doubleValue {
                params.blurRadius = max(0, min(10, v))
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/tolerance":
            if let v = first?.doubleValue {
                params.rdpTolerance = max(0.1, min(5.0, v))
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/smoothing":
            if let v = first?.doubleValue {
                params.curveSmoothing = max(0.0, min(1.0, v))
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/continuity":
            if let v = first?.doubleValue {
                params.continuity = max(0.0, min(100.0, v))
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/pens":
            if let v = first?.intValue {
                params.penCount = max(1, min(4, v))
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/paper":
            if let s = first?.stringValue {
                let match = PaperFormat.allCases.first { $0.rawValue.lowercased() == s.lowercased() }
                if let match {
                    params.paperFormat = match
                    scheduleVectorization(debounceMs: 0)
                }
            }
        case "/simplevectorizer/hatch":
            if let b = first?.boolValue {
                params.hatchEnabled = b
                scheduleVectorization(debounceMs: 0)
            }
        case "/simplevectorizer/preset":
            if let s = first?.stringValue, let preset = SyntheticPreset(rawValue: s.lowercased()) {
                loadPreset(preset, runSynchronously: true)
            }
        case "/simplevectorizer/open":
            if let s = first?.stringValue {
                let url = URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
                _ = loadFile(at: url, runSynchronously: true)
            }
        case "/simplevectorizer/export":
            if let s = first?.stringValue, let svg = result?.svgAxiDraw {
                let url = URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
                try? svg.write(to: url, atomically: true, encoding: .utf8)
            }
        case "/simplevectorizer/axidraw/plot":
            if let res = result {
                plotter?.startPlot(result: res)
            }
        case "/simplevectorizer/axidraw/pause":
            plotter?.pausePlot()
        case "/simplevectorizer/axidraw/resume":
            plotter?.resumePlot()
        case "/simplevectorizer/axidraw/stop":
            plotter?.stopPlot()
        case "/simplevectorizer/axidraw/penup":
            plotter?.raisePen()
        case "/simplevectorizer/axidraw/pendown":
            plotter?.lowerPen()
        case "/simplevectorizer/axidraw/home":
            plotter?.returnToHome()
        case "/simplevectorizer/axidraw/unlock":
            plotter?.unlockMotorsAndZeroOrigin()
        case "/simplevectorizer/reset":
            resetParameters()
        default:
            break
        }
    }

    // MARK: - Local HTTP JSON Server (`127.0.0.1:17940/v1`)

    func startHTTPServer(port: UInt16? = nil) {
        stopHTTPServer()
        let envPort = ProcessInfo.processInfo.environment["SIMPLEVECTORIZER_API_PORT"].flatMap(UInt16.init)
        let targetPort = port ?? envPort ?? kSimpleVectorizerDefaultHTTPPort

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = targetPort.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0, Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            return
        }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &len)
            }
        }
        self.httpListenFD = fd
        self.httpPort = UInt16(bigEndian: bound.sin_port)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                var caddr = sockaddr_in()
                var clen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let cfd = withUnsafeMutablePointer(to: &caddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.accept(fd, $0, &clen)
                    }
                }
                if cfd < 0 { break }
                var one: Int32 = 1
                setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                self?.handleHTTPConnection(cfd)
            }
        }
    }

    func stopHTTPServer() {
        if httpListenFD >= 0 {
            Darwin.close(httpListenFD)
            httpListenFD = -1
        }
    }

    func stopAllServices() {
        pendingTask?.cancel()
        oscServer?.stop()
        stopHTTPServer()
    }

    nonisolated private func handleHTTPConnection(_ fd: Int32) {
        defer { Darwin.close(fd) }
        var buf = [UInt8](repeating: 0, count: 32768)
        let n = Darwin.recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return }
        let requestText = String(decoding: buf[0..<n], as: UTF8.self)
        let firstLine = requestText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let tokens = firstLine.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return }
        let method = tokens[0].uppercased()
        let rawTarget = tokens[1]
        let pathParts = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pathParts.first ?? "")
        let query = pathParts.count > 1 ? String(pathParts[1]) : ""

        var jsonArgs: [String: Any] = [:]
        if let bodyRange = requestText.range(of: "\r\n\r\n") {
            let bodyStr = String(requestText[bodyRange.upperBound...])
            if let data = bodyStr.data(using: .utf8),
               let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                jsonArgs = parsed
            }
        }
        let args = jsonArgs

        let sem = DispatchSemaphore(value: 0)
        let box = LockBox<Data>(Data("{\"ok\":true}".utf8))
        let statusBox = LockBox<Int>(200)
        let contentTypeBox = LockBox<String>("application/json; charset=utf-8")

        Task { @MainActor [weak self] in
            defer { sem.signal() }
            guard let self else { return }
            self.dispatchHTTPRequest(
                method: method,
                path: path,
                query: query,
                args: args,
                box: box,
                statusBox: statusBox,
                contentTypeBox: contentTypeBox
            )
        }
        _ = sem.wait(timeout: .now() + 8.0)

        let body = box.get()
        let code = statusBox.get()
        let ctype = contentTypeBox.get()
        let header = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Bad Request")\r\nContent-Type: \(ctype)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        _ = response.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!, response.count, 0)
        }
    }

    private func dispatchHTTPRequest(
        method: String,
        path: String,
        query: String,
        args: [String: Any],
        box: LockBox<Data>,
        statusBox: LockBox<Int>,
        contentTypeBox: LockBox<String>
    ) {
        func writeJSON(_ dict: [String: Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                box.set(data)
            }
        }

        switch (method, path) {
        case ("GET", "/v1/state"), ("GET", "/v1/status"):
            let m = result?.metrics ?? PlotterMetrics()
            writeJSON([
                "app": "SimpleVectorizer",
                "version": AppVersion.current.version,
                "sourceTitle": sourceTitle,
                "algorithm": params.algorithm.rawValue,
                "paperFormat": params.paperFormat.rawValue,
                "penCount": params.penCount,
                "isProcessing": isProcessing,
                "oscInPort": Int(oscServer?.port ?? kSimpleVectorizerDefaultOSCInPort),
                "apiPort": Int(httpPort),
                "statusMessage": statusMessage,
                "metrics": [
                    "imageWidth": m.imageWidth,
                    "imageHeight": m.imageHeight,
                    "pageWidthMM": m.pageWidthMM,
                    "pageHeightMM": m.pageHeightMM,
                    "pathCount": m.pathCount,
                    "pointCount": m.pointCount,
                    "bezierSegmentCount": m.bezierSegmentCount,
                    "drawDistanceMM": m.drawDistanceMM,
                    "travelDistanceMM": m.travelDistanceOptimizedMM,
                    "travelSavingsPercent": m.travelSavingsPercent,
                    "penLifts": m.penLifts,
                    "estimatedPlotSeconds": m.estimatedPlotSeconds,
                    "computeMilliseconds": m.computeMilliseconds,
                    "usedNeuralEngine": m.usedNeuralEngine,
                ],
                "layers": (result?.layers ?? []).map { layer in
                    [
                        "index": layer.index + 1,
                        "name": layer.name,
                        "widthMM": layer.widthMM,
                        "colorHex": layer.colorHex,
                        "visible": layer.visible,
                        "pathCount": layer.paths.count,
                    ] as [String: Any]
                },
            ])

        case ("GET", "/v1/help"):
            writeJSON([
                "app": "SimpleVectorizer",
                "httpEndpoints": [
                    "GET /v1/state",
                    "GET /v1/help",
                    "GET /v1/svg",
                    "GET /v1/snapshot.png?view=split|overlay|vector",
                    "POST /v1/open {\"path\":\"/path/to/drawing.png\",\"preset\":\"portrait|stage|hatching|rosette\"}",
                    "POST /v1/params {\"algorithm\":\"neural_centerline\",\"curveSmoothing\":0.65,\"penCount\":2,\"paperFormat\":\"A4\"}",
                    "POST /v1/export {\"outputPath\":\"/tmp/out.svg\",\"format\":\"svg|json|txt|csv\"}",
                    "POST /v1/reset",
                ],
                "oscAddresses": [
                    "/simplevectorizer/algorithm <neural_centerline|vision_contours|skeletonize|canny_edges>",
                    "/simplevectorizer/threshold <0..255>",
                    "/simplevectorizer/adaptive <0|1>",
                    "/simplevectorizer/invert <0|1>",
                    "/simplevectorizer/blur <0..10>",
                    "/simplevectorizer/tolerance <0.1..5.0>",
                    "/simplevectorizer/smoothing <0.0..1.0>",
                    "/simplevectorizer/continuity <0..100>",
                    "/simplevectorizer/pens <1..4>",
                    "/simplevectorizer/paper <A4|A3|A5|A6|original>",
                    "/simplevectorizer/hatch <0|1>",
                    "/simplevectorizer/preset <portrait|stage|hatching|rosette>",
                    "/simplevectorizer/open <filepath>",
                    "/simplevectorizer/export <filepath>",
                ],
            ])

        case ("GET", "/v1/svg"):
            let svg = result?.svgAxiDraw ?? ""
            contentTypeBox.set("image/svg+xml; charset=utf-8")
            box.set(Data(svg.utf8))

        case ("GET", "/v1/snapshot.png"):
            let snapModel = AppModel(startServices: false, persistEnabled: false)
            if let src = self.sourceImage {
                snapModel.vectorizer.sourceImage = src
                snapModel.vectorizer.displayNSImage = self.displayNSImage
                snapModel.vectorizer.sourceTitle = self.sourceTitle
                snapModel.vectorizer.params = self.params
                snapModel.vectorizer.result = self.result
            } else {
                snapModel.vectorizer.loadPreset(.portrait, runSynchronously: true)
            }
            if query.contains("view=overlay") {
                snapModel.viewMode = .overlay
            } else if query.contains("view=vector") {
                snapModel.viewMode = .vectorOnly
            } else {
                snapModel.viewMode = .sideBySide
            }
            if let png = Snapshot.renderOffscreenPNG(model: snapModel) {
                contentTypeBox.set("image/png")
                box.set(png)
            }

        case ("POST", "/v1/open"):
            if let presetStr = args["preset"] as? String,
               let preset = SyntheticPreset(rawValue: presetStr.lowercased()) {
                loadPreset(preset, runSynchronously: true)
                writeJSON(["ok": true, "preset": preset.rawValue, "pathCount": result?.metrics.pathCount ?? 0])
            } else if let filePath = args["path"] as? String, !filePath.isEmpty {
                let url = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)
                let ok = loadFile(at: url, runSynchronously: true)
                if !ok { statusBox.set(400) }
                writeJSON(["ok": ok, "path": url.path, "pathCount": result?.metrics.pathCount ?? 0])
            } else {
                statusBox.set(400)
                writeJSON(["error": "Provide 'path' or 'preset'"])
            }

        case ("POST", "/v1/params"):
            applyJSONParams(args)
            runSynchronousVectorization()
            let m = result?.metrics ?? PlotterMetrics()
            writeJSON([
                "ok": true,
                "pathCount": m.pathCount,
                "drawDistanceMM": m.drawDistanceMM,
                "travelDistanceMM": m.travelDistanceOptimizedMM,
                "travelSavingsPercent": m.travelSavingsPercent,
                "computeMilliseconds": m.computeMilliseconds,
            ])

        case ("POST", "/v1/export"):
            guard let res = result else {
                statusBox.set(400)
                writeJSON(["error": "No active vectorization result"])
                return
            }
            let fmtStr = (args["format"] as? String)?.lowercased() ?? "svg"
            let fmt = VectorExportFormat(rawValue: fmtStr) ?? .svgAxiDraw
            let rendered = SVGExporter.render(result: res, params: params, format: fmt)
            if let outPath = args["outputPath"] as? String, !outPath.isEmpty {
                let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try rendered.write(to: url, atomically: true, encoding: .utf8)
                    writeJSON(["ok": true, "outputPath": url.path, "bytes": rendered.utf8.count])
                } catch {
                    statusBox.set(500)
                    writeJSON(["error": error.localizedDescription])
                }
            } else {
                writeJSON(["ok": true, "format": fmt.rawValue, "content": rendered])
            }

        case ("POST", "/v1/reset"):
            resetParameters()
            runSynchronousVectorization()
            writeJSON(["ok": true])

        case ("GET", "/v1/axidraw"):
            if let p = plotter {
                writeJSON([
                    "port": p.selectedPortPath,
                    "isSimulator": p.selectedDevice.isSimulator,
                    "isBusy": p.runState.isBusy,
                    "isPaused": p.runState.isPaused,
                    "isPenDown": p.isPenDown,
                    "posXMM": p.currentPosMM.x,
                    "posYMM": p.currentPosMM.y,
                    "progress": p.progressFraction,
                    "status": p.statusLog,
                ])
            } else {
                writeJSON(["ok": false])
            }

        case ("POST", "/v1/axidraw"):
            let action = (args["action"] as? String)?.lowercased() ?? "status"
            switch action {
            case "plot", "start":
                if let res = result {
                    plotter?.startPlot(result: res)
                }
            case "frame":
                if let res = result {
                    plotter?.startBoundingBoxFrame(result: res)
                }
            case "pause":
                plotter?.pausePlot()
            case "resume":
                plotter?.resumePlot()
            case "stop":
                plotter?.stopPlot()
            case "pen_up", "penup":
                plotter?.raisePen()
            case "pen_down", "pendown":
                plotter?.lowerPen()
            case "home":
                plotter?.returnToHome()
            case "unlock":
                plotter?.unlockMotorsAndZeroOrigin()
            default:
                break
            }
            writeJSON([
                "ok": true,
                "action": action,
                "status": plotter?.statusLog ?? "",
            ])

        default:
            statusBox.set(404)
            writeJSON(["error": "not found", "path": path])
        }
    }

    func applyJSONParams(_ args: [String: Any]) {
        if let s = args["algorithm"] as? String, let alg = VectorAlgorithm(rawValue: s) {
            params.algorithm = alg
        }
        if let b = args["adaptiveThreshold"] as? Bool { params.adaptiveThreshold = b }
        if let b = args["invert"] as? Bool { params.invert = b }
        if let v = (args["threshold"] as? Int) ?? (args["threshold"] as? Double).map(Int.init) {
            params.threshold = max(0, min(255, v))
        }
        if let v = (args["blurRadius"] as? Double) ?? (args["blurRadius"] as? Int).map(Double.init) {
            params.blurRadius = max(0, min(10, v))
        }
        if let v = (args["morphCleanup"] as? Int) ?? (args["morphCleanup"] as? Double).map(Int.init) {
            params.morphCleanup = max(0, min(2, v))
        }
        if let v = (args["rdpTolerance"] as? Double) ?? (args["rdpTolerance"] as? Int).map(Double.init) {
            params.rdpTolerance = max(0.1, min(5.0, v))
        }
        if let v = (args["curveSmoothing"] as? Double) ?? (args["curveSmoothing"] as? Int).map(Double.init) {
            params.curveSmoothing = max(0.0, min(1.0, v))
        }
        if let v = (args["cornerAngleDeg"] as? Int) ?? (args["cornerAngleDeg"] as? Double).map(Int.init) {
            params.cornerAngleDeg = max(15, min(90, v))
        }
        if let v = (args["minPathLengthPx"] as? Int) ?? (args["minPathLengthPx"] as? Double).map(Int.init) {
            params.minPathLengthPx = max(1, min(30, v))
        }
        if let b = args["stegerSubpixel"] as? Bool { params.stegerSubpixel = b }
        if let b = args["crossJunctions"] as? Bool { params.crossJunctions = b }
        if let v = (args["maxStitchGapPx"] as? Double) ?? (args["maxStitchGapPx"] as? Int).map(Double.init) {
            params.maxStitchGapPx = max(1, min(25, v))
        }
        if let v = (args["continuity"] as? Double) ?? (args["continuity"] as? Int).map(Double.init) {
            params.continuity = max(0, min(100, v))
        }
        if let b = args["hatchEnabled"] as? Bool { params.hatchEnabled = b }
        if let v = (args["hatchSpacingPx"] as? Double) ?? (args["hatchSpacingPx"] as? Int).map(Double.init) {
            params.hatchSpacingPx = max(2.5, min(20, v))
        }
        if let v = (args["hatchAngleDeg"] as? Double) ?? (args["hatchAngleDeg"] as? Int).map(Double.init) {
            params.hatchAngleDeg = v
        }
        if let b = args["crossHatch"] as? Bool { params.crossHatch = b }
        if let v = (args["penCount"] as? Int) ?? (args["penCount"] as? Double).map(Int.init) {
            params.penCount = max(1, min(4, v))
        }
        if let s = args["paperFormat"] as? String,
           let pf = PaperFormat.allCases.first(where: { $0.rawValue.lowercased() == s.lowercased() }) {
            params.paperFormat = pf
        }
        if let s = args["paperOrientation"] as? String,
           let po = PaperOrientation(rawValue: s.lowercased()) {
            params.paperOrientation = po
        }
        if let v = (args["marginMM"] as? Double) ?? (args["marginMM"] as? Int).map(Double.init) {
            params.marginMM = max(0, min(50, v))
        }
        if let b = args["optimize2Opt"] as? Bool { params.optimize2Opt = b }
        if let b = args["exportBlackStrokes"] as? Bool { params.exportBlackStrokes = b }
    }
}
