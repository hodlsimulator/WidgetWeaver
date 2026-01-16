#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_minute_hand_font.py

Per-second minute-hand ticking font.

Clones WWClockSecondHand-Regular.ttf into WWClockMinuteHand-Regular.ttf and replaces:
- GSUB ligature lookup so Text(timerInterval:) selects a minute-hand glyph based on mm:ss (and m:ss)
- adds mh0000..mh3599 glyphs (one per second-of-hour) as rotated needle silhouettes
- updates the name table

The GSUB mapping intentionally ignores the hour prefix. In strings like "1:05:07", the
sequence "05:07" still exists and is sufficient to select the correct per-second
minute-hand position. Hour digits/colon glyphs in the template are empty/zero-width.

Output:
  WidgetWeaverWidget/Clock/WWClockMinuteHand-Regular.ttf

Dependencies:
  python3 -m pip install --user fonttools

Run from repo root:
  python3 -u Scripts/generate_minute_hand_font.py

Debug:
  - While saving, a heartbeat prints periodically.
  - Sending SIGUSR1 prints a Python stack trace:
      pgrep -f generate_minute_hand_font.py
      kill -USR1 <pid>
"""

from __future__ import annotations

import faulthandler
import math
import os
import signal
import sys
import threading
import time
from typing import Dict, List, Optional, Tuple

from fontTools.otlLib import builder as otl
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont


# 1 = per-second positions (3600 glyphs/hour). 5 = every 5s (720 glyphs/hour), etc.
TICK_SECONDS = 1

SECONDS_PER_HOUR = 3600
GLYPH_PREFIX = "mh"

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
      - rotation clockwise on screen -> negative rotation here
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

            for first, lst in ligs.items():
                for lig in lst:
                    out = getattr(lig, "LigGlyph", "")
                    if isinstance(out, str) and out.startswith("sec"):
                        return idx

    return None


def update_name_table(font: TTFont) -> None:
    if "name" not in font:
        return

    name_table = font["name"]

    def set_name(name_id: int, value: str) -> None:
        remove = []
        for rec in name_table.names:
            if rec.nameID == name_id and rec.platformID == 3 and rec.langID == 0x409:
                remove.append(rec)
        for rec in remove:
            name_table.names.remove(rec)
        name_table.setName(value, name_id, 3, 1, 0x409)

    set_name(1, "WWClockMinuteHand")
    set_name(2, "Regular")
    set_name(3, "WWClockMinuteHand-Regular")
    set_name(4, "WWClockMinuteHand Regular")
    set_name(5, "Version 1.0")
    set_name(6, "WWClockMinuteHand-Regular")


def main() -> None:
    if SECONDS_PER_HOUR % TICK_SECONDS != 0:
        raise ValueError("TICK_SECONDS must divide 3600 evenly")

    faulthandler.enable()
    try:
        faulthandler.register(signal.SIGUSR1)
    except Exception:
        pass

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

    log("Building ligature mappings for mm:ss and m:ss…")
    mapping_mmss: Dict[Tuple[str, ...], str] = {}
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

    log(f"Mapping entries mm:ss: {len(mapping_mmss)}")
    log(f"Mapping entries  m:ss: {len(mapping_mss)}")
    log(f"Mapping total entries: {len(mapping_mmss) + len(mapping_mss)}")

    idx = find_seconds_ligature_lookup_index(font)
    if idx is None:
        raise RuntimeError("Could not locate the seconds-hand ligature lookup in GSUB")

    log(f"Replacing GSUB ligature lookup at index {idx}…")
    sub_mmss = otl.buildLigatureSubstSubtable(mapping_mmss)
    sub_mss = otl.buildLigatureSubstSubtable(mapping_mss)

    gsub = font["GSUB"].table
    lookup = gsub.LookupList.Lookup[idx]
    lookup.LookupType = 4
    lookup.SubTable = [sub_mmss, sub_mss]
    lookup.SubTableCount = 2

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

    log("Saving font (heartbeat will print)…")
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
