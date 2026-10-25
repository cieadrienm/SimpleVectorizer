import AppKit
import Foundation
import Observation
import SimpleVectorizerCore
import SwiftUI
import UniformTypeIdentifiers

enum CanvasViewMode: String, CaseIterable, Identifiable {
    case sideBySide = "split"
    case overlay = "overlay"
    case vectorOnly = "vector"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: return L("Côte à côte", "Side by Side")
        case .overlay: return L("Superposition", "Overlay")
        case .vectorOnly: return L("Vecteur seul", "Vector Only")
        }
    }

    var icon: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .overlay: return "square.on.square"
        case .vectorOnly: return "doc.richtext"
        }
    }
}

enum CanvasEditTool: String, CaseIterable, Identifiable {
    case pan = "pan"
    case select = "select"
    case erase = "erase"
    case draw = "draw"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pan: return L("Déplacer", "Pan")
        case .select: return L("Sélection", "Select")
        case .erase: return L("Gomme", "Eraser")
        case .draw: return L("Tracer", "Draw")
        }
    }

    var helpText: String {
        switch self {
        case .pan:
            return L("Déplacer l'image (cliquer-glisser, 2 doigts au trackpad, ou clic milieu/droit)", "Pan canvas (drag, 2-finger trackpad scroll, or middle/right drag)")
        case .select:
            return L("Sélectionner, déplacer des sommets/traits, changer de stylo ou supprimer (⌫)", "Select, drag vertices/strokes, change pen layer, or delete (⌫)")
        case .erase:
            return L("Gomme : cliquer-glisser sur les traits indésirables pour les effacer", "Eraser: click and drag over unwanted strokes to erase them")
        case .draw:
            return L("Tracer un nouveau trait à main levée dans le stylo actif", "Draw a new freehand stroke in the active pen layer")
        }
    }

    var icon: String {
        switch self {
        case .pan: return "hand.draw"
        case .select: return "cursorarrow.click"
        case .erase: return "eraser"
        case .draw: return "pencil.tip"
        }
    }
}

@Observable
@MainActor
final class AppModel {
    private static let defaultsPrefix = "net.cieadrienm.simplevectorizer."
    private static let recentPathsKey = "net.cieadrienm.simplevectorizer.recentPaths"
    private static let blackOnWhiteKey = "net.cieadrienm.simplevectorizer.blackOnWhitePreview"
    private static let showAxiDrawSectionKey = "net.cieadrienm.simplevectorizer.showAxiDrawSection"

    let vectorizer: VectorizerController
    let plotter: AxiDrawPlotterController
    let updater: SimpleUpdater
    private let persistEnabled: Bool

    var language: AppLanguage = Localization.current {
        didSet {
            Localization.current = language
        }
    }

    var viewMode: CanvasViewMode = .sideBySide
    var editTool: CanvasEditTool = .select
    var showSidebar: Bool = true
    var showTravelMoves: Bool = false
    var showControlPoints: Bool = false
    var blackOnWhitePreview: Bool = false {
        didSet {
            if persistEnabled {
                UserDefaults.standard.set(blackOnWhitePreview, forKey: Self.blackOnWhiteKey)
            }
        }
    }
    var showAxiDrawSection: Bool = false {
        didSet {
            if persistEnabled {
                UserDefaults.standard.set(showAxiDrawSection, forKey: Self.showAxiDrawSectionKey)
            }
        }
    }
    var bitmapOpacity: Double = 0.45
    var vectorOpacity: Double = 1.0

    // Stroke selection & editing state
    var selectedPathIDs: Set<Int> = []
    var selectedVertex: (pathID: Int, index: Int)? = nil
    var activeDrawPenIndex: Int = 0
    var eraserRadiusPx: Double = 8.0

    // Recent files list
    var recentURLs: [URL] = []

    // Zoom & pan synchronized across panes
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero

    // Sheets
    var showAbout: Bool = false
    var showHelp: Bool = false
    var showShortcuts: Bool = false
    var showOSCGuide: Bool = false
    var showUpdater: Bool = false
    var showExport: Bool = false
    var exportFormat: VectorExportFormat = .svgAxiDraw

