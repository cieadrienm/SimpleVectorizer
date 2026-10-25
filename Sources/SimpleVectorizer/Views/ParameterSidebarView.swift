import SimpleVectorizerCore
import SwiftUI

struct ParameterSidebarView: View {
    static let sidebarWidth: CGFloat = 324
    private static let innerWidth: CGFloat = sidebarWidth - 28

    @Bindable var model: AppModel

    var body: some View {
        @Bindable var vec = model.vectorizer
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                outputModeSection(vec: vec)
                algorithmSection(vec: vec)
                preprocessingSection(vec: vec)
                vectorizationSection(vec: vec)
                stitchingAndHatchSection(vec: vec)
                pensAndAxiDrawSection(vec: vec)
                metricsCard(vec: vec)
            }
            .frame(width: Self.innerWidth, alignment: .leading)
            .clipped()
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.sidebarWidth)
        .background(Theme.panel.swiftUI)
        .clipped()
    }

    // MARK: - 0. Output Mode (Illustration Variable-Width vs AxiDraw Uniform Plotter)

    @ViewBuilder
    private func outputModeSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Mode de vectorisation", "Vectorization Mode")) {
                TextButton(
                    title: L("Réinitialiser", "Reset"),
                    symbol: "arrow.counterclockwise",
                    compact: true
                ) {
                    vec.resetParameters()
                }
            }

            HStack(spacing: 6) {
                ForEach(VectorOutputMode.allCases) { mode in
                    outputModeCard(mode: mode, vec: vec)
                }
            }

            if vec.params.outputMode == .illustration {
                illustrationThicknessSection(vec: vec)
            }
        }
    }

    private func outputModeCard(mode: VectorOutputMode, vec: VectorizerController) -> some View {
        let active = (vec.params.outputMode == mode)
        let bgFill = active ? Theme.laneSelected.swiftUI : Theme.lane.swiftUI.opacity(0.6)
        let borderColor = active ? Theme.accent.swiftUI.opacity(0.55) : Color.white.opacity(0.05)
        return Button {
            model.setOutputMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
                    Text(mode.label)
                        .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Text(mode.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(active ? Theme.textDim.swiftUI : Theme.textFaint.swiftUI)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(bgFill)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.detail)
    }

    @ViewBuilder
    private func illustrationThicknessSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(spacing: 4) {
                ForEach(IllustrationStrokeStyle.allCases) { style in
                    illustrationStyleRow(style: style, vec: vec)
                }
            }

            SliderRow(
                label: L("Facteur d'épaisseur", "Thickness scale"),
                valueText: "×\(Format.decimal(vec.params.strokeWidthScale, digits: 2))",
                value: Binding(
                    get: { vec.params.strokeWidthScale },
                    set: {
                        guard abs(vec.params.strokeWidthScale - $0) > 1e-6 else { return }
                        vec.params.strokeWidthScale = $0
                        vec.scheduleVectorization(debounceMs: 12)
                    }
                ),
                range: 0.30...2.50,
                step: 0.05,
                tint: Theme.tcp.swiftUI
            )
        }
        .padding(.top, 2)
    }

    private func illustrationStyleRow(style: IllustrationStrokeStyle, vec: VectorizerController) -> some View {
        let active = (vec.params.illustrationStrokeStyle == style)
        let bgFill = active ? Theme.laneSelected.swiftUI.opacity(0.85) : Theme.lane.swiftUI.opacity(0.5)
        let borderColor = active ? Theme.tcp.swiftUI.opacity(0.45) : Color.white.opacity(0.04)
        return Button {
            guard vec.params.illustrationStrokeStyle != style else { return }
            vec.params.illustrationStrokeStyle = style
            vec.scheduleVectorization(debounceMs: 10)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(active ? Theme.tcp.swiftUI : Theme.textFaint.swiftUI.opacity(0.4))
                    .frame(width: 6.5, height: 6.5)
                Text(style.label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                Spacer(minLength: 0)
                Text(style.shortBadge)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(active ? Theme.tcp.swiftUI : Theme.textFaint.swiftUI)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(bgFill)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(borderColor, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.detail)
    }

    // MARK: - 1. Algorithm

    @ViewBuilder
    private func algorithmSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Algorithme d'extraction", "Extraction Algorithm"))

            VStack(spacing: 4) {
                ForEach(VectorAlgorithm.allCases) { alg in
                    let active = vec.params.algorithm == alg
                    Button {
                        guard vec.params.algorithm != alg else { return }
                        vec.params.algorithm = alg
                        vec.scheduleVectorization(debounceMs: 10)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(active ? Theme.accent.swiftUI : Theme.textFaint.swiftUI.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(alg.label)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                            Spacer(minLength: 0)
                            Text(alg.shortBadge)
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(active ? Theme.accent.swiftUI : Theme.textFaint.swiftUI)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(active ? Theme.laneSelected.swiftUI : Theme.lane.swiftUI.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(active ? Theme.accent.swiftUI.opacity(0.45) : Color.white.opacity(0.05), lineWidth: 1)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(alg.detail)
                }
            }
        }
    }

    // MARK: - 2. Preprocessing

    @ViewBuilder
    private func preprocessingSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Prétraitement", "Preprocessing"))

            HStack(spacing: 10) {
                Toggle(
                    L("Seuil adaptatif", "Adaptive threshold"),
                    isOn: Binding(
                        get: { vec.params.adaptiveThreshold },
                        set: {
                            guard vec.params.adaptiveThreshold != $0 else { return }
                            vec.params.adaptiveThreshold = $0
                            vec.scheduleVectorization()
                        }
                    )
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)

                Toggle(
                    L("Inverser", "Invert"),
                    isOn: Binding(
                        get: { vec.params.invert },
                        set: {
                            guard vec.params.invert != $0 else { return }
                            vec.params.invert = $0
                            vec.scheduleVectorization()
                        }
                    )
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)

                Spacer(minLength: 0)
            }

            SliderRow(
                label: vec.params.adaptiveThreshold ? L("Fenêtre & sensibilité", "Window & sensitivity") : L("Seuil binaire", "Binary threshold"),
                valueText: "\(vec.params.threshold)",
                value: Binding(
                    get: { Double(vec.params.threshold) },
                    set: {
                        let v = Int($0.rounded())
                        guard vec.params.threshold != v else { return }
                        vec.params.threshold = v
                        vec.scheduleVectorization()
                    }
                ),
                range: 10...245,
                step: 1
            )

            SliderRow(
                label: L("Flou gaussien (vDSP)", "Gaussian blur (vDSP)"),
                valueText: "\(Format.decimal(vec.params.blurRadius, digits: 1)) px",
                value: Binding(
                    get: { vec.params.blurRadius },
                    set: {
                        guard abs(vec.params.blurRadius - $0) > 1e-6 else { return }
                        vec.params.blurRadius = $0
                        vec.scheduleVectorization()
                    }
                ),
                range: 0...6,
                step: 0.2
            )

            SliderRow(
                label: L("Nettoyage morphologique", "Morphological cleanup"),
                valueText: cleanupLabel(vec.params.morphCleanup),
                value: Binding(
                    get: { Double(vec.params.morphCleanup) },
                    set: {
                        let v = Int($0.rounded())
                        guard vec.params.morphCleanup != v else { return }
                        vec.params.morphCleanup = v
                        vec.scheduleVectorization()
                    }
                ),
                range: 0...2,
                step: 1
            )
        }
    }

    private func cleanupLabel(_ v: Int) -> String {
        switch v {
        case 0: return L("0 · Traits fins", "0 · Fine lines")
        case 1: return L("1 · Fermer micro-trous", "1 · Close gaps")
        default: return L("2 · Fort (antipoussière)", "2 · Strong (denoise)")
        }
    }

    // MARK: - 3. Vectorization & Curves

    @ViewBuilder
    private func vectorizationSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Vectorisation & Courbes", "Vectorization & Curves"))

            HStack(spacing: 8) {
                Toggle(
                    L("Sub-pixel Steger", "Steger sub-pixel"),
                    isOn: Binding(
                        get: { vec.params.stegerSubpixel },
                        set: {
                            guard vec.params.stegerSubpixel != $0 else { return }
                            vec.params.stegerSubpixel = $0
                            vec.scheduleVectorization()
                        }
                    )
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)
                .help(L("Affinement sub-pixel par développement de Taylor du Hessien", "Sub-pixel refinement via 2nd-order Hessian Taylor expansion"))

                Toggle(
                    L("Croisements continus", "Cross junctions"),
                    isOn: Binding(
                        get: { vec.params.crossJunctions },
                        set: {
                            guard vec.params.crossJunctions != $0 else { return }
                            vec.params.crossJunctions = $0
                            vec.scheduleVectorization()
                        }
                    )
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)
                .help(L("Traverse les intersections X et T sans casser le trait", "Crosses X and T junctions without breaking the stroke"))

                Spacer(minLength: 0)
            }

            SliderRow(
                label: L("Tolérance RDP", "RDP tolerance"),
                valueText: "\(Format.decimal(vec.params.rdpTolerance, digits: 1)) px",
                value: Binding(
                    get: { vec.params.rdpTolerance },
                    set: {
                        guard abs(vec.params.rdpTolerance - $0) > 1e-6 else { return }
                        vec.params.rdpTolerance = $0
                        vec.scheduleVectorization(debounceMs: 15)
                    }
                ),
                range: 0.1...5.0,
                step: 0.1,
                tint: Theme.tcp.swiftUI
            )

            SliderRow(
                label: L("Lissage Bézier (Schneider)", "Bézier smoothing (Schneider)"),
                valueText: "\(Format.decimal(vec.params.curveSmoothing, digits: 2))",
                value: Binding(
                    get: { vec.params.curveSmoothing },
                    set: {
                        guard abs(vec.params.curveSmoothing - $0) > 1e-6 else { return }
                        vec.params.curveSmoothing = $0
                        vec.scheduleVectorization(debounceMs: 15)
                    }
                ),
                range: 0.0...1.0,
                step: 0.05,
                tint: Theme.tcp.swiftUI
            )

            SliderRow(
                label: L("Angle de coin vif", "Sharp corner angle"),
                valueText: "\(vec.params.cornerAngleDeg)°",
                value: Binding(
                    get: { Double(vec.params.cornerAngleDeg) },
                    set: {
                        let v = Int($0.rounded())
                        guard vec.params.cornerAngleDeg != v else { return }
                        vec.params.cornerAngleDeg = v
                        vec.scheduleVectorization(debounceMs: 15)
                    }
                ),
                range: 15...90,
                step: 1,
                tint: Theme.tcp.swiftUI
            )

            SliderRow(
                label: L("Longueur minimale", "Minimum length"),
                valueText: "\(vec.params.minPathLengthPx) px",
                value: Binding(
                    get: { Double(vec.params.minPathLengthPx) },
                    set: {
                        let v = Int($0.rounded())
                        guard vec.params.minPathLengthPx != v else { return }
                        vec.params.minPathLengthPx = v
                        vec.scheduleVectorization()
                    }
                ),
                range: 1...30,
                step: 1
            )
        }
    }

    // MARK: - 4. Stitching & Hatching

    @ViewBuilder
    private func stitchingAndHatchSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Fusion & Hachures", "Stitching & Hatching"))

            SliderRow(
                label: L("Écart max de fusion", "Max stitch gap"),
                valueText: "\(Int(vec.params.maxStitchGapPx.rounded())) px",
                value: Binding(
                    get: { vec.params.maxStitchGapPx },
                    set: {
                        guard abs(vec.params.maxStitchGapPx - $0) > 1e-6 else { return }
                        vec.params.maxStitchGapPx = $0
                        vec.scheduleVectorization()
                    }
                ),
                range: 1...24,
                step: 1
            )

            SliderRow(
                label: L("Continuité des tracés", "Stroke continuity"),
                valueText: "\(Int(vec.params.continuity.rounded())) %",
                value: Binding(
                    get: { vec.params.continuity },
                    set: {
                        guard abs(vec.params.continuity - $0) > 1e-6 else { return }
                        vec.params.continuity = $0
                        vec.scheduleVectorization()
                    }
                ),
                range: 0...100,
                step: 5
            )

            HStack(spacing: 12) {
                Toggle(
                    L("Hachurer les aplats", "Hatch dark fills"),
                    isOn: Binding(
                        get: { vec.params.hatchEnabled },
                        set: {
                            guard vec.params.hatchEnabled != $0 else { return }
                            vec.params.hatchEnabled = $0
                            vec.scheduleVectorization()
                        }
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)

                if vec.params.hatchEnabled {
                    Toggle(
                        L("Croisées", "Cross-hatch"),
                        isOn: Binding(
                            get: { vec.params.crossHatch },
                            set: {
                                guard vec.params.crossHatch != $0 else { return }
                                vec.params.crossHatch = $0
                                vec.scheduleVectorization()
                            }
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text.swiftUI)
                }
            }

            if vec.params.hatchEnabled {
                SliderRow(
                    label: L("Pas des hachures", "Hatch spacing"),
                    valueText: "\(Format.decimal(vec.params.hatchSpacingPx, digits: 1)) px",
                    value: Binding(
                        get: { vec.params.hatchSpacingPx },
                        set: {
                            guard abs(vec.params.hatchSpacingPx - $0) > 1e-6 else { return }
                            vec.params.hatchSpacingPx = $0
                            vec.scheduleVectorization()
                        }
                    ),
                    range: 3.0...16.0,
                    step: 0.5,
                    tint: Theme.osc.swiftUI
                )
            }
        }
    }

    // MARK: - 5. Multi-Pen & AxiDraw Layout (Collapsible)

    @ViewBuilder
    private func pensAndAxiDrawSection(vec: VectorizerController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle(
                    L("Noir sur blanc", "Black on white"),
                    isOn: $model.blackOnWhitePreview
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)
                .help(L("Afficher les vecteurs en traits noirs sur papier blanc (B / ⌘B)", "Render vectors as black strokes on white paper (B / ⌘B)"))

                Toggle(
                    L("SVG traits noirs", "Black SVG strokes"),
                    isOn: Binding(
                        get: { vec.params.exportBlackStrokes },
                        set: {
                            guard vec.params.exportBlackStrokes != $0 else { return }
                            vec.params.exportBlackStrokes = $0
                            vec.scheduleVectorization(debounceMs: 10)
                        }
                    )
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)

                Spacer(minLength: 0)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    model.showAxiDrawSection.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.showAxiDrawSection ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Theme.accent.swiftUI)
                        .frame(width: 10)
                    Text(L("TRACEUR AXIDRAW & STYLOS", "AXIDRAW PLOTTER & PENS"))
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(Theme.textFaint.swiftUI)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(vec.params.penCount) stylo\(vec.params.penCount > 1 ? "s" : "") · \(vec.params.paperFormat.shortLabel)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.lane.swiftUI.opacity(0.65)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Déplier ou replier les réglages spécifiques au traceur AxiDraw et aux calques multi-stylos", "Expand or collapse AxiDraw plotter and multi-pen layer settings"))

            if model.showAxiDrawSection {
                VStack(alignment: .leading, spacing: 8) {
                    SliderRow(
                        label: L("Nombre de stylos (k-means)", "Pen count (k-means)"),
                        valueText: "\(vec.params.penCount)",
                        value: Binding(
                            get: { Double(vec.params.penCount) },
                            set: {
                                let v = Int($0.rounded())
                                guard vec.params.penCount != v else { return }
                                vec.params.penCount = v
                                vec.scheduleVectorization()
                            }
                        ),
                        range: 1...4,
                        step: 1,
                        tint: Theme.accent.swiftUI
                    )

                    if let layers = vec.result?.layers {
                        VStack(spacing: 5) {
                            ForEach(layers) { layer in
                                penLayerRow(layer: layer, vec: vec)
                            }
                        }
                    }

                    FieldRow(L("Format papier", "Paper size"), width: 88) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { vec.params.paperFormat },
                                set: {
                                    guard vec.params.paperFormat != $0 else { return }
                                    vec.params.paperFormat = $0
                                    vec.scheduleVectorization(debounceMs: 10)
                                }
                            )
                        ) {
                            ForEach(PaperFormat.allCases) { pf in
                                Text(pf.label).tag(pf)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    FieldRow(L("Orientation", "Orientation"), width: 88) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { vec.params.paperOrientation },
                                set: {
                                    guard vec.params.paperOrientation != $0 else { return }
                                    vec.params.paperOrientation = $0
                                    vec.scheduleVectorization(debounceMs: 10)
                                }
                            )
                        ) {
                            ForEach(PaperOrientation.allCases) { po in
                                Text(po.label).tag(po)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if vec.params.paperFormat != .original {
                        SliderRow(
                            label: L("Marge de feuille", "Sheet margin"),
                            valueText: "\(Int(vec.params.marginMM.rounded())) mm",
                            value: Binding(
                                get: { vec.params.marginMM },
                                set: {
                                    guard abs(vec.params.marginMM - $0) > 1e-6 else { return }
                                    vec.params.marginMM = $0
                                    vec.scheduleVectorization(debounceMs: 10)
                                }
                            ),
                            range: 0...35,
                            step: 1,
                            tint: Theme.alive.swiftUI
                        )
                    }

                    Toggle(
                        L("Optimisation de parcours 2-opt (stylo levé)", "2-opt pen-up travel order"),
                        isOn: Binding(
                            get: { vec.params.optimize2Opt },
                            set: {
                                guard vec.params.optimize2Opt != $0 else { return }
                                vec.params.optimize2Opt = $0
                                vec.scheduleVectorization(debounceMs: 10)
                            }
                        )
                    )
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text.swiftUI)
                    .lineLimit(1)

                    Divider().padding(.vertical, 2)

                    directAxiDrawHardwareCard(vec: vec)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Direct AxiDraw Hardware Control Card (USB EBB / Simulator)

    @ViewBuilder
    private func directAxiDrawHardwareCard(vec: VectorizerController) -> some View {
        @Bindable var plotter = model.plotter
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(plotter.selectedDevice.isSimulator ? Theme.standby.swiftUI : Theme.alive.swiftUI)
                    .frame(width: 7, height: 7)
                Text(L("PILOTAGE DIRECT AXIDRAW (USB / EBB)", "DIRECT AXIDRAW CONTROL (USB / EBB)"))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.textFaint.swiftUI)
                    .lineLimit(1)
                Spacer(minLength: 4)
                IconButton(
                    symbol: "arrow.clockwise",
                    helpText: L("Actualiser les ports USB (/dev/cu.usbmodem*)", "Refresh USB serial ports (/dev/cu.usbmodem*)")
                ) {
                    plotter.refreshPorts()
                }
            }

            FieldRow(L("Port USB", "USB Port"), width: 76) {
                Picker("", selection: $plotter.selectedPortPath) {
                    ForEach(plotter.availablePorts) { port in
                        Text(port.displayName).tag(port.path)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldRow(L("Modèle", "Machine"), width: 76) {
                Picker("", selection: $plotter.config.machineModel) {
                    ForEach(AxiDrawMachineModel.allCases) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Manual Jog & Setup Toolbar
            axiDrawJogToolbar(vec: vec, plotter: plotter)

            // Primary Plot / Pause / Stop Action Row
            axiDrawPlotActionRow(vec: vec, plotter: plotter)

            // Pen-Change Interactive Prompt Banner
            if case let .pausedForPenChange(_, penName, widthMM) = plotter.runState {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.standby.swiftUI)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Insérez \(penName) (\(Format.decimal(widthMM, digits: 1)) mm)", "Insert \(penName) (\(Format.decimal(widthMM, digits: 1)) mm)"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(L("La tête est revenue en (0, 0). Changez de stylo puis cliquez sur Reprendre.", "Carriage is at (0, 0). Swap pen and click Resume."))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textDim.swiftUI)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.standby.swiftUI.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.standby.swiftUI.opacity(0.5), lineWidth: 1))
                )
            }

            // Servo & Speed Sliders
            SliderRow(
                label: L("Hauteur stylo haut (SP,1)", "Pen-up height (SP,1)"),
                valueText: "\(plotter.config.penUpPercent) %",
                value: Binding(
                    get: { Double(plotter.config.penUpPercent) },
                    set: {
                        plotter.config.penUpPercent = Int($0.rounded())
                        plotter.pushServoConfigIfConnected()
                    }
                ),
                range: 0...100,
                step: 2,
                tint: Theme.tcp.swiftUI
            )

            SliderRow(
                label: L("Hauteur stylo bas (SP,0)", "Pen-down height (SP,0)"),
                valueText: "\(plotter.config.penDownPercent) %",
                value: Binding(
                    get: { Double(plotter.config.penDownPercent) },
                    set: {
                        plotter.config.penDownPercent = Int($0.rounded())
                        plotter.pushServoConfigIfConnected()
                    }
                ),
                range: 0...100,
                step: 2,
                tint: Theme.tcp.swiftUI
            )

            SliderRow(
                label: L("Vitesse de tracé", "Drawing speed"),
                valueText: "\(plotter.config.drawSpeedPercent) % (~\(Int(plotter.config.drawSpeedMMPerSec.rounded())) mm/s)",
                value: Binding(
                    get: { Double(plotter.config.drawSpeedPercent) },
                    set: { plotter.config.drawSpeedPercent = Int($0.rounded()) }
                ),
                range: 5...100,
                step: 5,
                tint: Theme.alive.swiftUI
            )

            SliderRow(
                label: L("Vitesse stylo levé", "Rapid travel speed"),
                valueText: "\(plotter.config.travelSpeedPercent) % (~\(Int(plotter.config.travelSpeedMMPerSec.rounded())) mm/s)",
                value: Binding(
                    get: { Double(plotter.config.travelSpeedPercent) },
                    set: { plotter.config.travelSpeedPercent = Int($0.rounded()) }
                ),
                range: 10...100,
                step: 5,
                tint: Theme.alive.swiftUI
            )

            if vec.params.penCount > 1 {
                Toggle(
                    L("Pause en (0, 0) entre chaque stylo", "Pause at (0, 0) between pen layers"),
                    isOn: $plotter.config.pauseBetweenPenLayers
                )
                .controlSize(.small)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)
            }

            // Live Carriage Position & Status Footer
            HStack(spacing: 6) {
                Circle()
                    .fill(plotter.isPenDown ? Theme.accent.swiftUI : Theme.textFaint.swiftUI)
                    .frame(width: 6, height: 6)
                Text(plotter.statusLog)
                    .font(.system(size: 10, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.lane.swiftUI.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent.swiftUI.opacity(0.28), lineWidth: 1))
    }

    @ViewBuilder
    private func axiDrawJogToolbar(vec: VectorizerController, plotter: AxiDrawPlotterController) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                TextButton(
                    title: L("Haut", "Up"),
                    symbol: "arrow.up.to.line",
                    compact: true,
                    flexibleWidth: true,
                    disabled: plotter.runState.isBusy
                ) {
                    plotter.raisePen()
                }
                .help(L("Lever le stylo (SP,1) pour tester la hauteur haute", "Raise pen (SP,1) to test pen-up height"))

                TextButton(
                    title: L("Bas", "Down"),
                    symbol: "arrow.down.to.line",
                    compact: true,
                    flexibleWidth: true,
                    disabled: plotter.runState.isBusy
                ) {
                    plotter.lowerPen()
                }
                .help(L("Baisser le stylo (SP,0) pour régler le contact papier", "Lower pen (SP,0) to calibrate paper contact"))

                TextButton(
                    title: L("Origine", "Home"),
                    symbol: "scope",
                    compact: true,
                    flexibleWidth: true,
                    disabled: plotter.runState.isBusy
                ) {
                    plotter.returnToHome()
                }
                .help(L("Revenir à l'origine (0, 0 mm) stylo levé", "Return carriage to home (0, 0 mm) with pen up"))
            }

            HStack(spacing: 4) {
                TextButton(
                    title: L("Libérer moteurs", "Unlock motors"),
                    symbol: "lock.open",
                    compact: true,
                    flexibleWidth: true,
                    disabled: plotter.runState.isBusy
                ) {
                    plotter.unlockMotorsAndZeroOrigin()
                }
                .help(L("Couper les moteurs (EM,0,0) pour placer la tête à la main au coin (0, 0)", "De-energize motors (EM,0,0) to move carriage by hand to (0, 0)"))

                TextButton(
                    title: L("Cadrer feuille", "Frame sheet"),
                    symbol: "viewfinder",
                    compact: true,
                    flexibleWidth: true,
                    disabled: plotter.runState.isBusy || vec.result == nil
                ) {
                    if let res = vec.result {
                        plotter.startBoundingBoxFrame(result: res)
                    }
                }
                .help(L("Parcourir le cadre englobant du dessin (stylo levé) pour vérifier l'alignement papier", "Trace drawing bounding box (pen up) to check paper alignment"))
            }
        }
    }

    @ViewBuilder
    private func axiDrawPlotActionRow(vec: VectorizerController, plotter: AxiDrawPlotterController) -> some View {
        HStack(spacing: 6) {
            if plotter.runState.isBusy {
                TextButton(
                    title: L("Pause", "Pause"),
                    symbol: "pause.fill",
                    prominent: true,
                    compact: false,
                    flexibleWidth: true
                ) {
                    plotter.pausePlot()
                }
                TextButton(
                    title: L("Stop (ES)", "Stop (ES)"),
                    symbol: "stop.fill",
                    compact: false,
                    flexibleWidth: true
                ) {
                    plotter.stopPlot()
                }
            } else if plotter.runState.isPaused {
                TextButton(
                    title: L("Reprendre", "Resume"),
                    symbol: "play.fill",
                    prominent: true,
                    compact: false,
                    flexibleWidth: true
                ) {
                    plotter.resumePlot()
                }
                TextButton(
                    title: L("Annuler", "Abort"),
                    symbol: "xmark",
                    compact: false,
                    flexibleWidth: true
                ) {
                    plotter.stopPlot()
                }
            } else {
                TextButton(
                    title: plotter.selectedDevice.isSimulator
                        ? L("Simuler le tracé AxiDraw", "Simulate AxiDraw Plot")
                        : L("Tracer sur l'AxiDraw", "Plot on AxiDraw"),
                    symbol: "play.fill",
                    prominent: true,
                    compact: false,
                    flexibleWidth: true,
                    disabled: vec.result == nil
                ) {
                    if let res = vec.result {
                        plotter.startPlot(result: res)
                    }
                }
            }
        }
    }

    private func penLayerRow(layer: PenLayer, vec: VectorizerController) -> some View {
        let color = Theme.penColor(layer.index).swiftUI
        return HStack(spacing: 8) {
            Button {
                vec.toggleLayerVisibility(layer.index)
            } label: {
                Image(systemName: layer.visible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 10.5))
                    .foregroundStyle(layer.visible ? color : Theme.textFaint.swiftUI)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(L("Afficher ou masquer ce calque de stylo", "Show or hide this pen layer"))

            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(layer.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(layer.visible ? Theme.text.swiftUI : Theme.textFaint.swiftUI)

            Spacer(minLength: 4)

            Text("\(layer.paths.count) ch.")
                .font(.system(size: 10, design: .monospaced).monospacedDigit())
                .foregroundStyle(Theme.textDim.swiftUI)

            Menu {
                ForEach([0.2, 0.3, 0.4, 0.5, 0.7, 0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { w in
                    Button("\(Format.decimal(w, digits: 1)) mm") {
                        vec.updatePenWidth(layer.index, widthMM: w)
                    }
                }
            } label: {
                Text("\(Format.decimal(layer.widthMM, digits: 1)) mm")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.lane.swiftUI))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }

    // MARK: - 6. Statistics & Plotter Metrics

    @ViewBuilder
    private func metricsCard(vec: VectorizerController) -> some View {
        let m = vec.result?.metrics ?? PlotterMetrics()
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(model.showAxiDrawSection ? L("Statistiques & Traceur", "Statistics & Plotter") : L("Statistiques", "Statistics")) {
                Button {
                    model.showExport = true
                } label: {
                    Text(L("Export / Fiche…", "Export / Report…"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent.swiftUI)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 5) {
                statRow(L("Image source", "Source image"), value: m.imageWidth > 0 ? "\(m.imageWidth) × \(m.imageHeight) px" : "—")
                statRow(L("Chemins / Courbes", "Paths / Curves"), value: "\(m.pathCount) / \(m.bezierSegmentCount)", tint: Theme.accent.swiftUI)
                statRow(L("Longueur tracé", "Stroke length"), value: Format.distanceMM(m.drawDistanceMM), tint: Theme.alive.swiftUI)
                if model.showAxiDrawSection {
                    statRow(L("Feuille AxiDraw", "AxiDraw sheet"), value: "\(Int(m.pageWidthMM.rounded())) × \(Int(m.pageHeightMM.rounded())) mm")
                    statRow(
                        L("Distance voyage", "Travel distance"),
                        value: "\(Format.distanceMM(m.travelDistanceOptimizedMM)) (-\(Int(m.travelSavingsPercent.rounded())) %)",
                        tint: Theme.tcp.swiftUI
                    )
                    statRow(L("Levées de stylo", "Pen lifts"), value: "\(m.penLifts)")
                    statRow(L("Temps tracé estimé", "Estimated plot time"), value: Format.duration(m.estimatedPlotSeconds), tint: Theme.accent.swiftUI)
                }
                statRow(L("Temps de calcul", "Compute time"), value: Format.latency(m.computeMilliseconds))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lane.swiftUI))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func statRow(_ label: String, value: String, tint: Color = Theme.text.swiftUI) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
