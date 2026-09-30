// S2 — the gap: the same stack, hollowed out. The agent writes the base plane; the four
// above it are outlines with only their names in them, and the way back from the pixels
// stops short. No blue on this page: blue is what Woodcase shows, and it is not here yet.
const GAP = { ox: 1600, oy: 600, s: 0.62, gap: 118 };
const A2 = [420, 400];
const parse2 = portAt(GAP, 'parse');
const render2 = portAt(GAP, 'render');
const stop2 = [720, 300];
const P2 = projector(GAP.ox, GAP.oy, GAP.s, GAP.gap);
const missing2 = ['resolve', 'expand', 'layout', 'render'].map(p => {
  const [cx, cy] = P2(U * 0.42, V * 0.3, PLANES.indexOf(p));
  return text(`Name ${p}`, p, cx - 150, cy - 10, { font: F.mono, size: 16, fill: C.ink3, width: 300, align: 'center' });
});

const SLIDE = {
  name: 'S2 Gap', index: 2,
  parts: [
    ['Stack', [stack({ ...GAP, look: { resolve: 'empty', expand: 'empty', layout: 'empty', render: 'empty' } }), ...missing2]],
    ['Labels', [
      text('Writes', 'the file it writes', parse2[0] - 330, parse2[1] + 20, { font: F.mono, size: 15, fill: C.ink2, width: 300, align: 'right' }),
      text('Never Sees', 'what the file draws:\nnever seen', P2(0, V, 2)[0] - 330, P2(0, V, 2)[1] - 60, { font: F.mono, size: 15, fill: C.ink3, width: 300, align: 'right', lh: 1.5 }),
    ]],
    ['Paths', [
      arrow('Write', [A2[0] + 20, A2[1] + 50], [A2[0] + 120, A2[1] + 230], [parse2[0] - 240, parse2[1]], [parse2[0] - 13, parse2[1]], { color: C.ink }),
      arrow('No Way Back', [render2[0] - 30, render2[1]], [render2[0] - 180, render2[1]], [stop2[0] + 120, stop2[1]], stop2, { color: C.ink3, dashed: true, head: false }),
      agent(A2[0], A2[1]),
    ]],
    ['Caption', caption('Without Woodcase, agents design blind.',
      'An agent can write a design file, but it can’t see what the file draws: not where things land, not how they look.',
      { width: 700 })],
  ],
};
