import AppKit
import SimpleVectorizerCore
import SwiftUI

/// Geometry helper mapping between a pane's local coordinates `(0...paneW, 0...paneH)`
/// (including `zoomScale` and `panOffset`) and image pixel coordinates `(0...imageW, 0...imageH)`.
struct CanvasTransformGeometry {
    let paneSize: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize
    let pageTransform: PageTransform
    let showPaperFrame: Bool

    /// Fitted sheet rect inside `paneSize` (with 20pt padding) BEFORE `zoomScale` and `panOffset`.
    var baseSheetRect: CGRect {
        let pad: CGFloat = 20
        let availW = max(8, paneSize.width - pad * 2)
        let availH = max(8, paneSize.height - pad * 2)
        let aspect: CGFloat = showPaperFrame
            ? CGFloat(max(1.0, pageTransform.pageWidthMM) / max(1.0, pageTransform.pageHeightMM))
            : CGFloat(max(1, pageTransform.imageWidth)) / CGFloat(max(1, pageTransform.imageHeight))

        let fittedW: CGFloat
        let fittedH: CGFloat
        if availW / availH > aspect {
            fittedH = availH
            fittedW = availH * aspect
        } else {
            fittedW = availW
            fittedH = availW / aspect
        }
        return CGRect(
            x: (paneSize.width - fittedW) * 0.5,
            y: (paneSize.height - fittedH) * 0.5,
            width: fittedW,
            height: fittedH
        )
    }

    var scaleX: CGFloat {
        let rect = baseSheetRect
        if showPaperFrame && !pageTransform.isRawPixels {
            let mmToCanvasX = rect.width / CGFloat(max(1.0, pageTransform.pageWidthMM))
            return CGFloat(pageTransform.scalePxToMM) * mmToCanvasX
        } else {
            return rect.width / CGFloat(max(1, pageTransform.imageWidth))
        }
    }

    var scaleY: CGFloat {
        let rect = baseSheetRect
        if showPaperFrame && !pageTransform.isRawPixels {
            let mmToCanvasY = rect.height / CGFloat(max(1.0, pageTransform.pageHeightMM))
            return CGFloat(pageTransform.scalePxToMM) * mmToCanvasY
        } else {
            return rect.height / CGFloat(max(1, pageTransform.imageHeight))
        }
    }

    var offX: CGFloat {
        let rect = baseSheetRect
        if showPaperFrame && !pageTransform.isRawPixels {
            let mmToCanvasX = rect.width / CGFloat(max(1.0, pageTransform.pageWidthMM))
            return rect.minX + CGFloat(pageTransform.offsetXMM) * mmToCanvasX
        } else {
            return rect.minX
        }
    }

    var offY: CGFloat {
        let rect = baseSheetRect
        if showPaperFrame && !pageTransform.isRawPixels {
            let mmToCanvasY = rect.height / CGFloat(max(1.0, pageTransform.pageHeightMM))
            return rect.minY + CGFloat(pageTransform.offsetYMM) * mmToCanvasY
        } else {
            return rect.minY
        }
    }

    /// Converts an image pixel point `(0...imageW, 0...imageH)` to screen point in the pane (including zoom & pan).
    func imageToPane(_ pt: VectorPoint) -> CGPoint {
        let basePt = CGPoint(
            x: offX + CGFloat(pt.x) * scaleX,
            y: offY + CGFloat(pt.y) * scaleY
        )
        let center = CGPoint(x: paneSize.width * 0.5, y: paneSize.height * 0.5)
        return CGPoint(
            x: center.x + (basePt.x - center.x) * zoomScale + panOffset.width,
            y: center.y + (basePt.y - center.y) * zoomScale + panOffset.height
        )
    }

    /// Zoomed and panned sheet rectangle in pane coordinates.
    var zoomedSheetRect: CGRect {
        let base = baseSheetRect
        let center = CGPoint(x: paneSize.width * 0.5, y: paneSize.height * 0.5)
        let minX = center.x + (base.minX - center.x) * zoomScale + panOffset.width
        let minY = center.y + (base.minY - center.y) * zoomScale + panOffset.height
        return CGRect(
            x: minX,
            y: minY,
            width: base.width * zoomScale,
            height: base.height * zoomScale
        )
    }

    /// Printable margin guide rectangle in pane coordinates when `showPaperFrame` is active.
    func zoomedMarginRect(marginMM: Double) -> CGRect? {
        guard showPaperFrame, !pageTransform.isRawPixels else { return nil }
        let sheet = zoomedSheetRect
        let marginX = CGFloat(marginMM / max(1.0, pageTransform.pageWidthMM)) * sheet.width
        let marginY = CGFloat(marginMM / max(1.0, pageTransform.pageHeightMM)) * sheet.height
        guard marginX * 2 < sheet.width, marginY * 2 < sheet.height else { return nil }
        return sheet.insetBy(dx: marginX, dy: marginY)
    }

    /// Affine transform mapping image pixel coordinates `(0...imageW, 0...imageH)` directly to pane screen coordinates.
    var imageToPaneTransform: CGAffineTransform {
        let center = CGPoint(x: paneSize.width * 0.5, y: paneSize.height * 0.5)
        let sx = scaleX * zoomScale
        let sy = scaleY * zoomScale
        let tx = center.x + (offX - center.x) * zoomScale + panOffset.width
        let ty = center.y + (offY - center.y) * zoomScale + panOffset.height
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty)
    }

    /// Visible rectangle in image pixel space (with a 24px safety margin) for frustum culling at high zoom.
    var visibleImageRect: CGRect {
        let p0 = paneToImage(.zero)
        let p1 = paneToImage(CGPoint(x: paneSize.width, y: paneSize.height))
        let minX = min(p0.x, p1.x)
        let minY = min(p0.y, p1.y)
        let maxX = max(p0.x, p1.x)
        let maxY = max(p0.y, p1.y)
        return CGRect(
            x: minX,
            y: minY,
            width: max(1.0, maxX - minX),
            height: max(1.0, maxY - minY)
        ).insetBy(dx: -24.0, dy: -24.0)
    }

    /// Converts a pane point (top-left origin) to image pixel coordinates `(0...imageW, 0...imageH)`.
    func paneToImage(_ panePt: CGPoint) -> VectorPoint {
        let center = CGPoint(x: paneSize.width * 0.5, y: paneSize.height * 0.5)
        let unzoomedX = center.x + (panePt.x - panOffset.width - center.x) / max(0.05, zoomScale)
        let unzoomedY = center.y + (panePt.y - panOffset.height - center.y) / max(0.05, zoomScale)
        let px = Double((unzoomedX - offX) / max(1e-5, scaleX))
        let py = Double((unzoomedY - offY) / max(1e-5, scaleY))
        return VectorPoint(x: px, y: py)
    }

    /// Converts a pixel radius to screen radius in points.
    func imageRadiusToPane(_ radiusPx: Double) -> CGFloat {
        CGFloat(radiusPx) * ((scaleX + scaleY) * 0.5) * zoomScale
    }

    /// Converts a screen distance in points to image pixels.
    func paneDistanceToImagePx(_ distPt: CGFloat) -> Double {
        let avgScale = max(1e-5, ((scaleX + scaleY) * 0.5) * zoomScale)
        return Double(distPt / avgScale)
    }
}

