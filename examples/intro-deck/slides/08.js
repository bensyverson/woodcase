// S8 — in the open: the viewer, in dark mode, following the agent through the banking
// screen seconds after its writes, their markers still up. Each mark is drawn where the
// page drew the thing it names (build/dash.js), and labeled from outside the shot, so the
// shot stays legible.
const X8 = 620, Y8 = 96, K8 = 1200 / DASH.w;
const at8 = b => ({ x: X8 + b.x * K8, y: Y8 + b.y * K8, w: b.w * K8, h: b.h * K8 });
const live8 = at8(DASH.marks.live), act8 = at8(DASH.marks.activity), out8 = at8(DASH.marks.outline);
const pad8 = 6;
const mark8 = (name, b) => rect(name, b.x - pad8, b.y - pad8, b.w + 2 * pad8, b.h + 2 * pad8, { stroke: C.signal, strokeWidth: 3, radius: 6 });
const lead8 = (name, a, b) => path(name, [{ pts: [a, b] }], { stroke: C.signal, strokeWidth: 2, cap: 'butt' });

// A label: the word in the signal color, and what it means beneath it.
function label8(name, word, gloss, x, y, align) {
  const o = { width: 420, align };
  return group(name, [
    text('Word', word, align === 'right' ? x - 420 : x, y, { font: F.mono, size: 20, weight: '500', fill: C.signal, ...o }),
    text('Gloss', gloss, align === 'right' ? x - 420 : x, y + 34, { size: 21, fill: C.ink2, ...o }),
  ]);
}

const serve8 = text('Command', '$ woodcase serve banking.pen', 0, 0, { font: F.mono, size: 22, weight: '500', fill: C.ink });
delete serve8.x; delete serve8.y;
const outY8 = out8.y + out8.h / 2;

const SLIDE = {
  name: 'S8 Open', index: 8, at: 7,
  parts: [
    ['Viewer', [
      { type: 'frame', name: 'Shot', layout: 'none', x: X8, y: Y8, width: DASH.w * K8, height: DASH.h * K8, cornerRadius: 10, clip: true,
        fill: [C.paper, { type: 'image', url: './assets/dashboard.png', mode: 'stretch' }], stroke: C.ink4, strokeWidth: 1,
        effect: [{ type: 'shadow', shadowType: 'outer', offset: { x: 0, y: 24 }, blur: 60, color: '#0E111729' }] },
    ]],
    ['Marks', [
      mark8('Live', live8),
      mark8('Every Write', act8),
      mark8('Every Node', out8),
    ]],
    ['Labels', [
      label8('Live', 'live', 'follows the agent as it writes', live8.x + live8.w + pad8, Y8 - 86, 'right'),
      lead8('Live Lead', [live8.x + live8.w / 2, Y8 - 14], [live8.x + live8.w / 2, live8.y - pad8]),
      label8('Every Write', 'every write', 'who made it, what it touched, when', act8.x + act8.w + pad8, Y8 + DASH.h * K8 + 44, 'right'),
      lead8('Write Lead', [act8.x + act8.w / 2, act8.y + act8.h + pad8], [act8.x + act8.w / 2, Y8 + DASH.h * K8 + 34]),
      label8('Every Node', 'every node', 'the tree the agent reads, by id', X8 - 48, outY8 - 30, 'right'),
      lead8('Node Lead', [X8 - 36, outY8], [out8.x - pad8, outY8]),
    ]],
    ['Caption', caption('Your agent works in the open.',
      'A live, read-only view in your browser: every page, every write, every node.',
      { width: 470, evidence: [serve8] })],
  ],
};
