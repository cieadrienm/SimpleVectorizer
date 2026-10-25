#!/usr/bin/env python3
"""
Vectoriseur Pro — Backend Python pour vectorisation bitmap → SVG
Optimisé pour traceurs à plumes (pen plotters)

Endpoints:
  GET /              → Serves index.html
  POST /process      → Process image with SSE progress updates
  POST /export       → Export final SVG
  GET /status        → Server capabilities
  GET /health        → Health check
"""

import os
import sys
import json
import time
import math
import copy
import logging
import io
import threading
from pathlib import Path
from typing import List, Tuple, Dict, Any, Optional, Union

import numpy as np
import cv2
from skimage.morphology import skeletonize
from scipy.spatial import KDTree
from scipy.ndimage import label as ndimage_label, find_objects as ndimage_find_objects
from flask import Flask, request, Response, send_file, jsonify, send_from_directory
from flask_cors import CORS
from werkzeug.utils import secure_filename

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

MAX_IMAGE_SIZE = 4096
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'bmp', 'tiff', 'gif'}
UPLOAD_FOLDER = Path('/tmp/vectorizer_uploads')
UPLOAD_FOLDER.mkdir(exist_ok=True)

app = Flask(__name__, static_folder=None)
CORS(app)
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024


# ============================================================================
# Parameters — mapped from frontend names
# ============================================================================

class Params:
    """Processing parameters, accepting frontend JSON keys."""
    def __init__(self, **kwargs):
        self.algorithm = kwargs.get('algorithm', 'skeletonize')
        self.threshold = int(kwargs.get('threshold', 128))
        self.blur = float(kwargs.get('blur', 0))
        self.invert = bool(kwargs.get('invert', False))
        self.adaptive = bool(kwargs.get('adaptive', True))
        self.cleanup = float(kwargs.get('cleanup', 0))  # 0=none, 1=gentle, 2=strong
        self.tolerance = float(kwargs.get('rdpTolerance', kwargs.get('tolerance', 1.0)))
        self.smoothing = float(kwargs.get('curveSmooth', kwargs.get('smoothing', 0.5)))
        self.corner_angle = int(kwargs.get('cornerAngle', 45))
        self.min_length = int(kwargs.get('minLength', 3))
        self.max_stitch_gap = int(kwargs.get('maxGap', kwargs.get('maxStitchGap', 8)))
        self.continuity = int(kwargs.get('continuity', 50))  # 0-100
        self.pen_count = int(kwargs.get('penCount', 2))
        self.pen_widths = kwargs.get('penWidths', kwargs.get('penStrokes', None))
        self.pen_thresholds = kwargs.get('penThresholds', None)

        if self.pen_widths is None:
            self.pen_widths = [0.5, 1.0, 1.5, 2.0][:self.pen_count]
        if self.pen_thresholds is None:
            self.pen_thresholds = [3, 6, 9, 12][:self.pen_count]


PEN_COLORS = ['#FF0080', '#00d4ff', '#FFB800', '#80FF00']

# Server-side cache for intermediate results (avoids recomputation on param tweaks)
import hashlib
_cache = {}  # image_hash → { binary, paths_by_pen_raw, image_size, params_hash_extract }


# ============================================================================
# Image Loading & Preprocessing
# ============================================================================

def allowed_file(filename: str) -> bool:
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def load_image(filepath: str) -> np.ndarray:
    img = cv2.imread(filepath)
    if img is None:
        raise ValueError(f"Failed to load image: {filepath}")
    h, w = img.shape[:2]
    if max(h, w) > MAX_IMAGE_SIZE:
        scale = MAX_IMAGE_SIZE / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return img


def preprocess_image(img: np.ndarray, params: Params) -> np.ndarray:
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img.copy()

    if params.blur > 0:
        k = int(params.blur) * 2 + 1
        gray = cv2.GaussianBlur(gray, (k, k), 0)

    if params.adaptive:
        # Adaptive threshold: adjusts to local contrast, preserves fine lines
        # even near varying backgrounds. Much better for hatching and fine detail.
        block_size = max(11, (params.threshold // 10) * 2 + 1)  # odd number, ~11-51
        C = 10  # bias: higher = less sensitive to faint marks
        binary = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY_INV,  # ink (dark) → 255 directly
            block_size, C
        )
        logger.info(f"Adaptive threshold: block={block_size}, C={C}")
    else:
        # Global threshold
        _, binary = cv2.threshold(gray, params.threshold, 255, cv2.THRESH_BINARY)
        if params.invert:
            binary = cv2.bitwise_not(binary)
        # Auto-detect polarity: ensure INK (minority) is foreground (255)
        if np.sum(binary > 127) > binary.size / 2:
            binary = cv2.bitwise_not(binary)
            logger.info("Auto-inverted: ink is now foreground (255)")

    # Morphological cleanup — controlled by cleanup param
    # 0 = none (preserve all fine lines)
    # 1 = gentle (close small gaps only, no opening)
    # 2 = strong (open to remove noise + close)
    if params.cleanup >= 2:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)
        binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel, iterations=1)
    elif params.cleanup >= 1:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel, iterations=1)
    # cleanup=0: no morphological operations → fine lines preserved

    return binary


# ============================================================================
# Skeleton / Edge Extraction
# ============================================================================

def extract_skeleton(binary: np.ndarray) -> np.ndarray:
    return (skeletonize(binary > 127).astype(np.uint8)) * 255


