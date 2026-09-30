// S3 — the loop, as a circuit the eye can travel: 1 set goes in at the base, the change
// rises through the planes, 2 tree comes back out of the layout plane as text. shot, the
// pixels, is the dashed branch: the last mile, not the loop.
const G3 = { ox: 1580, oy: 560, s: 0.6, gap: 118 };
const A3 = [380, 562];
const R3 = 64, DISC3 = 46;
const p3 = portAt(G3, 'parse'), l3 = portAt(G3, 'layout'), r3 = portAt(G3, 'render');

const SLIDE = {
  name: 'S3 Loop', index: 3,
  parts: [
    ['Stack', [stack({ ...G3, look: { resolve: 'ghost', expand: 'ghost', layout: 'lit', render: 'dim' }, ports: ['parse', 'layout', 'render'], thread: { from: 'parse', to: 'layout' } })]],
    ['Circuit', [
      // view, tree: out of the layout plane, left along the line, down into the agent.
      (() => {
        const t = turn([A3[0] + R3, l3[1]], [-1, 0], [0, 1], R3);
        return arrowPath('Tree', [['M', l3[0] - 14, l3[1]], ['L', A3[0] + R3, l3[1]], t.seg, ['L', A3[0], A3[1] - DISC3 - 2]]);
      })(),
      // command, set: down out of the agent, right along the line, into the file.
      (() => {
        const t = turn([A3[0], p3[1] - R3], [0, 1], [1, 0], R3);
        return arrowPath('Set', [['M', A3[0], A3[1] + DISC3 + 2], ['L', A3[0], p3[1] - R3], t.seg, ['L', p3[0] - 13, p3[1]]]);
      })(),
      // view, shot: the dashed branch from the pixels, landing beside tree on the agent.
      (() => {
        const x = A3[0] - 34, y = A3[1] - Math.sqrt(DISC3 * DISC3 - 34 * 34) - 2;
        const t = turn([x + R3, r3[1]], [-1, 0], [0, 1], R3);
        return arrowPath('Shot', [['M', r3[0] - 14, r3[1]], ['L', x + R3, r3[1]], t.seg, ['L', x, y]], { dashed: true });
      })(),
      text('Tree Label', 'view  tree', 600, l3[1] - 44, { font: F.mono, size: 26, weight: '500', fill: C.signal }),
      text('Tree Gloss', 'the result, read back as text', 600, l3[1] + 16, { size: 20, fill: C.ink2 }),
      text('Set Label', 'command  set', 600, p3[1] - 44, { font: F.mono, size: 26, weight: '500', fill: C.signal }),
      text('Set Gloss', 'one change, guarded by its revision', 600, p3[1] + 16, { size: 20, fill: C.ink2 }),
      text('Shot Label', 'view  shot', 600, r3[1] - 38, { font: F.mono, size: 20, weight: '500', fill: C.signal }),
      text('Shot Gloss', 'pixels, only when text isn’t enough', 760, r3[1] - 35, { size: 18, fill: C.ink3 }),
      text('Iterate Label', 'iterate', A3[0] + DISC3 + 18, A3[1] - 18, { font: F.mono, size: 26, weight: '500', fill: C.signal }),
      agent(A3[0], A3[1]),
    ]],
    ['Caption', caption('Woodcase closes the feedback loop: command, view, iterate.',
      'Each pass is one small change and one read. Most checks need no screenshot at all.',
      { width: 960 })],
  ],
};
