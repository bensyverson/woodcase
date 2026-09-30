// S8 — the reveal, in the deck's own light: the stack comes back, and its planes are this
// deck's pages 1–7, beside the log of the writes that made them and the undo that would
// take the last one back.
const G8 = { ox: 1330, oy: 690, s: 0.58, gap: 80, u: 960, v: 540 };
const pages8 = [1, 2, 3, 4, 5, 6, 7].map(n => ({ key: `page ${n}`, label: String(n), image: `./assets/iso-thumb-${n}.png` }));
const rows8 = LOG.map(l => l.replace(/\s+\|\s+/g, '  '));
const half8 = Math.ceil(rows8.length / 2);
const size8 = 13, lh8 = 1.62;

const SLIDE = {
  name: 'S8 Reveal', index: 8, at: 7,
  parts: [
    ['Stack', [stack({ ...G8, planes: pages8 })]],
    ['Log', [
      text('Command', `$ TZ=UTC woodcase activity deck.pen   (${rows8.length} writes)`, 120, 96, { font: F.mono, size: 14, fill: C.ink3 }),
      mono('First', rows8.slice(0, half8), 120, 136, { size: size8, lh: lh8, fill: C.ink }),
      mono('Then', rows8.slice(half8), 530, 136, { size: size8, lh: lh8, fill: C.ink }),
    ]],
    ['Undo', [
      text('Command', UNDO[0], 120, 136 + half8 * size8 * lh8 + 34, { font: F.mono, size: 14, fill: C.ink3 }),
      mono('Answer', UNDO.slice(1), 120, 136 + half8 * size8 * lh8 + 64, { size: size8, lh: lh8, fill: C.signal }),
    ]],
    ['Caption', caption('Of course, this deck was built with Woodcase.',
      'Every page, and the log of every write that made it.',
      { width: 900 })],
  ],
};
