import Foundation

public let simpleVectorizerToolDefinitions: [[String: Any]] = [
    [
        "name": "simplevectorizer_state",
        "description": "Returns the current state of SimpleVectorizer: current image name & dimensions, active algorithm, parameters, plotter metrics (pathCount, drawDistanceMM, travelDistanceMM, travelSavingsPercent, penLifts, estimatedPlotSeconds, computeMilliseconds), pen layers, oscInPort, apiPort, version.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simplevectorizer_help",
        "description": "Returns the full HTTP API, MCP tool reference, OSC address map, and CLI flags.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simplevectorizer_open",
        "description": "Opens an image file from disk (PNG, JPEG, TIFF, BMP) or loads one of the built-in synthetic line-art presets ('portrait', 'stage', 'hatching', 'rosette') and runs vectorization.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Path to an image file on disk"],
                "preset": ["type": "string", "enum": ["portrait", "stage", "hatching", "rosette"], "description": "Optional synthetic line-drawing preset"],
            ],
        ],
    ],
    [
        "name": "simplevectorizer_set_params",
        "description": "Updates one or more vectorization or AxiDraw layout parameters and triggers re-vectorization (uses fast Stage-B cache when only curve fitting, paper size, or 2-opt changes).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "algorithm": ["type": "string", "enum": ["neural_centerline", "vision_contours", "skeletonize", "canny_edges"]],
                "adaptiveThreshold": ["type": "boolean"],
                "invert": ["type": "boolean"],
                "threshold": ["type": "integer", "description": "Threshold 0..255"],
                "blurRadius": ["type": "number", "description": "Gaussian blur sigma 0..10"],
                "morphCleanup": ["type": "integer", "description": "0=none, 1=close, 2=open+close"],
                "rdpTolerance": ["type": "number", "description": "RDP simplification tolerance 0.1..5.0 px"],
                "curveSmoothing": ["type": "number", "description": "Schneider cubic Bézier smoothing 0.0..1.0"],
                "cornerAngleDeg": ["type": "integer", "description": "Corner split angle 15..90 deg"],
                "minPathLengthPx": ["type": "integer", "description": "Minimum path length in pixels 1..30"],
                "stegerSubpixel": ["type": "boolean", "description": "Enable Steger Hessian sub-pixel centerline refinement"],
                "crossJunctions": ["type": "boolean", "description": "Enable collinear junction crossing"],
                "maxStitchGapPx": ["type": "number", "description": "Maximum stitch gap 1..25 px"],
                "continuity": ["type": "number", "description": "Stitching continuity 0..100"],
                "hatchEnabled": ["type": "boolean", "description": "Enable hatch fill for dark regions"],
                "hatchSpacingPx": ["type": "number", "description": "Hatch spacing in pixels 2.5..20"],
                "hatchAngleDeg": ["type": "number", "description": "Hatch angle in degrees"],
                "crossHatch": ["type": "boolean"],
                "penCount": ["type": "integer", "description": "Number of pens 1..4"],
                "paperFormat": ["type": "string", "enum": ["A4", "A3", "A5", "A6", "original"]],
                "paperOrientation": ["type": "string", "enum": ["auto", "portrait", "landscape"]],
                "marginMM": ["type": "number", "description": "Paper margin in mm"],
                "optimize2Opt": ["type": "boolean", "description": "Enable 2-opt toolpath travel optimization"],
                "exportBlackStrokes": ["type": "boolean"],
            ],
        ],
    ],
    [
        "name": "simplevectorizer_export_svg",
        "description": "Returns the generated AxiDraw-ready SVG (or writes it to an output file path if 'outputPath' is given).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "outputPath": ["type": "string", "description": "Optional file path where the SVG should be saved"],
                "format": ["type": "string", "enum": ["svg", "svg-preview", "json", "txt", "csv"], "description": "Export format (default 'svg')"],
            ],
        ],
    ],
    [
        "name": "simplevectorizer_snapshot",
        "description": "Captures the SimpleVectorizer window as a PNG image ('split', 'overlay', or 'vector' view).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "view": ["type": "string", "enum": ["split", "overlay", "vector"], "description": "Optional view mode"],
            ],
        ],
    ],
]
