#!/usr/bin/env python3
"""
add_seconds_arc_trail.py

Adds a "motion trail" arc behind the seconds-hand tip by appending one or more
thin, tapered arc-sector contours to each sec00...sec59 glyph.

The original glyph outlines are preserved by replaying the glyph draw commands,
so curves remain curves (no flattening into line segments).

Typical usage (in-place overwrite after making a backup):
  python3 WidgetWeaver/Tools/add_seconds_arc_trail.py \
    WidgetWeaverWidget/Clock/WWClockSecondHand-Regular.ttf \
    WidgetWeaverWidget/Clock/WWClockSecondHand-Regular.ttf
"""

import argparse
import math
import os
import tempfile
from typing import List, Optional, Tuple

from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen


Point = Tuple[float, float]


def _normalise_rad(a: float) -> float:
    return (a + math.pi) % (2.0 * math.pi) - math.pi


def _split_contours(ttfont: TTFont, glyph_name: str) -> List[List[Point]]:
    glyf = ttfont["glyf"]
    glyph = glyf[glyph_name]
    coords, end_pts, _flags = glyph.getCoordinates(glyf)
    coords = [(float(x), float(y)) for x, y in coords]

    contours: List[List[Point]] = []
    start = 0
    for end in list(end_pts):
        contours.append(coords[start : end + 1])
        start = end + 1
    return contours


def _bbox(points: List[Point]) -> Tuple[float, float, float, float]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def _is_keeper_contour(points: List[Point]) -> bool:
    xmin, ymin, xmax, ymax = _bbox(points)

    # Bottom-left keeper square (roughly 0..32)
    if xmax <= 40.0 and ymax <= 40.0:
        return True

    # Top-right keeper square (roughly 968..1000)
    if xmin >= 960.0 and ymin >= 960.0:
        return True

    return False


def _tip_angle_radius(
    ttfont: TTFont, glyph_name: str, cx: float, cy: float
) -> Optional[Tuple[float, float]]:
    contours = _split_contours(ttfont, glyph_name)

    pts: List[Point] = []
    for c in contours:
        if _is_keeper_contour(c):
            continue
        pts.extend(c)

    if not pts:
        return None

    max_d2 = -1.0
    tip: Optional[Point] = None
    for x, y in pts:
        dx = x - cx
        dy = y - cy
        d2 = dx * dx + dy * dy
        if d2 > max_d2:
            max_d2 = d2
            tip = (x, y)

    if tip is None:
        return None

    angle = math.atan2(tip[1] - cy, tip[0] - cx)
    radius = math.sqrt(max_d2)
    return angle, radius


def _detect_motion_sign(ttfont: TTFont, cx: float, cy: float) -> int:
    # +1 means angle increases as seconds advance; -1 means angle decreases.
    a0 = _tip_angle_radius(ttfont, "sec00", cx, cy)
    a1 = _tip_angle_radius(ttfont, "sec01", cx, cy)
    if a0 is None or a1 is None:
        return -1

    d = _normalise_rad(a1[0] - a0[0])
    if abs(d) < 1e-6:
        return -1
    return 1 if d > 0 else -1


