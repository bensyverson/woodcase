# Selecting inside a component instance: two causes, not one

*2026-08-30 — from the viewer review (`job` leaf ShaCv).*

Ben's review reported three symptoms and one suspicion: clicking an element inside a
component instance selected nothing in the outline; the same one level deeper; the Details
pane sometimes answered `'224Gu/oqIX' names no node in this file`; and the suspected root
cause was "expansion id-paths not agreeing between the render overlay, the outline rows
and the details endpoint".

The suspicion is half right. There are **two independent causes**, and only one of them is
an id-path disagreement.

## 1. The outline did not walk into instances

`ViewState.expand` defaulted to `false` and `ArtboardPageBuilder.rows` passed it to
`TreeView.rows(expandInstances:)`, so a `ref` was one row with nothing under it. The
render is always drawn from the **expanded** document, so every node inside an instance is
on screen and clickable — and a click on one selected `Card1/Ttl03`, which no row carried.

What made this read as an id-path bug is that the outline *did* show the component's whole
tree: a reusable definition is a root node, so `CardC → Grp01 → Ttl03` is listed at top
level, under its authored ids. It looks like the row is right there and the click missed.

**Fixed** by deleting `ViewState.expand` and always passing `expandInstances: true` in the
viewer. The knob had no UI, and an outline that can disagree with the render about what
exists is not a preference. `tree --expand` and `/files/{file}/tree.json?expand=` keep the
flag: a text listing has a reason to be short.

## 2. An instance root has two spellings

`PenRefExpander.prefixIDs` roots a clone at `<refID>/<componentRootID>` — the instance
`Card1` of `CardC` is `Card1/CardC`. `ArtboardLayout` copied expanded ids verbatim, so
that is what a click on the instance's own frame selected. But:

- `TreeView` names that row `Card1` (the `ref`), not `Card1/CardC`;
- `EditableDocument.resolve` has **no step onto a component root** — stepping through a
  `ref` lands on the component's *children* — so `Card1/CardC` throws `addressNotFound`.

That throw is the pane's "names no node in this file" verbatim, and `224Gu/oqIX` in the
report is a ref id followed by a component root id. Descendants were never affected:
`Card1/Ttl03` and `Card1/Btn02/Lbl02` are both the id-path `tree --expand` prints and the
prefixed id expansion produces, which is why only *some* selections failed.

**Fixed** in `ArtboardLayout.address(of:under:)`: a box whose instance prefix is longer
than its parent's is a clone root and takes the prefix — the `ref`'s id-path — as its id.
The rule is read off the expanded ids alone, so it needs no second walk of the authored
tree and no assumption about nesting depth. `EditableDocument.expandedID(of:)` already
performs the same translation in the other direction, which is why Details has always
worked when the *outline row* was clicked.

`InstanceSelectionTests` asserts the invariant rather than the two cases: every box in an
artboard's layout has a row in the outline, and every box resolves to details. Reproduce
with `swift test --filter InstanceSelectionTests`.

## Not fixed here

`PreparedDocument.artboardIDs(containing:)` still misses a write to a ref node's own id
(`project/gotchas.md`, 2026-08-30). It matches an authored id against the expanded tree
exactly or by the id-path's last component, and a top-level-or-nested `ref` matches
neither. Same family, different pipeline — the change log's, not the viewer's.
