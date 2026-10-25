import AppKit
import Foundation
import SimpleVectorizerCore

@MainActor
enum SelfTest {
    static func runAndExit() -> Never {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
                fputs("FAIL: \(message)\n", stderr)
            } else {
                print("PASS: \(message)")
            }
        }

        // 1. Test synthetic drawing generation & ANE/Steger centerline extraction
        let portrait = SyntheticDrawing.generate(preset: .portrait, width: 480, height: 640)
        check(portrait.width == 480 && portrait.height == 640, "Synthetic portrait drawing generated (480x640)")

        var params = VectorizerParams()
        params.algorithm = .neuralCenterline
        params.penCount = 2
        params.curveSmoothing = 0.65
        params.paperFormat = .a4
        params.optimize2Opt = true

        let (_, res) = VectorizationEngine.vectorize(image: portrait, params: params)
        check(res.metrics.pathCount >= 10, "ANE + Steger centerline extracts >= 10 paths (\(res.metrics.pathCount))")
        check(res.metrics.bezierSegmentCount > 20, "Schneider cubic Bézier fitting produces cubic segments (\(res.metrics.bezierSegmentCount))")
        check(res.layers.count == 2, "Multi-pen k-means separates into 2 pen layers")
        check(res.layers[0].paths.count > 0 && res.layers[1].paths.count > 0, "Both thin and thick pen layers receive paths (\(res.layers[0].paths.count) / \(res.layers[1].paths.count))")

        // 2. Test 2-opt travel optimization does not increase travel distance
        check(res.metrics.travelDistanceOptimizedMM <= res.metrics.travelDistanceRawMM + 0.01, "2-opt travel optimization reduces or preserves travel distance")

        // 3. Test Inkscape / AxiDraw SVG structure & Illustration variable-width ribbon mode
        check(res.svgAxiDraw.contains("width=\"210.00mm\" height=\"297.00mm\""), "AxiDraw SVG has physical A4 millimeter dimensions")
        check(res.svgAxiDraw.contains("inkscape:groupmode=\"layer\""), "AxiDraw SVG contains Inkscape pen layer groups")
        check(res.svgAxiDraw.contains("C"), "AxiDraw SVG contains cubic Bézier C commands")

        let hasRibbonOutlines = res.layers.flatMap(\.paths).contains { !$0.outlineBeziers.isEmpty && !$0.pointRadiiPx.isEmpty }
        check(hasRibbonOutlines, "Illustration mode generates variable-width cubic Bézier ribbons (outlineBeziers) from local EDT radii")

        let compiledJob = AxiDrawCompiledJob.compile(result: res, config: AxiDrawConfig())
        check(!compiledJob.steps.isEmpty && compiledJob.totalDrawMM > 50.0, "AxiDraw direct EBB job compiler generates motion steps (\(compiledJob.steps.count) steps)")

        // 4. Test Vision contours (both without hatching and with hatching)
        var visionOnlyParams = params
        visionOnlyParams.algorithm = .visionContours
        visionOnlyParams.hatchEnabled = false
        let (_, visionOnlyRes) = VectorizationEngine.vectorize(image: portrait, params: visionOnlyParams)
        check(visionOnlyRes.metrics.pathCount >= 10, "Vision contours (no hatch) extracts closed contours (\(visionOnlyRes.metrics.pathCount))")

        var visionParams = params
        visionParams.algorithm = .visionContours
        visionParams.hatchEnabled = true
        visionParams.crossHatch = true
        let hatchImg = SyntheticDrawing.generate(preset: .hatching, width: 360, height: 480)
        let (_, visionRes) = VectorizationEngine.vectorize(image: hatchImg, params: visionParams)
        check(visionRes.metrics.pathCount >= 5, "Vision contours + hatching extracts paths (\(visionRes.metrics.pathCount))")

        // 5. Test Canny edge mode
        var cannyParams = params
        cannyParams.algorithm = .cannyEdges
        let (_, cannyRes) = VectorizationEngine.vectorize(image: portrait, params: cannyParams)
        check(cannyRes.metrics.pathCount >= 5, "Canny edge mode extracts paths (\(cannyRes.metrics.pathCount))")

        // 6. Test empty initial state, OSC codec & interactive stroke editing + Undo/Redo
        let emptyModel = AppModel(startServices: false, persistEnabled: false, loadDefaultPreset: false)
        check(emptyModel.vectorizer.sourceImage == nil && emptyModel.vectorizer.result == nil, "AppModel launches empty without default image")

        let model = AppModel(startServices: false, persistEnabled: false, loadDefaultPreset: true)
        model.vectorizer.handleOSCMessage(OSCCodec.Message(address: "/simplevectorizer/pens", arguments: [.int(3)]))
        model.vectorizer.runSynchronousVectorization()
        check(model.vectorizer.params.penCount == 3 && model.vectorizer.result?.layers.count == 3, "OSC /simplevectorizer/pens updates pen layers to 3")

        if let firstPathID = model.vectorizer.result?.layers.first(where: { !$0.paths.isEmpty })?.paths.first?.id {
            let countBefore = model.vectorizer.result?.metrics.pathCount ?? 0
            model.selectedPathIDs = [firstPathID]
            model.deleteSelectedPaths()
            let countAfterDelete = model.vectorizer.result?.metrics.pathCount ?? 0
            check(countAfterDelete == countBefore - 1, "Interactive stroke deletion removes selected path (\(countBefore) -> \(countAfterDelete))")
            model.undoEdit()
            let countAfterUndo = model.vectorizer.result?.metrics.pathCount ?? 0
            check(countAfterUndo == countBefore, "Undo restores deleted stroke (\(countAfterUndo))")
        }

        // 7. Test offscreen PNG snapshot rendering (both Illustration and AxiDraw modes)
        let pngSplit = Snapshot.renderOffscreenPNG(model: model)
        check((pngSplit?.count ?? 0) > 15_000, "Offscreen split PNG snapshot renders (> 15 KB)")
        model.setOutputMode(.axidraw)
        model.vectorizer.runSynchronousVectorization()
        model.viewMode = .vectorOnly
        let pngSheet = Snapshot.renderOffscreenPNG(model: model)
        check((pngSheet?.count ?? 0) > 15_000, "Offscreen AxiDraw sheet PNG snapshot renders (> 15 KB)")

        if failures.isEmpty {
            print("SimpleVectorizer self-test: ALL PASSED")
            exit(0)
        } else {
            fputs("SimpleVectorizer self-test: \(failures.count) FAILURE(S)\n", stderr)
            exit(1)
        }
    }
}
