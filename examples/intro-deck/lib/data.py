#!/usr/bin/env python3
"""Turns what build.sh read from the tool into build/data.js, one `DATA` constant.

Nothing here is authored: every string is a line the CLI printed, a line of a file the
CLI wrote, or a line of the repo. Absolute scratch paths are shortened to the file name,
which is what the command was given.
"""
import json
import os
import sys

root = sys.argv[1]
raw = os.path.join(root, 'build', 'raw')
scratch = os.path.join(root, 'build', 'scratch')
real_scratch = os.path.realpath(scratch)


def clean(text):
    for prefix in (real_scratch + '/', scratch + '/', '/private' + scratch + '/'):
        text = text.replace(prefix, '')
    return text


def lines(name):
    with open(os.path.join(raw, name)) as f:
        return [clean(l.rstrip('\n')) for l in f.read().rstrip('\n').split('\n')]


def read(path):
    with open(path) as f:
        return f.read()


# Layout rows, relative to the screen's own origin.
tree = json.load(open(os.path.join(raw, 'tree.json')))
kit = json.load(open(os.path.join(raw, 'kit-tree.json')))
names = {r['id']: r['name'] for r in kit['rows'] if r.get('name')}
rows = tree['rows']
home = rows[0]['absRect']
for r in rows:
    if r.get('name'):
        names.setdefault(r['id'], r['name'])
boxes = []
for r in rows:
    a = r.get('absRect')
    if not a:
        continue
    ref = (r.get('properties') or {}).get('kind.ref')
    ref_name = None
    if ref:
        ref_name = names.get(ref.split(':')[-1]) or names.get(ref) or ref
    boxes.append({
        'address': r['address'], 'name': r.get('name') or r['id'], 'id': r['id'],
        'type': r['type'], 'depth': r['depth'], 'instance': r['isInstance'],
        'ref': ref, 'refName': ref_name,
        'x': a['x'] - home['x'], 'y': a['y'] - home['y'], 'w': a['width'], 'h': a['height'],
        'rect': r['rect'],
    })

# Variables: the default value, and the night value where there is one.
variables = []
for v in json.load(open(os.path.join(raw, 'vars.json')))['variables']:
    default = next((x['value'] for x in v['values'] if not x.get('theme')), None)
    night = next((x['value'] for x in v['values'] if x.get('theme') == {'scheme': 'night'}), None)
    variables.append({'name': v['name'], 'type': v['type'], 'value': default, 'night': night,
                      'count': len(v['values'])})

# The file itself, from the screen's first line.
pen = read(os.path.join(raw, 'banking.pen.txt')).split('\n')
start = next(i for i, l in enumerate(pen) if '"content": "9:41"' in l) - 5
json_lines = pen[start:start + 90]

react = read(os.path.join(scratch, 'react', 'components', 'ComponentQuickaction.tsx')).split('\n')
swift = read(os.path.join(scratch, 'swiftui', 'Sources', 'Banking', 'Components',
                          'ComponentQuickaction.swift')).split('\n')
readme = read(os.path.join(root, '..', '..', 'README.md')).split('\n')
layout_call = next(l.strip() for l in readme if 'PenLayoutEngine.layout(' in l)
renderer = read(os.path.join(root, '..', '..', 'Sources', 'Woodcase', 'Rendering', 'PenRenderer.swift'))
assert 'into context: CGContext' in renderer, 'PenRenderer lost render(_:layoutRects:into:)'
# The README's layout line, then the documented call that draws into a caller's context.
render_call = [layout_call, 'PenRenderer.render(expanded, layoutRects: rects, into: context)']


def span(src, first, count):
    i = next(i for i, l in enumerate(src) if first in l)
    return src[i:i + count]


qa = next(r for r in rows if r['address'] == 'banking-home/quick-actions')['absRect']

DATA = {
    'quickActions': {'w': qa['width'], 'h': qa['height']},
    'home': {'w': home['width'], 'h': home['height']},
    'boxes': boxes,
    'vars': variables,
    'json': json_lines,
    'jsonStart': start + 1,
    'quotes': {
        'treeHeader': lines('tree-header.txt'),
        'set': lines('set.txt'),
        'shot': lines('shot.txt'),
        'refused': lines('refused.txt'),
        'fixed': lines('fixed.txt'),
        'js': lines('js.txt'),
        'reactGen': [l for l in lines('react-gen.txt') if l.startswith('Generated')],
        'swiftuiGen': [l for l in lines('swiftui-gen.txt') if l.startswith('Generated')],
        'react': span(react, 'return (', 9),
        'swiftui': span(swift, 'public var body', 7),
        'cgcontext': render_call,
        'script': read(os.path.join(root, 'quotes', 'measure.js')).rstrip('\n').split('\n'),
    },
}
print('const DATA = ' + json.dumps(DATA, ensure_ascii=False) + ';')
