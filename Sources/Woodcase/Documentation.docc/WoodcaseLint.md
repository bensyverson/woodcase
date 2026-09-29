# Linting a Document

Find what is wrong with a .pen file before rendering it.

## Overview

``DocumentLinter`` answers one question: *what about this document will not come out
the way it was authored?* It is a read — it opens nothing, writes nothing, and reports
what a renderer would do rather than what the file says — and it is the cheapest
review of a design an agent can run, because it needs no pixels.

```swift
let findings = try await PenFileTransaction.read(at: url) { document in
    try DocumentLinter.findings(in: document, theme: ["mode": "dark"])
}
print(LintFormatter.text(findings.value))
// warning clipped  Card/Title (x9Kqp)  20,80 160×24 sits partly outside Card (200×100).
```

The `woodcase lint` verb is a thin wrapper over exactly this: it prints
``LintFormatter/text(_:)`` (or ``LintFormatter/json(_:)``) and exits 1 when there is
anything to report, so `woodcase lint design.pen && woodcase render design.pen`
renders only a file that passed.

Two reads are about the *checks* rather than about one file. `lint --list` prints the
catalog — every ``LintCheck`` with its severity and its ``LintCheck/summary`` — and
reads no file at all, so an agent can discover the rules before it has a document:

```text
$ woodcase lint --list
warning pipeline  A diagnostic from the parse, migration, font or render pipeline.
error broken-ref  A component instance whose component this document does not define.
…
```

`lint --summary` runs the same checks over the same file and reports one row per check
that fired, with a count, instead of one line per finding — the read for a file with
sixty of them. A check that found nothing has no row:

```text
$ woodcase lint design.pen --summary
warning clipped  57
error unknown-icon  2
```

Both keep ``LintFormatter``'s line shape (severity, check id, two spaces, payload), both
take `--json` (an array of ``LintCheckDescription`` for `--list`, an object keyed by
check id for `--summary`), and both narrow with `--exclude` and `--severity`. `--list`
refuses a file, a subtree and `--theme`, and refuses to run with `--summary`: it settles
no document, so accepting any of those would be accepting an argument it ignores.

## The checks

| Check | Severity | Fires when |
|---|---|---|
| `pipeline` | the diagnostic's | The caller hands in a ``PenDiagnostic`` |
| `broken-ref` | error | A `ref` names a component neither the document nor its imported libraries define |
| `import-not-found` | error | An `imports` entry has no library to read: no file at the path (relative to the document, and nowhere else), a library bundled with Pen (``PenLibraries/bundledScheme``), or a location that is not a file |
| `import-unreadable` | error | An `imports` entry names a file that is not a readable .pen document |
| `import-not-followed` | warning | An imported library itself imports another, which Pen does not follow |
| `unresolved-variable` | error | A property still holds `$name` after resolution |
| `text-without-fill` | warning | A text node declares no fill, so it draws nothing, as Pen draws it |
| `text-overflow` | warning | A text node's box cannot grow and is too short for its content |
| `collapsed-text` | warning | A text node's settled width or height is zero while its content is not |
| `fill-in-fit-parent` | warning | `fill_container` under a `fit_content` parent on the same axis |
| `empty-fit-content` | warning | A `fit_content` container that is not a slot has no children |
| `collapsed-absolute-frame` | warning | A `layout: none` frame with children has no width or height, so it settles at 0 on that axis, as Pen settles it |
| `clipped` | warning | A node's settled rect falls outside its parent's, on an axis no scroll annotation declares |
| `unknown-icon-library` | error | An `icon` node's library is not one this build bundles or knows |
| `unknown-icon` | error | An `icon` node's name is not in its library's codepoint table |
| `artboard-overlap` | warning | Two roots' settled rects sit on top of each other |
| `duplicate-name` | warning | Two children of one parent share a name |
| `override-value-rejected` | error | A `ref`'s stored override carries a value the descendant it patches cannot decode |
| `override-target-not-found` | error | A `ref`'s stored override key names no descendant Pen lets it reach, so Pen drops it |
| `override-key-unread` | error | A `ref`'s stored override carries a property path (`kind.content`) instead of the raw .pen key the merge reads |
| `codegen-prop-path` | error | A reusable node's `_props` entry is not a path, names no descendant, or reads a field another entry already reads |
| `codegen-role` | error | A `_role` value is outside ``ComponentRole`` |
| `codegen-unmapped-override` | warning | An instance overrides a descendant no declared prop reads |
| `mesh-gradient-dropped` | error | A mesh gradient's `points` or `colors` do not number `columns × rows`, one of the four is missing, the grid is under 2×2, or a point is malformed in a way Pen cannot place: Pen paints nothing |
| `mesh-gradient-distorted` | warning | A mesh gradient has a color Pen's mesh misreads (4-digit `#RGBA`, a word), a patch that folds over itself, or a malformed point Pen places its own way |
| `text-style-stripped` | warning | A text node carries a stroke, `underline: true` or `strikethrough: true`, which Pen strips on load and never draws |
| `shader-not-drawn` | warning | An enabled shader fill, in a node's fills or its stroke, which Pen runs and Woodcase does not draw on any target |
| `per-side-stroke-on-shape` | warning | An ellipse, polygon, path or line with a stroke paint and a per-side `strokeWidth` whose sides differ from its `top`, or that has no `top`: Pen draws the `top` width alone, all round |

