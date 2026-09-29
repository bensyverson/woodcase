#!/usr/bin/env python3
"""Extracts Pen's bundled Google font table from Pen.app's app.asar, as JSON.

Pen's editor JavaScript carries the Google Fonts catalog it offers as a literal array of
`{name:"Family",styles:[{url:"https://fonts.gstatic.com/s/<dir>/v<N>/<hash>.ttf",weight:400,
italic:!0,axes:[{tag:"wght",start:100,end:700}]}, ...]}` objects. This reads the archive
read-only, finds every such object and prints one JSON object per family:

    {"name": ..., "styles": [{"url", "weight", "italic", "axes": [{"tag", "start", "end"}]}]}

Usage: scripts/pen-font-table.py [--asar <path>] > pen-fonts.json
Default archive: /Applications/Pen.app/Contents/Resources/app.asar. Used by
scripts/pen-font-audit; see project/2026-09-28-pen-font-faces.md.
"""

import argparse
import json
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--asar", default="/Applications/Pen.app/Contents/Resources/app.asar")
args = parser.parse_args()

with open(args.asar, "rb") as handle:
    blob = handle.read()

# The minifier writes numbers as `1e3` as often as `1000`.
NUMBER = rb'-?(?:\d+\.?\d*|\.\d+)(?:e\d+)?'
start = re.compile(rb'\{name:"((?:[^"\\]|\\.)*)",styles:\[\{url:"https://fonts\.gstatic\.com/')
style = re.compile(rb'\{url:"([^"]+)"((?:,[a-z]+:(?:!0|!1|' + NUMBER + rb'|\[[^\]]*\]))*)\}')
field = re.compile(rb',([a-z]+):(!0|!1|' + NUMBER + rb'|\[[^\]]*\])')
axis = re.compile(rb'\{tag:"(\w{4})",start:(' + NUMBER + rb'),end:(' + NUMBER + rb')\}')


def number(text):
    value = float(text)
    return int(value) if value.is_integer() else value


families = {}
for match in start.finditer(blob):
    name = match.group(1).decode("utf-8")
    cursor = blob.rfind(b"[", match.start(), match.end()) + 1
    styles = []
    while True:
        found = style.match(blob, cursor)
        if not found:
            break
        entry = {"url": found.group(1).decode(), "weight": 400, "italic": False, "axes": []}
        for key, value in field.findall(found.group(2)):
            key = key.decode()
            if key == "weight":
                entry["weight"] = number(value)
            elif key == "italic":
                entry["italic"] = value == b"!0"
            elif key == "axes":
                entry["axes"] = [{"tag": t.decode(), "start": number(s), "end": number(e)} for t, s, e in axis.findall(value)]
        styles.append(entry)
        cursor = found.end()
        if blob[cursor:cursor + 1] == b",":
            cursor += 1
    if styles and name not in families:
        families[name] = {"name": name, "styles": styles}

if not families:
    sys.exit("no font table found in " + args.asar)
json.dump(sorted(families.values(), key=lambda f: f["name"]), sys.stdout, indent=1)
print()
