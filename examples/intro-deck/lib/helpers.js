// Tokens, geometry and node builders shared by every script.
// Loaded after build/data.js and before planes.js / stack.js.

const C = {
  sweepHi: '#FBFAF7',
  sweepMid: '#EEEEEC',
  sweepLo: '#D5D9DF',
  ink: '#0E1117',
  ink2: '#454B57',
  ink3: '#8A919D',
  ink4: '#B9BFC8',
  edge: '#9AA2AF',
  signal: '#2A36F5',
  stop: '#F0441C',
  paper: '#FFFFFF',
  night: '#0B0D12',
  nightInk: '#E9ECF1',
  nightInk2: '#9AA1AD',
  nightInk3: '#5C6370',
};

const F = {
  display: 'Schibsted Grotesk',
  mono: 'Martian Mono',
};

const W = 1920;
const H = 1080;

// A plane is the banking screen, in its own points.
const U = DATA.home.w;
const V = DATA.home.h;
const ANGLE = 20 * Math.PI / 180;
const CA = Math.cos(ANGLE);
const SA = Math.sin(ANGLE);
const ROOT2 = Math.SQRT2;

// The engine's planes, bottom to top: the file goes in at the base and the pixels sit on
// top, the finished design over the stages that made it.
const PLANES = ['parse', 'resolve', 'expand', 'layout', 'render'];

function projector(ox, oy, s, gap) {
  return (u, v, k) => [ox + (u - v) * CA * s, oy + (u + v) * SA * s - k * gap];
}

function fmt(n) { return Math.round(n * 100) / 100; }

// A path node from subpaths in slide coordinates; the node sits at its own bounds.
// A subpath is { pts: [[x,y],…], closed } or { d: [['M',x,y],['C',x1,y1,x2,y2,x,y],…] }.
function path(name, subpaths, opts = {}) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  const see = (x, y) => { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); };
  for (const s of subpaths) {
    if (s.pts) s.pts.forEach(([x, y]) => see(x, y));
    else s.d.forEach(c => { for (let i = 1; i < c.length; i += 2) see(c[i], c[i + 1]); });
  }
  const w = Math.max(maxX - minX, 1);
  const h = Math.max(maxY - minY, 1);
  const parts = [];
  for (const s of subpaths) {
    if (s.pts) {
      s.pts.forEach(([x, y], i) => parts.push(`${i ? 'L' : 'M'}${fmt(x - minX)} ${fmt(y - minY)}`));
      if (s.closed) parts.push('Z');
    } else {
      for (const c of s.d) {
        const xs = [];
        for (let i = 1; i < c.length; i += 2) xs.push(`${fmt(c[i] - minX)} ${fmt(c[i + 1] - minY)}`);
        parts.push(c[0] + xs.join(' '));
      }
    }
  }
  const node = {
    type: 'path', name, x: fmt(minX), y: fmt(minY), width: fmt(w), height: fmt(h),
    viewBox: [0, 0, fmt(w), fmt(h)], geometry: parts.join(' '),
  };
  if (opts.fill) node.fill = opts.fill;
  if (opts.stroke) {
    node.stroke = opts.stroke;
    node.strokeWidth = opts.strokeWidth || 1;
    node.strokeLinecap = opts.cap || 'round';
    node.strokeLinejoin = 'round';
  }
  if (opts.opacity !== undefined) node.opacity = opts.opacity;
  return node;
}

function rectPts(x, y, w, h) {
  return [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
}

function circlePts(cx, cy, r, n = 48) {
  const pts = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return pts;
}

// Dashes along a straight segment, as open subpaths.
function dashes(a, b, on = 6, off = 6) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const len = Math.hypot(dx, dy);
  const out = [];
  for (let t = 0; t < len; t += on + off) {
    const t1 = Math.min(t + on, len);
    out.push({ pts: [[a[0] + dx * t / len, a[1] + dy * t / len], [a[0] + dx * t1 / len, a[1] + dy * t1 / len]] });
  }
  return out;
}

