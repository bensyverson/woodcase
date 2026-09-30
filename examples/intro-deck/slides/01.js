// S1 — the cover: the stack whole, every plane named, and what Woodcase is.
const HOME = { ox: 1590, oy: 650, s: 0.62, gap: 118 };

// The cover's title is the deck's first sentence, set large; the name leads it in bold.
function titleSlide1() {
  const size = 104;
  const line = (name, runs) => ({
    type: 'frame', name, layout: 'horizontal', gap: size * 0.26,
    children: runs.map(([content, weight], i) => titleText(`Run ${i + 1}`, content, { size, weight })),
  });
  return {
    type: 'frame', name: 'Title', layout: 'vertical', x: 112, y: 96,
    children: [
      line('Line 1', [['Woodcase', '600'], ['is the design', '500']]),
      line('Line 2', [['layer for agents.', '500']]),
    ],
  };
}

const SLIDE = {
  name: 'S1 Title', index: 1,
  parts: [
    ['Stack', [stack({ ...HOME, labels: true })]],
    ['Title', [titleSlide1()]],
    ['Caption', caption(null,
      'An engine for .pen files, the format of Pen. Agents run it from a terminal, you watch it in a browser, and apps build it in as a Swift library.',
      { width: 780 })],
  ],
};
