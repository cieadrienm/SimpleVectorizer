import Foundation
@testable import SimpleVectorizer
import SimpleVectorizerCore
import SimpleVectorizerMCPCore
import Testing

@Suite("SimpleVectorizerApp & MCP Tests")
struct SimpleVectorizerAppTests {
    @Test("AppModel launches empty by default, supports stroke editing + undo/redo, and renders offscreen PNG")
    @MainActor
    func testAppModelAndSnapshot() {
        let emptyModel = AppModel(startServices: false, persistEnabled: false, loadDefaultPreset: false)
        #expect(emptyModel.vectorizer.sourceImage == nil)
        #expect(emptyModel.vectorizer.result == nil)

        // Incremental zoom around anchor never resets to 1.0
        emptyModel.applyZoom(newScale: 2.0, anchorFromCenter: CGPoint(x: 40, y: -30))
        #expect(abs(emptyModel.zoomScale - 2.0) < 1e-4)
        emptyModel.applyZoom(newScale: emptyModel.zoomScale * 1.5, anchorFromCenter: CGPoint(x: 40, y: -30))
        #expect(abs(emptyModel.zoomScale - 3.0) < 1e-4)

        let model = AppModel(startServices: false, persistEnabled: false, loadDefaultPreset: true)
        #expect(model.vectorizer.result != nil)
        let initialCount = model.vectorizer.result?.metrics.pathCount ?? 0
        #expect(initialCount >= 8)

        // Test interactive stroke deletion + undo/redo
        if let firstID = model.vectorizer.result?.layers.first(where: { !$0.paths.isEmpty })?.paths.first?.id {
            model.selectedPathIDs = [firstID]
            model.deleteSelectedPaths()
            #expect(model.vectorizer.result?.metrics.pathCount == initialCount - 1)
            model.undoEdit()
            #expect(model.vectorizer.result?.metrics.pathCount == initialCount)
            model.redoEdit()
            #expect(model.vectorizer.result?.metrics.pathCount == initialCount - 1)
            model.undoEdit()
        }

        let png = Snapshot.renderOffscreenPNG(model: model)
        #expect((png?.count ?? 0) > 15_000)
    }

    @Test("Consecutive async image loads always recalculate Stage A and never reuse stale cache")
    @MainActor
    func testConsecutiveAsyncImageLoadsAlwaysRecalculate() async throws {
        let vec = VectorizerController(startServices: false)
        vec.loadPreset(.portrait, runSynchronously: false)
        // Simulate a spurious scheduleVectorization(forceFullExtraction: false) right after loading
        vec.scheduleVectorization(debounceMs: 5, forceFullExtraction: false)
        while vec.isProcessing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let portraitSVG = vec.result?.svgAxiDraw ?? ""
        #expect(!portraitSVG.isEmpty)
        let rev1 = vec.imageRevision

        // Load a second distinct image asynchronously
        vec.loadPreset(.rosette, runSynchronously: false)
        #expect(vec.imageRevision == rev1 + 1)
        vec.scheduleVectorization(debounceMs: 5, forceFullExtraction: false)
        while vec.isProcessing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let archSVG = vec.result?.svgAxiDraw ?? ""
        #expect(!archSVG.isEmpty)
        #expect(archSVG != portraitSVG)
    }

    @Test("MCP server handles initialize, tools/list, and tools/call")
    func testMCPServer() {
        let srv = SimpleVectorizerMCPServer(transport: { method, path, _ in
            let body = "{\"app\":\"SimpleVectorizer\",\"method\":\"\(method)\",\"path\":\"\(path)\"}"
            return APIResponse(status: 200, data: Data(body.utf8), contentType: "application/json")
        })

        let initReply = srv.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
        #expect(initReply?.contains("simplevectorizer") == true)

        let listReply = srv.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
        #expect(listReply?.contains("simplevectorizer_export_svg") == true)

        let callReply = srv.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"simplevectorizer_state\",\"arguments\":{}}}")
        #expect(callReply?.contains("/v1/state") == true)
    }
}