function text(name, content, x, y, opts = {}) {
  const node = {
    type: 'text', name, content, x, y,
    fontFamily: opts.font || F.display,
    fontSize: opts.size || 32,
    fill: opts.fill || C.ink,
  };
  if (opts.weight) node.fontWeight = opts.weight;
  if (opts.lh) node.lineHeight = opts.lh;
  if (opts.ls !== undefined) node.letterSpacing = opts.ls;
  if (opts.width) { node.width = opts.width; node.textGrowth = 'fixed-width'; }
  if (opts.align) node.textAlign = opts.align;
  if (opts.opacity !== undefined) node.opacity = opts.opacity;
  return node;
}

function rect(name, x, y, w, h, opts = {}) {
  const node = { type: 'rectangle', name, x, y, width: w, height: h };
  if (opts.fill) node.fill = opts.fill;
  if (opts.stroke) { node.stroke = opts.stroke; node.strokeWidth = opts.strokeWidth || 1; node.strokeAlignment = 'inner'; }
  if (opts.radius) node.cornerRadius = opts.radius;
  if (opts.opacity !== undefined) node.opacity = opts.opacity;
  return node;
}

function group(name, children, opts = {}) {
  const g = { type: 'group', name, children };
  if (opts.opacity !== undefined) g.opacity = opts.opacity;
  return g;
}

// A monospace block: one text node per line, so each line keeps its own color.
function mono(name, lines, x, y, opts = {}) {
  const size = opts.size || 18;
  const lead = size * (opts.lh || 1.6);
  const kids = lines.map((line, i) => text(`Line ${i + 1}`, line === '' ? ' ' : line, x, y + i * lead, {
    font: F.mono, size, fill: (opts.color && opts.color(line, i)) || opts.fill || C.ink2,
    weight: opts.weight,
  }));
  return group(name, kids);
}

const SLIDE_SPACING = W + 100;

function slide(name, index, children, opts = {}) {
  const fill = opts.fill || [
    { type: 'gradient', gradientType: 'radial', center: { x: 0.64, y: 0.46 }, size: { width: 1.5, height: 1.9 },
      colors: [{ color: C.sweepHi, position: 0 }, { color: C.sweepMid, position: 0.45 }, { color: C.sweepLo, position: 1 }] },
  ];
  return {
    type: 'frame', name, layout: 'none', clip: true,
    x: (index - 1) * SLIDE_SPACING, y: 0, width: W, height: H,
    fill, children,
  };
}

// The display headline every slide sets at the same size and tracking.
function headline(name, content, x, y, opts = {}) {
  return text(name, content, x, y, { size: opts.size || 76, weight: '500', ls: -(opts.size || 76) * 0.029, lh: 1.02, width: opts.width || 1100, fill: opts.fill || C.ink });
}

function bezier(a, c1, c2, b, t) {
  const s = 1 - t;
  return [
    s * s * s * a[0] + 3 * s * s * t * c1[0] + 3 * s * t * t * c2[0] + t * t * t * b[0],
    s * s * s * a[1] + 3 * s * s * t * c1[1] + 3 * s * t * t * c2[1] + t * t * t * b[1],
  ];
}

// Every arrow in the deck shares one stroke and one head.
const ARROW = { width: 2.5, head: 16 };

// Points along a run of segments: ['M', x, y], then ['L', x, y] or ['C', x1, y1, x2, y2, x, y].
function sampleSegments(segs) {
  const pts = [[segs[0][1], segs[0][2]]];
  for (let k = 1; k < segs.length; k++) {
    const s = segs[k], p = pts[pts.length - 1];
    if (s[0] === 'L') {
      const n = Math.max(2, Math.ceil(Math.hypot(s[1] - p[0], s[2] - p[1]) / 3));
      for (let i = 1; i <= n; i++) pts.push([p[0] + (s[1] - p[0]) * i / n, p[1] + (s[2] - p[1]) * i / n]);
    } else {
      for (let i = 1; i <= 80; i++) pts.push(bezier(p, [s[1], s[2]], [s[3], s[4]], [s[5], s[6]], i / 80));
    }
  }
  return pts;
}

