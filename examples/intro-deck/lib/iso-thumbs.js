// Adds this deck's own slides to build/planes.pen, each turned 45° like the engine's
// planes, so the reveal can stack them.
// woodcase js build/planes.pen -F build/data.js -F lib/helpers.js -F lib/planes.js -F lib/iso-thumbs.js

const TU = 960, TV = 540;
for (let n = 1; n <= 7; n++) {
  const side = (TU + TV) / ROOT2;
  doc.add(null, {
    type: 'frame', name: `Iso thumb ${n}`, layout: 'none', x: (n - 1) * (side + 100), y: 2000, width: side, height: side,
    children: [{
      type: 'frame', name: `Thumb ${n}`, layout: 'none', x: TV / ROOT2, y: 0, rotation: -45, width: TU, height: TV,
      fill: { type: 'image', url: `./thumbs/slide-0${n}.png`, mode: 'stretch' },
    }],
  });
}
null;