    var flashMessage: String? = nil
    private var flashTask: Task<Void, Never>? = nil
    @ObservationIgnored private nonisolated(unsafe) var keyMonitor: Any? = nil

    init(startServices: Bool = true, persistEnabled: Bool = true, loadDefaultPreset: Bool = false) {
        self.persistEnabled = persistEnabled
        let plotterCtrl = AxiDrawPlotterController()
        self.plotter = plotterCtrl
        self.vectorizer = VectorizerController(startServices: startServices, plotter: plotterCtrl)
        self.updater = SimpleUpdater(
            appName: "SimpleVectorizer",
            bundleID: "net.cieadrienm.simplevectorizer",
            githubRepo: "cieadrienm/SimpleVectorizer",
            currentVersion: AppVersion.current.version,
            currentBuild: Int(AppVersion.current.build ?? "1") ?? 1,
            startAutoCheck: startServices
        )
        loadRecentURLs()
        if persistEnabled {
            if UserDefaults.standard.object(forKey: Self.blackOnWhiteKey) != nil {
                self.blackOnWhitePreview = UserDefaults.standard.bool(forKey: Self.blackOnWhiteKey)
            }
            if UserDefaults.standard.object(forKey: Self.showAxiDrawSectionKey) != nil {
                self.showAxiDrawSection = UserDefaults.standard.bool(forKey: Self.showAxiDrawSectionKey)
            }
        }
        if loadDefaultPreset {
            self.vectorizer.loadPreset(.portrait, runSynchronously: !startServices)
        }
    }

    func setOutputMode(_ mode: VectorOutputMode) {
        guard vectorizer.params.outputMode != mode else { return }
        vectorizer.params.outputMode = mode
        withAnimation(.easeInOut(duration: 0.16)) {
            showAxiDrawSection = (mode == .axidraw)
        }
        vectorizer.scheduleVectorization(debounceMs: 10)
    }

