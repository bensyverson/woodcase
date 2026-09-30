// S9 — the reveal, in the deck's own light: the stack comes back, and its planes are this
// deck's pages 1–8, beside the log of the writes that made them and the undo that would
// take the last one back.
const G9 = { ox: 1330, oy: 690, s: 0.58, gap: 80, u: 960, v: 540 };
const pages9 = [1, 2, 3, 4, 5, 6, 7, 8].map(n => ({ key: `page ${n}`, label: String(n), image: `./assets/iso-thumb-${n}.png` }));
const rows9 = LOG.map(l => l.replace(/\s+\|\s+/g, '  '));
const half9 = Math.ceil(rows9.length / 2);
const size9 = 13, lh9 = 1.62;

const SLIDE = {
  name: 'S9 Reveal', index: 9, at: 8,
  parts: [
    ['Stack', [stack({ ...G9, planes: pages9 })]],
    ['Log', [
      text('Command', `$ TZ=UTC woodcase activity deck.pen   (${rows9.length} writes)`, 120, 96, { font: F.mono, size: 14, fill: C.ink3 }),
      mono('First', rows9.slice(0, half9), 120, 136, { size: size9, lh: lh9, fill: C.ink }),
      mono('Then', rows9.slice(half9), 530, 136, { size: size9, lh: lh9, fill: C.ink }),
    ]],
    ['Undo', [
      text('Command', UNDO[0], 120, 136 + half9 * size9 * lh9 + 34, { font: F.mono, size: 14, fill: C.ink3 }),
      mono('Answer', UNDO.slice(1), 120, 136 + half9 * size9 * lh9 + 64, { size: size9, lh: lh9, fill: C.signal }),
    ]],
    ['Caption', caption('Of course, this deck was built with Woodcase.',
      'Every page, and the log of every write that made it.',
      { width: 900 })],
  ],
};
