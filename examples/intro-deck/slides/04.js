// S4 — tree, close: the camera drops onto the layout plane, flat, beside the command that
// printed it. Every box and tag on the plane is a rect `tree` reported; the header's row
// is joined to the header's box.
const Z4 = 2.0;
const Q4 = DATA.quotes.treeHeader;
const size4 = 17, lead4 = size4 * 1.8, top4 = 300;
const rowY4 = top4 + 3 * lead4 + size4 * 0.62;
const header4 = DATA.boxes.find(b => b.address === 'banking-home/header');
const plane4Y = rowY4 - (header4.y + header4.h / 2) * Z4;
const plane4X = 1920 - U * Z4 - 96;
const tag4 = b => b.depth === 1 || (['hdrL', 'hdrN', 'bellBtn'].includes(b.name) && b.address.startsWith('banking-home/header'));
const plane4 = layoutPlane('Layout Plane', Z4, { x: plane4X, y: plane4Y, lit: true, stroke: 1.5, tagSize: 6.4, tagFilter: tag4, fill: '#F5F6FF' });
plane4.effect = [{ type: 'shadow', shadowType: 'outer', offset: { x: 0, y: 24 }, blur: 60, color: '#0E111729' }];
const rowEnd4 = 120 + Q4[3].replace(/\s+$/, '').length * size4 * 0.655;

const SLIDE = {
  name: 'S4 Tree', index: 4,
  parts: [
    ['Plane', [plane4]],
    ['Output', [mono("Tree Out", Q4, 120, top4, { size: size4, lh: 1.8, color: (l, i) => i === 0 ? C.ink3 : (i === 3 ? C.signal : C.ink) })]],
    ['Link', [
      rect('Header Mark', plane4X + header4.x * Z4, plane4Y + header4.y * Z4, header4.w * Z4, header4.h * Z4, { stroke: C.signal, strokeWidth: 4 }),
      arrow('Row To Box', [rowEnd4 + 24, rowY4], [rowEnd4 + 120, rowY4], [plane4X - 110, rowY4], [plane4X - 3, rowY4]),
    ]],
    ['Caption', caption(codeTitle([[['woodcase tree', true], ['turns a layout', false]], [['into text an agent can', false]], [['read and act on.', false]]]),
      'One row per box: its type, name, position and size, and an id the next command can target.',
      { width: 860 })],
  ],
};
