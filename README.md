# SimpleVectorizer

**Vectorisation de dessin au trait & préparation de tracé AxiDraw pour macOS.**  
Application native Swift / SwiftUI / Accelerate `vDSP` / Apple Vision (`VNDetectContoursRequest`), membre de la famille **Simple** ([cie Adrien M](https://www.adrien-m.net/software)).

---

## Fonctionnalités

- **Deux modes de vectorisation complémentaires** :
  - **Illustration SVG (Épaisseur variable · Pleins & déliés)** : mesure le profil continu de demi-épaisseur locale le long de chaque trait via la transformée en distance euclidienne 2D exacte (`pointRadiiPx`) et génère soit un **ruban de Bézier cubique fermé d'épaisseur variable** (`outlineBeziers`), soit une **ligne centrale avec épaisseur propre par trait** (`stroke-width` individuel), ajustable en temps réel via le curseur **Facteur d'épaisseur**.
  - **Traceur AxiDraw (Stylos calibrés · 2-opt)** : épaisseur mécanique constante par calque de stylo (`0,3 mm`, `0,5 mm`, etc.), classification multi-stylos, cadrage sur feuille physique et pilotage USB direct.
- **Quatre moteurs d'extraction** :
  1. **Ligne médiane ANE + Steger** (`neuralCenterline`) — débruitage gaussien séparable `vDSP`, seuillage adaptatif par image intégrale, filtre de crête curviligne (valeurs propres de la matrice Hessienne 2×2), squelettisation morphologique 8-connexe de Guo-Hall par table de vérité (LUT 256 entrées), raffinement sous-pixel de Carsten Steger (développement de Taylor au 2ᵉ ordre de la Hessienne), traversée colinéaire des jonctions X/T, recollage multi-passes par grille spatiale et ajustement de courbes de Bézier cubiques par moindres carrés de Philip Schneider.
  2. **Contours Vision ANE + Hachures** (`visionContours`) — extraction de contours fermés sur Apple Neural Engine / GPU via `VNDetectContoursRequest` (avec repli marching-squares déterministe) et générateur optionnel de hachures parallèles ou croisées pour remplir les aplats sombres au traceur.
  3. **Squelettisation Guo-Hall** (`skeletonize`) — amincissement médian pur 8-connexe sans lissage préalable, idéal pour les encrages nets et les plans techniques.
  4. **Contours Canny (double seuil)** (`cannyEdges`) — gradient de Sobel, suppression des non-maxima dans la direction du gradient et suivi par hystérésis.
- **Séparation multi-stylos automatique (1 à 4 stylos)** :
  - Transformée en distance euclidienne exacte 2D séparable (algorithme de Meijster/Felzenszwalb en $O(W\times H)$).
  - Mesure de l'épaisseur locale au 75ᵉ centile le long de chaque trait et classification par k-moyennes 1D en 1 à 4 calques Inkscape numérotés (`1 - Stylo 1 (0.3mm)`, `2 - Stylo 2 (0.5mm)`, etc.) directement reconnus par l'onglet *Layers* du plugin AxiDraw Control.
- **Optimisation du parcours de plume (Nearest-Neighbor + 2-opt)** :
  - Réordonnancement réversible des polylignes par plus proche voisin suivi d'une amélioration locale **2-opt** qui décroise les déplacements plume levée.
  - Métriques temps réel : nombre de chemins, segments de Bézier, distance de tracé plume baissée (`mm` / `m`), distance de déplacement rapide plume levée (`mm`), gain d'optimisation (`%`) et estimation de la durée de tracé.
- **Pilotage direct du traceur AxiDraw en USB (protocole série EiBotBoard / EBB)** :
  - Détection automatique des ports `/dev/cu.usbmodem*` (et simulateur AxiDraw virtuel intégré lorsqu'aucun traceur n'est connecté).
  - Modèles **AxiDraw V3 / SE (A4)**, **AxiDraw V3/A3 (A3)** et **AxiDraw MiniKit 2 (A6)** à `80 pas/mm` (`1/16` micropas, cinématique croisée CoreXY `XM`).
  - Commandes de réglage en direct : test stylo `Haut` (`SP,1`), test stylo `Bas` (`SP,0`), `Origine (0, 0)`, `Libérer` les moteurs (`EM,0,0`), `Cadrer` (parcours du rectangle englobant stylo levé), pause automatique en `(0, 0)` entre les calques multi-stylos et suivi visuel de la tête en temps réel sur le canevas.
- **Mise en page physique, Rendu 120 Hz & Édition directe** :
  - Rendu vectoriel 120 Hz indépendant de la résolution jusqu'à **6400 %** de zoom (`VectorRenderCache` avec grille spatiale `8×8` et frustum culling), aperçu **Noir sur blanc** (`B` / `⌘B`) et réinitialisation fluide de la vue (`Z`).
  - Outils d'édition directe sur le canevas (`Déplacer H`, `Sélection V`, `Gomme E`, `Tracer P`) avec historique `⌘Z` / `⇧⌘Z`.
  - Formats **A4**, **A3**, **A5**, **A6** (portrait ou paysage, `width`/`height` en `mm`) ou dimensions pixels d'origine.

---

## Compilation & Installation

Prérequis : macOS 15+ et Swift 6.0+ (Xcode 16 ou Command Line Tools). Aucune dépendance externe.

```bash
# Compiler et exécuter la suite de tests
swift build
swift test

# Assembler, signer et installer SimpleVectorizer.app dans /Applications
./Scripts/bundle.sh release

# Exécuter l'auto-test complet sans écran
./build/SimpleVectorizer.app/Contents/MacOS/SimpleVectorizer --self-test
```

---

## Ligne de commande

```bash
# Vectoriser un dessin vers un fichier SVG AxiDraw A4 avec 2 stylos
SimpleVectorizer --vectorize dessin.png -o sortie.svg --algorithm neural_centerline --pens 2 --paper A4

# Vectoriser un des 4 dessins synthétiques intégrés (portrait, stage, hatching, rosette)
SimpleVectorizer --vectorize rosette -o rosace.svg --pens 3 --paper A3

#Exporter les statistiques de tracé en JSON, CSV ou TXT
SimpleVectorizer --vectorize dessin.png --format json -o stats.json

# Capturer une image de contrôle hors écran (split, overlay, vector, about, help, shortcuts, settings, osc)
SimpleVectorizer --snapshot /tmp/preview.png --view split --lang fr
```

---

## Pilotage OSC, API HTTP & MCP

- **OSC (UDP)** : écoute sur `0.0.0.0:9140`, retour d'état sur `127.0.0.1:9141` (`/simplevectorizer/algorithm`, `/simplevectorizer/threshold`, `/simplevectorizer/smoothing`, `/simplevectorizer/tolerance`, `/simplevectorizer/pens`, `/simplevectorizer/paper`, `/simplevectorizer/preset`, `/simplevectorizer/export`, `/simplevectorizer/axidraw/plot`, `pause`, `resume`, `stop`, `penup`, `pendown`, `home`, `unlock`).
- **HTTP `/v1` (JSON)** : serveur local sur `http://127.0.0.1:17940/v1` (`/v1/state`, `/v1/params`, `/v1/open`, `/v1/export`, `/v1/svg`, `/v1/axidraw`, `/v1/snapshot.png`).
- **Serveur MCP embarqué** : `SimpleVectorizer.app/Contents/MacOS/simplevectorizer-mcp` (13 outils MCP sur `stdio` JSON-RPC 2.0).

---

## Confidentialité

SimpleVectorizer traite les images exclusivement en local sur le Mac (CPU, GPU, Apple Neural Engine) et n'ouvre que les ports locaux OSC (`:9140`) et HTTP/MCP (`127.0.0.1:17940`). Aucune télémétrie, aucun compte, aucune connexion externe hors vérification quotidienne optionnelle des mises à jour sur `api.github.com/repos/cieadrienm/SimpleVectorizer/releases/latest`.

---

## Crédits & Licence

- **Conception & développement** : Adrien Mondot · **cie Adrien M** — [adrien-m.net/software](https://www.adrien-m.net/software)
- **Licence** : GNU General Public License v3.0 or later ([LICENSE](LICENSE))
