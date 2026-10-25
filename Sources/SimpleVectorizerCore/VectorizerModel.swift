import Foundation

/// Top-level output paradigm: general-purpose variable-width SVG illustration vs mechanical AxiDraw plotter.
public enum VectorOutputMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case illustration = "illustration"
    case axidraw = "axidraw"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .illustration:
            return L("Illustration SVG", "SVG Illustration")
        case .axidraw:
            return L("Traceur AxiDraw", "AxiDraw Plotter")
        }
    }

    public var subtitle: String {
        switch self {
        case .illustration:
            return L("Pleins & déliés", "Variable width")
        case .axidraw:
            return L("Stylos & 2-opt", "Pen layers & 2-opt")
        }
    }

    public var icon: String {
        switch self {
        case .illustration: return "paintbrush.pointed.fill"
        case .axidraw: return "scribble.variable"
        }
    }

    public var detail: String {
        switch self {
        case .illustration:
            return L(
                "Mode Illustration SVG : préserve les variations d'épaisseur des traits (pleins & déliés en ruban de Bézier ou épaisseur mesurée par trait).",
                "SVG Illustration mode: preserves stroke thickness variations (variable-width Bézier ribbons or per-stroke measured width)."
            )
        case .axidraw:
            return L(
                "Mode Traceur AxiDraw : épaisseur mécanique constante par calque de stylo (0,3 mm, 0,5 mm…), mise en page papier et optimisation 2-opt.",
                "AxiDraw Plotter mode: uniform mechanical pen width per layer (0.3 mm, 0.5 mm…), sheet layout, and 2-opt travel optimization."
            )
        }
    }
}

/// Stroke thickness representation in Illustration mode.
public enum IllustrationStrokeStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case variableRibbon = "variable_ribbon"
    case perStrokeWidth = "per_stroke_width"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .variableRibbon:
            return L("Pleins & déliés (Ruban variable)", "Tapered Ribbon (Variable width)")
        case .perStrokeWidth:
            return L("Ligne centrale (Épaisseur par trait)", "Centerline (Per-stroke width)")
        }
    }

    public var shortBadge: String {
        switch self {
        case .variableRibbon:
            return L("Ruban", "Ribbon")
        case .perStrokeWidth:
            return L("Par trait", "Per-stroke")
        }
    }

    public var detail: String {
        switch self {
        case .variableRibbon:
            return L(
                "Construit une enveloppe de Bézier fermée autour de chaque trait en suivant les variations locales d'épaisseur (pinceau, plume, feutre).",
                "Builds a closed cubic Bézier ribbon around each stroke following local thickness variations (brush, nib, marker)."
            )
        case .perStrokeWidth:
            return L(
                "Conserve un chemin central unique par trait (facile à éditer par sommets) mais attribue à chaque trait son épaisseur réelle mesurée.",
                "Keeps a single centerline path per stroke (easy to edit by vertices) while assigning each stroke its measured thickness."
            )
        }
    }
}