def extract_edges(gray: np.ndarray, params: Params) -> np.ndarray:
    lo = max(0, params.threshold - 50)
    hi = min(255, params.threshold + 50)
    edges = cv2.Canny(gray, lo, hi)
    return (skeletonize(edges > 127).astype(np.uint8)) * 255


# ============================================================================
# Path Tracing  (returns paths in row,col = y,x order)
# ============================================================================

def trace_paths(skeleton: np.ndarray, params: Params) -> List[List[Tuple[int, int]]]:
    """
    Fast path tracing using connected-component labeling + zero-padded flat-array traversal.
    Returns paths as lists of (row, col) = (y, x) tuples.

    Key optimizations:
    - scipy.ndimage.label (C) for connected components
    - find_objects for O(1) bounding boxes (no per-component scan)
    - Zero-padded flat array → no bounds checking in inner loop
    - Sub-images per component → Phase 3 scans tiny regions
    """
    skel_bool = skeleton > 0
    h, w = skeleton.shape
    total_px = int(np.sum(skel_bool))

    if total_px == 0:
        return []

    # Connected component labeling with 8-CONNECTIVITY (matches skeleton topology!)
    struct8 = np.ones((3, 3), dtype=np.int32)
    labeled, n_comp = ndimage_label(skel_bool, structure=struct8)
    slices = ndimage_find_objects(labeled)

    # Neighbor-count kernel
    kern = np.ones((3, 3), dtype=np.uint8)
    kern[1, 1] = 0

    paths = []
    min_len = params.min_length

    DY = (-1, -1, -1,  0, 0,  1, 1, 1)
    DX = (-1,  0,  1, -1, 1, -1, 0, 1)

    for comp_id in range(n_comp):
        sl = slices[comp_id]
        if sl is None:
            continue

        y0, y1 = sl[0].start, sl[0].stop
        x0, x1 = sl[1].start, sl[1].stop
        sh = y1 - y0
        sw = x1 - x0

        # Extract sub-image for this component only
        sub_labeled = labeled[y0:y1, x0:x1]
        sub_bool = (sub_labeled == comp_id + 1)
        n_px = int(np.sum(sub_bool))
        if n_px < min_len:
            continue

        # Padded sub-image (1px border of zeros → no bounds check)
        padded = np.zeros((sh + 2, sw + 2), dtype=np.uint8)
        padded[1:sh+1, 1:sw+1] = sub_bool

        flat = padded.ravel()
        stride = sw + 2
        offsets = tuple(dy * stride + dx for dy, dx in zip(DY, DX))

        # Compute neighbor count PER-COMPONENT (not global — avoids false junctions)
        nc_comp = cv2.filter2D(sub_bool.astype(np.uint8), -1, kern)
        ep_ys, ep_xs = np.where(sub_bool & (nc_comp == 1))
        junc_ys, junc_xs = np.where(sub_bool & (nc_comp >= 3))

        def _trace_flat(sy, sx):
            pos = (sy + 1) * stride + (sx + 1)
            if not flat[pos]:
                return [], []
            flat[pos] = 0
            path_y = [sy]
            path_x = [sx]
            while True:
                found = False
                for off in offsets:
                    npos = pos + off
                    if flat[npos]:
                        flat[npos] = 0
                        pos = npos
                        path_y.append(pos // stride - 1)
                        path_x.append(pos % stride - 1)
                        found = True
                        break
                if not found:
                    break
            return path_y, path_x

        def _collect(py, px):
            if len(py) >= min_len:
                paths.append([(py[i] + y0, px[i] + x0) for i in range(len(py))])

        # Phase 1: endpoints
        for i in range(len(ep_ys)):
            ey, ex = int(ep_ys[i]), int(ep_xs[i])
            py, px = _trace_flat(ey, ex)
            _collect(py, px)

        # Phase 2: junction neighbors
        for i in range(len(junc_ys)):
            jy, jx = int(junc_ys[i]), int(junc_xs[i])
            for dy, dx in zip(DY, DX):
                ny, nx = jy + dy, jx + dx
                if 0 <= ny < sh and 0 <= nx < sw:
                    py, px = _trace_flat(ny, nx)
                    _collect(py, px)

        # Phase 3: remaining loops (tiny sub-image scan)
        rem_ys, rem_xs = np.where(padded[1:sh+1, 1:sw+1] > 0)
        for i in range(len(rem_ys)):
            py, px = _trace_flat(int(rem_ys[i]), int(rem_xs[i]))
            _collect(py, px)

    logger.info(f"Traced {len(paths)} paths ({n_comp} components, {total_px} px)")
    return paths


# ============================================================================
# Path Stitching (KD-tree + tangent alignment)
# ============================================================================

def stitch_paths(paths, params: Params):
    """
    Multi-pass bidirectional path stitching with continuity control.

    continuity (0-100) controls:
    - 0:   conservative — small gap, strict tangent, single pass
    - 50:  balanced — moderate gap, relaxed tangent, 2 passes
    - 100: aggressive — large gap, very relaxed tangent, 3 passes
           (maximizes long continuous curves)
    """
    if len(paths) <= 1:
        return paths

    c = params.continuity / 100.0  # 0.0 → 1.0

    # Multi-pass with increasing gap radius
    # At continuity=0: 1 pass at gap; at 100: 3 passes at gap, 2×gap, 3×gap
    base_gap = params.max_stitch_gap
    n_passes = 1 + int(c * 2)  # 1, 2, or 3 passes
    gap_multipliers = [1.0, 1.5 + c, 2.0 + c * 2][:n_passes]

    # Tangent rejection threshold: -0.5 (strict) → -0.95 (very relaxed, only rejects U-turns)
    cos_reject = -0.3 - c * 0.6  # -0.3 → -0.9

    current_paths = list(paths)

    for pass_idx, gap_mult in enumerate(gap_multipliers):
        gap = base_gap * gap_mult

        if len(current_paths) <= 1:
            break

        # Build KD-tree of endpoints for this pass
        ep_list = []
        for i, p in enumerate(current_paths):
            ep_list.append((p[0], i, False))
            ep_list.append((p[-1], i, True))

        coords = np.array([e[0] for e in ep_list], dtype=np.float64)
        try:
            tree = KDTree(coords)
        except Exception:
            break

        merged = [False] * len(current_paths)
        result = []

        # Sort paths by length (descending) — start with longest paths
        # so they "attract" shorter fragments
        order = sorted(range(len(current_paths)),
                       key=lambda idx: len(current_paths[idx]), reverse=True)

        for i in order:
            if merged[i]:
                continue
            cur = list(current_paths[i])
            changed = True

            while changed:
                changed = False

                # Try both ends
                for try_end in (True, False):
                    if try_end:
                        probe_pt = cur[-1]
                        if len(cur) >= 3:
                            # Average tangent over last few points for stability
                            tang = np.array(cur[-1]) - np.array(cur[-min(5, len(cur))])
                        elif len(cur) >= 2:
                            tang = np.array(cur[-1]) - np.array(cur[-2])
                        else:
                            tang = None
                    else:
                        probe_pt = cur[0]
                        if len(cur) >= 3:
                            tang = np.array(cur[0]) - np.array(cur[min(4, len(cur)-1)])
                        elif len(cur) >= 2:
                            tang = np.array(cur[0]) - np.array(cur[1])
                        else:
                            tang = None

                    probe = np.array(probe_pt, dtype=np.float64)
                    idxs = tree.query_ball_point(probe, gap)
                    best = None
                    best_score = float('inf')

                    for idx in idxs:
                        _, pidx, is_end_ep = ep_list[idx]
                        if merged[pidx] or pidx == i:
                            continue
                        pt = np.array(ep_list[idx][0], dtype=np.float64)
                        d = np.linalg.norm(probe - pt)
                        if d > gap:
                            continue

                        # Tangent check
                        cand = current_paths[pidx]
                        cos_val = 1.0
                        if tang is not None and len(cand) >= 2:
                            if is_end_ep:
                                d2 = np.array(cand[-1]) - np.array(cand[-min(5, len(cand))])
                            else:
                                d2 = np.array(cand[1]) - np.array(cand[0])
                            n1, n2 = np.linalg.norm(tang), np.linalg.norm(d2)
                            if n1 > 0 and n2 > 0:
                                cos_val = np.dot(tang, d2) / (n1 * n2)
                                if cos_val < cos_reject:
                                    continue

                        # Score: prefer close + aligned
                        # Lower score = better candidate
                        score = d * (1.5 - max(cos_val, 0))
                        if score < best_score:
                            ordered = list(reversed(cand)) if is_end_ep else list(cand)
                            best = (ordered, pidx)
                            best_score = score

                    if best:
                        ordered, pidx = best
                        if try_end:
                            cur.extend(ordered)
                        else:
                            cur = list(reversed(ordered)) + cur
                        merged[pidx] = True
                        changed = True
                        break  # restart both-ends loop

            result.append(cur)

        before = len(current_paths)
        current_paths = result
        logger.info(f"Stitch pass {pass_idx+1} (gap={gap:.0f}): "
                    f"{before} → {len(current_paths)}")

    return current_paths


# ============================================================================
# Simplification (RDP via OpenCV)
# ============================================================================

def simplify_path(path, epsilon: float):
    if len(path) < 3:
        return path
    pts = np.array(path, dtype=np.float32)
    simplified = cv2.approxPolyDP(pts, epsilon, False)
    return [(int(p[0][0]), int(p[0][1])) for p in simplified]


# ============================================================================
# Pen Assignment (distance transform + adaptive clustering)
# ============================================================================

def _kmeans_1d(values, k, max_iter=30):
    """Simple 1D k-means clustering. Returns sorted breakpoints between clusters."""
    if len(values) < k or k <= 1:
        return []
    vals = np.sort(values)

    # Initialize centroids at evenly spaced quantiles
    centroids = np.percentile(vals, np.linspace(0, 100, k + 2)[1:-1])

    for _ in range(max_iter):
        # Assign to nearest centroid
        diffs = np.abs(vals[:, None] - centroids[None, :])
        labels = np.argmin(diffs, axis=1)
        # Update centroids
        new_c = np.array([vals[labels == i].mean() if np.any(labels == i)
                          else centroids[i] for i in range(k)])
        if np.allclose(centroids, new_c, atol=0.01):
            break
        centroids = new_c

    centroids.sort()
    # Breakpoints = midpoints between consecutive centroids
    return [(centroids[i] + centroids[i + 1]) / 2 for i in range(k - 1)]


def assign_paths_to_pens(paths, binary: np.ndarray, params: Params):
    """
    Assign paths to pen layers based on stroke width.

    Uses distance transform to measure stroke half-width at each skeleton pixel,
    then k-means clustering to find natural width groups.
    Paths are still in (y, x) order here.
    """
    # Distance transform: value at each ink pixel = distance to nearest edge
    # Since binary has ink=255 after auto-detect, DT gives stroke half-width
    dist = cv2.distanceTransform(binary, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)

    # Measure median width along each path
    path_widths = np.zeros(len(paths), dtype=np.float64)
    for idx, path in enumerate(paths):
        samples = [dist[y, x] for y, x in path
                   if 0 <= y < dist.shape[0] and 0 <= x < dist.shape[1]
                   and dist[y, x] > 0]
        path_widths[idx] = np.median(samples) if samples else 0

    by_pen = {i: [] for i in range(params.pen_count)}

    if params.pen_count <= 1:
        by_pen[0] = list(paths)
        return by_pen

    # Find natural breakpoints via 1D k-means
    valid_widths = path_widths[path_widths > 0]

    if len(valid_widths) < params.pen_count:
        # Not enough data to cluster, put everything in pen 0
        by_pen[0] = list(paths)
        return by_pen

    breakpoints = _kmeans_1d(valid_widths, params.pen_count)

    if not breakpoints:
        by_pen[0] = list(paths)
        return by_pen

    # Assign each path to a pen based on its width
    for path, w in zip(paths, path_widths):
        pen = 0
        for i, bp in enumerate(breakpoints):
            if w > bp:
                pen = i + 1
        by_pen[min(pen, params.pen_count - 1)].append(path)

    for pen_idx in range(params.pen_count):
        logger.info(f"Pen {pen_idx}: {len(by_pen[pen_idx])} paths "
                     f"(width threshold: {'<' if pen_idx == 0 else '>'}"
                     f"{breakpoints[min(pen_idx, len(breakpoints))-1]:.1f}px)"
                     if breakpoints else "")

    return by_pen


# ============================================================================
# Multi-Pass Extraction — separate skeleton per pen thickness
# ============================================================================

def extract_multi_pass(binary, params: Params, progress_cb=None):
    """
    Single-skeleton extraction with post-hoc path-level pen assignment.

    Strategy:
    1. ONE skeleton from full binary → trace ALL paths → ZERO lost coverage
    2. Distance transform measures median stroke width per path
    3. K-means on path widths → assign each path to a pen

    This avoids the binary-masking approach that loses contour lines
    wherever their local thickness dips below the threshold.

    progress_cb(stage, percent): optional callback for SSE progress reporting.
    """
    # ── Step 1: Single skeleton extraction ──
    if progress_cb:
        progress_cb('Squelettisation', 18)

    skeleton = extract_skeleton(binary)

    if progress_cb:
        progress_cb('Traçage', 22)

    paths = trace_paths(skeleton, params)

    if progress_cb:
        progress_cb('Fusion', 30)

    # Conservative single-pass stitch first (for width measurement)
    conservative_params = copy.copy(params)
    conservative_params.continuity = 0  # minimal stitch
    paths = stitch_paths(paths, conservative_params)

    if not paths:
        return {i: [] for i in range(params.pen_count)}

    if params.pen_count <= 1:
        # Single pen: apply full continuity stitch directly
        if progress_cb:
            progress_cb('Fusion continuité', 35)
        paths = stitch_paths(paths, params)
        return {0: paths}

    # ── Step 2: Measure stroke width per path via distance transform ──
    if progress_cb:
        progress_cb('Mesure épaisseurs', 35)

    dist = cv2.distanceTransform(binary, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    h_dt, w_dt = dist.shape

    path_widths = np.zeros(len(paths), dtype=np.float64)

    for idx, path in enumerate(paths):
        # Sample DT at regular intervals along the path
        step = max(1, len(path) // 60)
        samples = []
        for j in range(0, len(path), step):
            y, x = path[j]
            if 0 <= y < h_dt and 0 <= x < w_dt:
                v = dist[y, x]
                if v > 0:
                    samples.append(v)
        # Use 75th percentile — robust to junction/endpoint dips
        path_widths[idx] = np.percentile(samples, 75) if len(samples) >= 3 else (
            np.median(samples) if samples else 0)

    # ── Step 3: Classify by width ONLY (no length bonus) ──
    if progress_cb:
        progress_cb('Classification stylos', 38)

    paths_by_pen = {i: [] for i in range(params.pen_count)}
    valid_mask = path_widths > 0

    if np.sum(valid_mask) < params.pen_count:
        paths_by_pen[0] = paths
        return paths_by_pen

    valid_widths = path_widths[valid_mask]
    breakpoints = _kmeans_1d(valid_widths, params.pen_count)
    if not breakpoints:
        breakpoints = [float(np.median(valid_widths))]

    logger.info(f"Path-level breakpoints: {[f'{b:.1f}' for b in breakpoints]} "
                f"(width p75 only, no length bonus)")

    for i, (path, w) in enumerate(zip(paths, path_widths)):
        pen = 0
        for k, bp in enumerate(breakpoints):
            if w > bp:
                pen = k + 1
        paths_by_pen[min(pen, params.pen_count - 1)].append(path)

    # ── Step 4: Apply full continuity stitch WITHIN each pen group ──
    if progress_cb:
        progress_cb('Fusion par stylo', 42)

    for pen_idx in range(params.pen_count):
        if paths_by_pen[pen_idx]:
            paths_by_pen[pen_idx] = stitch_paths(paths_by_pen[pen_idx], params)

    for pen_idx in range(params.pen_count):
        n = len(paths_by_pen[pen_idx])
        logger.info(f"Pen {pen_idx}: {n} paths")

    return paths_by_pen


# ============================================================================
# Coordinate Conversion  (y,x) → (x,y) for SVG
# ============================================================================

def yx_to_xy(paths_by_pen):
    """Convert all paths from numpy (row,col) to SVG (x,y) in-place."""
    converted = {}
    for pen, paths in paths_by_pen.items():
        converted[pen] = [[(x, y) for y, x in path] for path in paths]
    return converted


# ============================================================================
# Corner Detection — split paths at sharp angles
# ============================================================================

def detect_corners(path, angle_deg: int):
    """Return indices where the path has a sharp angle change."""
    if len(path) < 3:
        return []
    cos_limit = math.cos(math.radians(180 - angle_deg))
    corners = []
    for i in range(1, len(path) - 1):
        ax, ay = path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]
        bx, by = path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1]
        na = math.sqrt(ax * ax + ay * ay)
        nb = math.sqrt(bx * bx + by * by)
        if na < 1e-6 or nb < 1e-6:
            continue
        cos_val = (ax * bx + ay * by) / (na * nb)
        if cos_val < cos_limit:
            corners.append(i)
    return corners


def split_at_corners(path, angle_deg: int):
    """Split a path into sub-paths at detected corners."""
    corners = detect_corners(path, angle_deg)
    if not corners:
        return [path]
    segments = []
    prev = 0
    for c in corners:
        seg = path[prev:c + 1]
        if len(seg) >= 2:
            segments.append(seg)
        prev = c
    tail = path[prev:]
    if len(tail) >= 2:
        segments.append(tail)
    return segments


# ============================================================================
# Bézier Fitting — Catmull-Rom → Cubic Bézier
# ============================================================================

def path_to_svg_d(path, smoothing: float, corner_angle: int) -> str:
    """
    Convert a point list to SVG path data with cubic Bézier curves.

    smoothing = 0 → straight lines (L commands)
    smoothing = 1 → full Catmull-Rom smoothing (C commands)

    Splits at corners first, then fits each segment.
    """
    if len(path) < 2:
        return ""

    segments = split_at_corners(path, corner_angle) if corner_angle > 0 else [path]
    d_parts = []

    for seg_idx, seg in enumerate(segments):
        if len(seg) < 2:
            continue

        # Move to start of this segment
        if seg_idx == 0:
            d_parts.append(f"M{seg[0][0]:.1f},{seg[0][1]:.1f}")
        else:
            d_parts.append(f"L{seg[0][0]:.1f},{seg[0][1]:.1f}")

        if smoothing <= 0.01 or len(seg) < 3:
            # Straight lines
            for i in range(1, len(seg)):
                d_parts.append(f"L{seg[i][0]:.1f},{seg[i][1]:.1f}")
        else:
            # Catmull-Rom → cubic Bézier
            n = len(seg)
            alpha = smoothing  # scale factor for control point offset

            for i in range(n - 1):
                p0 = np.array(seg[max(0, i - 1)], dtype=np.float64)
                p1 = np.array(seg[i], dtype=np.float64)
                p2 = np.array(seg[min(n - 1, i + 1)], dtype=np.float64)
                p3 = np.array(seg[min(n - 1, i + 2)], dtype=np.float64)

                # Catmull-Rom tangent vectors, scaled by smoothing
                c1 = p1 + alpha * (p2 - p0) / 6.0
                c2 = p2 - alpha * (p3 - p1) / 6.0

                d_parts.append(
                    f"C{c1[0]:.1f},{c1[1]:.1f},{c2[0]:.1f},{c2[1]:.1f},{p2[0]:.1f},{p2[1]:.1f}"
                )

    return "".join(d_parts)


# ============================================================================
# Path Optimization — nearest-neighbor with KD-tree for plotter
# ============================================================================

_SVG_COORD_RE = __import__('re').compile(r'[-+]?\d*\.?\d+')


def _extract_endpoints(p):
    """Extract (start, end) as numpy arrays from a path (list or SVG string)."""
    if isinstance(p, str):
        m = _SVG_COORD_RE.findall(p)
        if len(m) >= 4:
            start = np.array([float(m[0]), float(m[1])])
            end = np.array([float(m[-2]), float(m[-1])])
        elif len(m) >= 2:
            start = end = np.array([float(m[0]), float(m[1])])
        else:
            start = end = np.array([0.0, 0.0])
        return start, end
    if p and len(p) >= 1:
        return np.array(p[0], dtype=np.float64), np.array(p[-1], dtype=np.float64)
    return np.array([0.0, 0.0]), np.array([0.0, 0.0])


def optimize_paths(paths):
    """Reorder paths to minimize travel distance using KD-tree. Allows path reversal."""
    n = len(paths)
    if n <= 1:
        return paths

    # Pre-compute all endpoints once
    starts = np.empty((n, 2), dtype=np.float64)
    ends = np.empty((n, 2), dtype=np.float64)
    for i, p in enumerate(paths):
        s, e = _extract_endpoints(p)
        starts[i] = s
        ends[i] = e

    # For small counts, brute-force nearest-neighbor is fine
    # For large counts, use KD-tree rebuilt periodically
    used = np.zeros(n, dtype=bool)
    ordered = []

    # Start with first path
    ordered.append(0)
    used[0] = True
    current_end = ends[0].copy()

    if n <= 500:
        # Simple O(n²) with numpy vectorized distance — fast enough
        for _ in range(n - 1):
            # Distances to all starts and ends of unused paths
            mask = ~used
            idxs = np.where(mask)[0]
            d_starts = np.linalg.norm(starts[idxs] - current_end, axis=1)
            d_ends = np.linalg.norm(ends[idxs] - current_end, axis=1)

            # Find minimum across both orientations
            min_s_idx = np.argmin(d_starts)
            min_e_idx = np.argmin(d_ends)

            if d_starts[min_s_idx] <= d_ends[min_e_idx]:
                chosen = idxs[min_s_idx]
                reverse = False
            else:
                chosen = idxs[min_e_idx]
                reverse = True

            if reverse:
                starts[chosen], ends[chosen] = ends[chosen].copy(), starts[chosen].copy()
                if isinstance(paths[chosen], list):
                    paths[chosen] = list(reversed(paths[chosen]))

            used[chosen] = True
            ordered.append(chosen)
            current_end = ends[chosen].copy()
    else:
        # KD-tree approach for large path counts
        # Build combined endpoint array: [starts; ends] with index mapping
        all_pts = np.vstack([starts, ends])  # shape (2n, 2)
        tree = KDTree(all_pts)

        for _ in range(n - 1):
            # Query nearest neighbors, skip used ones
            k = min(20, n)  # check top-k candidates
            dists, idxs_kd = tree.query(current_end, k=k)

            chosen = -1
            reverse = False
            for d, ki in zip(dists, idxs_kd):
                # ki < n → start of path ki; ki >= n → end of path (ki - n)
                path_idx = ki if ki < n else ki - n
                if used[path_idx]:
                    continue
                reverse = (ki >= n)
                chosen = path_idx
                break

            if chosen == -1:
                # Fallback: scan remaining
                remaining = np.where(~used)[0]
                d_s = np.linalg.norm(starts[remaining] - current_end, axis=1)
                d_e = np.linalg.norm(ends[remaining] - current_end, axis=1)
                min_si = np.argmin(d_s)
                min_ei = np.argmin(d_e)
                if d_s[min_si] <= d_e[min_ei]:
                    chosen = remaining[min_si]
                    reverse = False
                else:
                    chosen = remaining[min_ei]
                    reverse = True

            if reverse:
                starts[chosen], ends[chosen] = ends[chosen].copy(), starts[chosen].copy()
                if isinstance(paths[chosen], list):
                    paths[chosen] = list(reversed(paths[chosen]))

            used[chosen] = True
            ordered.append(chosen)
            current_end = ends[chosen].copy()

    return [paths[i] for i in ordered]


# ============================================================================
# Metrics
# ============================================================================

def compute_metrics(paths_by_pen, params: Params):
    """Compute draw/travel distances and pen lifts."""
    total_draw = 0.0
    total_travel = 0.0
    total_lifts = 0
    total_paths = 0

    for pen_idx in range(params.pen_count):
        paths = paths_by_pen.get(pen_idx, [])
        if not paths:
            continue
        total_paths += len(paths)

        prev_end = None
        for p in paths:
            s, e = _extract_endpoints(p)

            # Draw distance: rough estimate from endpoints for SVG strings,
            # accurate for point lists
            if isinstance(p, list) and len(p) >= 2:
                for j in range(1, len(p)):
                    total_draw += math.dist(p[j - 1], p[j])
            else:
                # For SVG strings, use chord length as estimate
                total_draw += np.linalg.norm(e - s)

            # Travel distance from previous path end
            if prev_end is not None:
                total_travel += np.linalg.norm(s - prev_end)
                total_lifts += 1
            prev_end = e

    # Pen-change lifts
    active_pens = [p for p in range(params.pen_count) if paths_by_pen.get(p)]
    if len(active_pens) > 1:
        total_lifts += len(active_pens) - 1

    return total_draw, total_travel, total_lifts, total_paths


# ============================================================================
# SVG Generation
# ============================================================================

def _build_path_d(item) -> str:
    """Build SVG d attribute from either a string or a point list."""
    if isinstance(item, str):
        return item
    if not item or len(item) < 2:
        return ""
    d = f"M{item[0][0]:.1f},{item[0][1]:.1f}"
    for p in item[1:]:
        d += f"L{p[0]:.1f},{p[1]:.1f}"
    return d


def generate_partial_svg(paths_by_pen, params: Params, image_size, preview=True):
    """Quick SVG preview (polylines or mixed). Used for progressive updates."""
    w, h = image_size
    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">']

    for pen_idx in range(params.pen_count):
        paths = paths_by_pen.get(pen_idx, [])
        if not paths:
            continue
        color = PEN_COLORS[pen_idx % len(PEN_COLORS)] if preview else '#000'
        sw = params.pen_widths[pen_idx] if pen_idx < len(params.pen_widths) else 1
        lines.append(
            f'<g id="stylo-{pen_idx}" stroke="{color}" stroke-width="{sw}" '
            f'fill="none" stroke-linecap="round" stroke-linejoin="round">'
        )
        for item in paths:
            d = _build_path_d(item)
            if d:
                lines.append(f'<path d="{d}"/>')
        lines.append('</g>')

    lines.append('</svg>')
    return '\n'.join(lines)


def generate_final_svg(paths_by_pen, params: Params, image_size, stats: dict, preview=True):
    """Full SVG with metadata comments and style defs."""
    w, h = image_size
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}mm" height="{h}mm">',
        '<!-- Generated by VECTORISEUR Pro -->',
        f'<!-- Draw distance: {stats.get("draw_distance", 0):.1f}px -->',
        f'<!-- Travel distance: {stats.get("travel_distance", 0):.1f}px -->',
        f'<!-- Pen lifts: {stats.get("pen_ups", 0)} -->',
        '<defs>',
    ]

    for pen_idx in range(params.pen_count):
        color = PEN_COLORS[pen_idx % len(PEN_COLORS)]
        sw = params.pen_widths[pen_idx] if pen_idx < len(params.pen_widths) else 1
        c = color if preview else 'black'
        lines.append(f'  <style>.stylo-{pen_idx}{{stroke:{c};stroke-width:{sw};fill:none;'
                     f'stroke-linecap:round;stroke-linejoin:round}}</style>')

    lines.append('</defs>')

    for pen_idx in range(params.pen_count):
        paths = paths_by_pen.get(pen_idx, [])
        if not paths:
            continue
        lines.append(f'<g id="stylo-{pen_idx}" class="stylo-{pen_idx}">')
        for item in paths:
            d = _build_path_d(item)
            if d:
                lines.append(f'  <path d="{d}"/>')
        lines.append('</g>')

    lines.append('</svg>')
    return '\n'.join(lines)


