// Writes build/planes.pen: each plane turned 45° clockwise inside a root sized to its
// turned bounds, so `shot` gives a PNG the stack stretches into its dimetric view
// (turn, then squash: the one affine map a turn and a stretch can make).
// woodcase js build/planes.pen -F build/data.js -F lib/helpers.js -F lib/planes.js -F lib/iso-sources.js

for (const row of doc.tree(null, { depth: 0 })) doc.rm(row.id);

// A root holding one turned frame; the frame's top-left is the turn's pivot.
function isoRoot(name, index, inner, u, v) {
  const side = (u + v) / ROOT2;
  inner.x = v / ROOT2;
  inner.y = 0;
  inner.rotation = -45;
  return { type: 'frame', name, layout: 'none', x: index * (side + 100), y: 0, width: side, height: side, children: [inner] };
}

PLANES.forEach((plane, i) => {
  const inner = PLANE_BUILDERS[plane](`Plane ${plane}`, 1, { base: '../assets', lit: false, labelDepth: 1 });
  doc.add(null, isoRoot(`Iso ${plane}`, i, inner, U, V));
});

// The layout plane lit, for the slides where the loop reads it.
doc.add(null, isoRoot('Iso layout lit', PLANES.length, layoutPlane('Plane layout lit', 1, { lit: true, labelDepth: 1, fill: '#F3F4FFE6' }), U, V));

null;