/// Vectorization algorithm modes.
public enum VectorAlgorithm: String, CaseIterable, Identifiable, Codable, Sendable {
    case neuralCenterline = "neural_centerline"
    case visionContours = "vision_contours"
    case skeletonize = "skeletonize"
    case cannyEdges = "canny_edges"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .neuralCenterline:
            return L("Ligne médiane ANE + Steger", "ANE Centerline + Steger")
        case .visionContours:
            return L("Contours Vision ANE + Hachures", "ANE Vision Contours + Hatch")
        case .skeletonize:
            return L("Squelettisation Guo-Hall", "Guo-Hall Skeletonization")
        case .cannyEdges:
            return L("Contours Canny (double seuil)", "Canny Edges (dual threshold)")
        }
    }

    public var shortBadge: String {
        switch self {
        case .neuralCenterline: return "ANE · Steger"
        case .visionContours: return "ANE · Vision"
        case .skeletonize: return "vDSP · Guo-Hall"
        case .cannyEdges: return "vDSP · Canny"
        }
    }

    public var detail: String {
        switch self {
        case .neuralCenterline:
            return L(
                "Extraction de crêtes par Neural Engine / vDSP + squelette topologique Guo-Hall + affinement sub-pixel de Steger (Hessien) + traversée continue des croisements.",
                "Neural Engine / vDSP ridge extraction + Guo-Hall topological skeleton + Steger Hessian sub-pixel refinement + collinear junction crossing."
            )
        case .visionContours:
            return L(
                "Détection de contours hiérarchiques par Apple Vision (VNDetectContoursRequest sur ANE/GPU) + remplissage optionnel par hachures croisées pour AxiDraw.",
                "Hierarchical contour detection via Apple Vision (VNDetectContoursRequest on ANE/GPU) + optional cross-hatch fill for AxiDraw."
            )
        case .skeletonize:
            return L(
                "Amincissement morphologique rapide Guo-Hall / Zhang-Suen avec classification multi-stylos par transformée en distance.",
                "Fast Guo-Hall / Zhang-Suen morphological thinning with multi-pen stroke width classification via distance transform."
            )
        case .cannyEdges:
            return L(
                "Gradient de Sobel, suppression des non-maxima et hystérésis pour extraire les doubles contours d'un dessin ou d'une photo.",
                "Sobel gradient, non-maximum suppression, and hysteresis thresholding to extract dual edge contours."
            )
        }
    }
}

/// Physical paper formats for AxiDraw plotters.
public enum PaperFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case a4 = "A4"
    case a3 = "A3"
    case a5 = "A5"
    case a6 = "A6"
    case original = "original"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .a4: return "A4 (210 × 297 mm)"
        case .a3: return "A3 (297 × 420 mm)"
        case .a5: return "A5 (148 × 210 mm)"
        case .a6: return "A6 (105 × 148 mm)"
        case .original: return L("Pixels d'origine", "Original pixels")
        }
    }

    public var shortLabel: String {
        switch self {
        case .a4: return "A4"
        case .a3: return "A3"
        case .a5: return "A5"
        case .a6: return "A6"
        case .original: return L("Pixels", "Pixels")
        }
    }

    /// Portrait base dimensions `(widthMM, heightMM)`.
    public var portraitSizeMM: (width: Double, height: Double) {
        switch self {
        case .a6: return (105.0, 148.0)
        case .a5: return (148.0, 210.0)
        case .a4: return (210.0, 297.0)
        case .a3: return (297.0, 420.0)
        case .original: return (210.0, 297.0)
        }
    }
}

/// Paper orientation for AxiDraw layout.
public enum PaperOrientation: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "auto"
    case portrait = "portrait"
    case landscape = "landscape"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return L("Auto (selon image)", "Auto (match image)")
        case .portrait: return L("Portrait", "Portrait")
        case .landscape: return L("Paysage", "Landscape")
        }
    }
}

/// 2D point in floating-point coordinates (sub-pixel image space or millimeter page space).
public struct VectorPoint: Equatable, Hashable, Codable, Sendable {
    public static let zero = VectorPoint(x: 0, y: 0)

    public var x: Double
    public var y: Double