struct CanvasViewportView: View {
    @Bindable var model: AppModel
    @Binding var isDropTargeted: Bool

    // Interactive editing transient state
    @State private var marqueeRect: CGRect? = nil
    @State private var freehandPointsPx: [VectorPoint] = []
    @State private var hoverPointPane: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if model.vectorizer.sourceImage == nil {
                    welcomeEmptyState
                } else {
                    switch model.viewMode {
                    case .sideBySide:
                        HStack(spacing: 0) {
                            paneContainer(
                                title: L("ORIGINAL (BITMAP)", "ORIGINAL (BITMAP)"),
                                badge: sourceSizeBadge,
                                isVectorEditable: false,
                                showPaperFrame: false
                            ) { paneSize in
                                originalPaneContent(paneSize: paneSize, showSheetBackground: true)
                            }
                            Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                            paneContainer(
                                title: L("VECTORISÉ (SVG)", "VECTORIZED (SVG)"),
                                badge: vectorPathsBadge,
                                isVectorEditable: true,
                                showPaperFrame: false
                            ) { paneSize in
                                vectorPaneContent(paneSize: paneSize, showPaperFrame: false, showSheetBackground: true)
                            }
                        }

                    case .overlay:
                        paneContainer(
                            title: L("SUPERPOSITION BITMAP + VECTEUR", "BITMAP + VECTOR OVERLAY"),
                            badge: vectorPathsBadge,
                            isVectorEditable: true,
                            showPaperFrame: false
                        ) { paneSize in
                            ZStack {
                                originalPaneContent(paneSize: paneSize, showSheetBackground: true)
                                    .opacity(model.bitmapOpacity)
                                vectorPaneContent(paneSize: paneSize, showPaperFrame: false, showSheetBackground: false)
                                    .opacity(model.vectorOpacity)
                            }
                        }

                    case .vectorOnly:
                        let vectorTitle = model.showAxiDrawSection
                            ? L("FEUILLE DE TRACÉ AXIDRAW (\(model.vectorizer.params.paperFormat.shortLabel))", "AXIDRAW PLOT SHEET (\(model.vectorizer.params.paperFormat.shortLabel))")
                            : L("APERÇU VECTORIEL (SVG)", "VECTOR PREVIEW (SVG)")
                        paneContainer(
                            title: vectorTitle,
                            badge: vectorPathsBadge,
                            isVectorEditable: true,
                            showPaperFrame: model.showAxiDrawSection
                        ) { paneSize in
                            vectorPaneContent(paneSize: paneSize, showPaperFrame: model.showAxiDrawSection, showSheetBackground: true)
                        }
                    }
                }

