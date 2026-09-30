// S7 — outlets: the render plane lifts out of the stack, and leaves by five doors. Each
// door shows what actually comes out of it.
const Q7 = DATA.quotes;
const G7 = { ox: 470, oy: 560, s: 0.4, gap: 84 };
const LIFT = { ox: 900, oy: 110, s: 0.64, gap: 0 };
const P7 = projector(G7.ox, G7.oy, G7.s, G7.gap);
const PL = projector(LIFT.ox, LIFT.oy, LIFT.s, 0);
const top7 = PLANES.indexOf('render');
const corners = f => [[0, 0], [U, 0], [U, V], [0, V]].map(([u, v]) => f(u, v));
const slot7 = corners((u, v) => P7(u, v, top7));
const lift7 = corners((u, v) => PL(u, v, 0));
const motion7 = [];
[0, 2, 3].forEach(i => motion7.push(...dashes(slot7[i], lift7[i], 3, 6)));

// Code keeps its own indentation, less what every line shares.
function dedent(lines) {
  const pad = Math.min(...lines.filter(l => l.trim()).map(l => l.match(/^ */)[0].length));
  return lines.map(l => l.slice(pad));
}
const count7 = line => (line.match(/Generated (\d+) file/) || [])[1];
const shotLine7 = Q7.shot[1].replace(/\s{2,}/g, '  ').replace(/\s*(gutter|rect)=\S+/g, '');
const outlets7 = [
  { name: 'PNG', meta: 'the render, at any scale', code: [Q7.shot[0], shotLine7] },
  { name: 'PDF', meta: 'vector: one page per top-level frame, like this deck', code: ['$ woodcase render deck.pen --format pdf'] },
  { name: 'CGContext', meta: 'drawn by the Swift library into a context your app owns', code: Q7.cgcontext },
  { name: 'React + Tailwind', meta: `${count7(Q7.reactGen[0])} files; this is ComponentQuickaction.tsx`, code: dedent(Q7.react.slice(0, 4)) },
  { name: 'SwiftUI', meta: `a Swift package of ${count7(Q7.swiftuiGen[0])} files; this is its QuickAction view`, code: dedent(Q7.swiftui.slice(0, 5)) },
];
const X7 = 1330, Y7 = 92, STEP7 = 170;
// Each door leaves the lifted plane from its own point on the rim, straight out along the
// rim's outward normal, then turns to arrive level with its label. The top door leaves
// the back edge (facing up); the rest leave the front edge (facing down), in order, so
// the branches nest instead of crossing.
const leave7 = [
  { at: PL(U * 0.8, 0, 0), n: [SA, -CA] },
  ...[0.04, 0.13, 0.22, 0.31].map(f => ({ at: PL(U, V * f, 0), n: [SA, CA] })),
];
const doors7 = [];
outlets7.forEach((o, i) => {
  const y = Y7 + i * STEP7;
  const { at, n } = leave7[i];
  const a = [at[0] + n[0] * 5, at[1] + n[1] * 5];
  const tip = [X7 - 10, y + 13];
  const reach = Math.min(90, Math.abs(tip[1] - a[1]) * 0.6 + 30);
  doors7.push(arrow(`To ${o.name}`, a, [a[0] + n[0] * reach, a[1] + n[1] * reach], [tip[0] - 130, tip[1]], tip));
  doors7.push(text(`${o.name} Name`, o.name, X7, y, { font: F.mono, size: 20, weight: '500', fill: C.ink }));
  doors7.push(text(`${o.name} Meta`, o.meta, X7, y + 32, { size: 16, fill: C.ink2, width: 460 }));
  doors7.push(mono(`${o.name} Code`, o.code, X7, y + 60, { size: 12, lh: 1.5, fill: C.ink3 }));
});

const SLIDE = {
  name: 'S7 Outlets', index: 7,
  parts: [
    ['Stack', [
      stack({ ...G7, look: { render: 'gone' } }),
      path('Slot', dashedLoop(slot7, 5, 5), { stroke: C.ink3, strokeWidth: 1.2, cap: 'butt' }),
      path('Lift', motion7, { stroke: C.ink4, strokeWidth: 1, cap: 'butt' }),
    ]],
    ['Lifted', [stack({ ...LIFT, name: 'Lifted Plane', planes: [{ key: 'render', label: 'render', image: './assets/iso-render.png' }], look: { render: 'lit' }, construction: false })]],
    ['Doors', [...doors7, text('Lifted Label', 'the rendered design', PL(0, V, 0)[0] - 250, PL(0, V, 0)[1] - 64, { font: F.mono, size: 14, fill: C.ink3, width: 230, align: 'right' })]],
    ['Caption', caption('One engine draws to PNG, PDF, your app, React and SwiftUI.',
      'The engine is a Swift library, and the command line is one thin layer over it.',
      { width: 1080 })],
  ],
};