// An arrow along segments. The head points along the last segment's end tangent (for a
// cubic, end minus its second control point), its tip lands exactly on the last point, and
// the line stops just inside the head's base, so no stroke shows past it.
function arrowPath(name, segs, opts = {}) {
  const color = opts.color || C.signal;
  const width = opts.width || ARROW.width;
  const s = ARROW.head;
  const nodes = [];
  const last = segs[segs.length - 1];
  const tip = last[0] === 'L' ? [last[1], last[2]] : [last[5], last[6]];
  let from;
  if (last[0] === 'L') {
    const prev = segs[segs.length - 2];
    from = prev[0] === 'C' ? [prev[5], prev[6]] : [prev[1], prev[2]];
  } else {
    from = [last[3], last[4]];
  }
  const l = Math.hypot(tip[0] - from[0], tip[1] - from[1]) || 1;
  const u = [(tip[0] - from[0]) / l, (tip[1] - from[1]) / l];
  const lines = segs.map(x => x.slice());
  if (opts.head !== false) {
    // Pull the line's end back to just inside the head's base, along the same tangent.
    const back = s - 3;
    const end = lines[lines.length - 1];
    const k = end[0] === 'L' ? [1] : [3, 5];
    for (const at of k) { end[at] -= u[0] * back; end[at + 1] -= u[1] * back; }
  }
  if (opts.dashed) {
    const pts = sampleSegments(lines);
    const runs = [];
    let acc = 0, on = true, cur = [pts[0]];
    for (let i = 1; i < pts.length; i++) {
      acc += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
      cur.push(pts[i]);
      if (acc >= 9) {
        if (on) runs.push({ pts: cur });
        on = !on; acc = 0; cur = [pts[i]];
      }
    }
    if (on && cur.length > 1) runs.push({ pts: cur });
    nodes.push(path('Line', runs, { stroke: color, strokeWidth: width, cap: 'butt' }));
  } else {
    nodes.push(path('Line', [{ d: lines }], { stroke: color, strokeWidth: width, cap: 'butt' }));
  }
  if (opts.head !== false) {
    const base = [tip[0] - u[0] * s, tip[1] - u[1] * s];
    const side = [-u[1] * s * 0.5, u[0] * s * 0.5];
    nodes.push(path('Head', [{ pts: [tip, [base[0] + side[0], base[1] + side[1]], [base[0] - side[0], base[1] - side[1]]], closed: true }], { fill: color }));
  }
  return group(name, nodes);
}

// A single cubic from a to b with explicit control points, and its head at b.
function arrow(name, a, c1, c2, b, opts = {}) {
  return arrowPath(name, [['M', ...a], ['C', ...c1, ...c2, ...b]], opts);
}

// A quarter turn of radius r from p0, travelling along d0, into travelling along d1.
// Returns the cubic segment and its end point. d0 and d1 are unit axis vectors.
function turn(p0, d0, d1, r) {
  const k = 0.552 * r;
  const end = [p0[0] + (d0[0] + d1[0]) * r, p0[1] + (d0[1] + d1[1]) * r];
  return { seg: ['C', p0[0] + d0[0] * k, p0[1] + d0[1] * k, end[0] - d1[0] * k, end[1] - d1[1] * k, end[0], end[1]], end };
}

// A verb, in mono, over a line of gloss.
function verb(name, word, gloss, x, y, opts = {}) {
  const kids = [
    text('Verb', word, x, y, { font: F.mono, size: opts.size || 30, weight: '500', fill: opts.color || C.signal }),
  ];
  if (gloss) kids.push(text('Gloss', gloss, x, y + (opts.size || 30) * 1.55, { size: 21, fill: opts.glossFill || C.ink2, width: opts.width || 380, lh: 1.3 }));
  return group(name, kids);
}

