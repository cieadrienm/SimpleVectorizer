import Foundation
import SimpleVectorizerCore
import Testing

@Suite("SimpleVectorizerCore Tests")
struct SimpleVectorizerCoreTests {
    @Test("Exact 2D Euclidean Distance Transform measures stroke radius accurately")
    func testExactEDT() {
        let w = 21
        let h = 21
        var binary = [UInt8](repeating: 0, count: w * h)
        // Draw a horizontal thick bar of height 5 px (rows 8..12)
        for y in 8...12 {
            for x in 3...17 {
                binary[y * w + x] = 1
            }
        }
        let edt = NeuralRidgeFilter.computeExactEDT(binary: binary, width: w, height: h)
        // Center row y=10 has 2 pixels inside bar on each vertical side, so distance to nearest 0 at y=7 or y=13 is 3.0
        #expect(abs(edt[10 * w + 10] - 3.0) < 0.01)
        #expect(edt[0] == 0.0)
    }

    @Test("Guo-Hall thinning reduces thick stroke to 1-pixel connected centerline")
    func testGuoHallThinning() {
        let w = 32
        let h = 32
        var binary = [UInt8](repeating: 0, count: w * h)
        for y in 13...17 {
            for x in 4...27 {
                binary[y * w + x] = 1
            }
        }
        let skel = CenterlineTracer.thinGuoHall(binary: binary, width: w, height: h)
        let activeCount = skel.reduce(0) { $0 + Int($1) }
        #expect(activeCount >= 18 && activeCount <= 26)
    }

    @Test("Schneider least-squares cubic Bézier fitting compresses smooth arc into cubic segments")
    func testSchneiderBezierFitting() {
        var pts: [VectorPoint] = []
        for i in 0...40 {
            let t = Double(i) / 40.0 * (.pi * 0.5)
            pts.append(VectorPoint(x: 100.0 * cos(t), y: 100.0 * sin(t)))
        }
        let beziers = BezierAndPlotterOptimizer.fitCubicBeziers(points: pts, smoothing: 0.7, cornerAngleDeg: 45)
        #expect(!beziers.isEmpty)
        #expect(beziers.count <= 4) // A quarter circle fits in 1-2 cubic Béziers
    }

    @Test("2-opt plotter tour optimizer reduces travel distance on scrambled paths")
    func testTwoOptPlotterOptimizer() {
        // Create 8 paths placed in alternating far corners vs sequential order
        var scrambled: [VectorPath] = []
        let coords: [(Double, Double)] = [
            (10, 10), (500, 500), (20, 10), (490, 500),
            (30, 10), (480, 500), (40, 10), (470, 500),
        ]
        for (i, c) in coords.enumerated() {
            let p0 = VectorPoint(x: c.0, y: c.1)
            let p1 = VectorPoint(x: c.0 + 5, y: c.1 + 5)
            scrambled.append(VectorPath(id: i + 1, points: [p0, p1]))
        }
        let (optimized, rawTravel, optTravel) = BezierAndPlotterOptimizer.optimizePlotterTour(paths: scrambled, enable2Opt: true)
        #expect(optimized.count == 8)
        #expect(optTravel < rawTravel * 0.4)
    }

    @Test("Full ANE + Steger vectorization produces multi-pen AxiDraw SVG")
    func testFullVectorizationPipeline() {
        let img = SyntheticDrawing.generate(preset: .portrait, width: 360, height: 480)
        var params = VectorizerParams()
        params.algorithm = .neuralCenterline
        params.penCount = 2
        params.paperFormat = .a4

        let (stageA, res) = VectorizationEngine.vectorize(image: img, params: params)
        #expect(res.metrics.pathCount >= 8)
        #expect(res.layers.count == 2)
        #expect(res.svgAxiDraw.contains("inkscape:groupmode=\"layer\""))
        #expect(res.svgAxiDraw.contains("width=\"210.00mm\" height=\"297.00mm\""))

        // Verify Stage B fast re-finalization with different paper format and Illustration vs AxiDraw modes
        let hasRibbons = res.layers.flatMap(\.paths).contains { !$0.outlineBeziers.isEmpty && !$0.pointRadiiPx.isEmpty }
        #expect(hasRibbons)

        params.outputMode = .axidraw
        params.paperFormat = .a3
        let resA3 = VectorizationEngine.finalizeStageB(stageA: stageA, params: params)
        #expect(resA3.svgAxiDraw.contains("width=\"297.00mm\" height=\"420.00mm\""))
        let axiDrawHasRibbons = resA3.layers.flatMap(\.paths).contains { !$0.outlineBeziers.isEmpty }
        #expect(!axiDrawHasRibbons)

        // Verify direct AxiDraw job compilation (with multi-pen pause and bounding box tour)
        var axiCfg = AxiDrawConfig()
        axiCfg.machineModel = .v3A4
        axiCfg.pauseBetweenPenLayers = true
        let compiledJob = AxiDrawCompiledJob.compile(result: res, config: axiCfg)
        #expect(!compiledJob.steps.isEmpty)
        #expect(compiledJob.totalDrawMM > 50.0)
        let hasPenSwapPause = compiledJob.steps.contains {
            if case .beginLayer = $0 { return true }
            return false
        }
        #expect(hasPenSwapPause)

        let frameJob = AxiDrawCompiledJob.compileBoundingBoxTour(result: res, config: axiCfg)
        #expect(frameJob.steps.count >= 6)
        #expect(frameJob.totalTravelMM > 20.0)
    }

    @Test("OSC codec encodes and decodes messages accurately")
    func testOSCCodec() {
        let msg = OSCCodec.Message(
            address: "/simplevectorizer/smoothing",
            arguments: [.float(0.75), .string("A4"), .bool(true)]
        )
        let data = OSCCodec.encode(msg)
        let decoded = OSCCodec.decode(data)
        #expect(decoded.count == 1)
        #expect(decoded[0].address == "/simplevectorizer/smoothing")
        #expect(decoded[0].arguments.count == 3)
    }

    @Test("SimpleUpdater compares semantic versions and parses manifests")
    func testSimpleUpdater() throws {
        #expect(SimpleUpdater.isNewer(candidateVersion: "1.1.0", thanVersion: "1.0.0"))
        #expect(!SimpleUpdater.isNewer(candidateVersion: "1.0.0", thanVersion: "1.0.0"))
        let json = """
        {
          "net.cieadrienm.simplevectorizer": {
            "version": "1.2.0",
            "build": 12,
            "url": "https://github.com/cieadrienm/SimpleVectorizer/releases/download/v1.2.0/SimpleVectorizer-1.2.0.zip",
            "notes_fr": "Nouvelle version"
          }
        }
        """.data(using: .utf8)!
        let rel = try SimpleUpdater.parseRelease(from: json, bundleID: "net.cieadrienm.simplevectorizer", appName: "SimpleVectorizer")
        #expect(rel.version == "1.2.0")
        #expect(rel.build == 12)
    }
}