# ============================================================================
# Flask Routes
# ============================================================================

@app.route('/')
def serve_index():
    return send_from_directory(Path(__file__).parent, 'index.html', mimetype='text/html')


@app.route('/status', methods=['GET'])
def status():
    has_cuda = False
    try:
        has_cuda = cv2.cuda.getCudaEnabledDeviceCount() > 0
    except Exception:
        pass
    return jsonify({
        'status': 'online', 'version': '2.0.0',
        'gpu': 'CUDA' if has_cuda else 'None',
        'maxImageSize': MAX_IMAGE_SIZE,
        'algorithms': ['skeletonize', 'canny', 'combined']
    })


@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy'})


def _extract_hash(params):
    """Hash of params that affect extraction (preprocess + skeleton + paths)."""
    keys = (params.algorithm, params.threshold, params.blur, params.invert,
            params.adaptive, params.cleanup, params.min_length, params.max_stitch_gap,
            params.continuity, params.tolerance, params.pen_count)
    return hashlib.md5(str(keys).encode()).hexdigest()


def _smooth_and_finalize(paths_by_pen_raw, params, image_size, img_hash=''):
    """Apply smoothing, optimization, metrics, and SVG generation.
    Yields SSE events. paths_by_pen_raw must be point lists in (x,y)."""
    import copy
    paths_by_pen = copy.deepcopy(paths_by_pen_raw)

    # Bézier fitting
    if params.smoothing > 0.01:
        total = sum(len(v) for v in paths_by_pen.values())
        done = 0
        for pen_idx in list(paths_by_pen.keys()):
            pen_paths = paths_by_pen[pen_idx]
            fitted = []
            batch = max(1, len(pen_paths) // 5)
            for i, p in enumerate(pen_paths):
                if isinstance(p, list) and len(p) >= 3:
                    svg_d = path_to_svg_d(p, params.smoothing, params.corner_angle)
                    fitted.append(svg_d if svg_d else p)
                else:
                    fitted.append(p)
                done += 1
                if (i + 1) % batch == 0 or i == len(pen_paths) - 1:
                    pct = 60 + int((done / max(total, 1)) * 25)
                    yield _sse({'type': 'progress',
                                'stage': f'Lissage Bézier ({done}/{total})', 'percent': pct})
                    paths_by_pen[pen_idx] = fitted + pen_paths[i + 1:]
                    yield _sse({'type': 'partial_svg',
                                'svg': generate_partial_svg(paths_by_pen, params, image_size)})
            paths_by_pen[pen_idx] = fitted

    # Optimize
    yield _sse({'type': 'progress', 'stage': 'Optimisation traceur', 'percent': 88})
    for pen_idx in paths_by_pen:
        paths_by_pen[pen_idx] = optimize_paths(paths_by_pen[pen_idx])

    # Metrics
    yield _sse({'type': 'progress', 'stage': 'Statistiques', 'percent': 93})
    draw_dist, travel_dist, pen_lifts, path_count = compute_metrics(paths_by_pen, params)
    est_time = (draw_dist / 50.0 + travel_dist / 100.0) * 1000

    stats = {
        'paths': path_count,
        'draw_distance': float(draw_dist),
        'travel_distance': float(travel_dist),
        'pen_ups': pen_lifts,
        'estimated_time': float(est_time),
    }

    yield _sse({'type': 'progress', 'stage': 'SVG final', 'percent': 98})
    svg = generate_final_svg(paths_by_pen, params, image_size, stats, preview=True)
    yield _sse({'type': 'progress', 'stage': 'Terminé', 'percent': 100})
    yield _sse({'type': 'result', 'svg': svg, 'stats': stats, 'imageHash': img_hash})


@app.route('/process', methods=['POST'])
def process():
    """Process image → SVG via Server-Sent Events. Supports partial recalculation."""
    global _cache

    # --- Extract from request before generator ---
    has_image = 'image' in request.files
    from_stage = request.form.get('fromStage', 'full')
    params_dict = json.loads(request.form.get('params', '{}'))
    params = Params(**params_dict)
    image_hash = request.form.get('imageHash', '')

    filepath = None
    if has_image:
        file = request.files['image']
        if not file.filename or not allowed_file(file.filename):
            def err_gen():
                yield _sse({'type': 'error', 'message': 'Invalid file type'})
            return Response(err_gen(), mimetype='text/event-stream')
        filename = secure_filename(file.filename)
        filepath = UPLOAD_FOLDER / f"{int(time.time())}_{filename}"
        file.save(str(filepath))
        # Compute hash from file content
        with open(str(filepath), 'rb') as f:
            image_hash = hashlib.md5(f.read()).hexdigest()

    def generate():
        try:
            start_time = time.time()

            # Check if we can skip extraction (only smoothing changed)
            extract_h = _extract_hash(params)
            cached = _cache.get(image_hash)

            if (from_stage == 'smooth' and cached
                    and cached.get('extract_hash') == extract_h):
                # === FAST PATH: only redo smoothing + optimization ===
                logger.info("Cache hit: skipping extraction, re-smoothing only")
                yield _sse({'type': 'progress', 'stage': 'Re-lissage (cache)', 'percent': 55})
                yield from _smooth_and_finalize(
                    cached['paths_by_pen_raw'], params, cached['image_size'], image_hash)
                return

            # === FULL PIPELINE ===
            if not filepath:
                yield _sse({'type': 'error', 'message': 'No image file'})
                return

            # 1. Load
            yield _sse({'type': 'progress', 'stage': 'Chargement', 'percent': 2})
            img = load_image(str(filepath))
            original_gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img
            image_size = (img.shape[1], img.shape[0])

            # 2. Preprocess
            yield _sse({'type': 'progress', 'stage': 'Prétraitement', 'percent': 5})
            binary = preprocess_image(img, params)

            # 3. Multi-pass extraction (separate skeleton per pen thickness)
            yield _sse({'type': 'progress', 'stage': 'Extraction multi-passes', 'percent': 15})
            # Progress messages collected during extraction (generator-safe)
            _progress_msgs = []
            def _collect_progress(stage, pct):
                _progress_msgs.append((stage, pct))
            paths_by_pen = extract_multi_pass(binary, params, progress_cb=_collect_progress)
            # Flush collected progress messages
            for stage, pct in _progress_msgs:
                yield _sse({'type': 'progress', 'stage': stage, 'percent': pct})

            # 4. RDP simplification
            yield _sse({'type': 'progress', 'stage': 'Simplification', 'percent': 45})
            for pen_idx in paths_by_pen:
                paths_by_pen[pen_idx] = [simplify_path(p, params.tolerance)
                                         for p in paths_by_pen[pen_idx]]

            # 5. Convert (y,x) → (x,y)
            paths_by_pen = yx_to_xy(paths_by_pen)

            # 6. Send raw preview
            yield _sse({'type': 'progress', 'stage': 'Aperçu brut', 'percent': 55})
            yield _sse({'type': 'partial_svg',
                        'svg': generate_partial_svg(paths_by_pen, params, image_size)})

            # Cache intermediate state for fast re-smoothing
            _cache[image_hash] = {
                'paths_by_pen_raw': paths_by_pen,
                'image_size': image_size,
                'extract_hash': extract_h,
            }
            # Keep cache small (max 3 images)
            if len(_cache) > 3:
                oldest = next(iter(_cache))
                del _cache[oldest]

            # 7. Smoothing + optimization + SVG
            yield from _smooth_and_finalize(paths_by_pen, params, image_size, image_hash)

        except Exception as e:
            logger.exception("Error in /process")
            yield _sse({'type': 'error', 'message': str(e)})
        finally:
            if filepath:
                try:
                    filepath.unlink()
                except Exception:
                    pass

    return Response(generate(), mimetype='text/event-stream')


@app.route('/export', methods=['POST'])
def export():
    try:
        data = request.get_json()
        svg = data.get('svg', '')
        if not svg:
            return jsonify({'error': 'No SVG content'}), 400
        return send_file(
            io.BytesIO(svg.encode('utf-8')),
            mimetype='image/svg+xml',
            as_attachment=True,
            download_name=f"vectorized_{int(time.time())}.svg"
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500


def _sse(data: dict) -> str:
    return f"data: {json.dumps(data)}\n\n"


# ============================================================================
# Main
# ============================================================================

if __name__ == '__main__':
    has_cuda = False
    try:
        has_cuda = cv2.cuda.getCudaEnabledDeviceCount() > 0
    except Exception:
        pass

    print("\n" + "=" * 60)
    print("  VECTORISEUR PRO v2 — Backend Python")
    print("  Bitmap → SVG pour traceurs à plumes")
    print("=" * 60)
    print(f"  URL: http://localhost:5555")
    print(f"  GPU: {'CUDA' if has_cuda else 'CPU'}")
    print("=" * 60 + "\n")

    app.run(host='0.0.0.0', port=5555, debug=False, threaded=True, use_reloader=False)
