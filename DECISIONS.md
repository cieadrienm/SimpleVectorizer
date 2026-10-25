# DECISIONS — SimpleVectorizer

Journal des choix structurants : contexte, décision, ce qui a été écarté. Toutes les décisions ont été prises le 25 octobre 2026 à partir de la demande d'Adrien (« faire une nouvelle appli de la famille Simple : SimpleVectorizer, avec les meilleurs algorithmes de vectorisation éventuellement basés sur Neural Engine pour respecter un dessin au trait et tracer à l'AxiDraw »).

---

## Vectorisation et algorithmes

- **D1 — Extraction de la ligne médiane simple-trait par défaut (`neuralCenterline`), et non détourage de contours extérieur/intérieur.**
  - **Contexte** : Les vectoriseurs généralistes (Potrace, Adobe Image Trace) encadrent chaque trait noir par deux contours fermés (bord gauche et bord droit). Sur un traceur à plume AxiDraw, cela double le temps de tracé et épaissit artificiellement le trait.
  - **Décision** : Le moteur par défaut combine un débruitage gaussien séparable `vDSP`, un seuillage adaptatif par image intégrale, un filtre de crête curviligne (valeurs propres de la matrice Hessienne 2×2), une squelettisation morphologique 8-connexe de Guo-Hall par table de vérité (LUT 256 entrées) suivie d'un élagage d'escaliers, et le raffinement sous-pixel de Carsten Steger (développement de Taylor au 2ᵉ ordre de la Hessienne dans la direction normale à la crête).
  - **Écarté** : Potrace seul (repasse deux fois sur chaque ligne) ; Zhang-Suen naïf sans LUT ni correction sous-pixel (crée des marches d'escalier visibles à la plume).

- **D2 — Traversée colinéaire des jonctions X/T et ajustement de courbes de Bézier cubiques par moindres carrés de Philip Schneider.**
  - **Contexte** : Sur un squelette morphologique, chaque croisement de traits (degré $\ge 3$) interrompt le suivi de chaîne et casse le geste calligraphique en 3 ou 4 tronçons, provoquant des levées de plume inutiles et des pâtés d'encre aux intersections.
  - **Décision** : `CenterlineTracer` s'arrête proprement aux nœuds de degré $\ge 3$, puis `mergeCollinearJunctions` ré-apparie les branches dont les tangentes sortantes sont colinéaires ($\cos\theta > 0{,}55$) avant le recollage multi-passes par grille spatiale. Les polylignes simplifiées par Ramer-Douglas-Peucker sont ensuite découpées aux coins vifs (`cornerAngleDeg`) et ajustées en courbes de Bézier cubiques par l'algorithme de moindres carrés de Philip Schneider (*Graphics Gems I*) avec reparamétrisation de Newton-Raphson et bornage des poignées (`alpha <= 0.85 * segLength`).
  - **Écarté** : Export de polylignes `<polyline>` brutes (saccades mécaniques des moteurs pas-à-pas AxiDraw et fichiers SVG 5× plus lourds).

- **D3 — Contours Apple Vision sur Neural Engine (`VNDetectContoursRequest`) + générateur de hachures pour les aplats (`visionContours`).**
  - **Contexte** : Certains dessins mêlent du trait fin et des masses encrées pleines qu'un squelette médian réduirait à une seule arête centrale.
  - **Décision** : Le deuxième moteur exécute `VNDetectContoursRequest` sur l'Apple Neural Engine / GPU (avec repli déterministe marching-squares si l'environnement sans tête refuse le contexte Vision) et propose un remplissage automatique des régions sombres par hachures parallèles ou croisées (`hatchingEnabled`, `hatchingSpacing`, `hatchingAngle`, `crossHatch`) directement traçables à la plume.
  - **Écarté** : Remplissage SVG `fill="#000"` (ignoré par l'AxiDraw qui ne trace que les chemins `stroke`).

- **D4 — Séparation automatique en 1 à 4 stylos par transformée en distance euclidienne exacte (EDT) + k-moyennes 1D.**
  - **Contexte** : Un dessin au trait comporte souvent plusieurs calibres de feutres (p. ex. Staedtler/Micron 0,2 mm pour les hachures et 0,8 mm pour les contours).
  - **Décision** : Lors du prétraitement, `NeuralRidgeFilter.computeExactEDT` calcule la transformée en distance euclidienne 2D exacte en $O(W\times H)$ (algorithme séparable de Meijster/Felzenszwalb). Pour chaque chemin tracé, `CenterlineTracer` échantillonne le rayon local au 75ᵉ centile (robuste à l'effilement des extrémités) et partitionne les traits en `1..4` stylos par k-moyennes 1D déterministe. Chaque stylo devient un calque Inkscape numéroté (`<g inkscape:groupmode="layer" inkscape:label="1 - Stylo 1 (0.3mm)">`), compatible avec l'onglet *Layers* d'AxiDraw Control.
  - **Écarté** : Seuils d'épaisseur fixes en pixels (dépendent de la résolution du scan).

- **D5 — Architecture de calcul à deux étages avec cache (`VectorizationEngine`) et optimisation de parcours Nearest-Neighbor + 2-opt.**
  - **Contexte** : Ajuster le lissage de Bézier, le nombre de stylos, le format papier (A4/A3/A5), les marges ou l'optimisation de parcours ne doit pas relancer le filtrage d'image et la squelettisation.
  - **Décision** : `VectorizationEngine` sépare l'Étage 1 (flou `vDSP` + Hessienne + EDT + Guo-Hall + Steger, mis en cache avec une empreinte des paramètres bitmap) et l'Étage 2 (RDP + Schneider + k-moyennes + Nearest-Neighbor réversible + amélioration locale **2-opt** + mise en page millimétrique). L'Étage 2 s'exécute en quelques millisecondes lors du déplacement des curseurs de courbes ou de mise en page.
  - **Écarté** : Recalcul complet à chaque mouvement de curseur ; pilotage série USB EBB direct dans l'app (l'export SVG multi-calques pour Inkscape / `axicli` couvre le flux de travail d'Adrien sans dupliquer le pilote matériel).

---

## Architecture et intégration SimpleFamily

- **D6 — Paquet SwiftPM natif (`macOS 15`, outils 6.0, mode Swift 5), zéro dépendance externe, archivage du prototype Python dans `legacy/`.**
  - **Contexte** : Le dossier `SimpleVectorizer` contenait un prototype Python/Flask + OpenCV/scikit-image de mars 2026 nécessitant un `.venv` de plusieurs centaines de mégaoctets et un navigateur web.
  - **Décision** : Le prototype Python est conservé intact dans `legacy/` (conformément à G133, rien n'est perdu) et remplacé à la racine par une application native SwiftPM en quatre cibles : `SimpleVectorizerCore` (zéro `import AppKit`, G30), `SimpleVectorizerMCPCore`, `simplevectorizer-mcp` et `SimpleVectorizer`.

- **D7 — Ports de la famille Simple (`x = 4`, G92) : HTTP `/v1` sur `127.0.0.1:17940`, OSC entrée `0.0.0.0:9140`, retour OSC `127.0.0.1:9141`.**
  - **Contexte** : SimpleVectorizer est pilotable par OSC (`OSCScore`, `eMotion`), par API HTTP JSON locale et par serveur MCP (`simplevectorizer-mcp` embarqué dans `Contents/MacOS/`).
  - **Décision** : Attribution du créneau `x = 4` dans `SimpleFamily/GUIDELINES.md` (G92).

- **D8 — Navigation Trackpad + Souris (`CanvasInteractiveNSView`) et confinement strict du hit-testing.**
  - **Contexte** : `MagnificationGesture` SwiftUI repartait de `1.0` à chaque pincement, ne gérait pas le défilement à deux doigts du trackpad ni la molette de souris, et `.scaleEffect` sans `.allowsHitTesting(false)` faisait déborder la boîte de clic de l'image zoomée par-dessus la barre latérale et la barre haute.
  - **Décision** : Une vue AppKit dédiée (`CanvasInteractiveNSView`) dans chaque panneau traite nativement `magnify(with:)` (zoom incrémental centré sous le curseur), `scrollWheel(with:)` (défilement fluide à 2 doigts au trackpad, zoom centré sous le curseur à la molette souris ou avec `⌥`/`⌘` + trackpad) et les glissés souris (clic milieu/droit ou outil Déplacer `H`). Les vues zoomées ont `.allowsHitTesting(false)` et `.clipped().contentShape(Rectangle())` pour ne jamais intercepter les clics destinés à l'interface.

- **D9 — Lancement à vide sans modèles synthétiques dans l'interface et menu `Fichier > Ouvrir récent`.**
  - **Contexte** : Adrien préfère ne pas embarquer d'images par défaut dans l'interface et disposer d'un menu `Fichier > Ouvrir récent`.
  - **Décision** : L'application s'ouvre sur un écran d'accueil sobre (*Ouvrir une image… `⌘O`*, *Coller `⌘V`*, glisser-déposer et liste des derniers fichiers ouverts) et synchronise `Fichier > Ouvrir récent` avec `UserDefaults` et `NSDocumentController`. Les dessins synthétiques restent réservés à `--self-test` et `--snapshot`.

- **D10 — Image RGBA 32 bits prétraitée et filtrage par longueur d'arc géométrique pour `VNDetectContoursRequest` (`visionContours`).**
  - **Contexte** : `VNDetectContoursRequest` échouait ou ignorait les réglages de seuil sur une `CGImage` `DeviceGray` 8 bits brute, et le filtrage par nombre de sommets (`pts.count >= minPathLengthPx`) éliminait les segments droits simplifiés par Vision (2 sommets).
  - **Décision** : `makePreprocessedVisionCGImage` construit une `CGImage` RGBA 32 bits reflétant le seuil adaptatif/binaire, le flou et le nettoyage morphologique ; `collectVNContour` parcourt `observation.topLevelContours`, écarte le rectangle du bord de l'image et filtre selon la longueur géométrique en pixels (`arcLen >= minPathLengthPx`). `stitchPaths` préserve en outre les contours fermés sans les souder entre eux.

- **D11 — Édition directe des traits sur le canevas avec Annuler / Rétablir (`⌘Z` / `⇧⌘Z`).**
  - **Contexte** : Avant de lancer un tracé AxiDraw, il est fréquent de vouloir gommer quelques poussières, supprimer un trait parasite, ajuster un sommet, relier deux traits ou changer un trait de stylo.
  - **Décision** : Quatre outils de canevas (`Déplacer H`, `Sélection V`, `Gomme E`, `Tracer P`) permettent de sélectionner (au clic ou par rectangle), déplacer des traits ou des sommets (avec recalcul immédiat des courbes de Bézier de Schneider), gommer à la volée, tracer un trait libre, changer de stylo (`1..4`), simplifier, inverser, relier (`⌘J`), scinder ou supprimer (`⌫`), avec pile d'historique `⌘Z` / `⇧⌘Z`.

- **D12 — Rendu vectoriel 120 Hz indépendant de la résolution (`VectorRenderCache`) et synchronisation du zoom jusqu'à `6400 %`.**
  - **Contexte** : Un `.scaleEffect` SwiftUI appliqué autour d'un `Canvas` pixellise les vecteurs au zoom et fait plafonner CoreAnimation dès que la texture dépasse `16 384 px` ; à l'inverse, reconstruire des milliers de `Path` à chaque frame dégrade la fluidité sur les grandes scènes.
  - **Décision** : `VectorRenderCache` pré-construit une seule fois hors boucle de rendu les `Path` en coordonnées image ainsi qu'une grille spatiale `8×8`. À chaque frame, `VectorCanvasRenderView` filtre les tuiles visibles (`visibleImageRect`), projette le `Path` par une unique `CGAffineTransform` (`Path.applying`) et dessine les courbes directement dans l'espace écran Retina jusqu'à `6400 %`. En vue **Côte à côte**, `BitmapCanvasRenderView` partage exactement la même géométrie pour garantir un zoom synchronisé sans blocage.

- **D13 — Double mode de vectorisation : `Illustration SVG` (épaisseur variable) vs `Traceur AxiDraw` (épaisseur constante par stylo).**
  - **Contexte** : Lorsqu'on n'utilise pas l'AxiDraw, les traits d'un dessin à l'encre ou au pinceau n'ont pas tous la même épaisseur et varient le long du geste (pleins et déliés).
  - **Décision** : `CenterlineTracer` échantillonne et lisse le profil continu de demi-épaisseur locale (`pointRadiiPx`) sur la transformée en distance euclidienne 2D exacte en chaque sommet. En mode **Illustration SVG**, `BezierAndPlotterOptimizer.buildVariableWidthRibbon` génère dans l'Étage B une enveloppe fermée en courbes de Bézier cubiques (`outlineBeziers` avec subdivision de De Casteljau et embouts arrondis), ou exporte un `stroke-width` mesuré par trait (`perStrokeWidth`). En mode **Traceur AxiDraw**, chaque calque conserve une épaisseur mécanique uniforme correspondant au feutre physique.

- **D14 — Pilotage matériel direct de l'AxiDraw en USB série (`EBBSerialTransport` / `AxiDrawPlotterController`) et simulateur intégré.**
  - **Contexte** : Adrien souhaite pouvoir piloter directement l'AxiDraw depuis l'application sans dépendre d'Inkscape ou d'`axicli`.
  - **Décision** : `EBBSerialTransport` ouvre directement les ports USB CDC `/dev/cu.usbmodem*` via `termios` POSIX (zéro dépendance externe, G9), configure les butées du servo (`SC,4` / `SC,5`) et les moteurs en `1/16` de pas (`EM,1,1`, soit `80 pas/mm`), et envoie les déplacements en cinématique croisée CoreXY (`XM,duration,dxSteps,dySteps`) avec accumulateur entier de pas sans dérive. Un simulateur virtuel intégré prend le relais lorsqu'aucun AxiDraw n'est branché en USB.

---

## Remis à plus tard

- Vectorisation couleur multi-passes par séparation CMJN / tons directs.

---

## Mesures

- **Binaire `SimpleVectorizer` (release, arm64)** : **2,9 Mo** (contre ~420 Mo pour l'environnement Python OpenCV + scikit-image + Flask remplacé).
- **Binaire `simplevectorizer-mcp` (release, arm64)** : **167 Ko**.
- **Bundle `SimpleVectorizer.app` complet signé** : **3,8 Mo** (règle G41 : binaire < 5 Mo, `.app` < 10 Mo).
- **Temps de vectorisation complet (Release, portrait synthétique 720×960, Étage 1 + Étage 2)** : **42 ms** (Étage 2 seul depuis le cache : **< 2 ms**).
- **Gain d'optimisation de parcours (Nearest-Neighbor réversible + 2-opt)** : réduction de **74 %** de la distance de déplacement plume levée sur le portrait de référence (592 mm au lieu de 2 280 mm).