The two sizing checks fire only where the engine has *nothing to fall back on*:
`fill_container(200)` under a `fit_content` parent, and `fit_content(200)` with no
children, both resolve to 200 and are left alone. Without a fallback the empty
`fit_content` resolves to 0, and the parent of a `fill_container` sizes without it while
the fill gets Pen's 1-pt floor and overflows it — which `clipped` reports on the same node
(`flex-fill-squeeze.pen`; Pen lays it out the same way). That is the bug being reported.

`empty-fit-content` makes one further exception: a **slot** frame — one a component
marks with `slot`, which ``TreeRow/isSlot`` reports — is empty by design, because its
children come from each instance's `children` override rather than from the definition.
Reporting one would be the check firing at the feature, and it is what taught writers
that a component with a hole in it was a mistake.

The two icon checks are `error`, not `warning`, for the same reason `broken-ref` is:
an unresolved library or name draws nothing at all, exactly like an instance of a
missing component. `unknown-icon` proposes up to five names — the same ranking
`woodcase icons` prints — from ``IconNameMatcher``, over ``PenIconFontRegistry``'s
bundled and registered tables; see <doc:PenIconFonts>.

## Agreeing with the tree

The geometric checks run over ``TreeView``'s own rows, so ``TreeRow/clip`` and
``TreeRow/overflowAxes`` are read rather than recomputed: `tree`'s own flags are never
re-derived with different arithmetic. `tree` always shows every geometric overflow —
what `clipped` does not always do is turn every one of them into a *finding*: a
designed scroll can exempt a child, and several children can fold into one finding on
their frame, without either changing what `tree` reports about the child's own rect.
See Scroll axes, below. Sizing questions go the same way, to
`PenLayoutEngine.widthSizing(of:)`, which answers with the defaults the layout pass
actually applies — an absent `width` is `fit_content`, and a `group` is always
`fit_content` around its children.

### One tolerance, at a hundredth of a point

``TreeRow/clipTolerance`` is the slack every geometric comparison carries: **0.01 pt**.
It exists because *landing exactly on an edge is the common case, and binary floating
point does not land exactly*. Sixty `fill_container` bars at gap 2 across a 350-point
frame divide it evenly; the last bar settles at `346.13 + 3.87`, which is 350 in
decimal and a few parts in 10¹³ past 350 in a `Double`. Without the tolerance every
such row read as a clipped design, which is the most common thing a bar chart or a
segmented control *is*.

A hundredth of a point is far below anything a renderer or a reader can see, and far
above the residue of a division, so the two never meet. Anything a design actually
means — a half-point overflow included — is still reported.

There is one constant, on ``TreeRow``, because ``TreeRow/clip`` is computed with it
once and this file's `clipped` check reads the flag rather than deciding again.
``RootOverlap`` uses the same number for the same reason: two artboards laid edge to
edge are not overlapping.

## Scroll axes

A clipping frame — `clip:true` — that overflows is not always a bug: a row five
screens down a scrolling list is designed to sit outside the fold. `common.metadata`
carries a `_scroll` extension key for saying so, following the `_role`/`_props`
underscore-key convention ``ComponentAnalyzer`` already reads: set it to `"vertical"`
or `"horizontal"` on the clipping frame, and `clipped` treats an overflow along that
axis as designed rather than as a finding.

```bash
woodcase set design.pen banking-home/list common.metadata._scroll=vertical
```

The deep key merges one entry into `common.metadata` and leaves `_role`, `_props` and
anything else set there alone (see <doc:WoodcaseEditor>); writing the whole object would
drop them. Every `clipped` finding proposes the command in this form.

**A child whose overflow is only the declared axis is not a finding**, however far
past the fold it goes:

```text
$ woodcase lint design.pen
# nothing, once List declares _scroll=vertical and its rows only overflow downward
```

**A child that also crosses the cross axis keeps its finding**, worded exactly as an
unannotated one — a row that spills sideways as well as down is not what the
annotation described:

```text
warning clipped  List/Row12 (Rw012)  0,600 320×48 sits partly outside List (320×400). Part of it is cut off if the parent clips.
```