def _add_arc_sector_contour(
    pen: TTGlyphPen,
    cx: float,
    cy: float,
    angle_tip: float,
    trail_dir: int,
    span_deg: float,
    r_outer: float,
    thickness: float,
    segments: int,
    taper_min_frac: float,
) -> None:
    # Trail spans from tail -> tip.
    span_rad = math.radians(span_deg) * float(trail_dir)
    angle_tail = angle_tip + span_rad

    outer: List[Point] = []
    for j in range(segments + 1):
        u = float(j) / float(segments)
        ang = angle_tail + (angle_tip - angle_tail) * u
        x = cx + r_outer * math.cos(ang)
        y = cy + r_outer * math.sin(ang)
        outer.append((x, y))

    inner: List[Point] = []
    for j in range(segments, -1, -1):
        u = float(j) / float(segments)
        ang = angle_tail + (angle_tip - angle_tail) * u

        # Taper thickness: thin at tail, thick at tip.
        t = thickness * (taper_min_frac + (1.0 - taper_min_frac) * u)
        r_inner = max(0.0, r_outer - t)

        x = cx + r_inner * math.cos(ang)
        y = cy + r_inner * math.sin(ang)
        inner.append((x, y))

    def ip(p: Point) -> Tuple[int, int]:
        return (int(round(p[0])), int(round(p[1])))

    pen.moveTo(ip(outer[0]))
    for p in outer[1:]:
        pen.lineTo(ip(p))
    for p in inner:
        pen.lineTo(ip(p))
    pen.closePath()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_ttf", help="Input WWClockSecondHand-Regular.ttf")
    parser.add_argument("output_ttf", help="Output .ttf (can equal input for in-place overwrite)")

    parser.add_argument("--arc-span-deg", type=float, default=5.5)
    parser.add_argument("--radius-inset", type=float, default=10.0)
    parser.add_argument("--thickness", type=float, default=10.0)
    parser.add_argument("--segments", type=int, default=20)
    parser.add_argument("--taper-min-frac", type=float, default=0.22)

    parser.add_argument("--layers", type=int, default=3)
    parser.add_argument("--span-decay", type=float, default=0.25)
    parser.add_argument("--thickness-decay", type=float, default=0.25)
    parser.add_argument("--inset-step", type=float, default=2.0)

    parser.add_argument("--flip-direction", action="store_true")
    parser.add_argument("--cx", type=float, default=500.0)
    parser.add_argument("--cy", type=float, default=500.0)

    args = parser.parse_args()

    font = TTFont(args.input_ttf)
    glyf = font["glyf"]
    glyph_set = font.getGlyphSet()

    glyph_order = font.getGlyphOrder()
    sec_glyphs = [g for g in glyph_order if len(g) == 5 and g.startswith("sec") and g[3:].isdigit()]

    motion_sign = _detect_motion_sign(font, args.cx, args.cy)
    trail_dir = -motion_sign  # opposite direction of motion
    if args.flip_direction:
        trail_dir = -trail_dir

    for gname in sec_glyphs:
        tip = _tip_angle_radius(font, gname, args.cx, args.cy)
        if tip is None:
            continue
        angle_tip, r_tip = tip

        pen = TTGlyphPen(glyph_set)
        glyph_set[gname].draw(pen)  # preserve original curves exactly

        for layer in range(max(1, int(args.layers))):
            layer_span = float(args.arc_span_deg) * max(0.0, 1.0 - float(args.span_decay) * float(layer))
            layer_thickness = float(args.thickness) * max(0.0, 1.0 - float(args.thickness_decay) * float(layer))
            layer_inset = float(args.radius_inset) + float(args.inset_step) * float(layer)

            if layer_span <= 0.1 or layer_thickness <= 0.1:
                continue

            r_outer = max(0.0, r_tip - layer_inset)

            _add_arc_sector_contour(
                pen=pen,
                cx=float(args.cx),
                cy=float(args.cy),
                angle_tip=float(angle_tip),
                trail_dir=int(trail_dir),
                span_deg=float(layer_span),
                r_outer=float(r_outer),
                thickness=float(layer_thickness),
                segments=int(args.segments),
                taper_min_frac=float(args.taper_min_frac),
            )

        new_glyph = pen.glyph()
        new_glyph.recalcBounds(glyf)
        glyf[gname] = new_glyph

    out_dir = os.path.dirname(os.path.abspath(args.output_ttf)) or "."
    os.makedirs(out_dir, exist_ok=True)

    fd, tmp_path = tempfile.mkstemp(prefix="arctrail_", suffix=".ttf", dir=out_dir)
    os.close(fd)

    try:
        font.save(tmp_path)
        os.replace(tmp_path, args.output_ttf)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