// The agent: a terminal prompt, set in a disc.
function agent(cx, cy, opts = {}) {
  const r = opts.r || 46;
  return group('Agent', [
    path('Disc', [{ pts: circlePts(cx, cy, r, 96), closed: true }], { fill: opts.fill || C.ink }),
    text('Prompt', '›_', cx - 40, cy - r * 0.37, { font: F.mono, size: r * 0.56, fill: opts.ink || C.paper, width: 80, align: 'center' }),
    text('Caption', 'agent', cx - r - 150, cy - 9, { font: F.mono, size: 13, fill: opts.caption || C.ink2, width: 130, align: 'right' }),
  ]);
}

// A small running folio: which plane the camera is on, bottom right.
function folio(n, label, opts = {}) {
  return text('Folio', `${String(n).padStart(2, '0')}  ${label}`, W - 420, H - 64, {
    font: F.mono, size: 13, fill: opts.fill || C.ink3, width: 300, align: 'right', ls: 0.4,
  });
}

// Dashes around a closed polygon, as open subpaths.
function dashedLoop(pts, on = 6, off = 6) {
  const out = [];
  pts.forEach((p, i) => out.push(...dashes(p, pts[(i + 1) % pts.length], on, off)));
  return out;
}

// The caption block every page but the cover carries at bottom left: the one sentence the
// picture has earned, and a line of support. It is anchored at its bottom edge, so a
// one-line and a two-line headline end in the same place.
const CAPTION = { x: 120, bottom: 1000, width: 1060 };

const TITLE_SIZE = 56;

function titleText(name, content, opts = {}) {
  const size = opts.size || TITLE_SIZE;
  const t = text(name, content, 0, 0, {
    size, weight: opts.weight || '500', ls: -size * 0.028, lh: 1.06, fill: opts.fill || C.ink, font: opts.font,
  });
  delete t.x; delete t.y;
  return t;
}

// title is a string, or a node already built (a title with code in it).
function caption(title, support, opts = {}) {
  const kids = [];
  if (typeof title === 'string') {
    const head = titleText('Title', title, opts);
    head.width = 'fill_container';
    head.textGrowth = 'fixed-width';
    kids.push(head);
  } else if (title) {
    kids.push(title);
  }
  for (const e of opts.evidence || []) kids.push(e);
  if (support) {
    const s = text('Support', support, 0, 0, { size: 23, fill: opts.supportFill || C.ink2, lh: 1.42 });
    s.width = 'fill_container';
    s.textGrowth = 'fixed-width';
    kids.push(s);
  }
  for (const e of opts.after || []) kids.push(e);
  for (const k of kids) { delete k.x; delete k.y; }
  const height = 420;
  return {
    type: 'frame', name: 'Caption', layout: 'vertical', justifyContent: 'end', gap: 22,
    x: CAPTION.x, y: CAPTION.bottom - height, width: opts.width || CAPTION.width, height,
    children: kids,
  };
}

// A mono label set on a line, with a patch of ground behind it so the line breaks for it.
function onLine(name, word, x, y, opts = {}) {
  const size = opts.size || 26;
  return {
    type: 'frame', name, layout: 'horizontal', x, y, padding: [4, 10], fill: opts.ground || C.sweepMid,
    children: [text('Word', word, 0, 0, { font: F.mono, size, weight: '500', fill: opts.fill || C.signal })],
  };
}

// A title with code in it: .pen text has no styled runs, so each line is a row of runs,
// the code runs in mono, the rest in the display face. lines: [[[text, isCode], …], …]
function codeTitle(lines, opts = {}) {
  const size = opts.size || TITLE_SIZE;
  const rows = lines.map((runs, i) => ({
    type: 'frame', name: `Line ${i + 1}`, layout: 'horizontal', alignItems: 'end', gap: size * 0.24,
    children: runs.map(([content, code], j) => {
      const t = code
        ? text(`Code ${j + 1}`, content, 0, 0, { font: F.mono, size: size * 0.86, weight: '500', fill: C.ink, lh: 1.06 * size / (size * 0.86) })
        : titleText(`Words ${j + 1}`, content, { size });
      delete t.x; delete t.y;
      return t;
    }),
  }));
  return { type: 'frame', name: 'Title', layout: 'vertical', width: 'fill_container', children: rows };
}