**An unannotated clipping frame that stacks its children** — `layout: vertical` or
`layout: horizontal` — folds every child whose overflow is exactly that stacking axis
into one finding on the frame, rather than one per row. This is deliberate: a
sixty-bar histogram or a long list produces one finding, not sixty, and the finding
proposes the exact fix:

```text
warning clipped  List (Lst01)  57 children continue 2280pt past the fold on the vertical axis, and List clips them. A designed scroll? Run `woodcase set <file> List common.metadata._scroll=vertical` to say so.
```

"Past the fold" is measured from the farthest child, not summed across all of
them — the number answers "how far would a reader have to scroll," not "how many
points of content exist." A child that also overflows the cross axis is excluded from
the fold and keeps its own individual finding instead. A freeform frame
(`layout: none`) has no single stacking axis, so nothing here collapses; every
overflowing child is reported on its own, exactly as before `_scroll` existed.

**An invalid `_scroll` value** — anything but `"vertical"` or `"horizontal"` — is its
own finding, on whatever node carries it, on top of whichever behavior above applies
as though the key were absent:

```text
warning clipped  List (Lst01)  declares common.metadata._scroll="diagonal", which is not a designed scroll axis. Valid values are "vertical" and "horizontal".
```

**The check id stays `clipped`.** Every finding here — suppressed, collapsed, or
about an invalid value — is still "this rect doesn't fit," reported differently rather
than as a different kind of problem, so `--exclude clipped` continues to exclude all
of it with no second id to remember.

## Artboards

`artboard-overlap` is the one check that is about the canvas rather than about a node
and its parent. A document's roots are artboards; two on top of each other hide one
another in every view that shows the whole file, and nothing in the format says which
is on top, so there is no reading of the overlap that is correct.

One finding per intersecting pair, reported on the **later** root of the two — the one
a remedy moves, and the one a caller most likely just wrote — naming both roots, both
rects, and the first `x` that clears the other by ``RootOverlap/margin``:

```text
warning artboard-overlap  Checkout (Chk01)  150,40 200×100 overlaps Home (Home1) 0,0 200×100. Artboards do not overlap: run `woodcase set <file> Chk01 common.x=300` to put it clear by 100pt.
```

The `<file>` in that command is literal: a lint is handed a document, not a path, and a
command with a wrong path in it teaches worse than one with a blank. The `woodcase`
verbs that write substitute the real path when they print the same sentence — see
<doc:WoodcaseEditor>. Sharing an edge exactly is not an overlap, and neither is a
lint scoped to one subtree, which lists no second root to pair with.

## Names

`duplicate-name` is the other check that is about the listing rather than about one
node and its parent — but where `artboard-overlap` is about the canvas,
`duplicate-name` is about **addressing**. It reports two nodes that share a name *and a
parent*, because those are the only two a name path cannot separate.

A name path is a run of consecutive parent→child steps whose first segment may be any
node in the document (``EditableDocument/resolve(_:tags:)-(String,_)``). So a `TopBar`
under `Files` and a `TopBar` under `Following` cost one extra segment and nothing else:
`Files/TopBar` names exactly one node, and the bare `TopBar` fails with
``EditingError/ambiguousAddress(address:candidates:)`` listing both candidates by full
path — an error that hands over the fix. Two `TopBar`s under the *same* parent have no
extra segment to reach for: every path that reaches one reaches the other, however far
back it starts, and only a rename or an id fixes it.

