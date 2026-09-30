// Writes one step of one slide, so the deck's log records how each page was put together:
// step 0 is the empty page, and each later step adds one named part of it.
// woodcase js deck.pen … -F slides/NN.js -F build/step.js -F lib/step.js
//
// A slide script defines SLIDE = { name, index, fill?, at?, parts: [[name, nodes], …] };
// build/step.js defines STEP. The result is "done" once the slide has no step STEP.

let STEP_RESULT = 'wrote';
if (STEP === 0) {
  const page = slide(SLIDE.name, SLIDE.index, [], SLIDE.fill ? { fill: SLIDE.fill } : {});
  doc.add(null, page, SLIDE.at === undefined ? {} : { at: SLIDE.at });
} else if (STEP <= SLIDE.parts.length) {
  const [name, nodes] = SLIDE.parts[STEP - 1];
  const node = Array.isArray(nodes) ? group(name, nodes) : Object.assign(nodes, { name });
  doc.add(SLIDE.name, node);
} else {
  STEP_RESULT = 'done';
}
STEP_RESULT;
