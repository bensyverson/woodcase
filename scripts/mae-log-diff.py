#!/usr/bin/env python3
"""Lists every MAE figure that moved between two logs of `swift test` (run without
--quiet, so the suites' MAE lines are printed) — the before/after of a change that
moves many gates at once, such as a test font swap (leaf BpaSrF).

Each line mentioning MAE is keyed by its text with every decimal figure blanked, so
`React layout-text-chips: MAE 2.861 (CG 3.104) 720x114 vs 720x114` pairs with the same
board's line in the other log, whatever its figures. A line printed more than once (a
test that runs twice, or at two scales) is paired in order.

Usage: scripts/mae-log-diff.py <before.log> <after.log> [--threshold 0.001]
Prints one tab-separated row per moved line: key, before figures, after figures.
"""

import argparse
import re
from collections import defaultdict

FIGURE = re.compile(r"-?\d+\.\d+")

parser = argparse.ArgumentParser()
parser.add_argument("before")
parser.add_argument("after")
parser.add_argument("--threshold", type=float, default=0.001)
args = parser.parse_args()


def figures(path):
    lines = defaultdict(list)
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if "MAE" not in line or 'Test "' in line or "Test run" in line:
                continue
            line = line.strip()
            lines[FIGURE.sub("N", line)].append([float(x) for x in FIGURE.findall(line)])
    return lines


before, after = figures(args.before), figures(args.after)
moved = 0
for key in sorted(set(before) | set(after)):
    for index in range(max(len(before.get(key, [])), len(after.get(key, [])))):
        old = before.get(key, [])[index] if index < len(before.get(key, [])) else None
        new = after.get(key, [])[index] if index < len(after.get(key, [])) else None
        if old is None or new is None or len(old) != len(new) or any(abs(a - b) > args.threshold for a, b in zip(old, new)):
            moved += 1
            print(f"{key}\t{old}\t{new}")
print(f"# {moved} moved lines", flush=True)
