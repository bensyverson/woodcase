#!/usr/bin/env python3
"""Turns `woodcase activity deck.pen` and `woodcase undo deck.pen --dry-run` (build/raw/)
into build/log.js: LOG and UNDO, the lines as printed, for the reveal. Nothing is
reworded."""
import json
import os
import sys

root = sys.argv[1]
raw = os.path.join(root, 'build', 'raw')


def lines(name):
    with open(os.path.join(raw, name)) as f:
        return [l.rstrip('\n') for l in f if l.strip()]


print('const LOG = ' + json.dumps(lines('log.txt'), ensure_ascii=False) + ';')
print('const UNDO = ' + json.dumps(lines('undo.txt'), ensure_ascii=False) + ';')
