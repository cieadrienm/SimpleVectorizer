import AppKit
import SimpleVectorizerCore
import SwiftUI

// MARK: - Export Sheet

struct ExportSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Exporter le tracé vectoriel & la fiche AxiDraw", "Export Vector Plot & AxiDraw Report"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text.swiftUI)

            SectionHeader("Format")
            VStack(spacing: 4) {
                ForEach(VectorExportFormat.allCases) { format in
                    let active = model.exportFormat == format
                    Button { model.exportFormat = format } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(active ? Theme.accent.swiftUI : Theme.textFaint.swiftUI)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text.swiftUI)
                                Text(format.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.laneSelected.swiftUI : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button(L("Annuler", "Cancel")) { model.showExport = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                TextButton(title: L("Copier", "Copy"), symbol: "doc.on.doc") { model.copyExport() }
                TextButton(title: L("Enregistrer…", "Save…"), symbol: "square.and.arrow.down", prominent: true) { model.saveExport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

// MARK: - OSC, HTTP & MCP Reference Sheet

struct OSCGuideSheet: View {
    @Bindable var model: AppModel
    let close: () -> Void

    private static var oscExamples: [(String, String, String)] {
        [
            ("/simplevectorizer/algorithm", "neural_centerline", L("Choisir l'algorithme (neural_centerline, vision_contours, skeletonize, canny_edges)", "Select algorithm (neural_centerline, vision_contours, skeletonize, canny_edges)")),
            ("/simplevectorizer/threshold", "0 … 255", L("Régler le seuil binaire ou la sensibilité adaptative", "Set binary threshold or adaptive sensitivity")),
            ("/simplevectorizer/blur", "0.0 … 10.0", L("Régler le rayon du flou gaussien vDSP", "Set vDSP Gaussian blur radius")),
            ("/simplevectorizer/tolerance", "0.1 … 5.0", L("Régler la tolérance de simplification RDP en pixels", "Set RDP simplification tolerance in pixels")),
            ("/simplevectorizer/smoothing", "0.0 … 1.0", L("Régler le lissage cubique de Bézier (algorithme de Schneider)", "Set cubic Bézier smoothing (Schneider algorithm)")),
            ("/simplevectorizer/continuity", "0 … 100", L("Régler l'agressivité de fusion des segments continus", "Set multi-pass stroke stitching continuity")),
            ("/simplevectorizer/pens", "1 … 4", L("Choisir le nombre de stylos classifiés par épaisseur (k-means)", "Set number of pens classified by stroke width (k-means)")),
            ("/simplevectorizer/paper", "A4 | A3 | A5 | A6", L("Changer le format de feuille physique pour AxiDraw", "Change physical paper format for AxiDraw")),
            ("/simplevectorizer/hatch", "1 | 0", L("Activer (1) ou désactiver (0) le hachurage des aplats sombres", "Enable (1) or disable (0) dark region hatching")),
            ("/simplevectorizer/open", "\"/chemin/image.png\"", L("Charger et vectoriser un fichier image", "Load and vectorize an image file")),
            ("/simplevectorizer/export", "\"/tmp/tracé.svg\"", L("Exporter le SVG AxiDraw vers un chemin disque", "Export AxiDraw SVG to a disk path")),
        ]
    }

    private static let mcpConfigJSON = """
    {
      "mcpServers": {
        "simplevectorizer": {
          "command": "/Applications/SimpleVectorizer.app/Contents/MacOS/simplevectorizer-mcp"
        }
      }
    }
    """

    var body: some View {
        let oscPort = model.vectorizer.oscServer?.port ?? kSimpleVectorizerDefaultOSCInPort
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Pilotage OSC, API HTTP & Serveur MCP — SimpleVectorizer", "OSC Control, HTTP API & MCP Server — SimpleVectorizer"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L("Automatisation depuis OSCScore, Montage, eMotion, ligne de commande ou un agent MCP.", "Automation from OSCScore, Montage, eMotion, command line, or an MCP agent."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                Spacer()
                Chip(text: "OSC UDP :\(oscPort)", tint: Theme.osc.swiftUI, filled: true)
                Chip(text: "HTTP/MCP :\(model.vectorizer.httpPort)", tint: Theme.tcp.swiftUI)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            SectionHeader(L("Adresses OSC entrantes (cliquer pour copier)", "Incoming OSC Addresses (click to copy)"))
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(Self.oscExamples, id: \.0) { addr, arg, desc in
                        Button {
                            AppModel.copyToPasteboard(addr)
                            model.flash(L("Copié : \(addr)", "Copied: \(addr)"))
                        } label: {
                            HStack(spacing: 10) {
                                Text(addr)
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.osc.swiftUI)
                                    .frame(width: 225, alignment: .leading)
                                Text(arg)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.accent.swiftUI)
                                    .frame(width: 120, alignment: .leading)
                                Text(desc)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textFaint.swiftUI)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 235)

            SectionHeader(L("Serveur MCP (simplevectorizer-mcp), CLI & API HTTP", "MCP Server (simplevectorizer-mcp), CLI & HTTP API"))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "MCP (stdio) : /Applications/SimpleVectorizer.app/Contents/MacOS/simplevectorizer-mcp")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.tcp.swiftUI)
                    .textSelection(.enabled)
                Text(verbatim: "CLI : SimpleVectorizer --vectorize dessin.png -o sortie.svg --paper A4 --pens 2")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.text.swiftUI)
                    .textSelection(.enabled)
                Text(verbatim: "HTTP : POST http://127.0.0.1:\(model.vectorizer.httpPort)/v1/export {\"outputPath\":\"/tmp/out.svg\"}")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .textSelection(.enabled)
            }

            HStack {
                TextButton(title: L("Copier config MCP JSON", "Copy MCP JSON Config"), symbol: "doc.on.doc", compact: true) {
                    AppModel.copyToPasteboard(Self.mcpConfigJSON)
                    model.flash(L("Configuration MCP copiée", "MCP configuration copied"))
                }
                Spacer()
                Button(L("Fermer", "Close"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 760)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

// MARK: - About Sheet (G60)

struct AboutSheet: View {
    @Bindable var model: AppModel
    let openHelp: () -> Void
    let close: () -> Void
    @State private var copiedVersion = false

    private struct Feature: Identifiable {
        var id: String { title }
        let icon: String
        let tint: NSColor
        let title: String
        let detail: String
    }

    private static var features: [Feature] {
        [
            Feature(
                icon: "cpu.fill",
                tint: Theme.accent,
                title: L("Ligne médiane ANE & Sub-pixel de Steger", "ANE Centerline & Steger Sub-Pixel"),
                detail: L("Extraction de crêtes curvilignes par Hessien + Apple Vision sur Neural Engine, squelette Guo-Hall 8-connexe et affinement sub-pixel d'ordre 2.", "Curvilinear Hessian ridge + Apple Vision on Neural Engine, 8-connected Guo-Hall skeleton, and 2nd-order Taylor sub-pixel refinement.")
            ),
            Feature(
                icon: "scribble.variable",
                tint: Theme.tcp,
                title: L("Courbes de Bézier de Schneider & Croisements", "Schneider Bézier Fitting & Junctions"),
                detail: L("Ajustement cubique par moindres carrés avec préservation des angles vifs et traversée colinéaire des croisements sans casser le trait.", "Least-squares cubic Bézier fitting with sharp corner preservation and collinear junction crossing without breaking strokes.")
            ),
            Feature(
                icon: "paintbrush.pointed.fill",
                tint: Theme.alive,
                title: L("Séparation multi-stylos & Calques AxiDraw", "Multi-Pen Clustering & AxiDraw Layers"),
                detail: L("Transformée en distance euclidienne exacte et classification k-means jusqu'à 4 stylos en calques Inkscape prêts pour AxiDraw.", "Exact Euclidean distance transform and k-means clustering into up to 4 pen layers compatible with Inkscape and AxiDraw.")
            ),
            Feature(
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                tint: Theme.osc,
                title: L("Optimisation 2-opt, CLI, OSC & MCP", "2-Opt Toolpath, CLI, OSC & MCP"),
                detail: L("Ordonnancement réversible plus proche voisin + recherche locale 2-opt réduisant les trajets stylo levé, pilotable en CLI, OSC et MCP.", "Reversible nearest-neighbor + 2-opt local search minimizing pen-up travel distance, controllable via CLI, OSC, and MCP.")
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x222731)), Color(nsColor: NSColor(hex: 0x0E1014))], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
                    VectorizerHeroGraphic(active: false, size: 58)
                }
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("SimpleVectorizer")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Button {
                            AppModel.copyToPasteboard(AppVersion.current.cliLine)
                            copiedVersion = true
                        } label: {
                            Text(copiedVersion ? L("copié", "copied") : AppVersion.current.shortLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.background.swiftUI)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent.swiftUI))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(L("Vectoriseur de dessins au trait natif pour traceurs AxiDraw — ligne médiane sub-pixel, Bézier de Schneider & multi-stylos", "Native line-drawing vectorizer for AxiDraw plotters — sub-pixel centerline, Schneider Bézier curves & multi-pen layers"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        pill(icon: "cpu", text: "ANE · Vision · vDSP", tint: Theme.accent)
                        pill(icon: "waveform.path", text: "OSC UDP :\(model.vectorizer.oscServer?.port ?? kSimpleVectorizerDefaultOSCInPort)", tint: Theme.osc)
                        pill(icon: "network", text: "HTTP / MCP :\(model.vectorizer.httpPort)", tint: Theme.tcp)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("POINTS FORTS", "HIGHLIGHTS"))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textFaint.swiftUI)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.features) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.tint.swiftUI)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(item.tint.swiftUI.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.text.swiftUI)
                                Text(item.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    }
                }
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Adrien Mondot ·")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.text.swiftUI)
                        Button {
                            if let url = URL(string: "https://adrien-m.net") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("cie Adrien M")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .underline()
                                Text("(adrien-m.net)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9.5))
                            }
                            .foregroundStyle(Theme.accent.swiftUI)
                        }
                        .buttonStyle(.plain)
                        .help("https://adrien-m.net")
                    }
                    Text(L("Licence publique générale GNU (GPL v3+). Zéro dépendance externe, aucune télémétrie.", "GNU General Public License (GPL v3+). Zero external dependencies, zero telemetry."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint.swiftUI)
                }
                Spacer()
                Button {
                    close()
                    DispatchQueue.main.async {
                        model.showUpdater = true
                        model.updater.checkForUpdates(silent: false)
                    }
                } label: {
                    Label(
                        model.updater.availableRelease.map { L("↑ MAJ v\($0.version)", "↑ Update v\($0.version)") }
                            ?? L("Mises à jour…", "Check for Updates…"),
                        systemImage: "arrow.down.circle"
                    )
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.updater.availableRelease != nil ? Theme.accent.swiftUI : Theme.textDim.swiftUI)

                Button { close(); openHelp() } label: {
                    Label(L("Guide (⌘?)", "Guide (⌘?)"), systemImage: "book.closed").font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)
                Button("OK", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 650)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private func pill(icon: String, text: String, tint: NSColor) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint.swiftUI)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.swiftUI.opacity(0.12)))
    }
}

