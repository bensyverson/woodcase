// The exploded stack, from the turned plane PNGs in assets/. Loaded after helpers.js.
//
// opts:
//   ox, oy   the top corner of the bottom plane, in slide points
//   s        points per plane point; gap: vertical distance between planes
//   look     plane → 'on' | 'lit' | 'dim' | 'ghost' | 'empty' (dashed outline) | 'gone'
//   labels   draw each plane's name at its left corner
//   ports    planes that show a port; thread: { from, to, color, dashed }
//   planes   override the plane list, bottom to top: [{ key, image, label }]
//   u, v     plane size in plane points, when the planes are not the screen
//   night    draw edges for a dark ground

const PORT = [16, V - 16];

function stack(opts) {
  const u = opts.u || U, v = opts.v || V;
  const P = projector(opts.ox, opts.oy, opts.s, opts.gap);
  const look = opts.look || {};
  const planes = opts.planes || PLANES.map(p => ({
    key: p, label: p,
    image: `./assets/iso-${p}${p === 'layout' && look.layout === 'lit' ? '-lit' : ''}.png`,
  }));
  const thick = opts.thick === undefined ? 5 : opts.thick;
  const kids = [];

  // The floor shadow, under the bottom plane: nested outlines of flat translucent ink,
  // each smaller and so each darker toward the middle. (A radial gradient with
  // transparent stops reads right in a PNG but exports to PDF as solid black.)
  const lift = -0.25 * (opts.gap / Math.max(opts.gap, 1));
  const rings = [];
  for (let i = 0; i < 16; i++) {
    const pad = 100 - i * 7;
    const pts = [[-pad, -pad], [u + pad, -pad], [u + pad, v + pad], [-pad, v + pad]].map(([a, b]) => P(a, b, lift));
    rings.push(path(`Ring ${i + 1}`, [{ pts, closed: true }], { fill: opts.night ? '#0000000D' : '#0E111703' }));
  }
  kids.push(group('Floor Shadow', rings));

  // Construction lines at the far corners, behind every plane.
  if (opts.gap > 0 && opts.construction !== false) {
    const guide = [];
    for (const [a, b] of [[0, 0], [u, 0], [u, v]]) guide.push(...dashes(P(a, b, 0), P(a, b, planes.length - 1), 2, 7));
    kids.push(path('Construction', guide, { stroke: opts.night ? C.nightInk3 : C.edge, strokeWidth: 1 }));
  }

  const thread = opts.thread;
  planes.forEach((plane, k) => {
    const state = look[plane.key] || 'on';
    if (state === 'gone') return;
    const lit = state === 'lit';
    const q = (a, b) => P(a, b, k);
    if (state === 'empty') {
      // A plane the reader is meant to miss: its outline only, dashed.
      kids.push(path(`Plane ${plane.key}`, dashedLoop([q(0, 0), q(u, 0), q(u, v), q(0, v)], 7, 7), { stroke: C.ink3, strokeWidth: 1.4, cap: 'butt' }));
      return;
    }
    const drop = ([x, y]) => [x, y + thick];
    const left = q(0, v), front = q(u, v), right = q(u, 0), back = q(0, 0);
    const planeKids = [];
    planeKids.push(path('Edge', [
      { pts: [left, front, drop(front), drop(left)], closed: true },
      { pts: [front, right, drop(right), drop(front)], closed: true },
    ], { fill: opts.night ? '#2A2F3A' : (plane.key === 'render' ? '#BFC5CE' : '#D5D9E0E6') }));
    const x0 = left[0], y0 = back[1];
    planeKids.push({
      type: 'frame', name: 'Image', layout: 'none', x: fmt(x0), y: fmt(y0),
      width: fmt(right[0] - left[0]), height: fmt(front[1] - back[1]),
      fill: { type: 'image', url: plane.image, mode: 'stretch' },
    });
    planeKids.push(path('Rim', [{ pts: [back, right, front, left], closed: true }], {
      stroke: lit ? C.signal : (opts.night ? C.nightInk3 : C.edge), strokeWidth: lit ? 2 : 1,
    }));
    const alpha = { on: 1, lit: 1, dim: 0.5, ghost: 0.24 }[state];
    kids.push(group(`Plane ${plane.key}`, planeKids, alpha < 1 ? { opacity: alpha } : {}));

    if (opts.ports && opts.ports.includes(plane.key)) {
      kids.push(path(`Port ${plane.key}`, [{ pts: circlePts(PORT[0], PORT[1], 11, 40).map(([a, b]) => q(a, b)), closed: true }], {
        fill: opts.portColor || C.signal,
      }));
    }

    // The thread from the port of the plane above down to this one's, drawn before the plane
    // above so that plane covers where the thread leaves it.
    if (thread) {
      const a0 = planes.findIndex(p => p.key === thread.from), b0 = planes.findIndex(p => p.key === thread.to);
      if (k >= Math.min(a0, b0) && k < Math.max(a0, b0)) {
        const a = P(PORT[0], PORT[1], k + 1), b = P(PORT[0], PORT[1], k);
        const seg = thread.dashed ? dashes(a, b, 5, 6) : [{ pts: [a, b] }];
        kids.push(path(`Thread ${k + 1}`, seg, { stroke: thread.color || C.signal, strokeWidth: thread.width || 3, cap: 'butt' }));
      }
    }
  });

  if (opts.labels) {
    planes.forEach((plane, k) => {
      const state = look[plane.key] || 'on';
      if (state === 'gone') return;
      const [lx, ly] = P(0, v, k);
      const color = opts.labelColor || (opts.night ? C.nightInk2 : (state === 'lit' ? C.signal : (state === 'on' ? C.ink2 : C.ink3)));
      kids.push(path(`Leader ${plane.key}`, [{ pts: [[lx - 16, ly], [lx - 60, ly]] }], { stroke: color, strokeWidth: 1 }));
      kids.push(text(`Label ${plane.key}`, plane.label, lx - 260, ly - 9, {
        font: F.mono, size: 13, fill: color, width: 186, align: 'right', ls: 0.5,
      }));
    });
  }

  return group(opts.name || 'Stack', kids);
}

function portAt(opts, plane) {
  const P = projector(opts.ox, opts.oy, opts.s, opts.gap);
  return P(PORT[0], PORT[1], PLANES.indexOf(plane));
}

// Stack placement helpers: the stack's footprint for a given top corner.
function stackBounds(opts, count = PLANES.length) {
  const u = opts.u || U, v = opts.v || V;
  return {
    left: opts.ox - v * CA * opts.s, right: opts.ox + u * CA * opts.s,
    top: opts.oy - (count - 1) * opts.gap, bottom: opts.oy + (u + v) * SA * opts.s,
  };
}
