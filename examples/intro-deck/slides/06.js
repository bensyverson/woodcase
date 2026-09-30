// S6 — built with its users: a refused write, set so the sentence's second half (the part
// that tells you what to do) reads as the tool's annotation, then the command it named,
// then what that command drew.
const Q6 = DATA.quotes;
const msg6 = Q6.refused[1];
const cut6 = msg6.indexOf(' — ');
const said6 = msg6.slice(0, cut6 + 2);
const told6 = msg6.slice(cut6 + 3);
const exit6 = Q6.refused[Q6.refused.length - 1];
const W6 = 1060;

const primer6 = text('Primer', 'woodcase help design', 0, 0, { font: F.mono, size: 22, weight: '500', fill: C.ink });
delete primer6.x; delete primer6.y;

const SLIDE = {
  name: 'S6 Users', index: 6,
  parts: [
    ['Refusal', [
      text('Command', Q6.refused[0], 120, 110, { font: F.mono, size: 18, fill: C.ink3 }),
      text('Said', said6, 120, 160, { font: F.mono, size: 22, fill: C.ink, width: W6, lh: 1.5 }),
      text('Told', told6, 120, 262, { font: F.mono, size: 22, fill: C.signal, width: W6, lh: 1.5 }),
      text('Exit', exit6, 120, 372, { font: F.mono, size: 18, fill: C.ink3 }),
    ]],
    ['Fix', [
      arrow('Named', [108, 292], [56, 292], [56, 492], [110, 492]),
      text('Command', Q6.fixed[0], 120, 478, { font: F.mono, size: 22, fill: C.ink }),
      mono('Answer', Q6.fixed.slice(1), 120, 524, { size: 16, lh: 1.6, fill: C.ink3 }),
    ]],
    ['Result', [
      text('Label', 'shot, after the override', 1220, 432, { font: F.mono, size: 14, fill: C.ink3 }),
      { type: 'frame', name: 'Quick Actions', layout: 'none', x: 1220, y: 470, width: 600, height: 600 * DATA.quickActions.h / DATA.quickActions.w,
        fill: [C.paper, { type: 'image', url: './assets/quick-actions-after.png', mode: 'stretch' }], stroke: C.ink4, strokeWidth: 1,
        effect: [{ type: 'shadow', shadowType: 'outer', offset: { x: 0, y: 12 }, blur: 30, color: '#0E11171F' }] },
    ]],
    ['Caption', caption('No Skill needed: agents learn Woodcase by using it.',
      'Each refusal names the command that works, like the one above. For everything else, the tool carries its own primer:',
      { width: 1100, after: [primer6] })],
  ],
};