```text
warning duplicate-name  Files/TopBar (FL002)  shares the name "TopBar" with its sibling Files/TopBar (FL001); siblings are the one case no name path separates, because every address that reaches one reaches the other. Rename one, or address either directly by id (`#FL001` / `#FL002`). Two same-named nodes under different parents are fine — an address may start at any node, so one more segment tells those apart.
```

One finding per node after the first occurrence of a name among one parent's children,
reported against the first. Three siblings sharing a name are two findings, not three:
a full pairwise listing would repeat the same advice once per extra pair for no new
information. A node with no name never collides — it is addressed by id alone.

> Important: this check was document-wide until 2026-09-02. The argument for that scope
> — `resolve` matches a bare name anywhere, so any shared name is a latent ambiguity —
> was wrong, not merely wider: it treated the bare name as the only address a caller
> could write. It also had a cost. Agents working under it prefixed every node on every
> board (`Masthead Top Row Title`) to keep the lint quiet, which is the opposite of the
> taught style: **short names, unique among siblings**. See
> `project/2026-09-02-teach-the-cli-what-it-does.md`.

**Scope.** Siblings are read off the listing — a row's parent is the nearest earlier row
at a shallower depth — so a document's roots are siblings of one another, and a lint
scoped to a subtree judges the rows that subtree puts in the listing. Scope matters far
less than it did under the wide check: two siblings are either both in the listing or
both out of it, unless the scope root *is* one of them.

## Text that does not fit

`text-overflow` is the one check about content disappearing rather than looking wrong.
Two halves of the pipeline agree to it. `PenLayoutEngine.layoutLeafNode` skips text
measurement entirely for a `fixed-width-height` node, so the box keeps the size the
file declares however much text is in it; and `PenTextRenderer` lays the text into a
frame of exactly that height, where Core Text composes **whole lines** and stops when
the next one would not fit. The overflow is not clipped — a half-line a reader can see
and diagnose — it is absent, and a screenshot of the design looks like a design that
says less than it does.

The check re-measures the settled text at the settled width, with the same
``PenLayoutEngine/defaultTextMeasurer`` the layout used, and reports the difference in
points along with both fixes:

```text
warning text-overflow  Card/Body (Bdy01)  needs 57pt of height for its text at 200pt wide, but its box is 40pt tall and cannot grow: 17pt of text falls outside it. A renderer composes whole lines and drops the ones past the bottom edge, so the overflow does not show at all. Run `woodcase set <file> Bdy01 kind.height=57` for a box that fits, or `woodcase set <file> Bdy01 kind.height=fit_content kind.textGrowth=fixed-width` to let it grow with its content.
```

A box "cannot grow" in two ways, and the layout engine draws the line at both: a
`fixed-width-height` growth skips measurement altogether, and any height that is not
`fit_content` — a number, or a `fill_container` a parent settles — is the file's answer
rather than the text's. `kind.textGrowth` alone is not the fix for the first case,
which is why the remedy names both paths: a `fit_content` height with
`fixed-width-height` growth still resolves without measuring.

**Only height.** Width alone can never overflow, because the renderer wraps at the box
width: a `fixed-width` node's text rewraps to fit and pushes the height instead. A
zero-width box is skipped — there is no wrap width to measure against, and the answer
would be an arbitrarily large number rather than a useful one.

## Text that collapses to zero

`collapsed-text` is what a zero-width box turns into instead of a `text-overflow`
finding: `text-overflow` explicitly skips it, because a box with no width has no wrap
width to measure against. This check is that skip's complement, and it covers height
too — a text node can settle to zero on either axis, and this is the only check that
says so.

`PenLayoutEngine.layoutLeafNode` resolves a leaf's width from `kind.width` alone,
before it ever looks at the text: a measurement only *overrides* that resolution when
`kind.textGrowth` says the axis should follow the text. `fixed-width` growth holds the
width to `kind.width` and never overrides it; `fixed-width-height` growth never
measures either axis, the same skip the section above describes for height under
`text-overflow`. Left at `fit_content` — a sizing mode that means "measure the
content" — with no numeric fallback, there is nothing left to resolve it to but 0. The
text is real; the box is not, and a renderer composes into a frame with no room to
draw it, showing at most a sliver of a glyph.

```text
warning collapsed-text  Card/Title (Ttl01)  settles to 0pt wide because kind.textGrowth=fixed-width holds its width to kind.width, and kind.width=fit_content has nothing to fall back on, so the layout engine resolves it to 0 instead of measuring the text. Run `woodcase set <file> Ttl01 kind.width=<value>` with a number, or `woodcase set <file> Ttl01 kind.textGrowth=auto` to let width follow the text.
```

`auto` growth never collapses either axis — it is the growth that always measures both
from the text — so the finding's second remedy is always to switch to it. The first
remedy is always a number on the axis that collapsed. A `fit_content` axis that
carries a numeric fallback (`fit_content(200)`) is clean for the same reason
`empty-fit-content` leaves one alone: the engine has something to fall back on, so it
never resolves to 0 in the first place.

## Absolute frames with no size

A `layout: "none"` frame places its children at their own `x`/`y`, so `fit_content` has
no flow to measure: Pen settles the axis at its fallback — 0 when there is none — and
never around the children, and re-saves a missing width or height as `fit_content(0)`.
Woodcase settles it the same way (see <doc:PenEngine>, "Absolute containers and
`fit_content`"). The children still draw, overhanging the frame's point, but the frame's
own fill has no area, `clip: true` hides every child, and in a flex parent the frame takes
no room, so the sibling after it lands on its children. `collapsed-absolute-frame` names
the axes that collapse:

```text
warning collapsed-absolute-frame  Board/Layer (Frm01)  is layout:none with no width or height, so it settles at 0×0, as Pen settles it: fit_content on an absolute frame is its fallback, not its children's union. Its children still draw, but its fill is invisible, clip hides its children, and it takes no space in a flow. Give it a size: `woodcase set <file> Frm01 kind.width=<value> kind.height=<value>`.
```

A fallback other than 0 (`fit_content(120)`) is clean: the author chose the size. A frame
with no children is `empty-fit-content`'s finding, and a group is never one — it takes its
children's union.

## Overrides a file already carries

Since d893dd0 the *write* path refuses an override that would be dropped on the way to
the pixels: a value the descendant it patches cannot decode
(``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``), or a
key naming no descendant at all
(``EditingError/overrideTargetNotFound(refID:descendantKey:candidates:)``). Neither guard
runs on a file that reaches Woodcase already carrying the fault — an import, or a file
the editor itself wrote — because there was no write to refuse it at.
``PenNodePatcher/patchNode(_:with:)`` stays tolerant at expansion time on purpose: it
falls back to the *unpatched* node rather than refuse to render a file Woodcase did not
write. These three checks are the read side of that tolerance:

```text
error override-value-rejected  Root/BadValue (Rf001)  stores `content` on Root/BadValue/Label as an override, but it takes a string or a $variable and the stored value is an object. An override a node cannot take is dropped silently when the instance expands, so it never draws. Run `woodcase override <file> Rf001/Lbl01 content=<value>` with one it can take.
error override-target-not-found  Root/Invalid (Rf002)  stores an override keyed `NoSuch`, but NoSuch is not in the component Invalid instantiates; the override is stored and never applies. It contains: Root/Invalid/Component (Rf002/Cmp01), Root/Invalid/Label (Rf002/Lbl01). Run `woodcase override <file> Rf002/<name> key=value` to address one of them.
error override-key-unread  Root/Stale (Rf001)  stores `kind.content` on Root/Stale/Label as an override, but a `descendants` map is keyed by the raw .pen name, not a property path — the merge does not read `kind.content` and silently drops it. Run `woodcase override <file> Rf001/Lbl01 content=<value>` to store it under the name the merge reads.
```

`override-key-unread` catches a third fault neither write-time guard does: a property
stored under a dotted path (`"kind.content"`) instead of the raw .pen key
(`"content"`) a merge reads. Every `override` since d893dd0 rekeys through
``NodePropertyCodec/rawKeyed(_:)`` before it is stored, so only a file written before
that fix carries the literal path — and a dotted key decodes as a harmless
unrecognized field, so the merge succeeds and the override is dropped with no error at
all. ``PenNodePatcher/patched(_:with:)`` has nothing to catch it with, which is why
this check reads the key itself rather than judging a merge.

`override-target-not-found` judges a key by the rule Pen applies it by, not only by the
one key an address yields: a bare id naming a node the component wrote into a nested
instance's slot, or a path stepping through a frame, is a key Pen applies and the
expansion draws, so it is no finding — see "Pen accepts other spellings of some keys"
in <doc:EditingDocuments>. A key Pen itself drops on re-save is one — including a key
naming content the instance wrote into a slot itself, which exists and draws but which
Pen never lets the same instance override. Woodcase never writes one — `override` on
that address rewrites the change into the slot's `children` — so the finding names the
slot and gives that command as the remedy.

All three read a ref's own `descendants` map, the same way `unresolved-variable` does —
see Instances, below — rather than expanding the instance, so a component is still
linted once, at every `ref` node that carries one, wherever in the document it sits.

## What Pen does to the file

Five checks describe **Pen's** behavior rather than Woodcase's, so a file Woodcase
writes is never one Pen opens badly. Each was observed with Pen itself — the 1.2.14 desktop app
and the headless `pen` CLI — by loading a probe file, reading back what Pen kept, and
exporting what it draws (`project/2026-09-26-what-pen-drops-from-a-file.md`).

`mesh-gradient-dropped` is an error. A mesh whose `points` or `colors` do not number
`columns × rows`, or that is missing one of the four keys, is **removed** when Pen opens
the file — it is gone from Pen's next save. A grid of one row or one column is kept
and paints nothing: no patch spans it. So is a mesh with a point Pen cannot place — a
short array such as `[1]`, a non-number entry, or a `position` or handle that is not an
array (<doc:PenMeshGradients>, "Malformed points"): Pen keeps the fill and paints none of
it. The finding names each such vertex and quotes what the file wrote.

`mesh-gradient-distorted` is a warning, for a mesh Pen paints but not as authored. A
color Pen's mesh cannot read paints as nothing: after one leading `#`, Pen's mesh reads
3, 6 or 8 digits and nothing else, so 4-digit `#RGBA`, a 5-digit typo and an empty string
are all transparent there; the finding names each one and spells `#RGBA` out as
`#RRGGBBAA`. A color of a readable length with a digit that is not hex — `red`,
`#eGeGeG` — paints as whatever Pen makes of it (`#00EEDD`, `#00000E`; see
``PenMeshColor/hexColor(penMesh:)``), and the finding names that color. And a patch
whose handles fold it over itself overdraws its own paint and leaves part of the box
bare. `MeshFoldDetector` samples each patch's Jacobian at 33 × 33 parameters and
reports a patch whose most negative sample is deeper than 5% of its mean — deep enough
to show. A strictly-negative sliver shallower than that is not reported: the mesh
report's `mwarp` probe, which Pen draws cleanly, has one. Two patches overlapping each
other without either turning over are not reported either. A point written in neither
`[x, y]` nor object form that Pen places anyway — `"oops"` at its grid position,
`[0.3, 0.2, 9]` at its first two numbers — is distorted too: Pen paints the mesh from
its own repair of the point, not from what the file says, and rewrites the point on its
next save. It belongs here rather than in a check of its own because it is exactly this
check's case, and its fix is the same kind: the finding quotes the point and the value
Pen draws, which is the value to write. A disabled mesh is skipped.