    func flash(_ message: String) {
        flashMessage = message
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.flashMessage = nil
        }
    }

    // MARK: - Zoom & Pan (Trackpad + Mouse)

    func resetZoom(animated: Bool = true) {
        if animated {
            withAnimation(.spring(duration: 0.18, bounce: 0.0)) {
                zoomScale = 1.0
                panOffset = .zero
            }
        } else {
            zoomScale = 1.0
            panOffset = .zero
        }
    }

    func zoomIn() {
        withAnimation(.easeOut(duration: 0.14)) {
            applyZoom(newScale: zoomScale * 1.25, anchorFromCenter: .zero)
        }
    }

    func zoomOut() {
        withAnimation(.easeOut(duration: 0.14)) {
            applyZoom(newScale: zoomScale / 1.25, anchorFromCenter: .zero)
        }
    }

    /// Installs a window-level key monitor so single-key shortcuts (`Z` to reset view, `H`/`V`/`E`/`P` tools, `⌫`, `⎋`)
    /// work anywhere in the main window regardless of which control currently holds focus.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleWindowKeyDown(event) } ? nil : event
        }
    }

    private var hasOpenSheet: Bool {
        showAbout || showHelp || showShortcuts || showOSCGuide || showExport || showUpdater
    }

    func handleWindowKeyDown(_ event: NSEvent) -> Bool {
        guard !hasOpenSheet else { return false }
        if let responder = event.window?.firstResponder, responder is NSText {
            return false
        }
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyCode = event.keyCode

        if flags.isEmpty {
            if keyCode == 51 || keyCode == 117 {
                if !selectedPathIDs.isEmpty {
                    deleteSelectedPaths()
                    return true
                }
            }
            if keyCode == 53 {
                if !selectedPathIDs.isEmpty || selectedVertex != nil {
                    clearSelection()
                    return true
                }
            }
            switch chars {
            case "z":
                resetZoom(animated: true)
                return true
            case "b":
                blackOnWhitePreview.toggle()
                return true
            case "h":
                editTool = .pan
                return true
            case "v":
                editTool = .select
                return true
            case "e":
                editTool = .erase
                return true
            case "p":
                editTool = .draw
                return true
            default:
                break
            }
        }
        return false
    }

    /// Zooms to `newScale` keeping the point at `anchorFromCenter` (in pane points relative to pane center) stationary.
    func applyZoom(newScale: CGFloat, anchorFromCenter: CGPoint) {
        let clamped = max(0.20, min(64.0, newScale))
        guard abs(clamped - zoomScale) > 1e-5 else { return }
        let ratio = clamped / zoomScale
        panOffset = CGSize(
            width: (panOffset.width - anchorFromCenter.x) * ratio + anchorFromCenter.x,
            height: (panOffset.height - anchorFromCenter.y) * ratio + anchorFromCenter.y
        )
        zoomScale = clamped
    }

    // MARK: - Interactive Stroke Editing Actions

    func clearSelection() {
        selectedPathIDs.removeAll()
        selectedVertex = nil
    }

    func selectAllPaths() {
        guard let layers = vectorizer.result?.layers else { return }
        var all = Set<Int>()
        for l in layers where l.visible {
            for p in l.paths {
                all.insert(p.id)
            }
        }
        selectedPathIDs = all
        selectedVertex = nil
    }

    func deleteSelectedPaths() {
        guard !selectedPathIDs.isEmpty else { return }
        let count = vectorizer.deletePaths(ids: selectedPathIDs)
        selectedPathIDs.removeAll()
        selectedVertex = nil
        if count > 0 {
            flash(L("\(count) trait\(count > 1 ? "s" : "") supprimé\(count > 1 ? "s" : "") (⌘Z pour annuler)", "\(count) stroke\(count > 1 ? "s" : "") deleted (⌘Z to undo)"))
        }
    }

    func assignSelectedToPen(_ penIndex: Int) {
        guard !selectedPathIDs.isEmpty else { return }
        vectorizer.assignPathsToPen(ids: selectedPathIDs, targetPenIndex: penIndex)
        flash(L("Affecté au Stylo \(penIndex + 1)", "Assigned to Pen \(penIndex + 1)"))
    }

    func simplifySelectedPaths() {
        guard !selectedPathIDs.isEmpty else { return }
        vectorizer.simplifySelectedPaths(ids: selectedPathIDs)
        flash(L("Traits sélectionnés simplifiés", "Selected strokes simplified"))
    }

    func reverseSelectedPaths() {
        guard !selectedPathIDs.isEmpty else { return }
        vectorizer.reverseSelectedPaths(ids: selectedPathIDs)
        flash(L("Sens de tracé inversé", "Stroke direction reversed"))
    }

    func joinSelectedPaths() {
        guard selectedPathIDs.count >= 2 else { return }
        if let newID = vectorizer.joinSelectedPaths(ids: selectedPathIDs) {
            selectedPathIDs = [newID]
            selectedVertex = nil
            flash(L("Traits reliés en un seul chemin", "Strokes joined into a single path"))
        }
    }

    func splitAtSelectedVertex() {
        guard let sv = selectedVertex else { return }
        if let (idA, idB) = vectorizer.splitPath(pathID: sv.pathID, atVertexIndex: sv.index) {
            selectedPathIDs = [idA, idB]
            selectedVertex = nil
            flash(L("Trait scindé en deux", "Stroke split in two"))
        }
    }

    func undoEdit() {
        guard vectorizer.canUndo else { return }
        vectorizer.undo()
        clearSelection()
        flash(L("Modification annulée", "Edit undone"))
    }

    func redoEdit() {
        guard vectorizer.canRedo else { return }
        vectorizer.redo()
        clearSelection()
        flash(L("Modification rétablie", "Edit redone"))
    }

    // MARK: - Recent Files Persistence

    private func loadRecentURLs() {
        var urls: [URL] = []
        if let savedPaths = UserDefaults.standard.stringArray(forKey: Self.recentPathsKey) {
            for p in savedPaths {
                let u = URL(fileURLWithPath: p)
                if FileManager.default.fileExists(atPath: u.path) && !urls.contains(u) {
                    urls.append(u)
                }
            }
        }
        for u in NSDocumentController.shared.recentDocumentURLs {
            if FileManager.default.fileExists(atPath: u.path) && !urls.contains(u) {
                urls.append(u)
            }
        }
        self.recentURLs = Array(urls.prefix(12))
    }

    private func recordRecentURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        recentURLs.removeAll { $0.standardizedFileURL.path == standardized.path }
        recentURLs.insert(standardized, at: 0)
        if recentURLs.count > 12 {
            recentURLs = Array(recentURLs.prefix(12))
        }
        if persistEnabled {
            UserDefaults.standard.set(recentURLs.map(\.path), forKey: Self.recentPathsKey)
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
        }
    }

    func clearRecentURLs() {
        recentURLs.removeAll()
        if persistEnabled {
            UserDefaults.standard.removeObject(forKey: Self.recentPathsKey)
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
    }

    // MARK: - File Open / Export / Pasteboard

    func openImagePanel() {
        let panel = NSOpenPanel()
        panel.title = L("Ouvrir un dessin ou une image", "Open Drawing or Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .bmp, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func open(_ url: URL) {
        if vectorizer.loadFile(at: url) {
            clearSelection()
            resetZoom(animated: false)
            recordRecentURL(url)
        }
    }

    func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first {
            open(first)
            return
        }
        if let image = NSImage(pasteboard: pb) {
            _ = vectorizer.loadNSImage(image, title: L("Presse-papiers", "Clipboard"))
            clearSelection()
            resetZoom(animated: false)
            flash(L("Image collée depuis le presse-papiers", "Image pasted from clipboard"))
        }
    }

    func copySVGToPasteboard() {
        guard let res = vectorizer.result else { return }
        Self.copyToPasteboard(res.svgAxiDraw)
        flash(L("SVG AxiDraw copié dans le presse-papiers (\(res.metrics.pathCount) chemins)", "AxiDraw SVG copied to clipboard (\(res.metrics.pathCount) paths)"))
    }

    func saveSVGPushPanel() {
        guard let res = vectorizer.result else { return }
        let panel = NSSavePanel()
        panel.title = L("Enregistrer le SVG pour AxiDraw", "Save AxiDraw SVG")
        let baseName = (vectorizer.sourceURL?.deletingPathExtension().lastPathComponent)
            ?? vectorizer.activePreset?.rawValue
            ?? "vectorized"
        panel.nameFieldStringValue = "\(baseName)-axidraw.svg"
        panel.allowedContentTypes = [.svg]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try res.svgAxiDraw.write(to: url, atomically: true, encoding: .utf8)
                flash(L("Enregistré : \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)"))
            } catch {
                flash(L("Erreur d'écriture : \(error.localizedDescription)", "Write error: \(error.localizedDescription)"))
            }
        }
    }

    func copyExport() {
        guard let res = vectorizer.result else { return }
        let text = SVGExporter.render(result: res, params: vectorizer.params, format: exportFormat)
        Self.copyToPasteboard(text)
        showExport = false
        flash(L("Export \(exportFormat.rawValue.uppercased()) copié dans le presse-papiers", "\(exportFormat.rawValue.uppercased()) export copied to clipboard"))
    }

    func saveExport() {
        guard let res = vectorizer.result else { return }
        let text = SVGExporter.render(result: res, params: vectorizer.params, format: exportFormat)
        let panel = NSSavePanel()
        panel.title = L("Exporter le tracé", "Export Plot")
        let baseName = (vectorizer.sourceURL?.deletingPathExtension().lastPathComponent)
            ?? vectorizer.activePreset?.rawValue
            ?? "vectorized"
        panel.nameFieldStringValue = "\(baseName).\(exportFormat.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                showExport = false
                flash(L("Exporté : \(url.lastPathComponent)", "Exported: \(url.lastPathComponent)"))
            } catch {
                flash(L("Erreur : \(error.localizedDescription)", "Error: \(error.localizedDescription)"))
            }
        }
    }

    static func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