    @inlinable
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    @inlinable
    public func distance(to other: VectorPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    @inlinable
    public func distanceSquared(to other: VectorPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

/// Cubic Bézier curve segment (`M p0 C c1 c2 p3`).
public struct CubicBezierSegment: Equatable, Codable, Sendable {
    public var p0: VectorPoint
    public var c1: VectorPoint
    public var c2: VectorPoint
    public var p3: VectorPoint

    public init(p0: VectorPoint, c1: VectorPoint, c2: VectorPoint, p3: VectorPoint) {
        self.p0 = p0
        self.c1 = c1
        self.c2 = c2
        self.p3 = p3
    }

    /// Approximate arc length using 8-step chord subdivision.
    public var approximateLength: Double {
        var length = 0.0
        var prev = p0
        let steps = 8
        for s in 1...steps {
            let t = Double(s) / Double(steps)
            let mt = 1.0 - t
            let b0 = mt * mt * mt
            let b1 = 3.0 * mt * mt * t
            let b2 = 3.0 * mt * t * t
            let b3 = t * t * t
            let pt = VectorPoint(
                x: b0 * p0.x + b1 * c1.x + b2 * c2.x + b3 * p3.x,
                y: b0 * p0.y + b1 * c1.y + b2 * c2.y + b3 * p3.y
            )
            length += prev.distance(to: pt)
            prev = pt
        }
        return length
    }
}

/// Single traced and fitted vector path assigned to a pen layer.
public struct VectorPath: Identifiable, Equatable, Codable, Sendable {
    public var id: Int
    public var penIndex: Int
    /// Points in image pixel space `(0...imageWidth, 0...imageHeight)`.
    public var points: [VectorPoint]
    /// Fitted cubic Bézier segments in image pixel space (centerline).
    public var beziers: [CubicBezierSegment]
    /// Measured 75th-percentile stroke radius in pixels (from Distance Transform).
    public var strokeRadiusPx: Double
    /// Smoothed local stroke radius in pixels at each point in `points` (for variable-width strokes).
    public var pointRadiiPx: [Double]
    /// Closed variable-width cubic Bézier ribbon outline in image pixel space (populated in `.illustration` + `.variableRibbon` mode).
    public var outlineBeziers: [CubicBezierSegment]
    public var isClosed: Bool
    public var isHatch: Bool

    public init(
        id: Int,
        penIndex: Int = 0,
        points: [VectorPoint],
        beziers: [CubicBezierSegment] = [],
        strokeRadiusPx: Double = 1.0,
        pointRadiiPx: [Double] = [],
        outlineBeziers: [CubicBezierSegment] = [],
        isClosed: Bool = false,
        isHatch: Bool = false
    ) {
        self.id = id
        self.penIndex = penIndex
        self.points = points
        self.beziers = beziers
        self.strokeRadiusPx = strokeRadiusPx
        self.pointRadiiPx = pointRadiiPx
        self.outlineBeziers = outlineBeziers
        self.isClosed = isClosed
        self.isHatch = isHatch
    }

    public var startPoint: VectorPoint {
        points.first ?? VectorPoint(x: 0, y: 0)
    }

    public var endPoint: VectorPoint {
        points.last ?? VectorPoint(x: 0, y: 0)
    }

    public var lengthPx: Double {
        if !beziers.isEmpty {
            return beziers.reduce(0.0) { $0 + $1.approximateLength }
        }
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<points.count {
            sum += points[i - 1].distance(to: points[i])
        }
        return sum
    }

    public func reversedPath() -> VectorPath {
        let revPoints = Array(points.reversed())
        let revRadii = Array(pointRadiiPx.reversed())
        let revBeziers = beziers.reversed().map {
            CubicBezierSegment(p0: $0.p3, c1: $0.c2, c2: $0.c1, p3: $0.p0)
        }
        return VectorPath(
            id: id,
            penIndex: penIndex,
            points: revPoints,
            beziers: revBeziers,
            strokeRadiusPx: strokeRadiusPx,
            pointRadiiPx: revRadii,
            outlineBeziers: outlineBeziers,
            isClosed: isClosed,
            isHatch: isHatch
        )
    }
}

/// Default preview colors for the 4 pen layers (matching Simple family palette).
public let kDefaultPenColorsHex: [String] = [
    "#FFB454", // Pen 1 — Amber (Fineliner 0.3 mm)
    "#5CE1E6", // Pen 2 — Cyan (Rotring 0.5 mm)
    "#C792EA", // Pen 3 — Purple (Marker 0.8 mm)
    "#9ECE6A", // Pen 4 — Green (Brush/Posca 1.2 mm)
]

public let kDefaultPenWidthsMM: [Double] = [0.3, 0.5, 0.8, 1.2]

/// A pen layer grouping paths of similar stroke width for AxiDraw multi-pen plotting.
public struct PenLayer: Identifiable, Equatable, Codable, Sendable {
    public var id: Int { index }
    public var index: Int
    public var name: String
    public var widthMM: Double
    public var colorHex: String
    public var visible: Bool
    public var paths: [VectorPath]

    public init(
        index: Int,
        name: String? = nil,
        widthMM: Double? = nil,
        colorHex: String? = nil,
        visible: Bool = true,
        paths: [VectorPath] = []
    ) {
        self.index = index
        let w = widthMM ?? kDefaultPenWidthsMM[index % kDefaultPenWidthsMM.count]
        self.widthMM = w
        self.name = name ?? L("Stylo \(index + 1)", "Pen \(index + 1)")
        self.colorHex = colorHex ?? kDefaultPenColorsHex[index % kDefaultPenColorsHex.count]
        self.visible = visible
        self.paths = paths
    }

    public var inkscapeLayerLabel: String {
        String(format: "%d - %@ (%.1fmm)", index + 1, name, widthMM)
    }
}

/// Complete vectorization & AxiDraw parameters.
public struct VectorizerParams: Equatable, Codable, Sendable {
    public var outputMode: VectorOutputMode = .illustration
    public var illustrationStrokeStyle: IllustrationStrokeStyle = .variableRibbon
    public var strokeWidthScale: Double = 1.0

    public var algorithm: VectorAlgorithm = .neuralCenterline

    // Preprocessing
    public var adaptiveThreshold: Bool = true
    public var invert: Bool = false
    public var threshold: Int = 128
    public var blurRadius: Double = 0.8
    public var morphCleanup: Int = 0 // 0 = none, 1 = close small gaps, 2 = open + close

    // Vectorization & Curves
    public var rdpTolerance: Double = 1.0
    public var curveSmoothing: Double = 0.65 // 0 = polylines, >0 = Schneider cubic Bézier
    public var cornerAngleDeg: Int = 45
    public var minPathLengthPx: Int = 4
    public var stegerSubpixel: Bool = true
    public var crossJunctions: Bool = true

    // Stitching & Hatching
    public var maxStitchGapPx: Double = 8.0
    public var continuity: Double = 55.0 // 0...100
    public var hatchEnabled: Bool = false
    public var hatchSpacingPx: Double = 6.0
    public var hatchAngleDeg: Double = 45.0
    public var crossHatch: Bool = false

    // Multi-Pen & AxiDraw Layout
    public var penCount: Int = 2
    public var penWidthsMM: [Double] = kDefaultPenWidthsMM
    public var paperFormat: PaperFormat = .a4
    public var paperOrientation: PaperOrientation = .auto
    public var marginMM: Double = 12.0
    public var optimize2Opt: Bool = true
    public var exportBlackStrokes: Bool = false

    public init() {}

    /// Key covering stages 1–3 (image preprocessing, ANE/vDSP ridge/skeleton extraction, tracing, stitching, pen clustering).
    /// When this key does not change, SimpleVectorizer skips extraction and only re-runs curve fitting + AxiDraw optimization in < 20 ms.
    public var extractionCacheKey: String {
        [
            algorithm.rawValue,
            "\(adaptiveThreshold)",
            "\(invert)",
            "\(threshold)",
            String(format: "%.2f", blurRadius),
            "\(morphCleanup)",
            "\(minPathLengthPx)",
            "\(stegerSubpixel)",
            "\(crossJunctions)",
            String(format: "%.1f", maxStitchGapPx),
            String(format: "%.0f", continuity),
            "\(hatchEnabled)",
            String(format: "%.1f", hatchSpacingPx),
            String(format: "%.0f", hatchAngleDeg),
            "\(crossHatch)",
            "\(penCount)",
        ].joined(separator: "|")
    }
}

/// Coordinate mapping from image pixels `(0...imageW, 0...imageH)` to physical page coordinates `(mm or px)`.
public struct PageTransform: Equatable, Codable, Sendable {
    public var imageWidth: Int
    public var imageHeight: Int
    public var pageWidthMM: Double
    public var pageHeightMM: Double
    public var scalePxToMM: Double
    public var offsetXMM: Double
    public var offsetYMM: Double
    public var isRawPixels: Bool

    public init(imageWidth: Int, imageHeight: Int, params: VectorizerParams) {
        self.imageWidth = max(1, imageWidth)
        self.imageHeight = max(1, imageHeight)

        if params.paperFormat == .original {
            let pxToMM = 25.4 / 96.0
            self.isRawPixels = true
            self.pageWidthMM = Double(self.imageWidth) * pxToMM
            self.pageHeightMM = Double(self.imageHeight) * pxToMM
            self.scalePxToMM = pxToMM
            self.offsetXMM = 0
            self.offsetYMM = 0
            return
        }

        self.isRawPixels = false
        let base = params.paperFormat.portraitSizeMM
        let useLandscape: Bool
        switch params.paperOrientation {
        case .portrait:
            useLandscape = false
        case .landscape:
            useLandscape = true
        case .auto:
            useLandscape = self.imageWidth > self.imageHeight
        }

        let pw = useLandscape ? base.height : base.width
        let ph = useLandscape ? base.width : base.height
        self.pageWidthMM = pw
        self.pageHeightMM = ph

        let margin = min(params.marginMM, min(pw, ph) * 0.4)
        let availW = max(10.0, pw - 2.0 * margin)
        let availH = max(10.0, ph - 2.0 * margin)

        let sx = availW / Double(self.imageWidth)
        let sy = availH / Double(self.imageHeight)
        let scale = min(sx, sy)
        self.scalePxToMM = scale

        let drawnW = Double(self.imageWidth) * scale
        let drawnH = Double(self.imageHeight) * scale
        self.offsetXMM = (pw - drawnW) * 0.5
        self.offsetYMM = (ph - drawnH) * 0.5
    }

    @inlinable
    public func toPage(_ pt: VectorPoint) -> VectorPoint {
        if isRawPixels { return pt }
        return VectorPoint(
            x: offsetXMM + pt.x * scalePxToMM,
            y: offsetYMM + pt.y * scalePxToMM
        )
    }
}

/// Statistics and AxiDraw plotter metrics for the current vectorization.
public struct PlotterMetrics: Equatable, Codable, Sendable {
    public var imageWidth: Int = 0
    public var imageHeight: Int = 0
    public var pageWidthMM: Double = 210.0
    public var pageHeightMM: Double = 297.0
    public var pathCount: Int = 0
    public var pointCount: Int = 0
    public var bezierSegmentCount: Int = 0
    public var drawDistancePx: Double = 0
    public var drawDistanceMM: Double = 0
    public var travelDistanceRawMM: Double = 0
    public var travelDistanceOptimizedMM: Double = 0
    public var travelSavingsPercent: Double = 0
    public var penLifts: Int = 0
    public var estimatedPlotSeconds: Double = 0
    public var computeMilliseconds: Double = 0
    public var usedNeuralEngine: Bool = true
    public var penPathCounts: [Int] = []
    public var penBreakpointsPx: [Double] = []

    public init() {}
}

/// Complete output of a vectorization run.
public struct VectorizationResult: Equatable, Sendable {
    public var layers: [PenLayer]
    public var pageTransform: PageTransform
    public var metrics: PlotterMetrics
    public var svgPreview: String
    public var svgAxiDraw: String

    public init(
        layers: [PenLayer],
        pageTransform: PageTransform,
        metrics: PlotterMetrics,
        svgPreview: String,
        svgAxiDraw: String
    ) {
        self.layers = layers
        self.pageTransform = pageTransform
        self.metrics = metrics
        self.svgPreview = svgPreview
        self.svgAxiDraw = svgAxiDraw
    }

    public var allVisiblePaths: [VectorPath] {
        layers.filter(\.visible).flatMap(\.paths)
    }
}

/// Formats for CLI / HTTP export (`--format svg|json|txt|csv`).
public enum VectorExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case svgAxiDraw = "svg"
    case svgPreview = "svg-preview"
    case json = "json"
    case txt = "txt"
    case csv = "csv"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .svgAxiDraw:
            return L("SVG AxiDraw / Inkscape (mm + calques stylos)", "AxiDraw / Inkscape SVG (mm + pen layers)")
        case .svgPreview:
            return L("SVG Aperçu coloré (pixels)", "Colored Preview SVG (pixels)")
        case .json:
            return L("JSON complet (métriques + chemins + courbes)", "Full JSON (metrics + paths + curves)")
        case .txt:
            return L("Fiche technique de tracé (.txt)", "Plotter technical sheet (.txt)")
        case .csv:
            return L("Tableau des chemins par stylo (.csv)", "Paths table by pen (.csv)")
        }
    }