// MARK: - Shortcuts Sheet (G61)

struct ShortcutsSheet: View {
    let close: () -> Void

    static var groups: [(String, [(String, String)])] {
        [
            (L("Fichier, Édition & Export", "File, Edit & Export"), [
                ("⌘O", L("Ouvrir une image bitmap (ou Fichier > Ouvrir récent)", "Open a bitmap image (or File > Open Recent)")),
                ("⌘V", L("Coller une image depuis le presse-papiers", "Paste image from clipboard")),
                ("⌘S / ⌘E", L("Enregistrer le SVG multi-calques pour AxiDraw", "Save multi-layer SVG for AxiDraw")),
                ("⇧⌘C", L("Copier le code SVG AxiDraw dans le presse-papiers", "Copy AxiDraw SVG code to clipboard")),
                ("⌘Z / ⇧⌘Z", L("Annuler / rétablir une modification de trait", "Undo / redo stroke edit")),
                ("V / E / P / H", L("Outils Sélection, Gomme, Tracer un trait, Déplacer", "Select, Eraser, Draw stroke, Pan tools")),
                ("⌫ / ⌘J", L("Supprimer les traits sélectionnés / Relier deux traits", "Delete selected strokes / Join strokes")),
            ]),
            (L("Affichage & Navigation", "View & Navigation"), [
                ("⌘1 / ⌘2 / ⌘3", L("Vues Côte à côte, Superposition, Vecteur seul", "Side-by-Side, Overlay, Vector Only views")),
                ("B / ⌘B", L("Basculer le rendu traits noirs sur fond blanc", "Toggle black strokes on white paper preview")),
                ("2 doigts / Clic droit", L("Déplacer l'image (trackpad 2 doigts ou clic milieu/droit)", "Pan canvas (2-finger trackpad or middle/right drag)")),
                ("Pinch / Molette", L("Zoomer autour du curseur (pincement ou molette souris)", "Zoom around cursor (pinch or mouse scroll wheel)")),
                ("⌘K / ⌘T", L("Poignées de Bézier cubiques / Trajets stylo levé (2-opt)", "Cubic Bézier control handles / Pen-up travel moves (2-opt)")),
                ("⌥⌘S", L("Afficher ou masquer la barre latérale des paramètres", "Show or hide parameters sidebar")),
                ("Z / ⌘0 / ⌘+ / ⌘-", L("Réinitialiser la vue (100 % animé), zoom avant, zoom arrière", "Reset view (animated 100%), zoom in, zoom out")),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Raccourcis clavier — SimpleVectorizer", "Keyboard Shortcuts — SimpleVectorizer"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Button(L("Fermer", "Close"), action: close).keyboardShortcut(.defaultAction)
            }
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            HStack(alignment: .top, spacing: 18) {
                ForEach(Self.groups, id: \.0) { groupTitle, items in
                    VStack(alignment: .leading, spacing: 7) {
                        SectionHeader(groupTitle)
                        ForEach(items, id: \.0) { key, label in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(key)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.accent.swiftUI)
                                    .frame(width: 96, alignment: .leading)
                                Text(label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(width: 820)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Multi-Section Help Manual Sheet (G62)

struct HelpManualSheet: View {
    let openShortcuts: () -> Void
    let close: () -> Void

    enum SectionID: String, CaseIterable, Identifiable {
        case quickStart
        case algorithmsAndANE
        case bezierAndJunctions
        case axiDrawAndPens
        case oscAndMCP

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quickStart: return L("Démarrage rapide", "Quick Start")
            case .algorithmsAndANE: return L("Algorithmes & Neural Engine", "Algorithms & Neural Engine")
            case .bezierAndJunctions: return L("Bézier & Croisements", "Bézier & Junctions")
            case .axiDrawAndPens: return L("Stylos & Traceur AxiDraw", "Pens & AxiDraw Plotter")
            case .oscAndMCP: return L("OSC, API HTTP & MCP", "OSC, HTTP API & MCP")
            }
        }

        var icon: String {
            switch self {
            case .quickStart: return "play.circle"
            case .algorithmsAndANE: return "cpu"
            case .bezierAndJunctions: return "scribble.variable"
            case .axiDrawAndPens: return "paintbrush.pointed"
            case .oscAndMCP: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @State private var selectedSection: SectionID = .quickStart

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent.swiftUI)
                Text(L("Guide d’utilisation — SimpleVectorizer", "User Guide — SimpleVectorizer"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textFaint.swiftUI)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.header.swiftUI)

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack(spacing: 0) {
                sidebar.frame(width: 204)
                Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionContent(selectedSection)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Theme.panel.swiftUI)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack {
                Button {
                    close()
                    openShortcuts()
                } label: {
                    Label(L("Raccourcis clavier (⌘/)", "Keyboard Shortcuts (⌘/)"), systemImage: "command")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)

                Spacer()

                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.header.swiftUI)
        }
        .frame(width: 760, height: 520)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SectionID.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
                            .frame(width: 16)
                        Text(section.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Theme.laneSelected.swiftUI : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.background.swiftUI)
    }

    @ViewBuilder
    private func sectionContent(_ section: SectionID) -> some View {
        switch section {
        case .quickStart: quickStartSection
        case .algorithmsAndANE: algorithmsSection
        case .bezierAndJunctions: bezierSection
        case .axiDrawAndPens: axiDrawSection
        case .oscAndMCP: oscSection
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Démarrage rapide", "Quick Start"),
                subtitle: L("Convertir un dessin au trait bitmap en tracé vectoriel optimisé pour AxiDraw en quatre étapes.", "Convert a bitmap line drawing into an optimized AxiDraw vector plot in four steps.")
            )
            numberedStep(
                number: "1",
                title: L("Charger une image (⌘O), glisser-déposer ou coller (⌘V)", "Open an image (⌘O), drag-and-drop, or paste (⌘V)"),
                body: L("SimpleVectorizer accepte les scans et dessins en PNG, JPEG, TIFF ou BMP. Quatre dessins synthétiques de référence sont aussi disponibles dans le menu « Modèles » de la barre haute.", "SimpleVectorizer accepts scans and drawings in PNG, JPEG, TIFF, or BMP. Four reference synthetic drawings are also available in the top bar \"Presets\" menu.")
            )
            numberedStep(
                number: "2",
                title: L("Choisir l'algorithme « Ligne médiane ANE + Steger »", "Select the \"ANE Centerline + Steger\" algorithm"),
                body: L("Contrairement aux vectoriseurs classiques qui dédoublent chaque trait en deux contours intérieur/extérieur, le mode Ligne médiane extrait un unique chemin central fidèle au geste de dessin.", "Unlike standard vectorizers that double every stroke into inner/outer contours, Centerline mode extracts a single central path faithful to the drawing gesture.")
            )
            numberedStep(
                number: "3",
                title: L("Ajuster le lissage Bézier et la séparation multi-stylos", "Adjust Bézier smoothing and multi-pen separation"),
                body: L("Un cache à deux étages recalcule instantanément l'ajustement cubique de Schneider, le format papier (A4, A3, A5) et l'optimisation 2-opt sans relancer la squelettisation.", "A two-stage cache instantaneously recomputes Schneider cubic Bézier fitting, paper layout (A4, A3, A5), and 2-opt optimization without re-running skeletonization.")
            )
            numberedStep(
                number: "4",
                title: L("Exporter le SVG multi-calques pour AxiDraw (⌘S)", "Export multi-layer SVG for AxiDraw (⌘S)"),
                body: L("Le SVG généré inclut les dimensions physiques en millimètres et un groupe inkscape:groupmode=\"layer\" par stylo, directement utilisable dans Inkscape AxiDraw Control ou axicli.", "The generated SVG includes physical dimensions in millimeters and one inkscape:groupmode=\"layer\" group per pen, ready for Inkscape AxiDraw Control or axicli.")
            )
            calloutBox(
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                tint: Theme.tcp,
                title: L("Visualisation des déplacements stylo levé (⌘T)", "Visualizing pen-up rapid travel moves (⌘T)"),
                text: L("Activer le bouton de trajets dans la barre haute (⌘T) affiche en pointillés les mouvements rapides stylo levé et permet de vérifier le gain de l'ordonnancement 2-opt.", "Enabling the travel moves toggle in the top bar (⌘T) displays dashed pen-up rapid moves so 2-opt ordering gains can be inspected visually.")
            )
        }
    }

    private var algorithmsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Algorithmes & Apple Neural Engine", "Algorithms & Apple Neural Engine"),
                subtitle: L("Quatre moteurs complémentaires combinant Vision (ANE), Accelerate vDSP et géométrie différentielle.", "Four complementary engines combining Vision (ANE), Accelerate vDSP, and differential geometry.")
            )
            bulletList([
                (L("Ligne médiane ANE + Steger (recommandé pour le trait)", "ANE Centerline + Steger (recommended for line art)"), L("Combine un filtre de crêtes curvilignes par valeurs propres du Hessien (vDSP), une squelettisation 8-connexe Guo-Hall à table de vérité précalculée et l'affinement sub-pixel d'ordre 2 de Carsten Steger pour éliminer tout effet d'escalier.", "Combines a Hessian eigenvalue curvilinear ridge filter (vDSP), LUT-accelerated 8-connected Guo-Hall thinning, and Carsten Steger's 2nd-order sub-pixel refinement to eliminate pixel staircase artifacts.")),
                (L("Contours Vision ANE + Hachures", "ANE Vision Contours + Hatching"), L("Exécute VNDetectContoursRequest sur le Neural Engine / GPU pour extraire les contours fermés et peut remplir automatiquement les aplats d'encre par des hachures parallèles ou croisées.", "Runs VNDetectContoursRequest on the Neural Engine / GPU to extract closed contours and optionally fills dark ink regions with parallel or cross-hatched plotter lines.")),
                (L("Squelettisation Guo-Hall & Contours Canny", "Guo-Hall Skeletonization & Canny Edges"), L("Le mode Guo-Hall fournit un amincissement topologique pur ultra-rapide ; le mode Canny extrait les doubles bords par gradient de Sobel et hystérésis.", "Guo-Hall mode provides ultra-fast pure topological thinning; Canny mode extracts dual edges via Sobel gradient and hysteresis."))
            ])
        }
    }

    private var bezierSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Courbes de Bézier de Schneider & Croisements", "Schneider Bézier Curves & Junctions"),
                subtitle: L("Des courbes cubiques fluides qui préservent la mécanique de l'AxiDraw.", "Smooth cubic curves that protect AxiDraw mechanics.")
            )
            bulletList([
                (L("Ajustement cubique par moindres carrés (Philip Schneider)", "Least-squares cubic fitting (Philip Schneider)"), L("Au lieu d'exporter des milliers de micro-segments droits qui font vibrer les moteurs pas-à-pas, SimpleVectorizer ajuste de vraies courbes de Bézier cubiques (commandes C) avec reparamétrisation de Newton-Raphson.", "Instead of exporting thousands of tiny straight segments that cause stepper resonance, SimpleVectorizer fits true cubic Bézier curves (C commands) with Newton-Raphson reparameterization.")),
                (L("Détection des coins vifs", "Sharp corner detection"), L("Les chemins sont scindés aux angles inférieurs au seuil configuré (« Angle de coin vif ») avant l'ajustement de Bézier pour garder des angles géométriques nets.", "Paths are split at turning angles sharper than the configured \"Sharp corner angle\" before Bézier fitting so geometric corners remain crisp.")),
                (L("Traversée colinéaire des croisements X et T", "Collinear X and T junction crossing"), L("Aux intersections de hachures ou de traits croisés, SimpleVectorizer associe les branches dont les tangentes sont alignées afin que le stylo traverse le croisement d'un seul geste continu.", "At hatching or stroke intersections, SimpleVectorizer pairs branches with aligned tangents so the pen crosses the intersection in a single continuous stroke."))
            ])
        }
    }

    private var axiDrawSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("Séparation multi-stylos & Traceur AxiDraw", "Multi-Pen Separation & AxiDraw Plotter"),
                subtitle: L("Du trait fin 0,3 mm au feutre 1,2 mm, prêt à tracer sur A4 ou A3.", "From 0.3 mm fineliner to 1.2 mm marker, ready to plot on A4 or A3.")
            )
            bulletList([
                (L("Transformée en distance euclidienne exacte & k-means", "Exact Euclidean distance transform & k-means"), L("La demi-épaisseur réelle du trait est mesurée au 75e centile le long de chaque chemin via une transformée en distance 2D exacte (Meijster), puis partitionnée par k-means 1D en 1 à 4 stylos.", "True stroke half-width is measured at the 75th percentile along each path via an exact 2D Euclidean distance transform (Meijster), then partitioned via 1D k-means into 1 to 4 pens.")),
                (L("Calques Inkscape / AxiDraw normalisés", "Standardized Inkscape / AxiDraw layers"), L("Chaque stylo produit un calque <g inkscape:groupmode=\"layer\" inkscape:label=\"1 - Stylo 1 (0.3mm)\"> permettant de tracer stylo par stylo dans Inkscape ou avec axicli --mode layers.", "Each pen outputs a <g inkscape:groupmode=\"layer\" inkscape:label=\"1 - Stylo 1 (0.3mm)\"> layer, enabling pen-by-pen plotting in Inkscape or via axicli --mode layers.")),
                (L("Optimisation de parcours 2-opt réversible", "Reversible 2-opt toolpath optimization"), L("Combine un ordonnancement glouton bidirectionnel (autorisant l'inversion du sens de tracé d'un chemin ouvert) et une recherche locale 2-opt qui décroise les déplacements à vide.", "Combines bidirectional greedy nearest-neighbor ordering (allowing open path reversal) with 2-opt local search that untangles rapid pen-up travels."))
            ])
        }
    }

    private var oscSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L("OSC, API HTTP, CLI & Serveur MCP", "OSC, HTTP API, CLI & MCP Server"),
                subtitle: L("Automatisation en ligne de commande et pilotage réseau local.", "Command-line batch automation and local network control.")
            )
            bulletList([
                (L("Ligne de commande directe (--vectorize)", "Direct command line (--vectorize)"), L("SimpleVectorizer --vectorize entree.png -o sortie.svg --paper A4 --pens 2 --smoothing 0.7 convertit une image sans ouvrir de fenêtre.", "SimpleVectorizer --vectorize input.png -o output.svg --paper A4 --pens 2 --smoothing 0.7 converts an image headlessly.")),
                (L("Serveur OSC UDP (:9140) & API HTTP (127.0.0.1:17940/v1)", "OSC UDP Server (:9140) & HTTP API (127.0.0.1:17940/v1)"), L("Expose GET /v1/state, GET /v1/svg, GET /v1/snapshot.png, POST /v1/open, POST /v1/params et POST /v1/export.", "Exposes GET /v1/state, GET /v1/svg, GET /v1/snapshot.png, POST /v1/open, POST /v1/params, and POST /v1/export.")),
                (L("Serveur MCP embarqué (simplevectorizer-mcp)", "Embedded MCP Server (simplevectorizer-mcp)"), L("Le binaire /Applications/SimpleVectorizer.app/Contents/MacOS/simplevectorizer-mcp expose 6 outils MCP sur stdio pour les agents IA.", "The binary /Applications/SimpleVectorizer.app/Contents/MacOS/simplevectorizer-mcp exposes 6 MCP tools over stdio for AI agents."))
            ])
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text.swiftUI)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim.swiftUI)
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1).padding(.top, 6)
        }
    }

    private func numberedStep(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.accent.swiftUI)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent.swiftUI.opacity(0.14)))
                .overlay(Circle().strokeBorder(Theme.accent.swiftUI.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(body)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    private func bulletList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { title, detail in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.accent.swiftUI).frame(width: 5, height: 5).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textDim.swiftUI)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1.5)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.lane.swiftUI))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func calloutBox(icon: String, tint: NSColor, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint.swiftUI)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.swiftUI.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.swiftUI.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Preferences View (G63)

