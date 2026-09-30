// S5 — JavaScript: the camera pulls far back, so the whole stack fits inside one
// transaction. The script beside it measured its own edit and refused to commit it.
const G5 = { ox: 1600, oy: 430, s: 0.34, gap: 52 };
const b5 = stackBounds(G5);
const Q5 = DATA.quotes;
const L5 = b5.left - 44, R5 = b5.right + 44, T5 = b5.top - 40, B5 = b5.bottom + 44;
const bracket5 = (x, d) => ({ pts: [[x + d, T5], [x, T5], [x, B5], [x + d, B5]] });
const stopY5 = (T5 + B5) / 2;
const out5 = Q5.js.slice(1, -1).map(l => l.replace(/^(\S+\.js:\d+:\d+)\s+/, '$1  '));
const exit5 = Q5.js[Q5.js.length - 1];
const outX5 = 1080, outY5 = B5 + 70;

const SLIDE = {
  name: 'S5 Script', index: 5,
  parts: [
    ['Script', [
      text('Script Label', 'measure.js', 120, 200, { font: F.mono, size: 15, fill: C.ink3 }),
      mono('Source', Q5.script, 120, 240, { size: 17, lh: 1.72, color: l => l.startsWith('//') ? C.ink3 : (/throw/.test(l) ? C.stop : C.ink) }),
    ]],
    ['Transaction', [
      stack({ ...G5, construction: false }),
      path('Bracket', [bracket5(L5, 22), bracket5(R5, -22)], { stroke: C.ink, strokeWidth: 2, cap: 'butt' }),
      text('Bracket Label', 'one transaction', L5, T5 - 36, { font: F.mono, size: 15, fill: C.ink, width: R5 - L5, align: 'center' }),
      path('Stop', [{ pts: circlePts(R5, stopY5, 18, 8), closed: true }], { fill: C.stop }),
      path('Stop Bar', [{ pts: [[R5 - 8, stopY5], [R5 + 8, stopY5]] }], { stroke: C.paper, strokeWidth: 3.5, cap: 'butt' }),
    ]],
    ['Output', [
      text('Command', Q5.js[0], outX5, outY5, { font: F.mono, size: 14, fill: C.ink3 }),
      mono('Run', out5, outX5, outY5 + 36, { size: 14, lh: 1.7, color: l => /nothing was written/.test(l) ? C.ink : (/clips/.test(l) ? C.stop : C.ink3) }),
      text('Exit', exit5, outX5, outY5 + 36 + out5.length * 14 * 1.7, { font: F.mono, size: 14, fill: C.ink3 }),
    ]],
    ['Caption', caption(codeTitle([[['Agents think in code, so', false]], [['woodcase js', true], ['lets them', false]], [['design in code.', false]]]),
      'Code is how agents already work. A script runs as one transaction, so it can check its own edit and refuse it: this one found the new name no longer fit, and nothing was saved.',
      { width: 900 })],
  ],
};
