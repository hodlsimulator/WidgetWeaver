#!/usr/bin/env python3
"""
make_seconds_sweep_font.py

Adds a "motion trail" to the WidgetWeaver seconds-hand font by duplicating the
hand contours inside each sec00...sec59 glyph at small angular offsets.

The font includes two small "keeper" squares (bottom-left and top-right) that
pin the glyph bounds. Those contours are left untouched so they remain clipped
outside the circular mask and do not swing into view.
"""

import argparse
import math
import os
import tempfile
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen


def _split_contours(ttfont: TTFont, glyph_name: str) -> list[list[tuple[float, float]]]:
    glyf_table = ttfont["glyf"]
    glyph = glyf_table[glyph_name]

    coords, end_pts, _flags = glyph.getCoordinates(glyf_table)
    coords = [(float(x), float(y)) for x, y in coords]
    end_pts = list(end_pts)

    contours: list[list[tuple[float, float]]] = []
    start = 0
    for end in end_pts:
        contours.append(coords[start : end + 1])
        start = end + 1
    return contours


def _bbox(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def _is_keeper(points: list[tuple[float, float]]) -> bool:
    xmin, ymin, xmax, ymax = _bbox(points)

    # Bottom-left keeper square (roughly 0..32)
    if xmax <= 40 and ymax <= 40:
        return True

    # Top-right keeper square (roughly 968..1000)
    if xmin >= 960 and ymin >= 960:
        return True

    return False


def _transform_points(
    points: list[tuple[float, float]],
    angle_deg: float,
    scale: float,
    cx: float = 500.0,
    cy: float = 500.0,
) -> list[tuple[float, float]]:
    rad = math.radians(angle_deg)
    c = math.cos(rad)
    s = math.sin(rad)

    out: list[tuple[float, float]] = []
    for x, y in points:
        dx = (x - cx) * scale
        dy = (y - cy) * scale

        tx = dx * c - dy * s
        ty = dx * s + dy * c

        out.append((tx + cx, ty + cy))
    return out


def _add_contour(pen: TTGlyphPen, points: list[tuple[float, float]]) -> None:
    pen.moveTo((round(points[0][0]), round(points[0][1])))
    for x, y in points[1:]:
        pen.lineTo((round(x), round(y)))
    pen.closePath()


def _add_trail_to_sec_glyph(
    ttfont: TTFont,
    glyph_name: str,
    trail_count: int,
    trail_step_deg: float,
    scale_step: float,
) -> None:
    contours = _split_contours(ttfont, glyph_name)
    keepers = [c for c in contours if _is_keeper(c)]
    hand = [c for c in contours if not _is_keeper(c)]

    # New glyph: keepers + trail + main hand
    pen = TTGlyphPen(ttfont.getGlyphSet())

    for c in keepers:
        _add_contour(pen, c)

    # Seconds hand moves clockwise. Trail is placed counter-clockwise (positive angles in font coords).
    for i in range(trail_count, 0, -1):
        angle = float(i) * float(trail_step_deg)
        scale = max(0.0, 1.0 - float(i) * float(scale_step))

        for c in hand:
            _add_contour(pen, _transform_points(c, angle_deg=angle, scale=scale))

    for c in hand:
        _add_contour(pen, c)

    new_glyph = pen.glyph()
    new_glyph.recalcBounds(ttfont["glyf"])
    ttfont["glyf"][glyph_name] = new_glyph


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_ttf", help="Path to WWClockSecondHand-Regular.ttf")
    parser.add_argument("output_ttf", help="Output .ttf path (can match input for in-place replace)")
    parser.add_argument("--trail-count", type=int, default=5)
    parser.add_argument("--trail-step-deg", type=float, default=1.0)
    parser.add_argument("--scale-step", type=float, default=0.03)
    args = parser.parse_args()

    font = TTFont(args.input_ttf)
    glyph_order = font.getGlyphOrder()

    sec_glyphs = [g for g in glyph_order if len(g) == 5 and g.startswith("sec") and g[3:].isdigit()]
    for gname in sec_glyphs:
        _add_trail_to_sec_glyph(
            font,
            gname,
            trail_count=args.trail_count,
            trail_step_deg=args.trail_step_deg,
            scale_step=args.scale_step,
        )

    # Safe write (supports input == output).
    out_dir = os.path.dirname(os.path.abspath(args.output_ttf)) or "."
    os.makedirs(out_dir, exist_ok=True)

    with tempfile.NamedTemporaryFile(prefix="sweepfont_", suffix=".ttf", delete=False, dir=out_dir) as tmp:
        tmp_path = tmp.name

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
