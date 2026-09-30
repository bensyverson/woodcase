// The five planes, each the banking screen at one stage of the pipeline, drawn flat from
// the real data in DATA. Every builder takes a zoom z (1 = the screen's own points) and
// returns one frame, so a slide can show a plane flat and legible, and iso-sources.js can
// turn the same frame for the stack.

const FACE = {
  parse: '#FBFBFADE',
  resolve: '#FAFAF9DE',
  expand: '#F8F8F7DE',
  layout: '#F5F6FAE0',
  render: '#FFFFFF',
};

function planeFrame(name, plane, z, children, opts = {}) {
  const f = {
    type: 'frame', name, layout: 'none', clip: true,
    width: U * z, height: V * z, fill: opts.fill || FACE[plane], children,
  };
  if (opts.x !== undefined) f.x = opts.x;
  if (opts.y !== undefined) f.y = opts.y;
  if (opts.rotation) f.rotation = opts.rotation;
  return f;
}

// base: the path from the .pen file being written to the repo's assets folder.
function renderPlane(name, z, opts = {}) {
  const base = opts.base || './assets';
  return planeFrame(name, 'render', z, [], {
    ...opts,
    fill: { type: 'image', url: `${base}/render.png`, mode: 'stretch' },
  });
}

function layoutPlane(name, z, opts = {}) {
  const col = opts.lit ? C.signal : C.ink2;
  const kids = [];
  const labelDepth = opts.labelDepth === undefined ? 1 : opts.labelDepth;
  DATA.boxes.forEach((b, i) => {
    if (b.depth === 0 || b.w <= 0 || b.h <= 0) return;
    kids.push(rect(`Box ${i}`, b.x * z, b.y * z, b.w * z, b.h * z, { stroke: col, strokeWidth: opts.stroke || 1 }));
  });
  const tagged = opts.tagFilter || (b => b.depth > 0 && b.depth <= labelDepth);
  if (labelDepth > 0 || opts.tagFilter) {
    DATA.boxes.forEach((b, i) => {
      if (!tagged(b) || b.w <= 0) return;
      const r = b.rect;
      const tag = `${b.name}  ${fmt(r.x)},${fmt(r.y)} ${fmt(r.width)}×${fmt(r.height)}`;
      // A tag sits on a chip of the plane's own ground, so the lines it crosses break for it;
      // a box against the right edge carries its tag right-aligned, inside the plane.
      const size = (opts.tagSize || 7) * z;
      const chip = {
        type: 'frame', name: `Tag ${i}`, layout: 'horizontal', padding: [1 * z, 3 * z],
        fill: opts.tagGround || opts.fill || FACE.layout,
        children: [text('Text', tag, 0, 0, { font: F.mono, size, fill: col })],
      };
      delete chip.children[0].x; delete chip.children[0].y;
      const est = tag.length * size * 0.68 + 6 * z;
      const right = b.x + b.w > U * 0.75 && b.w < U * 0.5;
      chip.x = right ? (b.x + b.w) * z - est - 2 * z : (b.x + 1) * z;
      chip.y = (b.y + 2) * z;
      kids.push(chip);
    });
  }
  return planeFrame(name, 'layout', z, kids, opts);
}

function expandPlane(name, z, opts = {}) {
  const kids = [];
  DATA.boxes.forEach((b, i) => {
    if (b.depth === 0 || b.w <= 0 || b.h <= 0) return;
    if (b.type === 'ref' && b.address.startsWith('banking-home/')) {
      kids.push(rect(`Instance ${i}`, b.x * z, b.y * z, b.w * z, b.h * z, { fill: '#DDE2F0', stroke: C.ink2, strokeWidth: 1, radius: 6 * z }));
      kids.push(text(`Of ${i}`, b.refName, (b.x + 4) * z, (b.y + 3) * z, { font: F.mono, size: 6.5 * z, fill: C.ink2 }));
    } else if (b.type === 'frame' && b.depth <= 2) {
      kids.push(rect(`Frame ${i}`, b.x * z, b.y * z, b.w * z, b.h * z, { stroke: C.ink4 }));
    }
  });
  return planeFrame(name, 'expand', z, kids, opts);
}

function resolvePlane(name, z, opts = {}) {
  const kids = [];
  const vars = DATA.vars;
  const top = 26, step = (V - 2 * top) / vars.length;
  vars.forEach((v, i) => {
    const y = top + i * step;
    kids.push(text(`Name ${i}`, `$${v.name}`, 22 * z, (y + 6) * z, { font: F.mono, size: 10 * z, fill: C.ink2 }));
    if (v.type === 'color') {
      const chip = (label, value, x) => {
        if (!value || value.startsWith('$')) {
          kids.push(text(`${label} ${i}`, value || '—', x * z, (y + 6) * z, { font: F.mono, size: 10 * z, fill: C.ink3 }));
          return;
        }
        kids.push(rect(`${label} ${i}`, x * z, (y + 3) * z, 44 * z, (step - 8) * z, { fill: value, stroke: '#0E11171F', radius: 4 * z }));
      };
      chip('Day', v.value, 250);
      chip('Night', v.night, 314);
    } else {
      kids.push(text(`Value ${i}`, String(v.value), 250 * z, (y + 6) * z, { font: F.mono, size: 10 * z, fill: C.ink3 }));
    }
  });
  return planeFrame(name, 'resolve', z, kids, opts);
}

function parsePlane(name, z, opts = {}) {
  const size = (opts.size || 9.6) * z;
  const lead = size * 1.62;
  const count = Math.min(DATA.json.length, Math.floor((V * z - 24 * z) / lead));
  const kids = [];
  for (let i = 0; i < count; i++) {
    const line = DATA.json[i];
    const isVar = /"\$/.test(line);
    kids.push(text(`Line ${i + 1}`, line.replace(/^ {6}/, '') || ' ', 16 * z, 14 * z + i * lead, {
      font: F.mono, size, fill: isVar ? C.signal : C.ink2,
    }));
  }
  return planeFrame(name, 'parse', z, kids, opts);
}

const PLANE_BUILDERS = { render: renderPlane, layout: layoutPlane, expand: expandPlane, resolve: resolvePlane, parse: parsePlane };
