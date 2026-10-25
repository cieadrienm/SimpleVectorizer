# SimpleVectorizer — notes pour les agents

SimpleVectorizer transforme les dessins au trait bitmap en tracés vectoriels SVG simple-trait optimisés pour les traceurs à plume AxiDraw (squelettisation sous-pixel de Steger, contours Apple Vision ANE + hachures, séparation multi-stylos 1–4 par épaisseur EDT et optimisation 2-opt). App de la famille Simple de la cie Adrien M. Adrien (spectacle vivant) est l'unique utilisateur ; il parle français.

## Lire d'abord
- `~/Programmation/SimpleFamily/GUIDELINES.md` — les règles communes de la famille (G1–G134).
- `DECISIONS.md` — D1–D10, le pourquoi de chaque choix. **Ajouter une entrée pour tout choix structurant.**
- `README.md` — fonctionnalités, ligne de commande, limites.

## Identité
- Bundle `net.cieadrienm.simplevectorizer` ; ports HTTP `127.0.0.1:17940`, OSC entrée `0.0.0.0:9140`, OSC retour `127.0.0.1:9141` (G92, `x = 4`) ; dépôt GitHub `cieadrienm/SimpleVectorizer`, jamais de push sans accord explicite.

## Build et tests
    swift build / swift test
    .build/debug/SimpleVectorizer --self-test
    .build/debug/SimpleVectorizer --snapshot /tmp/simplevectorizer.png [--view split|vector|source|skeleton|about|help|shortcuts|settings|osc]
    Scripts/bundle.sh [debug|release]

## Règles qui ont coûté cher
- **Ne jamais utiliser un traceur de contours extérieur/intérieur classique (type Potrace) par défaut pour un dessin au trait AxiDraw** (D1) : le traceur à plume repasserait deux fois sur chaque ligne. Le mode par défaut `neuralCenterline` extrait la ligne centrale unique.
- **Ne jamais recalculer l'étape 1 (flou vDSP + Hessienne + Guo-Hall + Steger + EDT) quand seuls le format papier, les marges, l'échelle ou l'optimisation 2-opt changent** (D5) : `VectorizationEngine` met en cache le squelette sous-pixel et ses rayons EDT pour que l'étape 2 tourne en moins de 5 ms.
- **Zéro `import AppKit` dans `SimpleVectorizerCore` et `SimpleVectorizerCoreTests`** (G30).

## Architecture en une minute
- `Sources/SimpleVectorizerCore/` — `VectorizerModel.swift` (modèle, modes `Illustration SVG` vs `Traceur AxiDraw`, export SVG), `NeuralRidgeFilter.swift` (`RasterImage`, `vDSP`, Hessienne 2×2, EDT 2D exacte Meijster/Felzenszwalb, `VNDetectContoursRequest` ANE, Canny), `CenterlineTracer.swift` (Guo-Hall LUT 256, Steger Taylor 2ᵉ ordre, traversée colinéaire X/T, profil de rayon local EDT `pointRadiiPx` et k-moyennes 1D multi-stylos), `BezierAndPlotterOptimizer.swift` (RDP avec rayons, Bézier cubiques de Philip Schneider, rubans d'épaisseur variable `outlineBeziers`, hachures, Nearest-Neighbor + 2-opt, cache `VectorizationEngine`), `AxiDrawHardware.swift` (compilation de parcours sub-millimétrique `AxiDrawCompiledJob` et transport série POSIX `EBBSerialTransport` sur `/dev/cu.usbmodem*`), `SyntheticDrawing.swift`, `OSCAndHTTP.swift`, `Localization.swift`, `SimpleUpdater.swift`.
- `Sources/SimpleVectorizerMCPCore/` & `Sources/simplevectorizer-mcp/` — serveur MCP stdio JSON-RPC 2.0 (13 outils) relayant vers HTTP `/v1` (`127.0.0.1:17940`).
- `Sources/SimpleVectorizer/` — studio SwiftUI/AppKit (`Theme.swift`, `Components.swift`, `VectorizerController.swift` + `VectorRenderCache` 120 Hz, `AxiDrawPlotterController.swift`, `AppModel.swift`, `Views/*`, `Snapshot.swift`, `SelfTest.swift`, `HeadlessCLI.swift`, `SimpleVectorizerApp.swift`).

## Invariants
- L'export SVG pour formats physiques (`a4`, `a3`, `a5`, `a6`) écrit toujours `width="<mm>mm" height="<mm>mm"` et des groupes `<g inkscape:groupmode="layer" inkscape:label="1 - Stylo 1 ...">` avec `fill="none"`.
- Toute chaîne visible passe par `L("fr", "en")` avec un français impersonnel (ni « vous » ni « tu », G55).