    public var detail: String {
        switch self {
        case .svgAxiDraw:
            return L(
                "Dimensions physiques en millimètres, calques inkscape:groupmode=\"layer\" par stylo, prêt pour AxiDraw Control et axicli.",
                "Physical dimensions in millimeters, inkscape:groupmode=\"layer\" per pen, ready for AxiDraw Control and axicli."
            )
        case .svgPreview:
            return L(
                "Couleurs de la palette Simple par épaisseur de stylo dans le repère de l'image source.",
                "Simple family palette colors per pen thickness in source image coordinates."
            )
        case .json:
            return L(
                "Toutes les statistiques, calques, points et segments de Bézier cubiques pour intégration pipeline.",
                "All statistics, layers, points, and cubic Bézier segments for pipeline integration."
            )
        case .txt:
            return L(
                "Résumé lisible : dimensions papier, distances de dessin/voyage, gain 2-opt, levées de stylo et durée estimée.",
                "Readable summary: paper size, draw/travel distances, 2-opt gain, pen lifts, and estimated duration."
            )
        case .csv:
            return L(
                "Une ligne par chemin : identifiant, stylo, épaisseur, nombre de points, longueur en mm, départ et arrivée.",
                "One row per path: ID, pen, width, point count, length in mm, start and end coordinates."
            )
        }
    }

