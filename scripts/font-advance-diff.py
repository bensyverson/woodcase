#!/usr/bin/env python3
"""Compares two builds of one face: their version strings and the advance of every
codepoint both map, at each named weight a variable face offers (or the one weight a
static cut draws).

Two files can differ in bytes and still lay text out identically — google/fonts' main
branch and fonts.gstatic.com's pinned version of the same family, say. Differing
advances move text layout; differing outlines only move pixels.

Usage: scripts/font-advance-diff.py <a.ttf> <b.ttf> [--weights 400,500,600]
Needs fontTools (`pip3 install fonttools`). See project/2026-09-28-pen-font-faces.md.
"""

import argparse

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

parser = argparse.ArgumentParser()
parser.add_argument("a")
parser.add_argument("b")
parser.add_argument("--weights", default="400,500,600,700")
args = parser.parse_args()


def advances(path, weight):
    font = TTFont(path)
    if "fvar" in font:
        axes = {a.axisTag: a for a in font["fvar"].axes}
        location = {tag: axis.defaultValue for tag, axis in axes.items()}
        if "wght" in axes:
            location["wght"] = min(max(weight, axes["wght"].minValue), axes["wght"].maxValue)
        font = instantiateVariableFont(font, location)
    metrics = font["hmtx"]
    return {cp: metrics[glyph][0] for cp, glyph in font.getBestCmap().items()}


def describe(path):
    font = TTFont(path)
    kind = "variable " + ",".join(a.axisTag for a in font["fvar"].axes) if "fvar" in font else "static"
    return f"{font['name'].getDebugName(5)}; {kind}; {len(font.getGlyphOrder())} glyphs"


print("a:", args.a, "—", describe(args.a))
print("b:", args.b, "—", describe(args.b))
static = "fvar" not in TTFont(args.a)
for weight in [400] if static else [int(w) for w in args.weights.split(",")]:
    a, b = advances(args.a, weight), advances(args.b, weight)
    shared = sorted(set(a) & set(b))
    differ = [cp for cp in shared if a[cp] != b[cp]]
    ascii_differ = [cp for cp in differ if 0x20 <= cp < 0x7F]
    sample = ", ".join(f"{chr(cp)!r} {a[cp]}/{b[cp]}" for cp in ascii_differ[:6])
    print(f"wght {weight}: {len(shared)} shared codepoints, {len(differ)} advances differ "
          f"({len(ascii_differ)} ASCII{': ' + sample if sample else ''}); "
          f"only in a {len(set(a) - set(b))}, only in b {len(set(b) - set(a))}")