```text
error mesh-gradient-dropped  Hero (Msh01)  has a mesh gradient fill with 3 points for a 2×2 grid of 4 vertices; Pen removes the whole fill when it opens the file. Write `columns × rows` points and colors, at least 2×2.
warning mesh-gradient-distorted  Hero (Msh01)  has a mesh gradient fill Pen paints wrong: colors Pen's mesh reads as nothing (it reads 3, 6 or 8 hex digits), at vertex 2 `#0F0F` (write `#00FF00FF`).
error mesh-gradient-dropped  Hero (Msh01)  has a mesh gradient fill with vertex 2 `[1]`, which Pen cannot read as a position or handle; Pen keeps the fill and paints nothing. Write each point as `[x, y]` or `{"position": [x, y], …}` with two-number handles.
warning mesh-gradient-distorted  Hero (Msh01)  has a mesh gradient fill Pen paints wrong: points in neither `[x, y]` nor object form, which Pen draws its own way and rewrites on save: vertex 2 `"oops"` as `[0.5,0]`; write what Pen draws.
```

`text-style-stripped` is a warning, one finding per case. Pen strips a text node's
stroke keys, `underline` and `strikethrough` when it opens the file and draws none of
them, although all three are in its schema. Woodcase keeps drawing an underline and a
strikethrough, so for those the finding says the two renders disagree; Woodcase draws
no text stroke either. `underline: false` loses nothing and is clean.

`shader-not-drawn` is a warning, one finding per enabled shader, fills first and then
the stroke, placed in its list when there are several (`fill 2 of 3`). The file is
well formed and Pen draws it as written — it runs the shader, uniforms, samplers,
`@sdf` and `@backdrop` included (`render-shader-fills.pen`) — but Woodcase has no shader
runtime: `render`, `shot`, the viewer and generated React and SwiftUI all leave that
paint out, so their output will not match Pen's. A disabled shader is clean.

```text
warning shader-not-drawn  Swatch (Rct01)  has a shader fill (`./shader-uv.frag`) that Pen runs and Woodcase does not draw: render, shot and generated code leave that paint out, so they will not match Pen.
```

`per-side-stroke-on-shape` is a warning, one finding per node. Pen lays a per-side
`strokeWidth` along the sides of a frame, a rectangle or a browser node, but strokes an
ellipse, a polygon, a path or a line with **one uniform stroke of the `top` width**, the
other three sides ignored, and draws no stroke when there is no `top`
(`render-per-side-shapes.pen`; see <doc:PenRendering>). Pen's choice of `top` looks
arbitrary, and the file does not say what its author meant, so the check fires whenever a
side is written that differs from the `top`, or the `top` is missing; four equal sides, a
lone `top`, a uniform width and a node with no stroke paint lose nothing and are clean.
Every Woodcase target draws what Pen draws (``PenStrokable/drawn(on:)``), so the render
is consistent — only not with the widths the file writes. The fix is one `strokeWidth`.

```text
warning per-side-stroke-on-shape  Ring (Shp01)  has a per-side strokeWidth (top 12, right 2, bottom 6, left 0), but Pen strokes an ellipse at its top width alone, all round (12); Woodcase draws it the same. Write one strokeWidth.
```

## What `generate react` will choke on

Three checks read nothing but the metadata the React emitter reads, and answer the one
question `lint` could not answer before: *will this file generate?* They fire only on a
document that has opted into codegen — a reusable node, and a `_props` or `_role` key on
it — so a design nobody intends to generate never sees them.

They are cheap. Each runs over reusable nodes and `ref`s alone, off
``EditableDocument/materializedComponents()`` — the registry the ref expander is already
handed — and none of them expands an instance or settles a second layout.

### `codegen-prop-path`

`common.metadata._props` is how a component declares its named parameters:
`{"title": "Body/Title"}` maps the prop `title` to the descendant at that path. It is
the declaration ``ComponentAnalyzer`` has read since the React emitter shipped, and the
one `override` and `cp --each` resolve a prop name through.

An entry fails on its own in two ways, and neither says anything today:

- **the value is not a string**, so the analyzer skips the entry and the prop never
  exists;
- **the value resolves to no descendant**, so the prop exists in the component's
  interface with nothing wired to it — and every instance that overrides the descendant
  the author meant is inlined (see `codegen-unmapped-override`, below).

```text
error codegen-prop-path  Card (Cmp01)  declares the prop `title` in common.metadata._props as `Nope`, but no descendant of Card answers to that path, so `generate react` emits the prop with nothing wired to it and inlines every instance that overrides the descendant it meant. It contains: Label (Lbl01), Row (Row01), Row/Tag (Tag01). Run `woodcase set <file> Cmp01 common.metadata._props.title=<path>` with one of them.
```

And two entries fail **together** when they resolve to the same descendant *and* read the
same field of it. An override of that descendant carries one value; nothing says which
prop the author meant it for. The emitter keeps the first by prop name, the rest are
declared with nothing wired to them, and the finding names the pair, the node they share,
and the edit that separates them:

```text
error codegen-prop-path  StatCard (Stc01)  declares the props `label` and `width` in common.metadata._props as paths that resolve to Title (Ttl01), and each reads the same string value from it, so `generate react` cannot tell them apart: it keeps `label` — the first by name — and `width` is declared with nothing wired to it. Point it at another descendant: run `woodcase set <file> Stc01 common.metadata._props.width=<path>`. StatCard contains: Body (Bdy01), Body/Title (Ttl01), Body/Swatch (Swt01).
```

Sharing a descendant is not itself the fault: a `label` reading a text node's content and
a `tint` reading its fill are two readings of one node, and ``PropMapper`` emits both.
What collides is the *field*, so the check compares the type
``ComponentAnalyzer/inferPropType(from:)`` gives each prop, not the node alone. Before
this check existed the emitter did not merely mis-emit here — it trapped, because the
node-id lookup was built with `Dictionary(uniqueKeysWithValues:)`.

The path is resolved by ``ComponentAnalyzer/resolveDescendantPath(_:from:)`` **itself**,
which was extracted from the analyzer for this check rather than re-implemented beside
it: a path the lint calls good is by construction a path codegen wires, and the two
cannot drift. The remedy uses `common.metadata._props.<name>=<path>` — the deep metadata
key, which merges one key rather than overwriting the object and silently dropping
`_role` or `_scroll` alongside it.

### `codegen-role`

``ComponentRole`` is a closed vocabulary — `button`, `link`, `toggle`, `textInput`,
`select`, `tabBar` — and an unknown value is read and dropped without a word:
`ComponentRole(rawValue:)` answers `nil` on a component's root, and a descendant with an
unrecognized role gets no default action and no binding. What generates is a plain
`<div>` with no semantic element, no `wc-*` class and no state rules.

```text
error codegen-role  Card (Cmp01)  declares common.metadata._role="buton", which is not a role `generate react` knows, so the declaration is read and dropped: the component emits a plain <div>, with no semantic element, no interactive states and no state rules. The roles are button, link, toggle, textInput, select, or tabBar. Run `woodcase set <file> Cmp01 common.metadata._role=<role>` with one of them, or drop the key.
```

**Scope is exactly what codegen reads.** ``ComponentAnalyzer`` enters `walkDescendants`
only from a reusable node, so a `_role` on a page — or on anything outside every
reusable subtree — reaches no emitter and is not a finding. The key is the file's own
above that line.

### `codegen-unmapped-override`

``PropMapper`` matches each of an instance's `descendants` keys against the definition's
declared props by target node id. One key it cannot match changes the emitter's whole
strategy: instead of `<Card title="…" />` it **inlines** the component — clones the
definition, patches the overrides onto the clone, emits the expanded tree in place of the
tag, and records a `codeGen` diagnostic (an error under `--strict`). The pixels are
right and the reuse is gone; a dozen such instances generate a dozen copies of one
component.

```text
warning codegen-unmapped-override  Root/Chip (Rf001)  overrides `Sub01` (Subtitle) on Card, which declares props in common.metadata._props but none that reads that descendant, so `generate react` inlines a whole copy of Card here instead of emitting a `<Card />` tag. Declare it: run `woodcase set <file> Cmp01 common.metadata._props.subtitle=Subtitle`.
```

Two silences are deliberate. **A definition that declares no `_props` at all is never a
finding** — nothing was declared, so nothing failed to map, and a component nobody has
parameterized yet is a stage of a design rather than a fault. And **a key naming no
descendant of the definition is `override-target-not-found` instead**, which says the
more specific thing; reporting both would be one fault twice.

What is left divides in two, and the message says which one it is holding. A key naming
a **named** descendant is one `_props` entry away, so the message writes that entry out.
A key naming an **unnamed** one cannot be declared at all — a path is a run of child
names, so ``ComponentAnalyzer/resolveDescendantPath(_:from:)`` has nothing to match —
and the message asks for the name first:

```text
warning codegen-unmapped-override  Root/Chip (Rf001)  overrides `Unn01` on Row, which declares props in common.metadata._props but none that reads that descendant, so `generate react` inlines a whole copy of Row here instead of emitting a `<Row />` tag. `Unn01` has no name, and a _props path is a run of child names, so no entry can reach it until it is named: run `woodcase set <file> Unn01 common.name=<name>`, then declare the prop the same way.
```

That is not a corner case. On `Tests/WoodcaseTests/Fixtures/woodcase-app.pen` — a file
drawn in an editor rather than written by hand — four of the seventeen findings are
unnamed wrapper frames inside
`Component/Toggle Row`, and no amount of `_props` would have silenced them
(`woodcase lint Tests/WoodcaseTests/Fixtures/woodcase-app.pen --summary`).

It is a `warning` where the other two are errors, on the grading in ``LintCheck/severity``:
the emitter does produce a correct rendering for it. Only the shape of the code degrades.

## What it does not check

**Text fonts.** Whether a font family is a typo or a Google font waiting to be
downloaded cannot be decided offline, and no local catalog exists to decide it from.
A lint never asks. A caller that has already run
``GoogleFontResolver/prepareFonts(for:diagnostics:)`` — `render` does — passes the
collector's diagnostics in as `diagnostics:`, and they arrive as `pipeline` findings
beside everything else. Icon fonts are different: `library`/`icon` draw from a closed,
bundled vocabulary rather than an open one that needs the network, so `unknown-icon`
and `unknown-icon-library` check them offline.

**Imports.** A document is linted with the libraries its own `imports` name, read from
beside it when the file is opened — the same ones `tree`, `shot`, `render` and the
viewer expand — so an instance of `V:Button` is judged against the library that defines
it, and a slash-path override through it (`M7RGT/V:Xxvji`) against that library's nodes.
An import that brought nothing in is one document-level finding at the top of the
report (`import-not-found`, `import-unreadable`), and every instance through it is also
a `broken-ref` whose message names the library it was looked for in. A lint scoped to a
subtree leaves the document-level import findings out, as it does every document-level
finding. Where the libraries are looked for is Pen's rule, not ours: see
<doc:PenImportNamespaces>.

> Correction (2026-09-26): this paragraph used to say no read verb resolves a
> document's `imports`, and before that "resolve imports first — as `render --library`
> does". Both were true of their day: `render --library` never worked (it keyed a
> library by its file name without extension, while the resolver looks it up by the
> import path as written), and nothing else resolved imports at all. Every read now
> does, and `--library` is gone.

**Instances.** The walk does not expand component instances. A component is linted
once, where it is defined, rather than once per instance; a fault that only an override
introduces, in one instance alone, is not reported.

The one exception is `unresolved-variable`, which does read an instance's own
`rootOverrides` and `descendants`. It has to work for it: the settled tree resolves
variables *after* expansion, and expansion has already replaced the `ref` with the
component's root, so the ref node the walk still shows carries override maps no
resolver ever touched. The linter therefore resolves the document a second time
**unexpanded**, and reads the ref from that — the same variable table the expansion
resolves the patched-in values with. A `$name` the document defines is not a finding
wherever it is overridden; a mistyped one is a finding at the instance, which is the
only row that can name it.

That second resolve is also where **text content's forgiveness** reaches an override.
A `content` whose `$name` the document defines nowhere is the literal it almost
certainly was — `$30.00` is a price, not a reference to a variable called `30.00` — so
it is not a finding, and it is not a finding whether it was written straight onto the
text node with `set` or into an instance's `descendants` map with `override`: one
string, one reading, whichever verb wrote it. The forgiveness stops at `content`. A
mistyped `$name` in any *other* property is still a finding, and so is a `content`
naming a variable the document *does* define but nothing resolves — a circular chain,
say — so this can never quiet a real dangling reference.

**A scoped root's own clipping.** `findings(in:root:)` lints a subtree, and the subtree's
root has no parent *in that listing* — exactly as `tree` shows it — so it is never
reported as clipped. Lint the parent to ask that question.

## Topics

### Linting

- ``DocumentLinter``
- ``LintCheck``
- ``LintCheckDescription``
- ``LintFinding``
- ``LintFormatter``

### Geometry

- ``TreeRow/clipTolerance``
- ``TreeRow/overflowAxes``
- ``TreeRow/OverflowAxis``
- ``RootOverlap``
