#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_minute_hand_font.py

Creates WWClockMinuteHand-Regular.ttf by cloning the existing WWClockSecondHand-Regular.ttf
and replacing:
- sec00 ... sec59 glyph outlines (to minute-hand geometry at 0..59 minutes)
- GSUB ligatures (to map the system timer string to the correct minute glyph)

The output file is written to:
WidgetWeaverWidget/Clock/WWClockMinuteHand-Regular.ttf

Dependencies:
  python3 -m pip install --user fonttools

Run from the repo root:
  python3 Scripts/generate_minute_hand_font.py
"""

from __future__ import annotations

import math
import os
from typing import Dict, List, Tuple

from fontTools.otlLib import builder as otl
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont


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


DIGIT_TO_GLYPH = {
    "0": "zero",
    "1": "one",
    "2": "two",
    "3": "three",
    "4": "four",
    "5": "five",
    "6": "six",
    "7": "seven",
    "8": "eight",
    "9": "nine",
}


def glyph_seq_for_string(s: str) -> Tuple[str, ...]:
    seq: List[str] = []
    for ch in s:
        if ch.isdigit():
            seq.append(DIGIT_TO_GLYPH[ch])
        elif ch == ":":
            seq.append("colon")
        else:
            raise ValueError(f"Unsupported char {ch!r} in {s!r}")
    return tuple(seq)


def minute_target_glyph_name(minute: int) -> str:
    return f"sec{minute:02d}"


def build_mapping_two_hours() -> Dict[Tuple[str, ...], str]:
    mapping: Dict[Tuple[str, ...], str] = {}

    for m in range(0, 60):
        for s in range(0, 60):
            if m < 10:
                timer_str = f"{m}:{s:02d}"
            else:
                timer_str = f"{m:02d}:{s:02d}"
            mapping[glyph_seq_for_string(timer_str)] = minute_target_glyph_name(m)

    for m in range(0, 60):
        for s in range(0, 60):
            timer_str = f"1:{m:02d}:{s:02d}"
            mapping[glyph_seq_for_string(timer_str)] = minute_target_glyph_name(m)

    return mapping


def make_square(pen: TTGlyphPen, x0: int, y0: int, x1: int, y1: int) -> None:
    pen.moveTo((x0, y0))
    pen.lineTo((x1, y0))
    pen.lineTo((x1, y1))
    pen.lineTo((x0, y1))
    pen.closePath()


def make_minute_hand_glyph(
    glyph_set,
    minute: int,
    *,
    dial_size: int = 1000,
    width: float = 18.0,
    length: float = 420.0,
):
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

    make_square(pen, 0, 0, 32, 32)
    make_square(pen, 968, 968, 1000, 1000)

    pen.moveTo(rotated[0])
    for p in rotated[1:]:
        pen.lineTo(p)
    pen.closePath()

    return pen.glyph()


def update_name_table(font: TTFont) -> None:
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

    font = TTFont(template_path)

    mapping = build_mapping_two_hours()

    first_glyphs = sorted({seq[0] for seq in mapping.keys()})
    subtables = []
    for fg in first_glyphs:
        submap = {seq: out for (seq, out) in mapping.items() if seq[0] == fg}
        subtables.append(otl.buildLigatureSubstSubtable(submap))

    gsub = font["GSUB"].table
    lookup = gsub.LookupList.Lookup[0]
    lookup.SubTable = subtables
    lookup.SubTableCount = len(subtables)

    glyph_set = font.getGlyphSet()
    glyf = font["glyf"]

    for m in range(60):
        glyf[f"sec{m:02d}"] = make_minute_hand_glyph(glyph_set, m)

    update_name_table(font)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    font.save(out_path)
    print(out_path)


if __name__ == "__main__":
    main()