struct PreferencesView: View {
    @Bindable var model: AppModel
    @State private var oscPortText: String = ""
    @State private var httpPortText: String = ""

    var body: some View {
        @Bindable var updater = model.updater
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(L("Langue & Mises à jour", "Language & Updates"))
            FieldRow(L("Langue", "Language"), width: 170) {
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            HStack(spacing: 10) {
                Toggle(L("Vérifier les mises à jour au lancement", "Check for updates on launch"), isOn: $updater.autoCheckOnLaunch)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                TextButton(title: L("Vérifier maintenant…", "Check Now…"), symbol: "arrow.down.circle", compact: true) {
                    model.showUpdater = true
                    model.updater.checkForUpdates(silent: false)
                }
            }

            Divider().overlay(Theme.separator.swiftUI)

            SectionHeader(L("Ports OSC, API HTTP & MCP", "OSC, HTTP API & MCP Ports"))
            FieldRow(L("Port OSC entrant (UDP)", "Incoming OSC Port (UDP)"), width: 170) {
                HStack(spacing: 6) {
                    TextField("9140", text: $oscPortText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text.swiftUI)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(width: 80)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)))
                        .onSubmit { applyPorts() }
                    TextButton(title: L("Appliquer", "Apply"), compact: true) { applyPorts() }
                }
            }
            FieldRow("Port HTTP / MCP (127.0.0.1)", width: 170) {
                HStack(spacing: 6) {
                    TextField("17940", text: $httpPortText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text.swiftUI)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(width: 80)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)))
                        .onSubmit { applyPorts() }
                    Text(verbatim: "/v1")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
            }

            Divider().overlay(Theme.separator.swiftUI)

            SectionHeader(L("Affichage", "Display"))
            Toggle(L("Barre latérale des paramètres", "Parameters sidebar"), isOn: $model.showSidebar)
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle(L("Trajets rapides stylo levé (2-opt)", "Pen-up rapid travel moves (2-opt)"), isOn: $model.showTravelMoves)
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle(L("Poignées de contrôle de Bézier", "Bézier control handles"), isOn: $model.showControlPoints)
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)

            Divider().overlay(Theme.separator.swiftUI)

            SectionHeader(L("Confidentialité", "Privacy"))
            Text(L("SimpleVectorizer traite les images exclusivement en local sur le Mac (CPU, GPU, Apple Neural Engine) et n'ouvre que les ports locaux OSC (:9140) et HTTP/MCP (127.0.0.1:17940). Aucune télémétrie, aucune connexion externe hors vérification quotidienne optionnelle des mises à jour sur GitHub.", "SimpleVectorizer processes images strictly locally on the Mac (CPU, GPU, Apple Neural Engine) and only opens local OSC (:9140) and HTTP/MCP (127.0.0.1:17940) ports. Zero telemetry, zero external network connections besides the optional daily GitHub update check."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        .frame(width: 470, height: 490)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
        .onAppear {
            oscPortText = "\(model.vectorizer.oscServer?.port ?? kSimpleVectorizerDefaultOSCInPort)"
            httpPortText = "\(model.vectorizer.httpPort)"
        }
    }

    private func applyPorts() {
        if let oscP = UInt16(oscPortText.trimmingCharacters(in: .whitespaces)), oscP > 0 {
            model.vectorizer.startOSCServer(port: oscP)
        }
        if let httpP = UInt16(httpPortText.trimmingCharacters(in: .whitespaces)), httpP > 0 {
            model.vectorizer.startHTTPServer(port: httpP)
        }
        model.flash(L("Ports OSC (:\(oscPortText)) et HTTP/MCP (:\(httpPortText)) mis à jour", "OSC (:\(oscPortText)) and HTTP/MCP (:\(httpPortText)) ports updated"))
    }
}

