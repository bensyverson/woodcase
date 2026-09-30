#!/usr/bin/env python3
"""Turns the viewer's page geometry (build/raw/dash-*.json, from `sleepy query`) into
build/dash.js: DASH, the screenshot's viewport and the box of each thing slide 8 marks,
in the page's CSS pixels. Nothing is placed by hand: each mark is where the page drew it."""
import json
import os
import sys

root = sys.argv[1]
raw = os.path.join(root, 'build', 'raw')
VIEW = {'w': 1600, 'h': 1000}


def box(name):
    # The page keeps a copy of some things for other states, hidden: take the one drawn.
    with open(os.path.join(raw, f'dash-{name}.json')) as f:
        g = next(m for m in json.load(f) if m['visible'])['geometry']
    # A panel taller than the viewport is marked where the shot cuts it.
    h = min(g['height'], VIEW['h'] - g['y'])
    return {'x': g['x'], 'y': g['y'], 'w': g['width'], 'h': h}


def union(*boxes):
    x, y = min(b['x'] for b in boxes), min(b['y'] for b in boxes)
    return {'x': x, 'y': y,
            'w': max(b['x'] + b['w'] for b in boxes) - x,
            'h': max(b['y'] + b['h'] for b in boxes) - y}


marks = {
    # Who is active and the live badge, as one box: the page moving with the agent.
    'live': union(box('presence'), box('live')),
    'activity': box('activity'),
    'outline': box('outline'),
}
print('const DASH = ' + json.dumps({**VIEW, 'marks': marks}) + ';')
