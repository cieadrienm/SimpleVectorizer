import Foundation
import SimpleVectorizerCore

enum HeadlessCLI {
    static func printHelpAndExit() -> Never {
        let text = L(
            """
            SimpleVectorizer \(AppVersion.current.description) — Vectoriseur de dessins au trait pour traceurs AxiDraw (cie Adrien M)

            Usage :
              SimpleVectorizer [options] [fichier_image]

            Options communes (famille Simple) :
              --version, -v                     Imprime « SimpleVectorizer x.y.z (build) » et quitte
              --help, -h                        Affiche cette aide et quitte
              --self-test [--strict]            Exécute l'auto-test complet sur les dessins synthétiques
              --snapshot <png> [--view <vue>]   Rend la fenêtre hors écran en PNG (split, overlay, vector, about, help, shortcuts, settings, osc)
              --lang fr|en                      Force la langue pour cette exécution

            Options de vectorisation :
              --vectorize <image|preset>        Vectorise une image (ou un preset : portrait, stage, hatching, rosette) sans interface
              -o, --output <fichier>            Chemin du fichier de sortie (par défaut : stdout)
              --format svg|svg-preview|json|txt|csv   Format de sortie (défaut : svg)
              --algorithm <nom>                 neural_centerline (défaut), vision_contours, skeletonize, canny_edges
              --paper A4|A3|A5|A6|original      Format de feuille physique AxiDraw (défaut : A4)
              --pens 1..4                       Nombre de stylos classifiés par épaisseur k-means (défaut : 2)
              --smoothing 0.0..1.0              Lissage cubique de Bézier de Schneider (défaut : 0.65)
              --tolerance 0.1..5.0              Tolérance de simplification RDP en pixels (défaut : 1.0)
              --threshold 0..255                Seuil binaire ou sensibilité adaptative (défaut : 128)
              --continuity 0..100               Continuité de fusion des tracés (défaut : 55)
              --hatch                           Active le hachurage des aplats sombres
              --black                           Exporte les traits SVG en noir (#000000)
            """,
            """
            SimpleVectorizer \(AppVersion.current.description) — Line-art vectorizer for AxiDraw plotters (cie Adrien M)

            Usage:
              SimpleVectorizer [options] [image_file]

            Common options (Simple family):
              --version, -v                     Print "SimpleVectorizer x.y.z (build)" and exit
              --help, -h                        Print this help message and exit
              --self-test [--strict]            Run end-to-end self-test on synthetic drawings
              --snapshot <png> [--view <view>]  Render window or sheet offscreen to PNG (split, overlay, vector, about, help, shortcuts, settings, osc)
              --lang fr|en                      Force language for this run

            Vectorization options:
              --vectorize <image|preset>        Vectorize an image file (or preset: portrait, stage, hatching, rosette) headlessly
              -o, --output <file>               Output file path (default: stdout)
              --format svg|svg-preview|json|txt|csv   Output format (default: svg)
              --algorithm <name>                neural_centerline (default), vision_contours, skeletonize, canny_edges
              --paper A4|A3|A5|A6|original      AxiDraw physical paper format (default: A4)
              --pens 1..4                       Number of pens classified by k-means stroke width (default: 2)
              --smoothing 0.0..1.0              Schneider cubic Bézier smoothing (default: 0.65)
              --tolerance 0.1..5.0              RDP simplification tolerance in pixels (default: 1.0)
              --threshold 0..255                Binary threshold or adaptive sensitivity (default: 128)
              --continuity 0..100               Multi-pass stroke stitching continuity (default: 55)
              --hatch                           Enable dark region hatching
              --black                           Export SVG strokes in black (#000000)
            """
        )
        print(text)
        exit(0)
    }

    static func runVectorizeAndExit(arguments: [String]) -> Never {
        var inputSpec = ""
        var outputPath: String? = nil
        var format: VectorExportFormat = .svgAxiDraw
        var params = VectorizerParams()

        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--vectorize":
                if i + 1 < arguments.count {
                    inputSpec = arguments[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            case "-o", "--output":
                if i + 1 < arguments.count {
                    outputPath = arguments[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            case "--format":
                if i + 1 < arguments.count {
                    format = VectorExportFormat(rawValue: arguments[i + 1].lowercased()) ?? .svgAxiDraw
                    i += 2
                } else {
                    i += 1
                }
            case "--algorithm":
                if i + 1 < arguments.count, let alg = VectorAlgorithm(rawValue: arguments[i + 1].lowercased()) {
                    params.algorithm = alg
                    i += 2
                } else {
                    i += 1
                }
            case "--paper":
                if i + 1 < arguments.count,
                   let pf = PaperFormat.allCases.first(where: { $0.rawValue.lowercased() == arguments[i + 1].lowercased() }) {
                    params.paperFormat = pf
                    i += 2
                } else {
                    i += 1
                }
            case "--pens":
                if i + 1 < arguments.count, let n = Int(arguments[i + 1]) {
                    params.penCount = max(1, min(4, n))
                    i += 2
                } else {
                    i += 1
                }
            case "--smoothing":
                if i + 1 < arguments.count, let v = Double(arguments[i + 1]) {
                    params.curveSmoothing = max(0.0, min(1.0, v))
                    i += 2
                } else {
                    i += 1
                }
            case "--tolerance":
                if i + 1 < arguments.count, let v = Double(arguments[i + 1]) {
                    params.rdpTolerance = max(0.1, min(5.0, v))
                    i += 2
                } else {
                    i += 1
                }
            case "--threshold":
                if i + 1 < arguments.count, let v = Int(arguments[i + 1]) {
                    params.threshold = max(0, min(255, v))
                    i += 2
                } else {
                    i += 1
                }
            case "--continuity":
                if i + 1 < arguments.count, let v = Double(arguments[i + 1]) {
                    params.continuity = max(0, min(100, v))
                    i += 2
                } else {
                    i += 1
                }
            case "--hatch":
                params.hatchEnabled = true
                i += 1
            case "--black":
                params.exportBlackStrokes = true
                i += 1
            default:
                if !arg.hasPrefix("-") && inputSpec.isEmpty {
                    inputSpec = arg
                }
                i += 1
            }
        }

        let raster: RasterImage
        if let preset = SyntheticPreset(rawValue: inputSpec.lowercased()) {
            raster = SyntheticDrawing.generate(preset: preset)
        } else if !inputSpec.isEmpty {
            let url = URL(fileURLWithPath: (inputSpec as NSString).expandingTildeInPath)
            guard let loaded = RasterImage(contentsOf: url) else {
                fputs("SimpleVectorizer error: could not read image '\(inputSpec)'\n", stderr)
                exit(1)
            }
            raster = loaded
        } else {
            raster = SyntheticDrawing.generate(preset: .portrait)
        }

        let (_, res) = VectorizationEngine.vectorize(image: raster, params: params)
        let rendered = SVGExporter.render(result: res, params: params, format: format)

        if let outputPath {
            let outURL = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            do {
                try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try rendered.write(to: outURL, atomically: true, encoding: .utf8)
                exit(0)
            } catch {
                fputs("SimpleVectorizer error: \(error.localizedDescription)\n", stderr)
                exit(2)
            }
        } else {
            print(rendered, terminator: "")
            exit(0)
        }
    }
}
