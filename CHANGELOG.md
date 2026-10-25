# Changelog

La version de SimpleVectorizer vit à un seul endroit : `VERSION` dans `Scripts/bundle.sh` (G110).
Correctif : `x.y.Z` ; fonction : `x.Y.0` ; rupture : `X.0.0`.

## 0.7.7 — 2026-10-25

- **Pilotage direct du traceur AxiDraw en USB (protocole série EiBotBoard / EBB)** (`AxiDrawHardware`, `AxiDrawPlotterController`) sans aucune dépendance externe :
  - Détection automatique des ports USB série macOS (`/dev/cu.usbmodem*`, `/dev/cu.usbserial*`) via `termios` POSIX et interrogation firmware `V`, avec bascule automatique sur un **Simulateur AxiDraw (Virtuel)** intégré lorsqu'aucun traceur physique n'est branché.
  - Prise en charge des modèles **AxiDraw V3 / SE (A4)**, **AxiDraw V3/A3 / SE/A3 (A3)** et **AxiDraw MiniKit 2 (A6)** en pas de `1/16` (`EM,1,1` — `80 pas/mm`) avec commandes de cinématique croisée CoreXY `XM`, configuration des butées servo `SC,4` / `SC,5`, levée/pose `SP,1` / `SP,0` et arrêt d'urgence `ES`.
  - **Commandes manuelles de mise en route** : test `Haut` (`SP,1`), test `Bas` (`SP,0`), `Origine (0, 0)`, `Libérer` les moteurs (`EM,0,0` pour positionner la tête à la main au coin de la feuille) et `Cadrer` (parcours du rectangle englobant stylo levé pour vérifier l'alignement papier).
  - **Tracé en direct & changement de stylo** : compilation sub-millimétrique des courbes de Bézier (`AxiDrawCompiledJob`), accumulation entière de pas sans dérive, pause automatique en `(0, 0)` entre les calques multi-stylos avec bannière d'invitation à changer de feutre, réticule de tête AxiDraw en temps réel sur le canevas et pilotage OSC (`/simplevectorizer/axidraw/*`) / HTTP (`/v1/axidraw`).

## 0.7.6 — 2026-10-25

- Deux modes de vectorisation distincts en tête de la barre latérale (**Mode de vectorisation** + badge rapide dans la barre d'outils) :
  - **Illustration SVG** (`VectorOutputMode.illustration`) : mesure le profil continu de demi-épaisseur locale le long de chaque trait via la transformée en distance euclidienne 2D exacte (`pointRadiiPx`) et propose deux rendus :
    - **Pleins & déliés (Ruban variable)** (`IllustrationStrokeStyle.variableRibbon`) : construit une enveloppe fermée en courbes de Bézier cubiques d'épaisseur variable (`outlineBeziers`, avec subdivision de De Casteljau et embouts arrondis) fidèle aux variations de pression du dessin original.
    - **Ligne centrale (Épaisseur par trait)** (`IllustrationStrokeStyle.perStrokeWidth`) : conserve une courbe centrale unique par trait mais attribue à chaque chemin son épaisseur propre mesurée (`strokeRadiusPx`).
    - Curseur **Facteur d'épaisseur** (`×0,30 … ×2,50`) réévalué en `< 15 ms` via le cache `Stage B`.
  - **Traceur AxiDraw** (`VectorOutputMode.axidraw`) : épaisseur mécanique uniforme par calque de stylo (`0,3 mm`, `0,5 mm`, etc.), classification multi-stylos par k-moyennes, mise en page papier et optimisation 2-opt, avec déploiement automatique de la section **Traceur AxiDraw & Multi-stylos**.

## 0.7.5 — 2026-10-25

- Accélération 120 Hz du rendu vectoriel sur les scènes complexes (`VectorRenderCache`) : pré-construction hors boucle des `Path` en espace pixel, grille spatiale `8×8` avec frustum culling (`visibleImageRect`), projection par une unique `CGAffineTransform` par calque (`Path.applying`) et rejet O(1) par boîte englobante lors du clic et de la sélection rectangle.
- Synchronisation stricte du zoom en vue **Côte à côte** (`BitmapCanvasRenderView`) : rendu du bitmap via le même `CanvasTransformGeometry` que la vue vectorielle, supprimant le blocage lié à la limite de texture CoreAnimation (`16384 px`) à fort grossissement.
- Mode d'aperçu **Noir sur blanc** (`B` / `⌘B`, bouton barre d'outils et inspecteur) : feuille blanche papier et traits à l'encre noire.
- Section **Traceur AxiDraw & Multi-stylos** repliable dans la barre latérale (repliée par défaut) pour alléger l'interface lors d'un usage SVG généraliste.

## 0.7.4 — 2026-10-25

- Rendu 100 % vectoriel indépendant de la résolution dans la vue vecteur (`VectorCanvasRenderView`) : suppression du `.scaleEffect` bitmap externe au profit d'une projection directe des courbes de Bézier cubiques dans l'espace écran Retina à chaque niveau de zoom (`Animatable`), et extension du zoom maximal jusqu'à **6400 %** (`64×`) sans aucune pixellisation.

## 0.7.3 — 2026-10-25

- Raccourci `Z` global à la fenêtre pour réinitialiser la vue (zoom 100 % et recentrage) avec une animation ressort fluide et rapide (`0,18 s`), actif quelle que soit la zone ayant le focus.

## 0.7.2 — 2026-10-25

- Correction du recalcul des traits lors du chargement d'une nouvelle image : suivi par compteur de révision d'image monotone (`imageRevision`), invalidation stricte du cache `Stage A` entre images et protection des `Binding` SwiftUI contre les réévaluations parasites lors des transitions de vue.
- Décodage d'image élargi via ImageIO (`CGImageSourceCreateThumbnailAtIndex` avec orientation EXIF et `startAccessingSecurityScopedResource`) et prise en charge complète du glisser-déposer (`URL`, `NSURL`, `Data`, `NSImage`).
- Indicateur de progression centré dans le panneau vectoriel pendant le calcul initial d'une nouvelle image.

## 0.7.1 — 2026-10-25

- Navigation Trackpad + Souris (`CanvasInteractiveNSView`) : pincement incrémental centré sous le curseur (sans repartir de zéro), défilement fluide à 2 doigts au trackpad, zoom molette souris centré sous le curseur, déplacement clic milieu/droit et confinement strict du hit-testing dans chaque panneau.
- Lancement à vide par défaut (sans image préchargée) avec écran d'accueil et menu `Fichier > Ouvrir récent`.
- Correction du pipeline **Contours Vision (ANE + Hachures)** (`visionContours`) : prétraitement RGBA 32 bits contrasté pour `VNDetectContoursRequest`, parcours de `topLevelContours` et filtrage par longueur géométrique en pixels.
- Outils d'édition directe des traits sur le canevas (`Déplacer H`, `Sélection V`, `Gomme E`, `Tracer P`) avec déplacement de traits et de sommets, changement de stylo (`1..4`), simplification, inversion de sens, liaison (`⌘J`), scission, suppression (`⌫`) et historique Annuler / Rétablir (`⌘Z` / `⇧⌘Z`).

## 0.7.0 — 2026-10-25

- Première version native macOS (SwiftPM, `macOS 15`, universelle sans dépendance externe) remplaçant l'ancien prototype Python/Flask (archivé dans `legacy/`).
- Quatre pipelines de vectorisation dédiés au dessin au trait et au traceur AxiDraw :
  - **Ligne centrale (Neural + Steger)** (`neuralCenterline`) : flou gaussien séparable `vDSP`, seuillage adaptatif par image intégrale, filtre de crête curviligne par valeurs propres de la Hessienne 2×2, amincissement morphologique 8-connexe de Guo-Hall par LUT, raffinement sous-pixel de Carsten Steger, traversée colinéaire des jonctions X/T et ajustement de courbes de Bézier cubiques de Philip Schneider.
  - **Contours Vision (ANE + Hachures)** (`visionContours`) : détection de contours fermés sur Apple Neural Engine (`VNDetectContoursRequest`) et remplissage optionnel des aplats sombres par hachures parallèles ou croisées.
  - **Squelette morphologique (Guo-Hall)** (`skeletonize`) : amincissement médian pur 8-connexe pour encrages nets et schémas techniques.
  - **Contours Canny (Double seuil)** (`cannyEdges`) : gradient de Sobel, suppression des non-maxima et suivi par hystérésis.
- Séparation automatique en **1 à 4 stylos** par épaisseur de trait : transformée en distance euclidienne 2D exacte (Meijster/Felzenszwalb) + mesure au 75ᵉ centile + classification par k-moyennes 1D en calques Inkscape numérotés (`1 - Stylo 1 (0.3mm)` … `4 - Stylo 4 (1.2mm)`).
- Optimisation du parcours de plume AxiDraw : plus proche voisin réversible + amélioration locale **2-opt** par calque, affichage des déplacements plume levée en pointillés et calcul du temps de tracé estimé.
- Mise en page physique en millimètres (**A4, A3, A5, A6** portrait/paysage ou dimensions pixels d'origine), marges, échelle et décalages X/Y.
- Ligne de commande sans tête (`--vectorize`, `--preset`, `--snapshot`, `--self-test`), serveur OSC UDP (`:9140` / `:9141`), API HTTP locale `/v1` (`127.0.0.1:17940`) et serveur MCP embarqué (`simplevectorizer-mcp`).
