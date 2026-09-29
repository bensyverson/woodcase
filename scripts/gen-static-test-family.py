#!/usr/bin/env python3
"""Writes "Woodcase Static Sans", a static family with a cut at each of CSS weights 400,
500, 600 and 700, into Tests/WoodcaseTests/Fonts/StaticSans/.

Each cut is Inter (the committed variable file) instanced at that `wght`, at its default
optical size, subset to printable ASCII, renamed, and given the OS/2 weight class it is
drawn at. The suites use it to check that a static family's weights resolve to the cut
CSS would pick (leaf BpaSrF, project/2026-09-28-pen-font-faces.md): no committed static
family has a Medium or a SemiBold, and a system family's cuts vary by machine.

Inter's license (LICENSES/inter-LICENSE, SIL OFL 1.1) reserves no font name, so a renamed
derivative is allowed; its copyright and license records are kept.

Usage: scripts/gen-static-test-family.py [--check]
--check exits 1 when a committed cut differs from what the script writes.
Needs fontTools (`pip3 install fonttools`).
"""

import io
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Tests/WoodcaseTests/Fonts/Inter[opsz,wght].ttf"
OUTPUT = ROOT / "Tests/WoodcaseTests/Fonts/StaticSans"
FAMILY = "Woodcase Static Sans"
CUTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}


def cut(weight, style):
    font = TTFont(SOURCE)
    opsz = next(a.defaultValue for a in font["fvar"].axes if a.axisTag == "opsz")
    font = instantiateVariableFont(font, {"wght": weight, "opsz": opsz})
    options = subset.Options()
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14, 16, 17]
    options.layout_features = ["kern"]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=range(0x20, 0x7F))
    subsetter.subset(font)

    names = font["name"]
    postscript = FAMILY.replace(" ", "") + "-" + style
    # A RIBBI-style name for old readers (family + "Regular"/"Bold"), the typographic
    # family and style for everyone else: Core Text groups the cuts by the latter.
    legacy_family = FAMILY if style in ("Regular", "Bold") else f"{FAMILY} {style}"
    legacy_style = "Bold" if style == "Bold" else "Regular"
    for record in list(names.names):
        if record.nameID in (1, 2, 3, 4, 6, 16, 17):
            names.removeNames(nameID=record.nameID)
    names.setName(legacy_family, 1, 3, 1, 0x409)
    names.setName(legacy_style, 2, 3, 1, 0x409)
    names.setName(f"{postscript};Woodcase test cut", 3, 3, 1, 0x409)
    names.setName(f"{FAMILY} {style}", 4, 3, 1, 0x409)
    names.setName(postscript, 6, 3, 1, 0x409)
    names.setName(FAMILY, 16, 3, 1, 0x409)
    names.setName(style, 17, 3, 1, 0x409)

    os2 = font["OS/2"]
    os2.usWeightClass = weight
    bold = style == "Bold"
    os2.fsSelection = (os2.fsSelection & ~0b1100001) | (0b100000 if bold else 0b1000000)
    font["head"].macStyle = 1 if bold else 0
    # The source's own timestamp, so the same script writes the same bytes.
    font.recalcTimestamp = False
    buffer = io.BytesIO()
    font.save(buffer)
    return buffer.getvalue()


def main():
    check = "--check" in sys.argv[1:]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    stale = []
    for weight, style in CUTS.items():
        path = OUTPUT / f"WoodcaseStaticSans-{style}.ttf"
        data = cut(weight, style)
        if check:
            if not path.exists() or path.read_bytes() != data:
                stale.append(path.name)
        else:
            path.write_bytes(data)
            print(f"{path.relative_to(ROOT)}: {len(data)} bytes, weight {weight}")
    if stale:
        print("differs: " + ", ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
