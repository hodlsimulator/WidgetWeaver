#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_minute_hand_font.py

Per-second minute-hand ticking font.

Clones WWClockSecondHand-Regular.ttf into WWClockMinuteHand-Regular.ttf and replaces:
- GSUB ligature lookup so Text(timerInterval:) selects a minute-hand glyph based on timer text
- adds mh0000..mh3599 glyphs (one per second-of-hour) as rotated needle silhouettes
- adds invisible corner markers (outside the dial circle) so glyph bounds remain 0..1000 like sec**,
  preventing CoreText/SwiftUI centring drift
- updates the name table (Mac + Windows records) so iOS registers the font as WWClockMinuteHand-Regular

Output:
  WidgetWeaverWidget/Clock/WWClockMinuteHand-Regular.ttf

Dependencies:
  python3 -m pip install --user fonttools

Run from repo root:
  python3 -u Scripts/generate_minute_hand_font.py
"""

from __future__ import annotations

import math
import os
import sys
import threading
import time
from typing import Dict, List, Optional, Tuple

from fontTools.otlLib import builder as otl
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont


# Must match WidgetWeaverClockWidgetLiveView.minuteHandTimerWindowSeconds (2 hours).
WINDOW_HOURS = 2

# 1 = per-second positions (3600 glyphs/hour). 5 = every 5s (720 glyphs/hour), etc.
TICK_SECONDS = 1

SECONDS_PER_HOUR = 3600
GLYPH_PREFIX = "mh"

# Matches WWClockSecondHand-Regular.ttf: two small squares in opposite corners.
# These sit outside the dial circle and get clipped away, but they force bounds to 0..1000.
CORNER_MARK_SIZE = 32

REPO_REL_TEMPLATE_TTF = os.path.join(
    "WidgetWeaverWidget",
    "Clock",
    "WWClockSecondHand-Regular.ttf",
)

REPO_REL_OUTPUT_TTF = os.path.join(
    "WidgetWeaverWidget",
    "Clock",
    "WWClockMinuteHand-Regular.ttf",
)


def log(msg: str) -> None:
    print(msg, flush=True)


def start_heartbeat(label: str, interval_seconds: float = 5.0) -> threading.Event:
    stop = threading.Event()

    def run() -> None:
        start = time.perf_counter()
        while not stop.wait(interval_seconds):
            elapsed = time.perf_counter() - start
            log(f"{label}… ({elapsed:.0f}s elapsed)")

    t = threading.Thread(target=run, daemon=True)
    t.start()
    return stop


def get_char_to_glyph(font: TTFont) -> Dict[str, str]:
    cmap = font.getBestCmap()
    if cmap is None:
        raise RuntimeError("Font has no cmap")

    needed = "0123456789:"
    out: Dict[str, str] = {}
    for ch in needed:
        g = cmap.get(ord(ch))
        if not g:
            raise RuntimeError(
                f"Font cmap missing glyph for character {ch!r} (U+{ord(ch):04X})"
            )
        out[ch] = g

    return out


def glyph_seq_for_string(char_to_glyph: Dict[str, str], s: str) -> Tuple[str, ...]:
    seq: List[str] = []
    for ch in s:
        if ch not in char_to_glyph:
            raise ValueError(f"Unsupported char {ch!r} in {s!r}")
        seq.append(char_to_glyph[ch])
    return tuple(seq)


def glyph_name_for_bucket(bucket: int) -> str:
    return f"{GLYPH_PREFIX}{bucket:04d}"


def add_corner_markers(pen: TTGlyphPen, dial_size: int) -> None:
    m = CORNER_MARK_SIZE
    maxv = dial_size

    # Bottom-left square: (0,0) .. (m,m)
    pen.moveTo((0, 0))
    pen.lineTo((m, 0))
    pen.lineTo((m, m))
    pen.lineTo((0, m))
    pen.closePath()

    # Top-right square: (maxv-m, maxv-m) .. (maxv, maxv)
    pen.moveTo((maxv - m, maxv - m))
    pen.lineTo((maxv, maxv - m))
    pen.lineTo((maxv, maxv))
    pen.lineTo((maxv - m, maxv))
    pen.closePath()


def make_hand_glyph(
    glyph_set,
    angle_degrees: float,
    *,
    dial_size: int = 1000,
    width: float = 18.0,
    length: float = 420.0,
):
    """
    Needle silhouette matching the Swift shape proportions:
      shaftInset = 0.10 * width
      tipHeight  = 0.95 * width

    Coordinates:
      - square dial box: 0..dial_size
      - centre at (dial_size/2, dial_size/2)
      - 0 degrees points up (12 o’clock)
    """
    cx = cy = dial_size / 2.0
    x0 = cx - (width / 2.0)

    shaft_inset = width * 0.10
    tip_height = max(1.0, width * 0.95)

    y_tip = cy + length
    shaft_top_y = y_tip - tip_height

    pts = [
        (x0 + shaft_inset, cy),
        (x0 + shaft_inset, shaft_top_y),
        (x0 + (width / 2.0), y_tip),
        (x0 + width - shaft_inset, shaft_top_y),
        (x0 + width - shaft_inset, cy),
    ]

    theta = -math.radians(angle_degrees)
    c = math.cos(theta)
    s = math.sin(theta)

    rotated: List[Tuple[int, int]] = []
    for x, y in pts:
        dx = x - cx
        dy = y - cy
        xr = cx + dx * c - dy * s
        yr = cy + dx * s + dy * c
        rotated.append((int(round(xr)), int(round(yr))))

    pen = TTGlyphPen(glyph_set)

    # Force stable 0..1000 bounds (outside-circle markers, clipped away in the widget).
    add_corner_markers(pen, dial_size)

    # Actual hand.
    pen.moveTo(rotated[0])
    for p in rotated[1:]:
        pen.lineTo(p)
    pen.closePath()

    return pen.glyph()


def find_seconds_ligature_lookup_index(font: TTFont) -> Optional[int]:
    if "GSUB" not in font:
        return None

    gsub = font["GSUB"].table
    lookups = gsub.LookupList.Lookup

    for idx, lookup in enumerate(lookups):
        if getattr(lookup, "LookupType", None) != 4:
            continue

        for st in lookup.SubTable:
            ligs = getattr(st, "ligatures", None)
            if not ligs:
                continue

            for _, lst in ligs.items():
                for lig in lst:
                    out = getattr(lig, "LigGlyph", "")
                    if isinstance(out, str) and out.startswith("sec"):
                        return idx

    return None


def update_name_table(font: TTFont) -> None:
    if "name" not in font:
        return

    name_table = font["name"]

    def set_name_all_platforms(name_id: int, value: str) -> None:
        kept = []
        for rec in name_table.names:
            if rec.nameID == name_id and rec.platformID in (1, 3):
                continue
            kept.append(rec)
        name_table.names = kept

        # Mac (platform 1) — language 0 = English, encoding 0 = Roman
        name_table.setName(value, name_id, 1, 0, 0)

        # Windows (platform 3) — encoding 1 = Unicode BMP, lang 0x0409 = en-US
        name_table.setName(value, name_id, 3, 1, 0x0409)

    set_name_all_platforms(1, "WWClockMinuteHand")
    set_name_all_platforms(2, "Regular")
    set_name_all_platforms(3, "WWClockMinuteHand-Regular")
    set_name_all_platforms(4, "WWClockMinuteHand Regular")
    set_name_all_platforms(5, "Version 1.0")
    set_name_all_platforms(6, "WWClockMinuteHand-Regular")


def main() -> None:
    if SECONDS_PER_HOUR % TICK_SECONDS != 0:
        raise ValueError("TICK_SECONDS must divide 3600 evenly")

    repo_root = os.getcwd()
    template_path = os.path.join(repo_root, REPO_REL_TEMPLATE_TTF)
    out_path = os.path.join(repo_root, REPO_REL_OUTPUT_TTF)

    if not os.path.exists(template_path):
        raise FileNotFoundError(f"Template font missing: {template_path}")

    log("Loading template font…")
    font = TTFont(template_path)

    log("Reading cmap for digit/colon glyph names…")
    char_to_glyph = get_char_to_glyph(font)

    positions = SECONDS_PER_HOUR // TICK_SECONDS
    log(f"Per-hour positions: {positions} (TICK_SECONDS={TICK_SECONDS})")

    log("Building ligature mappings…")

    # 1) Hour form: h:mm:ss (covers WINDOW_HOURS, to avoid m:ss matching the hour prefix)
    mapping_h_mm_ss: Dict[Tuple[str, ...], str] = {}

    # Map hours 0..(WINDOW_HOURS-1). For WINDOW_HOURS=2 => 0 and 1.
    for h in range(0, WINDOW_HOURS):
        for m in range(0, 60):
            for s in range(0, 60):
                t = m * 60 + s
                bucket = t // TICK_SECONDS
                out_glyph = glyph_name_for_bucket(bucket)

                timer_h = f"{h}:{m:02d}:{s:02d}"
                mapping_h_mm_ss[glyph_seq_for_string(char_to_glyph, timer_h)] = out_glyph

    # 2) Under 1 hour: mm:ss
    mapping_mmss: Dict[Tuple[str, ...], str] = {}
    # 3) Under 10 minutes: m:ss
    mapping_mss: Dict[Tuple[str, ...], str] = {}

    for m in range(0, 60):
        for s in range(0, 60):
            t = m * 60 + s
            bucket = t // TICK_SECONDS
            out_glyph = glyph_name_for_bucket(bucket)

            timer_mmss = f"{m:02d}:{s:02d}"
            mapping_mmss[glyph_seq_for_string(char_to_glyph, timer_mmss)] = out_glyph

            if m < 10:
                timer_mss = f"{m}:{s:02d}"
                mapping_mss[glyph_seq_for_string(char_to_glyph, timer_mss)] = out_glyph

    log(f"Mapping entries h:mm:ss: {len(mapping_h_mm_ss)}")
    log(f"Mapping entries mm:ss:  {len(mapping_mmss)}")
    log(f"Mapping entries  m:ss:  {len(mapping_mss)}")
    log(
        f"Mapping total entries:  {len(mapping_h_mm_ss) + len(mapping_mmss) + len(mapping_mss)}"
    )

    idx = find_seconds_ligature_lookup_index(font)
    if idx is None:
        raise RuntimeError("Could not locate the seconds-hand ligature lookup in GSUB")

    log(f"Replacing GSUB ligature lookup at index {idx}…")
    sub_h = otl.buildLigatureSubstSubtable(mapping_h_mm_ss)
    sub_mmss = otl.buildLigatureSubstSubtable(mapping_mmss)
    sub_mss = otl.buildLigatureSubstSubtable(mapping_mss)

    gsub = font["GSUB"].table
    lookup = gsub.LookupList.Lookup[idx]
    lookup.LookupType = 4
    lookup.SubTable = [sub_h, sub_mmss, sub_mss]
    lookup.SubTableCount = 3

    log("Adding mh**** glyphs + outlines…")
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    glyph_set = font.getGlyphSet()

    base_aw = hmtx["sec00"][0] if "sec00" in hmtx.metrics else 1000

    new_names: List[str] = []
    for bucket in range(positions):
        name = glyph_name_for_bucket(bucket)
        new_names.append(name)

        t = bucket * TICK_SECONDS
        angle_deg = (t / 3600.0) * 360.0  # 360° per hour

        glyf[name] = make_hand_glyph(glyph_set, angle_deg)
        hmtx.metrics[name] = (base_aw, 0)

        if bucket % 300 == 0:
            log(f"  wrote {name} (t={t:4d}s, angle={angle_deg:7.3f}°)…")

    order = font.getGlyphOrder()
    existing = set(order)
    for name in new_names:
        if name not in existing:
            order.append(name)
    font.setGlyphOrder(order)

    if "maxp" in font:
        font["maxp"].numGlyphs = len(order)

    log("Updating name table…")
    update_name_table(font)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    log("Saving font (heartbeat will print if slow)…")
    stop = start_heartbeat("Saving font", interval_seconds=5.0)
    try:
        font.save(out_path)
    finally:
        stop.set()

    log(f"Wrote: {out_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
