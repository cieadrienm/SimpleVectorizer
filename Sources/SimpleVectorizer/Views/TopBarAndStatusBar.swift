import SimpleVectorizerCore
import SwiftUI

struct TopBar: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var vec = model.vectorizer
        HStack(spacing: 8) {
            IconButton(
                symbol: "sidebar.left",
                helpText: L("Afficher ou masquer les paramètres (⌥⌘S)", "Show or hide parameters (⌥⌘S)"),
                active: model.showSidebar
            ) {
                model.showSidebar.toggle()
            }

            HStack(spacing: 3) {
                TextButton(
                    title: L("Ouvrir…", "Open…"),
                    symbol: "folder",
                    compact: true
                ) {
                    model.openImagePanel()
                }
                .help(L("Ouvrir une image bitmap (⌘O)", "Open a bitmap image (⌘O)"))

                Menu {
                    if model.recentURLs.isEmpty {
                        Text(L("Aucun fichier récent", "No Recent Files"))
                    } else {
                        Section(L("Fichiers récents", "Recent Files")) {
                            ForEach(model.recentURLs, id: \.path) { url in
                                Button {
                                    model.open(url)
                                } label: {
                                    Label(url.lastPathComponent, systemImage: "doc")
                                }
                            }
                        }
                        Divider()
                        Button(L("Effacer le menu", "Clear Menu")) {
                            model.clearRecentURLs()
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("Ouvrir un fichier récent", "Open Recent File"))
            }

            Divider().frame(height: 16)

            // View Mode Selector (⌘1 Split, ⌘2 Overlay, ⌘3 AxiDraw Sheet)
            HStack(spacing: 3) {
                ForEach(CanvasViewMode.allCases) { mode in
                    let active = model.viewMode == mode
                    Button {
                        model.viewMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(mode.label)
                                .font(.system(size: 11, weight: active ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? Theme.background.swiftUI : Theme.textDim.swiftUI)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(active ? Theme.accent.swiftUI : Color.white.opacity(0.05))
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.viewMode == .overlay {
                HStack(spacing: 6) {
                    Text(L("Img", "Bmp"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                    Slider(value: $model.bitmapOpacity, in: 0...1)
                        .tint(Theme.textDim.swiftUI)
                        .controlSize(.mini)
                        .frame(width: 56)
                    Text(L("Vec", "Vec"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.accent.swiftUI)
                    Slider(value: $model.vectorOpacity, in: 0...1)
                        .tint(Theme.accent.swiftUI)
                        .controlSize(.mini)
                        .frame(width: 56)
                }
            }

            Divider().frame(height: 16)

            // Interactive Vector Editing Tools (Pan H, Select/Edit V, Eraser E, Draw P)
            HStack(spacing: 2) {
                ForEach(CanvasEditTool.allCases) { tool in
                    let active = model.editTool == tool
                    Button {
                        model.editTool = tool
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(tool.label)
                                .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? Theme.tcp.swiftUI : Theme.textDim.swiftUI)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(active ? Theme.tcp.swiftUI.opacity(0.16) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(active ? Theme.tcp.swiftUI.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help(tool.helpText)
                }
            }

            HStack(spacing: 2) {
                IconButton(
                    symbol: "arrow.uturn.backward",
                    helpText: L("Annuler la modification de trait (⌘Z)", "Undo stroke edit (⌘Z)"),
                    disabled: !vec.canUndo
                ) {
                    model.undoEdit()
                }
                IconButton(
                    symbol: "arrow.uturn.forward",
                    helpText: L("Rétablir la modification de trait (⇧⌘Z)", "Redo stroke edit (⇧⌘Z)"),
                    disabled: !vec.canRedo
                ) {
                    model.redoEdit()
                }
            }

            Divider().frame(height: 16)

            IconButton(
                symbol: model.blackOnWhitePreview ? "sun.max.fill" : "circle.lefthalf.filled",
                helpText: L("Aperçu traits noirs sur fond blanc (B / ⌘B)", "Black strokes on white paper preview (B / ⌘B)"),
                active: model.blackOnWhitePreview,
                tint: Theme.accent.swiftUI
            ) {
                model.blackOnWhitePreview.toggle()
            }

            IconButton(
                symbol: "skew",
                helpText: L("Afficher les poignées de Bézier cubiques (⌘K)", "Show cubic Bézier control handles (⌘K)"),
                active: model.showControlPoints,
                tint: Theme.osc.swiftUI
            ) {
                model.showControlPoints.toggle()
            }

            if model.showAxiDrawSection {
                IconButton(
                    symbol: "point.topleft.down.curvedto.point.bottomright.up",
                    helpText: L("Afficher les trajets stylo levé AxiDraw (⌘T)", "Show AxiDraw pen-up rapid travel moves (⌘T)"),
                    active: model.showTravelMoves,
                    tint: Theme.tcp.swiftUI
                ) {
                    model.showTravelMoves.toggle()
                }
            }

            Spacer(minLength: 6)

            outputModeQuickButton(vec: vec)

            // Algorithm & Paper badges
            Chip(text: vec.params.algorithm.shortBadge, tint: Theme.alive.swiftUI)
            if model.showAxiDrawSection {
                Chip(text: vec.params.paperFormat.shortLabel, tint: Theme.tcp.swiftUI)
            }

            Divider().frame(height: 16)

            if model.showAxiDrawSection || vec.params.outputMode == .axidraw {
                axiDrawTopToolbarButton(vec: vec)
            }

            TextButton(
                title: L("Copier SVG", "Copy SVG"),
                symbol: "doc.on.doc",
                compact: true,
                disabled: vec.result == nil
            ) {
                model.copySVGToPasteboard()
            }
            .help(L("Copier le SVG dans le presse-papiers (⇧⌘C)", "Copy SVG to clipboard (⇧⌘C)"))

            TextButton(
                title: L("Exporter SVG…", "Export SVG…"),
                symbol: "square.and.arrow.down",
                prominent: true,
                compact: true,
                disabled: vec.result == nil
            ) {
                model.saveSVGPushPanel()
            }
            .help(L("Enregistrer le fichier SVG (⌘S / ⌘E)", "Save SVG file (⌘S / ⌘E)"))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.header.swiftUI)
    }

    @ViewBuilder
    private func axiDrawTopToolbarButton(vec: VectorizerController) -> some View {
        let plotter = model.plotter
        if plotter.runState.isBusy {
            TextButton(
                title: L("Pause AxiDraw", "Pause AxiDraw"),
                symbol: "pause.fill",
                compact: true
            ) {
                plotter.pausePlot()
            }
        } else if plotter.runState.isPaused {
            TextButton(
                title: L("Reprendre", "Resume"),
                symbol: "play.fill",
                prominent: true,
                compact: true
            ) {
                plotter.resumePlot()
            }
        } else {
            TextButton(
                title: L("Tracer AxiDraw", "Plot AxiDraw"),
                symbol: "play.fill",
                compact: true,
                disabled: vec.result == nil
            ) {
                if let res = vec.result {
                    plotter.startPlot(result: res)
                }
            }
            .help(L("Lancer directement le tracé sur l'AxiDraw USB (ou le simulateur)", "Start plotting directly on USB AxiDraw (or simulator)"))
        }
    }

    @ViewBuilder
    private func outputModeQuickButton(vec: VectorizerController) -> some View {
        let isIllus = (vec.params.outputMode == .illustration)
        let badgeText = isIllus ? vec.params.illustrationStrokeStyle.shortBadge : L("AxiDraw", "AxiDraw")
        let badgeTint = isIllus ? Theme.tcp.swiftUI : Theme.accent.swiftUI
        Button {
            let next: VectorOutputMode = isIllus ? .axidraw : .illustration
            model.setOutputMode(next)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vec.params.outputMode.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(badgeTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(badgeTint.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .help(vec.params.outputMode.detail)
    }
}

struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        let vec = model.vectorizer
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                if vec.isProcessing {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(vec.lastError != nil ? Theme.danger.swiftUI : Theme.alive.swiftUI)
                        .frame(width: 6, height: 6)
                }
                Text(model.flashMessage ?? (vec.isProcessing ? vec.progressStage : vec.statusMessage))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(vec.lastError != nil ? Theme.danger.swiftUI : Theme.textDim.swiftUI)
                    .lineLimit(1)
            }

            Spacer()

            if let m = vec.result?.metrics {
                Text(
                    L(
                        "\(m.bezierSegmentCount) courbes · \(m.penLifts) levées · ~\(Format.duration(m.estimatedPlotSeconds))",
                        "\(m.bezierSegmentCount) curves · \(m.penLifts) lifts · ~\(Format.duration(m.estimatedPlotSeconds))"
                    )
                )
                .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                .foregroundStyle(Theme.textFaint.swiftUI)
            }

            Divider().frame(height: 12)

            // Right-hand links in strict G53 order: OSC, ? aide, ⌘/ raccourcis, version, ↑ MAJ
            HStack(spacing: 12) {
                Button { model.showOSCGuide = true } label: {
                    Text(verbatim: "OSC :\(vec.oscServer?.port ?? kSimpleVectorizerDefaultOSCInPort)")
                        .foregroundStyle(Theme.osc.swiftUI)
                }
                .buttonStyle(.plain)
                .help(L("Commandes OSC, API HTTP et serveur MCP", "OSC commands, HTTP API, and MCP server"))

                Button { model.showHelp = true } label: { Text(L("? aide", "? help")) }
                    .buttonStyle(.plain)
                    .help(L("Guide d'utilisation (⌘?)", "User Guide (⌘?)"))

                Button { model.showShortcuts = true } label: { Text(L("⌘/ raccourcis", "⌘/ shortcuts")) }
                    .buttonStyle(.plain)
                    .help(L("Raccourcis clavier (⌘/)", "Keyboard Shortcuts (⌘/)"))

                Button { model.showAbout = true } label: {
                    Text(AppVersion.current.shortLabel)
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain)
                .help(L("À propos de SimpleVectorizer \(AppVersion.current.description)", "About SimpleVectorizer \(AppVersion.current.description)"))

                if let rel = model.updater.availableRelease {
                    Button {
                        model.showUpdater = true
                    } label: {
                        Text(L("↑ MAJ v\(rel.version)", "↑ Update v\(rel.version)"))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.background.swiftUI)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.accent.swiftUI))
                    }
                    .buttonStyle(.plain)
                    .help(L("Mise à jour SimpleVectorizer v\(rel.version) disponible", "SimpleVectorizer v\(rel.version) update available"))
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Theme.textFaint.swiftUI)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Theme.panel.swiftUI)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator.swiftUI).frame(height: 1) }
    }
}