    public var fileExtension: String {
        switch self {
        case .svgAxiDraw, .svgPreview: return "svg"
        case .json: return "json"
        case .txt: return "txt"
        case .csv: return "csv"
        }
    }
}

/// SVG and technical report generator for Illustration SVG and AxiDraw plotters.
public enum SVGExporter {
    public static func buildBezierLoopD(
        beziers: [CubicBezierSegment],
        isClosed: Bool = true,
        transform: PageTransform? = nil
    ) -> String {
        guard !beziers.isEmpty else { return "" }
        @inline(__always)
        func mapPt(_ p: VectorPoint) -> VectorPoint {
            transform?.toPage(p) ?? p
        }
        var parts: [String] = []
        parts.reserveCapacity(beziers.count + 2)
        let first = mapPt(beziers[0].p0)
        parts.append(String(format: "M%.2f,%.2f", first.x, first.y))
        for seg in beziers {
            let c1 = mapPt(seg.c1)
            let c2 = mapPt(seg.c2)
            let p3 = mapPt(seg.p3)
            parts.append(String(format: "C%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", c1.x, c1.y, c2.x, c2.y, p3.x, p3.y))
        }
        if isClosed { parts.append("Z") }
        return parts.joined()
    }

    public static func buildPathD(
        path: VectorPath,
        transform: PageTransform? = nil
    ) -> String {
        @inline(__always)
        func mapPt(_ p: VectorPoint) -> VectorPoint {
            transform?.toPage(p) ?? p
        }

        if !path.beziers.isEmpty {
            return buildBezierLoopD(beziers: path.beziers, isClosed: path.isClosed, transform: transform)
        }

        guard path.points.count >= 2 else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(path.points.count + 1)
        let first = mapPt(path.points[0])
        parts.append(String(format: "M%.2f,%.2f", first.x, first.y))
        for i in 1..<path.points.count {
            let p = mapPt(path.points[i])
            parts.append(String(format: "L%.2f,%.2f", p.x, p.y))
        }
        if path.isClosed { parts.append("Z") }
        return parts.joined()
    }

