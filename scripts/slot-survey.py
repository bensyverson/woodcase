#!/usr/bin/env python3
"""Count the distinct `slot` lists the frames of every .pen file under some roots carry.

Usage: python3 -I scripts/slot-survey.py <root> [<root> ...]

Prints each list with how many frames carry it and up to three files that do, most
common first. Written for project/2026-10-14-slot-semantics.md, which uses it to show
that Pen-authored files list component ids, not node types.
"""

import collections
import json
import os
import sys

SKIPPED_DIRECTORIES = {".build", ".git", "node_modules", "worktrees", "DerivedData"}


def walk(node, path, counts, where):
    if isinstance(node, dict):
        if node.get("type") == "frame" and "slot" in node:
            value = json.dumps(node["slot"])
            counts[value] += 1
            where[value].add(path)
        for child in node.values():
            walk(child, path, counts, where)
    elif isinstance(node, list):
        for child in node:
            walk(child, path, counts, where)


def main(roots):
    counts = collections.Counter()
    where = collections.defaultdict(set)
    for root in roots:
        for directory, directories, files in os.walk(root):
            directories[:] = [d for d in directories if d not in SKIPPED_DIRECTORIES]
            for name in files:
                if not name.endswith(".pen"):
                    continue
                path = os.path.join(directory, name)
                try:
                    with open(path) as handle:
                        walk(json.load(handle), path, counts, where)
                except (OSError, ValueError):
                    continue
    for value, count in counts.most_common():
        print(count, value, sorted(where[value])[:3])


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
