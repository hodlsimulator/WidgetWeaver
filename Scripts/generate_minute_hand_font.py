#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_minute_hand_font.py

Clones WWClockSecondHand-Regular.ttf into WWClockMinuteHand-Regular.ttf and replaces:
- sec00..sec59 outlines with a minute-hand needle silhouette at 60 angles
- the GSUB ligature lookup so Text(timerInterval:) selects minute-of-hour (0..59)

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
from typing import Dict, List, Optional, Tuple

from fontTools.otlLib import builder as otl
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont


WINDOW_HOURS = 2  # Must match Swift timer window (2 hours recommended)


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


def get_char_to_glyph(font: TTFont) -> Dict[str, str]:
    cmap = font.getBestCmap()
    if cmap is None:
        raise RuntimeError("Font has no cmap")

    needed = "0123456789:"
    out: Dict[str, str] = {}
    for ch in needed:
        g = cmap.get(ord(ch))
        if not g:
            raise RuntimeError(f"Font cmap missing glyph for character {ch!r} (U+{ord(ch):04X})")
        out[ch] = g

    return out


def glyph_seq_for_string(char_to_glyph: Dict[str, str], s: str) -> Tuple[str, ...]:
    seq: List[str] = []
    for ch in s:
        if ch not in char_to_glyph:
            raise ValueError(f"Unsupported char {ch!r} in {s!r}")
        seq.append(char_to_glyph[ch])
    return tuple(seq)


def minute_target_glyph_name(minute: int) -> str:
    return f"sec{minute:02d}"


def build_mapping_window(char_to_glyph: Dict[str, str], hours: int) -> Dict[Tuple[str, ...], str]:
    """
    Maps timer strings to minute-of-hour.

    For < 1 hour, SwiftUI timer strings are typically:
      m:ss   (m < 10)
      mm:ss  (m >= 10)

    For >= 1 hour:
      h:mm:ss

    Each mapping collapses all seconds in a minute to the same output glyph.
    """
    if hours < 1:
        raise ValueError("hours must be >= 1")

    mapping: Dict[Tuple[str, ...], str] = {}

    # Hour 0: m:ss / mm:ss
    for m in range(0, 60):
        for s in range(0, 60):
            if m < 10:
                timer_str = f"{m}:{s:02d}"
            else:
                timer_str = f"{m:02d}:{s:02d}"

            mapping[glyph_seq_for_string(char_to_glyph, timer_str)] = minute_target_glyph_name(m)

    # Hours 1..(hours-1): h:mm:ss
    for h in range(1, hours):
        for m in range(0, 60):
            for s in range(0, 60):
                timer_str = f"{h}:{m:02d}:{s:02d}"
                mapping[glyph_seq_for_string(char_to_glyph, timer_str)] = minute_target_glyph_name(m)

    return mapping


def make_minute_hand_glyph(
    glyph_set,
    minute: int,
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

    theta = -math.radians(minute * 6.0)
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
    repo_root = os.getcwd()

    template_path = os.path.join(repo_root, REPO_REL_TEMPLATE_TTF)
    out_path = os.path.join(repo_root, REPO_REL_OUTPUT_TTF)

    if not os.path.exists(template_path):
        raise FileNotFoundError(f"Template font missing: {template_path}")

    log("Loading template font…")
    font = TTFont(template_path)

    glyph_order = set(font.getGlyphOrder())
    if "sec00" not in glyph_order or "sec59" not in glyph_order:
        raise RuntimeError("Template font does not contain sec00..sec59 glyphs")

    log("Reading cmap for digit/colon glyph names…")
    char_to_glyph = get_char_to_glyph(font)

    log(f"Building ligature mapping (WINDOW_HOURS={WINDOW_HOURS})…")
    mapping = build_mapping_window(char_to_glyph, WINDOW_HOURS)
    log(f"Mapping entries: {len(mapping)}")

    idx = find_seconds_ligature_lookup_index(font)
    if idx is None:
        raise RuntimeError("Could not locate the seconds-hand ligature lookup in GSUB")

    log(f"Replacing GSUB ligature lookup at index {idx}…")
    subtable = otl.buildLigatureSubstSubtable(mapping)

    gsub = font["GSUB"].table
    lookup = gsub.LookupList.Lookup[idx]
    lookup.LookupType = 4
    lookup.SubTable = [subtable]
    lookup.SubTableCount = 1

    log("Rebuilding sec00..sec59 outlines as minute-hand needles…")
    glyph_set = font.getGlyphSet()
    glyf = font["glyf"]

    for m in range(60):
        glyf[f"sec{m:02d}"] = make_minute_hand_glyph(glyph_set, m)
        if m % 10 == 0:
            log(f"  wrote sec{m:02d}…")

    log("Updating name table…")
    update_name_table(font)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    log("Saving font (no output until complete)…")
    font.save(out_path)

    log(f"Wrote: {out_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