// MARK: - Update Sheet

struct UpdateSheet: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        let updater = model.updater
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VectorizerHeroGraphic(active: updater.state == .checking, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Mises à jour — SimpleVectorizer", "Software Update — SimpleVectorizer"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L("Version installée : v\(updater.currentVersion) (build \(updater.currentBuild))", "Installed version: v\(updater.currentVersion) (build \(updater.currentBuild))"))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                Spacer()
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            switch updater.state {
            case .idle, .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Recherche de mises à jour en cours…", "Checking for updates…"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                .padding(.vertical, 14)

            case .upToDate(let v):
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.alive.swiftUI)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("SimpleVectorizer v\(v) est à jour.", "SimpleVectorizer v\(v) is up to date."))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(L("Aucune mise à jour plus récente n'est disponible.", "No newer update is available."))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim.swiftUI)
                    }
                }
                .padding(.vertical, 10)

            case .updateAvailable(let rel):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Chip(text: L("NOUVELLE VERSION v\(rel.version)", "NEW VERSION v\(rel.version)"), tint: Theme.accent.swiftUI, filled: true)
                        Spacer()
                    }
                    ScrollView {
                        Text(rel.localizedNotes)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text.swiftUI)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 70, maxHeight: 140)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Téléchargement de la mise à jour…", "Downloading update…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text.swiftUI)
                    ProgressView(value: progress)
                        .tint(Theme.accent.swiftUI)
                }
                .padding(.vertical, 10)

            case .installing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Vérification de la signature et installation…", "Verifying code signature and installing…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text.swiftUI)
                }
                .padding(.vertical, 10)

            case .failed(let message):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.warning.swiftUI)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Impossible de vérifier ou d'installer la mise à jour", "Could not check or install update"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim.swiftUI)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }

            HStack {
                TextButton(title: L("Rechercher à nouveau", "Check Again"), symbol: "arrow.clockwise", compact: true) {
                    updater.checkForUpdates(silent: false)
                }
                Spacer()
                if case .updateAvailable(let rel) = updater.state {
                    Button(L("Plus tard", "Later"), action: close)
                    TextButton(title: L("Mettre à jour et relancer", "Update & Relaunch"), symbol: "arrow.down.circle.fill", prominent: true) {
                        updater.downloadAndInstall(rel)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Fermer", "Close"), action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}