                // Drop target highlight border
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent.swiftUI, style: StrokeStyle(lineWidth: 2.5, dash: [8, 4]))
                        .background(Theme.accent.swiftUI.opacity(0.06))
                        .padding(8)
                        .allowsHitTesting(false)
                }

                // Floating contextual selection bar, AxiDraw live plot banner & zoom bar
                if model.vectorizer.sourceImage != nil {
                    VStack(spacing: 8) {
                        if model.plotter.runState.isBusy || model.plotter.runState.isPaused {
                            axiDrawLiveBanner
                                .padding(.top, 34)
                        }
                        if !model.selectedPathIDs.isEmpty {
                            selectionActionOverlayBar
                                .padding(.top, (model.plotter.runState.isBusy || model.plotter.runState.isPaused) ? 0 : 34)
                        }
                        Spacer()
                        HStack {
                            editHintPill
                            Spacer()
                            zoomOverlayBar
                        }
                        .padding(14)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.background.swiftUI)
            .clipped()
            .contentShape(Rectangle())
        }
    }

    private var sourceSizeBadge: String {
        guard let img = model.vectorizer.sourceImage else { return "" }
        return "\(img.width) × \(img.height) px"
    }

    private var vectorPathsBadge: String {
        guard let m = model.vectorizer.result?.metrics else { return "" }
        return L(
            "\(m.pathCount) chemins · \(Format.distanceMM(m.drawDistanceMM))",
            "\(m.pathCount) paths · \(Format.distanceMM(m.drawDistanceMM))"
        )
    }

    private func paneContainer<Content: View>(
        title: String,
        badge: String,
        isVectorEditable: Bool,
        showPaperFrame: Bool,
        @ViewBuilder content: @escaping (CGSize) -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textFaint.swiftUI)
                Spacer()
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Theme.header.swiftUI)

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            GeometryReader { innerGeo in
                ZStack {
                    canvasGridBackground
                    content(innerGeo.size)
                        .allowsHitTesting(false)

                    if isVectorEditable {
                        interactiveEditingOverlay(paneSize: innerGeo.size)
                            .allowsHitTesting(false)
                    }

                    // Native AppKit trackpad + mouse overlay strictly clipped to innerGeo
                    CanvasTrackpadMouseView(
                        model: model,
                        paneSize: innerGeo.size,
                        isVectorEditable: isVectorEditable,
                        showPaperFrame: showPaperFrame,
                        marqueeRect: $marqueeRect,
                        freehandPointsPx: $freehandPointsPx,
                        hoverPointPane: $hoverPointPane
                    )
                }
                .frame(width: innerGeo.size.width, height: innerGeo.size.height)
                .clipped()
                .contentShape(Rectangle())
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func interactiveEditingOverlay(paneSize: CGSize) -> some View {
        if let res = model.vectorizer.result {
            let geom = CanvasTransformGeometry(
                paneSize: paneSize,
                zoomScale: model.zoomScale,
                panOffset: model.panOffset,
                pageTransform: res.pageTransform,
                showPaperFrame: model.viewMode == .vectorOnly
            )
            Canvas { ctx, _ in
                // Draw marquee selection box if dragging selection rectangle
                if let rect = marqueeRect {
                    ctx.fill(Path(rect), with: .color(Theme.tcp.swiftUI.opacity(0.12)))
                    ctx.stroke(
                        Path(rect),
                        with: .color(Theme.tcp.swiftUI.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                }

                // Draw live freehand path being sketched
                if model.editTool == .draw && freehandPointsPx.count >= 2 {
                    var freePath = Path()
                    freePath.move(to: geom.imageToPane(freehandPointsPx[0]))
                    for i in 1..<freehandPointsPx.count {
                        freePath.addLine(to: geom.imageToPane(freehandPointsPx[i]))
                    }
                    let penColor = Theme.penColor(model.activeDrawPenIndex).swiftUI
                    ctx.stroke(
                        freePath,
                        with: .color(penColor),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                }

                // Draw eraser circle preview
                if model.editTool == .erase, let hp = hoverPointPane {
                    let r = max(4.0, geom.imageRadiusToPane(model.eraserRadiusPx))
                    let circleRect = CGRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: circleRect), with: .color(Theme.danger.swiftUI.opacity(0.15)))
                    ctx.stroke(
                        Path(ellipseIn: circleRect),
                        with: .color(Theme.danger.swiftUI.opacity(0.85)),
                        lineWidth: 1.2
                    )
                }

                // Draw live AxiDraw carriage crosshair when plotting, paused, or displaced from (0, 0)
                let plotter = model.plotter
                let showCarriage = plotter.runState.isBusy
                    || plotter.runState.isPaused
                    || plotter.currentPosMM.distance(to: .zero) > 0.1
                if showCarriage {
                    let t = res.pageTransform
                    let sheet = geom.zoomedSheetRect
                    let fracX = CGFloat(plotter.currentPosMM.x / max(1.0, t.pageWidthMM))
                    let fracY = CGFloat(plotter.currentPosMM.y / max(1.0, t.pageHeightMM))
                    let carriagePt = CGPoint(
                        x: sheet.minX + fracX * sheet.width,
                        y: sheet.minY + fracY * sheet.height
                    )

                    let headColor = plotter.isPenDown ? Theme.accent.swiftUI : Theme.tcp.swiftUI
                    let ringR: CGFloat = plotter.isPenDown ? 8.5 : 10.5
                    let ringRect = CGRect(x: carriagePt.x - ringR, y: carriagePt.y - ringR, width: ringR * 2, height: ringR * 2)

                    var crosshair = Path()
                    crosshair.move(to: CGPoint(x: carriagePt.x - 14, y: carriagePt.y))
                    crosshair.addLine(to: CGPoint(x: carriagePt.x + 14, y: carriagePt.y))
                    crosshair.move(to: CGPoint(x: carriagePt.x, y: carriagePt.y - 14))
                    crosshair.addLine(to: CGPoint(x: carriagePt.x, y: carriagePt.y + 14))

                    ctx.stroke(crosshair, with: .color(headColor.opacity(0.85)), lineWidth: 1.2)
                    ctx.fill(Path(ellipseIn: ringRect), with: .color(headColor.opacity(plotter.isPenDown ? 0.28 : 0.12)))
                    ctx.stroke(Path(ellipseIn: ringRect), with: .color(headColor), lineWidth: 1.8)

                    if plotter.isPenDown {
                        let nibRect = CGRect(x: carriagePt.x - 3.0, y: carriagePt.y - 3.0, width: 6.0, height: 6.0)
                        ctx.fill(Path(ellipseIn: nibRect), with: .color(headColor))
                    }
                }
            }
        }
    }

    private var canvasGridBackground: some View {
        Canvas { ctx, size in
            let step: CGFloat = 24
            var minor = Path()
            var x: CGFloat = 0
            while x < size.width {
                minor.move(to: CGPoint(x: x, y: 0))
                minor.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                minor.move(to: CGPoint(x: 0, y: y))
                minor.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(minor, with: .color(Theme.gridMinor.swiftUI), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func originalPaneContent(paneSize: CGSize, showSheetBackground: Bool) -> some View {
        if let nsImage = model.vectorizer.displayNSImage, let src = model.vectorizer.sourceImage {
            BitmapCanvasRenderView(
                nsImage: nsImage,
                imageWidth: src.width,
                imageHeight: src.height,
                paneSize: paneSize,
                zoomScale: model.zoomScale,
                panOffsetX: model.panOffset.width,
                panOffsetY: model.panOffset.height,
                showSheetBackground: showSheetBackground
            )
        }
    }

    @ViewBuilder
    private func vectorPaneContent(paneSize: CGSize, showPaperFrame: Bool, showSheetBackground: Bool = true) -> some View {
        if let res = model.vectorizer.result {
            VectorCanvasRenderView(
                result: res,
                renderCache: model.vectorizer.renderCache,
                params: model.vectorizer.params,
                paneSize: paneSize,
                zoomScale: model.zoomScale,
                panOffsetX: model.panOffset.width,
                panOffsetY: model.panOffset.height,
                showPaperFrame: showPaperFrame,
                showSheetBackground: showSheetBackground,
                blackOnWhitePreview: model.blackOnWhitePreview,
                showTravelMoves: model.showTravelMoves,
                showControlPoints: model.showControlPoints,
                selectedPathIDs: model.selectedPathIDs,
                selectedVertex: model.selectedVertex
            )
        } else if model.vectorizer.isProcessing {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(model.vectorizer.progressStage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textDim.swiftUI)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.panel.swiftUI.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }

    // MARK: - Welcome Empty State (No Default Image)

    private var welcomeEmptyState: some View {
        VStack(spacing: 18) {
            VectorizerHeroGraphic(active: false, size: 96)

            VStack(spacing: 6) {
                Text(L("Aucune image ouverte", "No image open"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(L("Glisser-déposer un dessin au trait ici, ouvrir un fichier (⌘O) ou coller depuis le presse-papiers (⌘V).", "Drag and drop a line drawing here, open an image file (⌘O), or paste from clipboard (⌘V)."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 10) {
                TextButton(
                    title: L("Ouvrir une image… (⌘O)", "Open Image… (⌘O)"),
                    symbol: "folder",
                    prominent: true
                ) {
                    model.openImagePanel()
                }

                TextButton(
                    title: L("Coller (⌘V)", "Paste (⌘V)"),
                    symbol: "doc.on.clipboard"
                ) {
                    model.pasteImageFromClipboard()
                }
            }

            if !model.recentURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("OUVRIR RÉCENT", "OPEN RECENT"))
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(Theme.textFaint.swiftUI)
                        .padding(.horizontal, 4)

                    VStack(spacing: 3) {
                        ForEach(model.recentURLs.prefix(5), id: \.path) { url in
                            Button {
                                model.open(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.accent.swiftUI)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Theme.text.swiftUI)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(url.deletingLastPathComponent().lastPathComponent)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.textFaint.swiftUI)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.lane.swiftUI)
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 360)
                }
                .padding(.top, 6)
            }
        }
        .padding(32)
    }

    // MARK: - Selection Contextual Bar & Overlays

    private var axiDrawLiveBanner: some View {
        let plotter = model.plotter
        let pct = Int((plotter.progressFraction * 100.0).rounded())
        return HStack(spacing: 10) {
            Circle()
                .fill(plotter.isPenDown ? Theme.accent.swiftUI : Theme.tcp.swiftUI)
                .frame(width: 8, height: 8)

            Text(plotter.statusLog)
                .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                .foregroundStyle(Theme.text.swiftUI)
                .lineLimit(1)

            ProgressView(value: plotter.progressFraction)
                .tint(Theme.accent.swiftUI)
                .frame(width: 90)

            Text("\(pct) %")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced).monospacedDigit())
                .foregroundStyle(Theme.accent.swiftUI)

            Divider().frame(height: 14)

            if plotter.runState.isBusy {
                TextButton(title: L("Pause", "Pause"), symbol: "pause.fill", compact: true) {
                    plotter.pausePlot()
                }
            } else if plotter.runState.isPaused {
                TextButton(title: L("Reprendre", "Resume"), symbol: "play.fill", prominent: true, compact: true) {
                    plotter.resumePlot()
                }
            }

            TextButton(title: L("Stop", "Stop"), symbol: "stop.fill", compact: true) {
                plotter.stopPlot()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.panel.swiftUI.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.swiftUI.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        )
    }

    private var selectionActionOverlayBar: some View {
        let count = model.selectedPathIDs.count
        let penCount = max(1, min(4, model.vectorizer.params.penCount))
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.tcp.swiftUI)
                    .frame(width: 7, height: 7)
                Text(L("\(count) trait\(count > 1 ? "s" : "") sélectionné\(count > 1 ? "s" : "")", "\(count) stroke\(count > 1 ? "s" : "") selected"))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Theme.text.swiftUI)
            }

            if penCount > 1 {
                Divider().frame(height: 14)
                Text(L("Stylo :", "Pen:"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                ForEach(0..<penCount, id: \.self) { pIdx in
                    Button {
                        model.assignSelectedToPen(pIdx)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.penColor(pIdx).swiftUI)
                                .frame(width: 8, height: 8)
                            Text("\(pIdx + 1)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.text.swiftUI)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(L("Affecter au Stylo \(pIdx + 1)", "Assign to Pen \(pIdx + 1)"))
                }
            }

            Divider().frame(height: 14)

            TextButton(title: L("Simplifier", "Simplify"), symbol: "wand.and.rays", compact: true) {
                model.simplifySelectedPaths()
            }
            .help(L("Simplifier les sommets des traits sélectionnés", "Simplify vertices of selected strokes"))

            TextButton(title: L("Inverser", "Reverse"), symbol: "arrow.left.arrow.right", compact: true) {
                model.reverseSelectedPaths()
            }
            .help(L("Inverser le sens de parcours AxiDraw", "Reverse AxiDraw drawing direction"))

            if count >= 2 {
                TextButton(title: L("Relier", "Join"), symbol: "link", compact: true) {
                    model.joinSelectedPaths()
                }
                .help(L("Relier les traits sélectionnés en un seul chemin continu", "Join selected strokes into a single continuous path"))
            }

            if model.selectedVertex != nil {
                TextButton(title: L("Scinder", "Split"), symbol: "scissors", compact: true) {
                    model.splitAtSelectedVertex()
                }
                .help(L("Scinder le trait en deux au sommet sélectionné", "Split stroke in two at selected vertex"))
            }

            TextButton(title: L("Supprimer (⌫)", "Delete (⌫)"), symbol: "trash", compact: true) {
                model.deleteSelectedPaths()
            }
            .help(L("Supprimer les traits sélectionnés (⌫)", "Delete selected strokes (⌫)"))

            IconButton(symbol: "xmark", helpText: L("Tout désélectionner (⎋)", "Deselect all (⎋)")) {
                model.clearSelection()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.panel.swiftUI.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.tcp.swiftUI.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        )
    }

    private var editHintPill: some View {
        HStack(spacing: 6) {
            Image(systemName: model.editTool.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent.swiftUI)
            Text(model.editTool.helpText)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textDim.swiftUI)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.panel.swiftUI.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        )
    }

    private var zoomOverlayBar: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "minus.magnifyingglass", helpText: L("Zoom arrière (⌘-)", "Zoom out (⌘-)")) {
                model.zoomOut()
            }
            Button {
                model.resetZoom(animated: true)
            } label: {
                Text("\(Int((model.zoomScale * 100).rounded())) %")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Theme.text.swiftUI)
                    .frame(width: 48)
            }
            .buttonStyle(.plain)
            .help(L("Réinitialiser la vue à 100 % et centrer (Z / ⌘0)", "Reset view to 100% and center (Z / ⌘0)"))

            IconButton(symbol: "plus.magnifyingglass", helpText: L("Zoom avant (⌘+)", "Zoom in (⌘+)")) {
                model.zoomIn()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.panel.swiftUI.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

// MARK: - Native AppKit Trackpad + Mouse + Stroke Editing Overlay

struct CanvasTrackpadMouseView: NSViewRepresentable {
    var model: AppModel
    var paneSize: CGSize
    var isVectorEditable: Bool
    var showPaperFrame: Bool
    @Binding var marqueeRect: CGRect?
    @Binding var freehandPointsPx: [VectorPoint]
    @Binding var hoverPointPane: CGPoint?

    func makeNSView(context: Context) -> CanvasInteractiveNSView {
        let v = CanvasInteractiveNSView()
        v.updateBindings(
            model: model,
            paneSize: paneSize,
            isVectorEditable: isVectorEditable,
            showPaperFrame: showPaperFrame,
            setMarquee: { marqueeRect = $0 },
            setFreehand: { freehandPointsPx = $0 },
            setHover: { hoverPointPane = $0 }
        )
        return v
    }

    func updateNSView(_ nsView: CanvasInteractiveNSView, context: Context) {
        nsView.updateBindings(
            model: model,
            paneSize: paneSize,
            isVectorEditable: isVectorEditable,
            showPaperFrame: showPaperFrame,
            setMarquee: { marqueeRect = $0 },
            setFreehand: { freehandPointsPx = $0 },
            setHover: { hoverPointPane = $0 }
        )
    }
}

@MainActor
final class CanvasInteractiveNSView: NSView {
    private weak var model: AppModel?
    private var paneSize: CGSize = .zero
    private var isVectorEditable: Bool = false
    private var showPaperFrame: Bool = false
    private var setMarquee: ((CGRect?) -> Void)?
    private var setFreehand: (([VectorPoint]) -> Void)?
    private var setHover: ((CGPoint?) -> Void)?

    private enum DragMode {
        case none
        case pan(startPan: CGSize, startPt: CGPoint)
        case moveVertex(pathID: Int, vertexIdx: Int)
        case movePaths(lastImagePt: VectorPoint, didRecordUndo: Bool)
        case marquee(startPt: CGPoint, additive: Bool)
        case erase(didRecordUndo: Bool)
        case draw(pointsPx: [VectorPoint])
    }

    private var dragMode: DragMode = .none
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func updateBindings(
        model: AppModel,
        paneSize: CGSize,
        isVectorEditable: Bool,
        showPaperFrame: Bool,
        setMarquee: @escaping (CGRect?) -> Void,
        setFreehand: @escaping ([VectorPoint]) -> Void,
        setHover: @escaping (CGPoint?) -> Void
    ) {
        self.model = model
        self.paneSize = paneSize
        self.isVectorEditable = isVectorEditable
        self.showPaperFrame = showPaperFrame
        self.setMarquee = setMarquee
        self.setFreehand = setFreehand
        self.setHover = setHover
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func localPoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func currentGeometry() -> CanvasTransformGeometry? {
        guard let model, let res = model.vectorizer.result else { return nil }
        return CanvasTransformGeometry(
            paneSize: bounds.size,
            zoomScale: model.zoomScale,
            panOffset: model.panOffset,
            pageTransform: res.pageTransform,
            showPaperFrame: showPaperFrame
        )
    }

    // MARK: - Trackpad 2-Finger Pinch (Incremental, Anchored at Cursor)

    override func magnify(with event: NSEvent) {
        guard let model else { return }
        let pt = localPoint(for: event)
        let center = CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5)
        let anchor = CGPoint(x: pt.x - center.x, y: pt.y - center.y)
        let factor = max(0.5, min(2.0, 1.0 + event.magnification))
        model.applyZoom(newScale: model.zoomScale * factor, anchorFromCenter: anchor)
    }

    // MARK: - Trackpad 2-Finger Scroll (Pan) & Mouse Wheel / Option-Scroll (Zoom)

    override func scrollWheel(with event: NSEvent) {
        guard let model else { return }
        let flags = event.modifierFlags
        let wantsZoom = !event.hasPreciseScrollingDeltas || flags.contains(.option) || flags.contains(.command)

        if wantsZoom {
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * 0.012
                : event.scrollingDeltaY * 0.085
            guard abs(delta) > 1e-4 else { return }
            let factor = CGFloat(pow(1.12, Double(delta)))
            let pt = localPoint(for: event)
            let center = CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5)
            let anchor = CGPoint(x: pt.x - center.x, y: pt.y - center.y)
            model.applyZoom(newScale: model.zoomScale * factor, anchorFromCenter: anchor)
        } else {
            // Two-finger trackpad scroll -> smooth pan
            model.panOffset = CGSize(
                width: model.panOffset.width + event.scrollingDeltaX,
                height: model.panOffset.height + event.scrollingDeltaY
            )
        }
    }

    // MARK: - Middle & Right Mouse Drag (Always Pan, Works with Any Mouse)

    override func otherMouseDown(with event: NSEvent) {
        guard let model else { return }
        dragMode = .pan(startPan: model.panOffset, startPt: localPoint(for: event))
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let model, case .pan(let startPan, let startPt) = dragMode else { return }
        let pt = localPoint(for: event)
        model.panOffset = CGSize(
            width: startPan.width + (pt.x - startPt.x),
            height: startPan.height + (pt.y - startPt.y)
        )
    }

    override func otherMouseUp(with event: NSEvent) {
        dragMode = .none
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let model else { return }
        dragMode = .pan(startPan: model.panOffset, startPt: localPoint(for: event))
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let model, case .pan(let startPan, let startPt) = dragMode else { return }
        let pt = localPoint(for: event)
        model.panOffset = CGSize(
            width: startPan.width + (pt.x - startPt.x),
            height: startPan.height + (pt.y - startPt.y)
        )
    }

    override func rightMouseUp(with event: NSEvent) {
        dragMode = .none
    }

    // MARK: - Hover & Cursor Updates

    override func mouseMoved(with event: NSEvent) {
        guard let model else { return }
        if isVectorEditable && model.editTool == .erase {
            setHover?(localPoint(for: event))
        } else {
            setHover?(nil)
        }
    }

    override func mouseExited(with event: NSEvent) {
        setHover?(nil)
    }

    // MARK: - Left Mouse Down / Dragged / Up (Pan, Select/Edit, Eraser, Draw)

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model else { return }
        let pt = localPoint(for: event)

        // If on original bitmap pane or using Pan tool (or Option-drag), pan the canvas
        if !isVectorEditable || model.editTool == .pan {
            if event.clickCount == 2 {
                model.resetZoom()
                return
            }
            dragMode = .pan(startPan: model.panOffset, startPt: pt)
            return
        }

        guard let geom = currentGeometry(), let res = model.vectorizer.result else {
            dragMode = .pan(startPan: model.panOffset, startPt: pt)
            return
        }
        let imgPt = geom.paneToImage(pt)

        switch model.editTool {
        case .pan:
            dragMode = .pan(startPan: model.panOffset, startPt: pt)

        case .erase:
            model.vectorizer.recordUndoSnapshot()
            _ = model.vectorizer.erasePathsNear(pointPx: imgPt, radiusPx: model.eraserRadiusPx)
            setHover?(pt)
            dragMode = .erase(didRecordUndo: true)

        case .draw:
            let pts = [imgPt]
            setFreehand?(pts)
            dragMode = .draw(pointsPx: pts)

        case .select:
            let hitTolerancePx = max(3.0, geom.paneDistanceToImagePx(9.0))
            let shiftHeld = event.modifierFlags.contains(.shift)

            // 1. Check if clicking near a vertex of an already-selected path
            if !shiftHeld, let vHit = hitTestSelectedVertex(at: imgPt, tolerancePx: hitTolerancePx * 1.15, in: res.layers, selectedIDs: model.selectedPathIDs) {
                model.selectedVertex = vHit
                model.vectorizer.recordUndoSnapshot()
                dragMode = .moveVertex(pathID: vHit.pathID, vertexIdx: vHit.index)
                return
            }

            // 2. Check if clicking near any visible stroke
            if let hitPathID = hitTestPath(at: imgPt, tolerancePx: hitTolerancePx, in: res.layers) {
                if shiftHeld {
                    if model.selectedPathIDs.contains(hitPathID) {
                        model.selectedPathIDs.remove(hitPathID)
                    } else {
                        model.selectedPathIDs.insert(hitPathID)
                    }
                    model.selectedVertex = nil
                } else {
                    if !model.selectedPathIDs.contains(hitPathID) {
                        model.selectedPathIDs = [hitPathID]
                    }
                    // Also check if near a vertex of this newly selected path
                    model.selectedVertex = hitTestSelectedVertex(at: imgPt, tolerancePx: hitTolerancePx * 1.15, in: res.layers, selectedIDs: [hitPathID])
                }
                if let sv = model.selectedVertex, model.selectedPathIDs.count == 1 {
                    model.vectorizer.recordUndoSnapshot()
                    dragMode = .moveVertex(pathID: sv.pathID, vertexIdx: sv.index)
                } else {
                    dragMode = .movePaths(lastImagePt: imgPt, didRecordUndo: false)
                }
                return
            }

            // 3. Clicked empty space: start marquee selection (or double-click to reset zoom)
            if event.clickCount == 2 {
                model.resetZoom()
                return
            }
            if !shiftHeld {
                model.clearSelection()
            }
            dragMode = .marquee(startPt: pt, additive: shiftHeld)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        let pt = localPoint(for: event)

        switch dragMode {
        case .none:
            break

        case .pan(let startPan, let startPt):
            model.panOffset = CGSize(
                width: startPan.width + (pt.x - startPt.x),
                height: startPan.height + (pt.y - startPt.y)
            )

        case .erase:
            guard let geom = currentGeometry() else { return }
            setHover?(pt)
            let imgPt = geom.paneToImage(pt)
            _ = model.vectorizer.erasePathsNear(pointPx: imgPt, radiusPx: model.eraserRadiusPx)

        case .draw(var pointsPx):
            guard let geom = currentGeometry() else { return }
            let imgPt = geom.paneToImage(pt)
            if let last = pointsPx.last, last.distance(to: imgPt) >= 1.2 {
                pointsPx.append(imgPt)
                setFreehand?(pointsPx)
                dragMode = .draw(pointsPx: pointsPx)
            }

        case .moveVertex(let pathID, let vertexIdx):
            guard let geom = currentGeometry() else { return }
            let imgPt = geom.paneToImage(pt)
            model.vectorizer.movePathVertex(pathID: pathID, pointIndex: vertexIdx, to: imgPt)

        case .movePaths(let lastImagePt, var didRecordUndo):
            guard let geom = currentGeometry() else { return }
            let imgPt = geom.paneToImage(pt)
            let dx = imgPt.x - lastImagePt.x
            let dy = imgPt.y - lastImagePt.y
            guard abs(dx) > 0.1 || abs(dy) > 0.1 else { return }
            if !didRecordUndo {
                model.vectorizer.recordUndoSnapshot()
                didRecordUndo = true
            }
            model.vectorizer.translatePaths(ids: model.selectedPathIDs, dxPx: dx, dyPx: dy)
            dragMode = .movePaths(lastImagePt: imgPt, didRecordUndo: didRecordUndo)

        case .marquee(let startPt, let additive):
            guard let geom = currentGeometry(), let res = model.vectorizer.result else { return }
            let rect = CGRect(
                x: min(startPt.x, pt.x),
                y: min(startPt.y, pt.y),
                width: abs(pt.x - startPt.x),
                height: abs(pt.y - startPt.y)
            )
            setMarquee?(rect)
            let p0 = geom.paneToImage(CGPoint(x: rect.minX, y: rect.minY))
            let p1 = geom.paneToImage(CGPoint(x: rect.maxX, y: rect.maxY))
            let minX = min(p0.x, p1.x), maxX = max(p0.x, p1.x)
            let minY = min(p0.y, p1.y), maxY = max(p0.y, p1.y)
            let imgMarquee = CGRect(x: minX, y: minY, width: max(0.5, maxX - minX), height: max(0.5, maxY - minY))
            let boundsByID = model.vectorizer.renderCache?.boundsByPathID

            var inside = additive ? model.selectedPathIDs : Set<Int>()
            for layer in res.layers where layer.visible {
                for vp in layer.paths {
                    if let bbox = boundsByID?[vp.id], !bbox.intersects(imgMarquee) {
                        continue
                    }
                    if vp.points.contains(where: { $0.x >= minX && $0.x <= maxX && $0.y >= minY && $0.y <= maxY }) {
                        inside.insert(vp.id)
                    }
                }
            }
            model.selectedPathIDs = inside
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        switch dragMode {
        case .marquee:
            setMarquee?(nil)
        case .draw(let pointsPx):
            setFreehand?([])
            if pointsPx.count >= 2 {
                if let newID = model.vectorizer.addFreehandPath(points: pointsPx, penIndex: model.activeDrawPenIndex) {
                    model.selectedPathIDs = [newID]
                }
            }
        default:
            break
        }
        dragMode = .none
    }

    // MARK: - Keyboard Shortcuts (Delete / Escape / Undo / Redo / Tool Switching)

    override func keyDown(with event: NSEvent) {
        guard let model else {
            super.keyDown(with: event)
            return
        }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyCode = event.keyCode

        // Delete (51) or Forward Delete (117)
        if keyCode == 51 || keyCode == 117 {
            if !model.selectedPathIDs.isEmpty {
                model.deleteSelectedPaths()
                return
            }
        }
        // Escape (53)
        if keyCode == 53 {
            model.clearSelection()
            return
        }
        // Single-key tool & view shortcuts when no modifier is held
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            switch chars {
            case "z":
                model.resetZoom(animated: true)
                return
            case "b":
                model.blackOnWhitePreview.toggle()
                return
            case "h":
                model.editTool = .pan
                return
            case "v":
                model.editTool = .select
                return
            case "e":
                model.editTool = .erase
                return
            case "p":
                model.editTool = .draw
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Hit Testing Helpers

    private func hitTestSelectedVertex(
        at pt: VectorPoint,
        tolerancePx: Double,
        in layers: [PenLayer],
        selectedIDs: Set<Int>
    ) -> (pathID: Int, index: Int)? {
        guard !selectedIDs.isEmpty else { return nil }
        let tolSq = tolerancePx * tolerancePx
        var best: (pathID: Int, index: Int)? = nil
        var bestDistSq = tolSq

        for layer in layers where layer.visible {
            for vp in layer.paths where selectedIDs.contains(vp.id) {
                for (idx, v) in vp.points.enumerated() {
                    let dSq = pt.distanceSquared(to: v)
                    if dSq <= bestDistSq {
                        bestDistSq = dSq
                        best = (vp.id, idx)
                    }
                }
            }
        }
        return best
    }

    private func hitTestPath(
        at pt: VectorPoint,
        tolerancePx: Double,
        in layers: [PenLayer]
    ) -> Int? {
        let tolSq = tolerancePx * tolerancePx
        var bestID: Int? = nil
        var bestDistSq = tolSq
        let boundsByID = model?.vectorizer.renderCache?.boundsByPathID
        let cgPt = CGPoint(x: pt.x, y: pt.y)

        for layer in layers where layer.visible {
            for vp in layer.paths {
                if let bbox = boundsByID?[vp.id] {
                    let expanded = bbox.insetBy(dx: -CGFloat(tolerancePx), dy: -CGFloat(tolerancePx))
                    if !expanded.contains(cgPt) { continue }
                }
                let dSq = VectorizerController.distanceSquaredToPath(pointPx: pt, path: vp)
                if dSq <= bestDistSq {
                    bestDistSq = dSq
                    bestID = vp.id
                }
            }
        }
        return bestID
    }
}

// MARK: - Immediate-Mode Bitmap & Vector Canvas Renderers (Synchronized & 120 Hz Accelerated)

struct BitmapCanvasRenderView: View, Animatable {
    let nsImage: NSImage
    let imageWidth: Int
    let imageHeight: Int
    let paneSize: CGSize
    var zoomScale: CGFloat
    var panOffsetX: CGFloat
    var panOffsetY: CGFloat
    let showSheetBackground: Bool

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(zoomScale, AnimatablePair(panOffsetX, panOffsetY)) }
        set {
            zoomScale = newValue.first
            panOffsetX = newValue.second.first
            panOffsetY = newValue.second.second
        }
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            guard canvasSize.width > 4, canvasSize.height > 4 else { return }
            var rawParams = VectorizerParams()
            rawParams.paperFormat = .original
            let dummyTransform = PageTransform(
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                params: rawParams
            )
            let geom = CanvasTransformGeometry(
                paneSize: canvasSize,
                zoomScale: zoomScale,
                panOffset: CGSize(width: panOffsetX, height: panOffsetY),
                pageTransform: dummyTransform,
                showPaperFrame: false
            )
            let sheetRect = geom.zoomedSheetRect
            if showSheetBackground {
                let cornerR = max(2.0, min(10.0, 4.0 * zoomScale))
                let sheetPath = Path(roundedRect: sheetRect, cornerRadius: cornerR)
                ctx.fill(sheetPath, with: .color(Theme.lane.swiftUI))
                ctx.stroke(sheetPath, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
            }
            let resolved = ctx.resolve(Image(nsImage: nsImage))
            ctx.draw(resolved, in: sheetRect)
        }
        .frame(width: paneSize.width, height: paneSize.height)
    }
}

struct VectorCanvasRenderView: View, Animatable {
    let result: VectorizationResult
    let renderCache: VectorRenderCache?
    let params: VectorizerParams
    let paneSize: CGSize
    var zoomScale: CGFloat
    var panOffsetX: CGFloat
    var panOffsetY: CGFloat
    let showPaperFrame: Bool
    let showSheetBackground: Bool
    let blackOnWhitePreview: Bool
    let showTravelMoves: Bool
    let showControlPoints: Bool
    let selectedPathIDs: Set<Int>
    let selectedVertex: (pathID: Int, index: Int)?

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(zoomScale, AnimatablePair(panOffsetX, panOffsetY)) }
        set {
            zoomScale = newValue.first
            panOffsetX = newValue.second.first
            panOffsetY = newValue.second.second
        }
    }

    var body: some View {
        let t = result.pageTransform

        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            guard w > 4, h > 4 else { return }

            let geom = CanvasTransformGeometry(
                paneSize: canvasSize,
                zoomScale: zoomScale,
                panOffset: CGSize(width: panOffsetX, height: panOffsetY),
                pageTransform: t,
                showPaperFrame: showPaperFrame
            )

            // Draw sheet background in vector space so edges stay razor-sharp at any zoom
            let sheetRect = geom.zoomedSheetRect
            if showSheetBackground {
                let cornerR = max(2.0, min(10.0, 4.0 * zoomScale))
                let sheetPath = Path(roundedRect: sheetRect, cornerRadius: cornerR)
                let sheetFill = blackOnWhitePreview
                    ? Color(red: 0.985, green: 0.982, blue: 0.972)
                    : Theme.lane.swiftUI
                let sheetBorder = blackOnWhitePreview
                    ? Color.black.opacity(0.22)
                    : Color.white.opacity(0.10)
                ctx.fill(sheetPath, with: .color(sheetFill))
                ctx.stroke(sheetPath, with: .color(sheetBorder), lineWidth: 1)
            }

            // Draw printable margin dashed guide in AxiDraw sheet mode
            if let marginRect = geom.zoomedMarginRect(marginMM: params.marginMM) {
                let marginTint = blackOnWhitePreview
                    ? Theme.standby.swiftUI.opacity(0.45)
                    : Theme.tcp.swiftUI.opacity(0.28)
                ctx.stroke(
                    Path(marginRect),
                    with: .color(marginTint),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }

            let xform = geom.imageToPaneTransform
            let visImageRect = geom.visibleImageRect
            let useSpatialCulling = zoomScale > 1.6

            // Optional rapid pen-up travel lines (visualizes AxiDraw 2-opt tour)
            if showTravelMoves, let cache = renderCache {
                let travelScreenPath = cache.fullTravelPathPx.applying(xform)
                ctx.stroke(
                    travelScreenPath,
                    with: .color(Theme.danger.swiftUI.opacity(blackOnWhitePreview ? 0.55 : 0.45)),
                    style: StrokeStyle(lineWidth: 0.9, dash: [3.5, 3.5])
                )
            }

            let pxToPanePt = ((geom.scaleX + geom.scaleY) * 0.5) * zoomScale
            let blackInk = Color(red: 0.07, green: 0.08, blue: 0.10)

            // Draw each visible pen layer using pre-built cached Paths + single CGAffineTransform
            for (layerIdx, layer) in result.layers.enumerated() where layer.visible && !layer.paths.isEmpty {
                let color = blackOnWhitePreview ? blackInk : Theme.penColor(layer.index).swiftUI
                let physicalWidthPx = layer.widthMM / max(0.08, t.scalePxToMM)
                let strokePt = max(1.0, CGFloat(physicalWidthPx) * pxToPanePt)

                if let cache = renderCache, layerIdx < cache.layers.count {
                    let lc = cache.layers[layerIdx]

                    // 1. Highlight selected paths in O(k) where k = selected count
                    var selectedHighlightPath = Path()
                    var selectedHandlesPx = Path()
                    var vertexDots = Path()
                    var activeVertexDot = Path()

                    if !selectedPathIDs.isEmpty {
                        var selectedPx = Path()
                        for selID in selectedPathIDs {
                            if let sp = lc.pathByID[selID] {
                                selectedPx.addPath(sp)
                            }
                            if let hp = lc.handlesByID[selID] {
                                selectedHandlesPx.addPath(hp)
                            }
                        }
                        if !selectedPx.isEmpty {
                            selectedHighlightPath = selectedPx.applying(xform)
                            for vp in layer.paths where selectedPathIDs.contains(vp.id) {
                                for (vIdx, pt) in vp.points.enumerated() {
                                    let cp = geom.imageToPane(pt)
                                    if selectedVertex?.pathID == vp.id && selectedVertex?.index == vIdx {
                                        activeVertexDot.addEllipse(in: CGRect(x: cp.x - 4.5, y: cp.y - 4.5, width: 9.0, height: 9.0))
                                    } else {
                                        vertexDots.addEllipse(in: CGRect(x: cp.x - 3.0, y: cp.y - 3.0, width: 6.0, height: 6.0))
                                    }
                                }
                            }
                        }
                    }

                    if !selectedHighlightPath.isEmpty {
                        let glowColor = blackOnWhitePreview
                            ? Theme.standby.swiftUI.opacity(0.65)
                            : Color.white.opacity(0.85)
                        ctx.stroke(
                            selectedHighlightPath,
                            with: .color(glowColor),
                            style: StrokeStyle(lineWidth: strokePt + 3.5, lineCap: .round, lineJoin: .round)
                        )
                    }

                    // 2. Render paths according to outputMode & illustrationStrokeStyle
                    let isIllustration = (params.outputMode == .illustration)
                    if isIllustration && params.illustrationStrokeStyle == .variableRibbon && !lc.fullFilledRibbonPathPx.isEmpty {
                        let ribbonScreenPath: Path
                        if useSpatialCulling {
                            var culledRibbonPx = Path()
                            for bucket in lc.buckets where bucket.boundsPx.intersects(visImageRect) {
                                culledRibbonPx.addPath(bucket.filledRibbonPathPx)
                            }
                            ribbonScreenPath = culledRibbonPx.applying(xform)
                        } else {
                            ribbonScreenPath = lc.fullFilledRibbonPathPx.applying(xform)
                        }
                        ctx.fill(ribbonScreenPath, with: .color(color))
                    } else if isIllustration && params.illustrationStrokeStyle == .perStrokeWidth && !lc.widthBands.isEmpty {
                        let visibleGridSet: Set<Int>?
                        if useSpatialCulling {
                            var s = Set<Int>()
                            for bucket in lc.buckets where bucket.boundsPx.intersects(visImageRect) {
                                s.insert(bucket.gridIndex)
                            }
                            visibleGridSet = s
                        } else {
                            visibleGridSet = nil
                        }
                        let scaleFactor = CGFloat(max(0.2, min(4.0, params.strokeWidthScale)))
                        for band in lc.widthBands {
                            let bandWidthPt = max(0.75, 2.0 * band.radiusPx * scaleFactor * pxToPanePt)
                            let bandScreenPath: Path
                            if let visSet = visibleGridSet {
                                var culledBandPx = Path()
                                for (gIdx, bPath) in band.bucketPathsPx where visSet.contains(gIdx) {
                                    culledBandPx.addPath(bPath)
                                }
                                guard !culledBandPx.isEmpty else { continue }
                                bandScreenPath = culledBandPx.applying(xform)
                            } else {
                                bandScreenPath = band.fullPathPx.applying(xform)
                            }
                            ctx.stroke(
                                bandScreenPath,
                                with: .color(color),
                                style: StrokeStyle(lineWidth: bandWidthPt, lineCap: .round, lineJoin: .round)
                            )
                        }
                    } else {
                        // Uniform mechanical pen thickness (AxiDraw Plotter mode)
                        let layerScreenPath: Path
                        if useSpatialCulling {
                            var culledPx = Path()
                            for bucket in lc.buckets where bucket.boundsPx.intersects(visImageRect) {
                                culledPx.addPath(bucket.pathPx)
                            }
                            layerScreenPath = culledPx.applying(xform)
                        } else {
                            layerScreenPath = lc.fullPathPx.applying(xform)
                        }
                        ctx.stroke(
                            layerScreenPath,
                            with: .color(color),
                            style: StrokeStyle(lineWidth: strokePt, lineCap: .round, lineJoin: .round)
                        )
                    }

                    if showControlPoints {
                        let handlesScreen: Path
                        if useSpatialCulling {
                            var culledHandlesPx = Path()
                            for bucket in lc.buckets where bucket.boundsPx.intersects(visImageRect) {
                                culledHandlesPx.addPath(bucket.handlesPx)
                            }
                            handlesScreen = culledHandlesPx.applying(xform)
                        } else {
                            handlesScreen = lc.fullHandlesPx.applying(xform)
                        }
                        ctx.stroke(
                            handlesScreen,
                            with: .color(Theme.osc.swiftUI.opacity(0.75)),
                            style: StrokeStyle(lineWidth: 0.85)
                        )
                    } else if !selectedHandlesPx.isEmpty {
                        ctx.stroke(
                            selectedHandlesPx.applying(xform),
                            with: .color(Theme.osc.swiftUI.opacity(0.75)),
                            style: StrokeStyle(lineWidth: 0.85)
                        )
                    }

                    if !vertexDots.isEmpty {
                        ctx.fill(vertexDots, with: .color(blackOnWhitePreview ? .white : Theme.background.swiftUI))
                        ctx.stroke(vertexDots, with: .color(Theme.tcp.swiftUI), lineWidth: 1.4)
                    }
                    if !activeVertexDot.isEmpty {
                        ctx.fill(activeVertexDot, with: .color(Theme.accent.swiftUI))
                        ctx.stroke(activeVertexDot, with: .color(blackOnWhitePreview ? .black : .white), lineWidth: 1.5)
                    }
                }
            }
        }
        .frame(width: paneSize.width, height: paneSize.height)
    }
}
