// S10 — install: the stack closed up into one slab, and the one command to try it.
const G10 = { ox: 1290, oy: 250, s: 0.8, gap: 8 };

// Two steps, two voices: a shell command, then a sentence typed to an agent, set in a
// composer field rather than as a shell line.
const brew10 = text('Command', '$ brew install bensyverson/tap/woodcase', 0, 0, { font: F.mono, size: 30, weight: '500', fill: C.ink });
delete brew10.x; delete brew10.y;
const ask10 = {
  type: 'frame', name: 'Prompt', layout: 'horizontal', gap: 16, alignItems: 'center',
  padding: [18, 26], cornerRadius: 16, fill: C.paper, stroke: C.ink4, strokeWidth: 1,
  effect: [{ type: 'shadow', shadowType: 'outer', offset: { x: 0, y: 8 }, blur: 24, color: '#0E111714' }],
  children: [
    text('Mark', '›', 0, 0, { size: 34, weight: '600', fill: C.signal }),
    text('Ask', 'Use woodcase to design a settings screen for my app.', 0, 0, { size: 30, fill: C.ink }),
  ].map(t => { delete t.x; delete t.y; return t; }),
};

const SLIDE = {
  name: 'S10 Install', index: 10,
  parts: [
    ['Stack', [stack({ ...G10, thick: 4, construction: false })]],
    ['Caption', caption('Install it, then tell your agent to use it.', null,
      { width: 1100, evidence: [brew10, ask10] })],
    ['Facts', [text('Facts', 'Swift 6  ·  macOS 15+ and iOS 18+ for rendering  ·  MIT licensed', 1160, 1000 - 16, { font: F.mono, size: 13, fill: C.ink3, width: 640, align: 'right' })]],
  ],
};
