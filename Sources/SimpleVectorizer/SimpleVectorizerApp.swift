import AppKit
import SimpleVectorizerCore
import SwiftUI

@main
struct SimpleVectorizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("SimpleVectorizer") {
            ContentView(model: appDelegate.model)
                .frame(minWidth: 980, minHeight: 580)
                .onAppear { appDelegate.didAppear() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1380, height: 820)
        .commands { appCommands(model: appDelegate.model) }

        Settings {
            PreferencesView(model: appDelegate.model)
        }
    }

    @CommandsBuilder
    private func appCommands(model: AppModel) -> some Commands {
        let _ = model.language
        CommandGroup(replacing: .appInfo) {
            Button(L("À propos de SimpleVectorizer", "About SimpleVectorizer")) { model.showAbout = true }
            Button(L("Rechercher des mises à jour…", "Check for Updates…")) {
                model.showUpdater = true
                model.updater.checkForUpdates(silent: false)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(L("Ouvrir une image…", "Open Image…")) { model.openImagePanel() }
                .keyboardShortcut("o", modifiers: [.command])

            Menu(L("Ouvrir récent", "Open Recent")) {
                if model.recentURLs.isEmpty {
                    Text(L("Aucun élément récent", "No Recent Items"))
                } else {
                    ForEach(model.recentURLs, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            model.open(url)
                        }
                    }
                    Divider()
                    Button(L("Effacer le menu", "Clear Menu")) {
                        model.clearRecentURLs()
                    }
                }
            }

            Divider()
            Button(L("Enregistrer le SVG AxiDraw…", "Save AxiDraw SVG…")) { model.saveSVGPushPanel() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(model.vectorizer.result == nil)
            Button(L("Exporter le tracé ou la fiche…", "Export Plot or Report…")) { model.showExport = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.vectorizer.result == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(L("Annuler", "Undo")) { model.undoEdit() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!model.vectorizer.canUndo)
            Button(L("Rétablir", "Redo")) { model.redoEdit() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.vectorizer.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button(L("Coller une image", "Paste Image")) { model.pasteImageFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command])
            Button(L("Copier le SVG AxiDraw", "Copy AxiDraw SVG")) { model.copySVGToPasteboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.vectorizer.result == nil)
            Divider()
            Button(L("Tout sélectionner", "Select All Strokes")) { model.selectAllPaths() }
                .keyboardShortcut("a", modifiers: [.command])
                .disabled(model.vectorizer.result == nil)
            Button(L("Tout désélectionner", "Deselect All")) { model.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.selectedPathIDs.isEmpty)
            Divider()
            Button(L("Supprimer les traits sélectionnés", "Delete Selected Strokes")) { model.deleteSelectedPaths() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedPathIDs.isEmpty)
            Button(L("Simplifier les traits sélectionnés", "Simplify Selected Strokes")) { model.simplifySelectedPaths() }
                .disabled(model.selectedPathIDs.isEmpty)
            Button(L("Inverser le sens des traits sélectionnés", "Reverse Selected Strokes")) { model.reverseSelectedPaths() }
                .disabled(model.selectedPathIDs.isEmpty)
            Button(L("Relier les traits sélectionnés", "Join Selected Strokes")) { model.joinSelectedPaths() }
                .keyboardShortcut("j", modifiers: [.command])
                .disabled(model.selectedPathIDs.count < 2)
        }

        CommandMenu(L("Vectorisation", "Vectorization")) {
            ForEach(VectorAlgorithm.allCases) { alg in
                Button {
                    model.vectorizer.params.algorithm = alg
                    model.vectorizer.scheduleVectorization(debounceMs: 10)
                } label: {
                    HStack {
                        if model.vectorizer.params.algorithm == alg {
                            Image(systemName: "checkmark")
                        }
                        Text(alg.label)
                    }
                }
            }
            Divider()
            Menu(L("Outil du canevas", "Canvas Tool")) {
                ForEach(CanvasEditTool.allCases) { tool in
                    Button {
                        model.editTool = tool
                    } label: {
                        HStack {
                            if model.editTool == tool {
                                Image(systemName: "checkmark")
                            }
                            Text(tool.label)
                        }
                    }
                }
            }
            Divider()
            Button(L("Relancer la vectorisation", "Re-run Vectorization")) {
                model.vectorizer.scheduleVectorization(debounceMs: 0)
            }
            .keyboardShortcut("r", modifiers: [.command])
            Button(L("Réinitialiser les paramètres", "Reset Parameters")) {
                model.vectorizer.resetParameters()
            }
            Divider()
            Menu(L("Format papier AxiDraw", "AxiDraw Paper Size")) {
                ForEach(PaperFormat.allCases) { pf in
                    Button(pf.label) {
                        model.vectorizer.params.paperFormat = pf
                        model.vectorizer.scheduleVectorization(debounceMs: 10)
                    }
                }
            }
            Menu(L("Nombre de stylos", "Pen Count")) {
                ForEach(1...4, id: \.self) { n in
                    Button(L("\(n) stylo\(n > 1 ? "s" : "")", "\(n) pen\(n > 1 ? "s" : "")")) {
                        model.vectorizer.params.penCount = n
                        model.vectorizer.scheduleVectorization(debounceMs: 10)
                    }
                }
            }
        }

        CommandGroup(after: .toolbar) {
            Button(L("Vue Côte à côte", "Side-by-Side View")) { model.viewMode = .sideBySide }
                .keyboardShortcut("1", modifiers: [.command])
            Button(L("Vue Superposition", "Overlay View")) { model.viewMode = .overlay }
                .keyboardShortcut("2", modifiers: [.command])
            Button(L("Vue Vecteur seul", "Vector Only View")) { model.viewMode = .vectorOnly }
                .keyboardShortcut("3", modifiers: [.command])
            Divider()
            Button(model.blackOnWhitePreview ? L("Aperçu sombre (couleurs stylos)", "Dark Preview (Pen Colors)") : L("Aperçu traits noirs sur fond blanc", "Black Strokes on White Paper Preview")) {
                model.blackOnWhitePreview.toggle()
            }
            .keyboardShortcut("b", modifiers: [.command])
            Button(model.showControlPoints ? L("Masquer les poignées de Bézier", "Hide Bézier Control Handles") : L("Afficher les poignées de Bézier", "Show Bézier Control Handles")) {
                model.showControlPoints.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command])
            Button(model.showTravelMoves ? L("Masquer les trajets stylo levé", "Hide Pen-Up Travel Moves") : L("Afficher les trajets stylo levé", "Show Pen-Up Travel Moves")) {
                model.showTravelMoves.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command])
            Button(model.showAxiDrawSection ? L("Replier la section Traceur AxiDraw", "Collapse AxiDraw Plotter Section") : L("Déplier la section Traceur AxiDraw", "Expand AxiDraw Plotter Section")) {
                model.showAxiDrawSection.toggle()
            }
            Button(model.showSidebar ? L("Masquer les paramètres", "Hide Parameters") : L("Afficher les paramètres", "Show Parameters")) {
                model.showSidebar.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button(L("Taille réelle (100 %)", "Actual Size (100%)")) { model.resetZoom() }
                .keyboardShortcut("0", modifiers: [.command])
            Button(L("Zoom avant", "Zoom In")) { model.zoomIn() }
                .keyboardShortcut("+", modifiers: [.command])
            Button(L("Zoom arrière", "Zoom Out")) { model.zoomOut() }
                .keyboardShortcut("-", modifiers: [.command])
            Divider()
            Button(L("Commandes OSC, HTTP & MCP…", "OSC, HTTP & MCP Commands…")) {
                model.showOSCGuide = true
            }
        }

        CommandGroup(replacing: .help) {
            Button(L("Aide SimpleVectorizer", "SimpleVectorizer Help")) { model.showHelp = true }
                .keyboardShortcut("?", modifiers: [.command])
            Divider()
            Button(L("Raccourcis clavier", "Keyboard Shortcuts")) { model.showShortcuts = true }
                .keyboardShortcut("/", modifiers: [.command])
            Button(L("Guide OSC, HTTP & MCP", "OSC, HTTP & MCP Guide")) { model.showOSCGuide = true }
            Divider()
            Button(L("Site web Simple Apps (adrien-m.net/software)", "Simple Apps Website (adrien-m.net/software)")) {
                if let url = URL(string: "https://adrien-m.net/software") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var model = AppModel(startServices: !headless, persistEnabled: !headless, loadDefaultPreset: false)
    private var headless = false
    private var didStart = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppVersion.runIfRequested()
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            headless = true
            HeadlessCLI.printHelpAndExit()
        }
        if args.contains("--self-test") {
            headless = true
            SelfTest.runAndExit()
        }
        if args.contains("--vectorize") {
            headless = true
            HeadlessCLI.runVectorizeAndExit(arguments: args)
        }
        if let index = args.firstIndex(of: "--snapshot") {
            headless = true
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("-") ? args[index + 1] : "/tmp/simplevectorizer.png"
            let view = args.firstIndex(of: "--view").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "split"
            Snapshot.runCLISnapshot(outputPath: path, view: view)
        }
    }

    func didAppear() {
        guard !didStart else { return }
        didStart = true
        NSApp.appearance = NSAppearance(named: .darkAqua)
        model.installKeyMonitor()
        let files = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let first = files.first {
            let url = URL(fileURLWithPath: (first as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                model.open(url)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let first = urls.first {
            model.open(first)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model.vectorizer.stopAllServices()
    }
}