    /// Generates an SVG (either variable-width Illustration SVG or physical `mm` AxiDraw multi-pen SVG).
    public static func generateSVG(
        layers: [PenLayer],
        transform: PageTransform,
        metrics: PlotterMetrics,
        params: VectorizerParams,
        forPreview: Bool
    ) -> String {
        let isIllustration = (params.outputMode == .illustration)
        let usePixelCoords = forPreview || transform.isRawPixels
        let viewW = usePixelCoords ? Double(transform.imageWidth) : transform.pageWidthMM
        let viewH = usePixelCoords ? Double(transform.imageHeight) : transform.pageHeightMM
        let coordTransform: PageTransform? = usePixelCoords ? nil : transform
        let unitScale = usePixelCoords ? 1.0 : transform.scalePxToMM

        var lines: [String] = []
        lines.reserveCapacity(layers.reduce(32) { $0 + $1.paths.count + 6 })

        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        if usePixelCoords {
            lines.append(
                String(
                    format: "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" viewBox=\"0 0 %.0f %.0f\" width=\"%.0fpx\" height=\"%.0fpx\">",
                    viewW, viewH, viewW, viewH
                )
            )
        } else {
            lines.append(
                String(
                    format: "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" viewBox=\"0 0 %.2f %.2f\" width=\"%.2fmm\" height=\"%.2fmm\">",
                    viewW, viewH, viewW, viewH
                )
            )
        }

        lines.append("<!-- Generated by SimpleVectorizer (cie Adrien M) — Mode: \(params.outputMode.rawValue) -->")
        lines.append(
            String(
                format: "<!-- Algorithm: %@ | Paths: %d | Draw: %.1f mm | Travel: %.1f mm (2-opt saved %.1f%%) | Lifts: %d -->",
                params.algorithm.rawValue,
                metrics.pathCount,
                metrics.drawDistanceMM,
                metrics.travelDistanceOptimizedMM,
                metrics.travelSavingsPercent,
                metrics.penLifts
            )
        )

        for layer in layers where layer.visible && !layer.paths.isEmpty {
            let strokeColor = (!forPreview && (params.exportBlackStrokes || isIllustration)) ? "#000000" : layer.colorHex
            if isIllustration {
                lines.append(
                    String(
                        format: "  <g id=\"calque-%d\" inkscape:groupmode=\"layer\" inkscape:label=\"%@\">",
                        layer.index + 1,
                        layer.inkscapeLayerLabel
                    )
                )
                for path in layer.paths {
                    if params.illustrationStrokeStyle == .variableRibbon && !path.outlineBeziers.isEmpty {
                        let d = buildBezierLoopD(beziers: path.outlineBeziers, isClosed: true, transform: coordTransform)
                        if !d.isEmpty {
                            lines.append("    <path d=\"\(d)\" fill=\"\(strokeColor)\" stroke=\"none\"/>")
                        }
                    } else {
                        let d = buildPathD(path: path, transform: coordTransform)
                        if !d.isEmpty {
                            let wUnit = max(0.4 * unitScale, path.strokeRadiusPx * 2.0 * params.strokeWidthScale * unitScale)
                            lines.append(
                                String(
                                    format: "    <path d=\"%@\" fill=\"none\" stroke=\"%@\" stroke-width=\"%.2f\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
                                    d,
                                    strokeColor,
                                    wUnit
                                )
                            )
                        }
                    }
                }
                lines.append("  </g>")
            } else {
                let strokeWidth: Double
                if usePixelCoords {
                    strokeWidth = max(0.8, layer.widthMM / max(0.05, transform.scalePxToMM))
                } else {
                    strokeWidth = layer.widthMM
                }
                lines.append(
                    String(
                        format: "  <g id=\"stylo-%d\" inkscape:groupmode=\"layer\" inkscape:label=\"%@\" stroke=\"%@\" stroke-width=\"%.2f\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\">",
                        layer.index + 1,
                        layer.inkscapeLayerLabel,
                        strokeColor,
                        strokeWidth
                    )
                )
                for path in layer.paths {
                    let d = buildPathD(path: path, transform: coordTransform)
                    if !d.isEmpty {
                        lines.append("    <path d=\"\(d)\"/>")
                    }
                }
                lines.append("  </g>")
            }
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    public static func render(
        result: VectorizationResult,
        params: VectorizerParams,
        format: VectorExportFormat
    ) -> String {
        switch format {
        case .svgAxiDraw:
            return result.svgAxiDraw
        case .svgPreview:
            return result.svgPreview
        case .txt:
            let m = result.metrics
            return [
                "SimpleVectorizer — Fiche de tracé AxiDraw",
                "=========================================",
                "Algorithme        : \(params.algorithm.label)",
                String(format: "Image source      : %d × %d px", m.imageWidth, m.imageHeight),
                String(format: "Format papier     : %@ (%.1f × %.1f mm, marge %.1f mm)", params.paperFormat.rawValue, m.pageWidthMM, m.pageHeightMM, params.marginMM),
                String(format: "Chemins           : %d (%d points, %d courbes de Bézier)", m.pathCount, m.pointCount, m.bezierSegmentCount),
                String(format: "Distance dessin   : %.2f m (%.0f mm / %.0f px)", m.drawDistanceMM / 1000.0, m.drawDistanceMM, m.drawDistancePx),
                String(format: "Distance voyage   : %.2f m (gain 2-opt : -%.1f%%)", m.travelDistanceOptimizedMM / 1000.0, m.travelSavingsPercent),
                String(format: "Levées de stylo   : %d", m.penLifts),
                String(format: "Temps tracé est.  : %.0f s", m.estimatedPlotSeconds),
                String(format: "Temps de calcul   : %.1f ms (Neural Engine : %@)", m.computeMilliseconds, m.usedNeuralEngine ? "oui" : "non"),
                "",
                "Calques stylos :",
            ].joined(separator: "\n") + "\n" + result.layers.map { layer in
                String(format: "  - %@ : %d chemins", layer.inkscapeLayerLabel, layer.paths.count)
            }.joined(separator: "\n") + "\n"

        case .csv:
            var rows = ["id,pen_index,pen_label,width_mm,points,beziers,length_mm,start_x_mm,start_y_mm,end_x_mm,end_y_mm"]
            let t = result.pageTransform
            for layer in result.layers {
                for p in layer.paths {
                    let s = t.toPage(p.startPoint)
                    let e = t.toPage(p.endPoint)
                    let lenMM = p.lengthPx * t.scalePxToMM
                    rows.append(
                        String(
                            format: "%d,%d,\"%@\",%.2f,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f",
                            p.id,
                            layer.index + 1,
                            layer.name,
                            layer.widthMM,
                            p.points.count,
                            p.beziers.count,
                            lenMM,
                            s.x, s.y,
                            e.x, e.y
                        )
                    )
                }
            }
            return rows.joined(separator: "\n") + "\n"

        case .json:
            let m = result.metrics
            let payload: [String: Any] = [
                "app": "SimpleVectorizer",
                "algorithm": params.algorithm.rawValue,
                "paperFormat": params.paperFormat.rawValue,
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
                "layers": result.layers.map { layer in
                    [
                        "index": layer.index + 1,
                        "name": layer.name,
                        "widthMM": layer.widthMM,
                        "colorHex": layer.colorHex,
                        "pathCount": layer.paths.count,
                    ] as [String: Any]
                },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                return String(decoding: data, as: UTF8.self) + "\n"
            }
            return "{}\n"
        }
    }
}
