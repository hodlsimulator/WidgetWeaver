#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_second_hand_font.py

Extends WWClockSecondHand-Regular.ttf GSUB ligature mapping so Text(timerInterval:)
can drive a sweeping second hand for up to 59:59 (no hour field).

This script:
- loads WidgetWeaverWidget/Clock/WWClockSecondHand-Regular.ttf
- replaces the existing seconds ligature lookup with:
    * mm:ss mappings for 00:00 ... 59:59
    * m:ss mappings for 0:00  ... 9:59
  Each mapping outputs sec00..sec59 based on the seconds value.
- preserves existing outlines (sec00..sec59 already include corner markers)
- saves in place to WidgetWeaverWidget/Clock/WWClockSecondHand-Regular.ttf

Dependencies:
  python3 -m pip install --user fonttools

Run from repo root:
  python3 -u Scripts/generate_second_hand_font.py
"""

from __future__ import annotations

import os
import sys
import threading
import time
from typing import Dict, List, Optional, Tuple

from fontTools.otlLib import builder as otl
from fontTools.ttLib import TTFont


REPO_REL_TTF = os.path.join(
    "WidgetWeaverWidget",
    "Clock",
    "WWClockSecondHand-Regular.ttf",
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


def main() -> None:
    repo_root = os.getcwd()
    font_path = os.path.join(repo_root, REPO_REL_TTF)

    if not os.path.exists(font_path):
        raise FileNotFoundError(f"Font missing: {font_path}")

    log("Loading second-hand font…")
    font = TTFont(font_path)

    log("Reading cmap for digit/colon glyph names…")
    char_to_glyph = get_char_to_glyph(font)

    log("Building ligature mappings for mm:ss and m:ss…")

    mapping_mmss: Dict[Tuple[str, ...], str] = {}
    mapping_mss: Dict[Tuple[str, ...], str] = {}

    for m in range(0, 60):
        for s in range(0, 60):
            out_glyph = f"sec{s:02d}"

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

    log("Saving font (heartbeat will print if slow)…")
    stop = start_heartbeat("Saving font", interval_seconds=5.0)
    try:
        font.save(font_path)
    finally:
        stop.set()

    log(f"Wrote: {font_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
