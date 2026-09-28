# Plan: a CLI that teaches, state that stays in the project, and a viewer for many artboards

*2026-08-30. Author: Claude (Fable 5) with Ben. Responds to
[the mobile-dashboard experience report](2026-08-30-jobs-mobile-dashboard-experience.md)
and Ben's notes on the web dashboard. The goal, in Ben's words: make `woodcase` as
seamless as `job`, so an agent is never tempted to write a throwaway script to make
nodes, and so the CLI itself — not a skill — teaches an agent the format and the
best practices. Decisions below were discussed and accepted; defaults marked *default*
were mine and Ben agreed.*

## Corrections to the experience report

Checked against the binary at `b6c54aa` and the 360 `.pen` files in the repo.

- **The font cache is `~/Library/Caches/com.bensyverson.woodcase/fonts/`**
  (`GoogleFontCache.swift`), not `~/Library/Caches/woodcase`. It is only touched when a
  document names a Google font. Either way it should never fail a command (below).
- **Variables have four types — `boolean`, `color`, `number`, `string` — each themeable
  per axis.** Real files use string variables for font families (`font-primary` in
  `woodcase-app.pen`, themed by `mode`; `v-sans`/`v-mono` in `tirekick.pen`) and
  numbers for radii and gaps (`card-radius`, themed by `density`). Tally across the
  repo: color 361, number 30, string 22, boolean 4. There is no composite "text style"
  type; a named style is a string variable plus number variables used together, or a
  reusable text node copied with `cp`.
- **No ellipsis truncation exists in the format** (`textGrowth` is `auto |
  fixed-width | fixed-width-height`). We cannot add a property the format does not
  render; what we can do is stop lint from reporting a designed clip.
- **The property vocabulary already exists in the binary** (`PenPropertyShape`,
  generated from the decoders — it is what the `set … kind.bogus` error lists). A
  schema surface is plumbing, not research.
- **`activity --file` vs positional**: defensible (the verb opens no `.pen`), still
  worth accepting a positional.
- Confirmed as reported: `add … document` on a missing file says only "check the
  path"; an unknown icon name renders nothing and lint says nothing; `kind.content=3`
  is refused; a root-level `add` without `x`/`y` is already auto-placed to the right of
  the existing roots (`RootCoordinates`).

## Rulings

- **Never reference the vendor.** Woodcase works on `.pen` files, and that is all a
  caller needs to know. Help, errors, DocC and README describe *the format* — "a `.pen`
  file", "the format", "a component instance's descendants map" — never the editor,
  its MCP or its documentation. API identifiers (`PenDocument`, `PenLayoutEngine`) keep
  their names: `.pen` is the format's name.
- **State lives in the project, like `.jobs.db`.** The activity log moves from
  `~/.woodcase/` to `.woodcase/activity.jsonl` at the nearest `.git` above the `.pen`
  file (else the file's directory). It is gitignored; the first write that creates it
  adds the ignore line the way `job init` does. `$WOODCASE_HOME` remains the explicit
  override. The old home-wide log is not read or migrated (stage BUILD).
- **The font cache is best-effort.** If its directory cannot be created, fonts are
  cached in memory for the process and one line on stderr names the path. No
  allow-list entry is ever required for a read, write or `shot`.
- **`serve` autoincrements from 7333** until a port binds, like `job serve`. A sandbox
  `EPERM` is reported as the sandbox, not as a busy port.
- **Artboards do not overlap.** A root added without coordinates is placed with a
  margin from every existing root (already the behaviour; the margin becomes explicit
  and tested). A root added or moved *with* coordinates that overlaps another root
  prints a warning on the write and is an `artboard-overlap` lint finding.
- **A write carries no theme, so follow mode never changes the viewer's theme.**
- **Teaching lives in `help`, the primer and the errors — not in a `tutorial` verb.**
  An agent does not run a tutorial unprompted; it reads the bare invocation, the
  `help` topics the primer names, and the error it just got.

## The CLI

### `new`

`woodcase new design.pen` writes the minimum a `.pen` file needs — the version and an
empty `children` — with no axes and no variables. It refuses to overwrite (exit 3,
"already exists — `woodcase tree design.pen` reads it") and does not create parent
directories (exit 4, naming the missing directory). The missing-file error on every
other verb names `new` as the next command.

### `help schema [type]`

One table per node type, generated from `PenPropertyShape`: the codec path
(`kind.fills`) with the raw key beside it (`fills`), the accepted value shape with
enum values spelled out, nested shapes recursed (`fills[]`, `effects[]`, `strokeWidth`
number-or-per-side object), and "accepts `$var` of type X" per property. With no
argument, the list of types and the `common.*` properties. `woodcase schema` is an
alias. The primer's "THEN" line names `help schema` and `help recipes`.

### `help recipes`

Copy-pasteable command sequences for what an agent actually does: start a file; build
a screen from the root down; make a component and place it with `cp` and props; repeat
a node with `cp --times`; register themed variables; the lint–shot loop; replace a
subtree in place. Each recipe ends with the read that verifies it.

### `icons`

`woodcase icons <library> [query]`: substring match first, then fuzzy, over the bundled
codepoint tables; no query lists everything for `grep`. Lint gains
`unknown-icon` (nearest names proposed, from the same matcher) and `unknown-icon-library`.
Both are offline.

### `cp --times N`

Copies N times into the parent, in order. Because identical names break path
addressing, `--times` requires `common.name` to contain `{n}` (1-based) and refuses
otherwise, naming the placeholder. *Default:* explicit placeholder over auto-suffix.

### `replace`

`woodcase replace design.pen <node> -F subtree` swaps a subtree for a new one keeping
the node's id, parent and position — the "rebuild it" idiom as one rev-guarded call.
Refuses to change the root type of a `reusable` definition that has instances (see the
kind-swap entry in the backlog).

### Small cuts

`kind.content` accepts a number and stores its string; `activity` takes the file as a
positional as well as `--file`; the clipped check shares one epsilon (0.01 pt) between
`tree`'s `clip` flag and `lint`, with the 59-bar distribution as the regression test.

## The viewer

### Bugs

New artboards do not appear until reload; selection works only in the first artboard;
selecting a node does not scroll the outline to its row. One leaf: the `change` event
must refresh the artboard list and the outline binding, not only the render region.

> Corrected 2026-08-30, when the leaf was done: that one sentence is the cause of the
> first bug only. The artboard strip was not a fragment at all, so no event could
> refresh it — it is one now (`/files/{file}/artboards/{artboard}/tabs`, `#v-tabs`).
> The second bug was not an event or a binding: `ArtboardLayout` published every box in
> **canvas** coordinates, because `absoluteRects(under:)` answers in the root's frame
> and a top-level frame's own rect is on the canvas. An artboard at `x: 500` therefore
> put all of its boxes past the right edge of its own image, so no click could hit one
> and the selection outline was drawn off-stage; the first artboard worked only because
> it happened to sit at the origin. `ArtboardLayout` now subtracts the artboard's origin,
> as `shot --outline` already did. The third was as described, and is a
> `scrollIntoView({block: "nearest"})` in `viewer.js`.

### Representation

The outline and the artboard strip mark a `reusable` definition, a `ref` instance and
a `slot` frame with a glyph and a label. Ids are styled as in the Jobs dashboard and
click-to-copy. The Variables pane renders every type — string values as text, numbers
with their themed variants, booleans, colours as swatches — scrolls, and collapses.
Multiple theme axes already render one control per axis; unchanged.

### Bird's-eye view

The artboard strip becomes a zoomed-out canvas with every artboard at its settled
`x`/`y` (from `absoluteRects`), clamped to a minimum zoom with labels that do not scale
away. Clicking one focuses it. Because artboards do not overlap by ruling, no packing
fallback is built; an overlapping file is shown as it is, and lint says why.

### Follow, live and unread

One control, *Follow*, with the options *nobody*, *anyone* (live) and one entry per
actor seen in the log. Following moves the focused artboard to the one most recently
written by that actor; it never changes the theme. Any manual navigation drops follow
to *nobody* with a one-click resume. Every artboard tab carries an unread dot, cleared
when viewed, kept per viewer in the browser (`localStorage`), never on the server.

### Keyboard and presentation

| Context | Key | Effect |
| --- | --- | --- |
| nothing selected | ← / → | previous / next artboard |
| node selected | ↑ / ↓ | previous / next outline row |
| node selected | ← / → | collapse / expand the row |
| any | `f` | presentation: chrome hidden, no overlays, selection kept |
| any | Esc | leave presentation, else clear selection |
| focus in a form control | any | untouched — the control keeps the key |

The JS and the browser test share this table.

### Right pane: Activity, Details, Export

Tabs. *Details* is selected automatically on selection and lists the node's attributes
from the expanded node, each marked *literal*, *`$var`* (with the resolved value) or
*override* (with where it came from). *Export* chooses scale (1×/2×/3×) or a maximum
edge, and a format — exactly the formats `render` and `generate` support, nothing
more — and downloads one artboard. *Code* is a split view of the main pane: visual left,
generated code right, language chosen in the code pane and persisted in the browser.
A whole-package download is parked in the backlog.

## Tasks

```yaml
tasks:
  - title: Agent-first CLI, project-local state and a many-artboard viewer
    desc: |
      Plan in project/2026-08-30-agent-first-cli-and-viewer-plan.md; read it first. Three branches with disjoint file surfaces: the CLI verbs that teach (WoodcaseCommandCore, Lint, help text), the state directories (Files, GoogleFonts, ServeCommand), and the viewer (WoodcaseViewer). Strict TDD; every leaf starts red.
    labels: [agent-first]
    children:
      - title: The CLI teaches
        children:
          - title: Vendor audit of every caller-facing sentence
            ref: audit
            desc: |
              Help text, errors, primer, DocC and README describe the .pen format only — never the editor, its MCP or its docs. Identifiers keep their Pen* names. Grep for Pen.app, Pencil, MCP, pen.dev and docs links; rewrite each in format terms. A test pins the primer and every verb's --help free of the vendor words.
            criteria:
              - No help, error, DocC or README sentence names the vendor, its app, MCP or docs
              - A test asserts the primer and each --help contain none of the vendor words
          - title: woodcase new, and the missing-file error names it
            ref: new-verb
            desc: |
              new writes the minimum .pen file (version, empty children; no axes, no variables). Refuses to overwrite (exit 3), does not create parent directories (exit 4, naming the directory). Every verb's missing-file error names `woodcase new` as the next command. help recipes' first recipe starts with it.
            criteria:
              - new creates a file tree accepts and add can extend, and refuses to overwrite
              - The missing-file error on read and write verbs names woodcase new
          - title: help schema from PenPropertyShape
            desc: |
              help schema [type] prints, per node type, each property as codec path with raw key beside it, value shape with enum values, nested shapes recursed, and the $var type it accepts; no argument lists the types and common.*. woodcase schema is an alias. The primer's THEN line names help schema and help recipes. Generated, not hand-written: a test walks every type and checks the table names every key the decoders accept.
            criteria:
              - help schema text lists every property set accepts on a text node, with shapes and enums
              - Nested shapes (fills, effects, strokeWidth) are recursed, not printed as "object"
              - The primer names help schema
          - title: help recipes
            desc: |
              Copy-pasteable sequences for starting a file, building a screen root-down, making a component and placing it with cp and props, repeating with cp --times, registering themed variables, the lint-shot loop, and replacing a subtree. Each recipe ends with its verifying read. A test runs every recipe against a scratch file and asserts it exits 0 — the recipes must not rot.
            blockedBy: [new-verb, times, replace]
            criteria:
              - Every recipe runs green end to end in a test
              - The primer names help recipes
          - title: woodcase icons, and unknown-icon lint findings
            desc: |
              icons <library> [query] over the bundled codepoint tables; substring then fuzzy; no query lists all. Lint adds unknown-icon (proposing the nearest names via the same matcher) and unknown-icon-library. Offline.
            criteria:
              - icons lucide check lists check, circle-check and their kin
              - An icon named check-circle-2 is a lint finding proposing circle-check
          - title: cp --times with a {n} name placeholder
            ref: times
            desc: |
              --times N copies N times in order; requires common.name containing {n} (1-based) and refuses otherwise, naming the placeholder. The name → id tree lists every copy.
            criteria:
              - cp --times 3 with name "Bar {n}" makes Bar 1..3 addressable by path
              - cp --times without {n} is refused with an error naming the placeholder
          - title: woodcase replace keeps id, parent and position
            ref: replace
            desc: |
              replace <node> -F subtree swaps the subtree in place, keeping id, parent and position; rev-guarded; logged as one event and undoable. Refuses to change the root type of a reusable definition that has instances.
            criteria:
              - After replace the node keeps its id and index and the new children are addressable
              - undo restores the previous subtree
          - title: Small cuts — content coercion, activity positional, clipped epsilon
            desc: |
              kind.content accepts a number and stores its string. activity takes the file as a positional as well as --file. tree's clip flag and lint's clipped check share one 0.01 pt epsilon; the regression test is 59 fill_container bars at gap 1 in a 350-wide frame (was reported clipped at 350.00).
            criteria:
              - set kind.content=3 stores "3"
              - The 59-bar layout produces no clipped finding and tree shows no clip flag
          - title: Root overlap — margin on auto-placement, warning and lint on collision
            desc: |
              A root added without coordinates lands with an explicit tested margin from every existing root. A root added or moved with coordinates that overlaps another root prints a warning on the write's stderr and lint reports artboard-overlap naming both roots.
            criteria:
              - Auto-placed roots never intersect and keep the documented margin
              - An add with overlapping x/y warns on the write and lint reports artboard-overlap
      - title: State that stays in the project
        children:
          - title: Project-local activity log at .woodcase/
            desc: |
              The log resolves to .woodcase/activity.jsonl at the nearest .git above the .pen file, else the file's directory; the first write that creates the directory adds .woodcase/ to that repo's .gitignore the way job init does. serve with no args reads the cwd's log; serve with files follows each file's own. $WOODCASE_HOME stays as the explicit override. The old ~/.woodcase log is neither read nor migrated. Docs (WoodcaseActivityLog.md, WoodcaseCLI.md, WoodcaseEditor.md, README) updated.
            criteria:
              - A write inside a repo creates .woodcase/activity.jsonl at the repo root and ignores it
              - A file outside any repo logs beside itself
              - serve with no args in a repo lists the files that repo's log has seen
          - title: Font cache is best-effort, never fatal
            desc: |
              When the cache directory cannot be created, fonts cache in memory for the process and one stderr line names the path. shot never exits non-zero for a missing or unwritable cache directory. Doc PenGoogleFonts.md says so.
            criteria:
              - shot with an unwritable cache location renders and exits 0 with one stderr line
          - title: serve autoincrements the port; sandbox-aware errors
            desc: |
              serve tries 7333 upward until one binds and reports the one it got; --port N pins exactly N. EPERM on bind is reported as the sandbox with the next command, distinct from EADDRINUSE. Same distinction for EPERM on the activity log and cache paths, printed once per process rather than per edit.
            criteria:
              - Two serves without --port get 7333 and 7334
              - A bind EPERM message names the sandbox, not a busy port
      - title: The viewer for many artboards
        children:
          - title: Live artboard list, selection in every artboard, scroll-to-row
            ref: viewer-bugs
            desc: |
              The change event refreshes the artboard list and the outline binding, not only the render. Selection works in any artboard. Selecting a node scrolls the outline to its row. Browser test for each.
            criteria:
              - An artboard added while the page is open appears without reload
              - Clicking a node in the third artboard selects it and its outline row scrolls into view
          - title: Marks for components, instances and slots; id chips; full Variables pane
            desc: |
              Outline rows and artboard entries mark reusable definitions, ref instances and slot frames with a glyph and label. Ids styled as in the Jobs dashboard, click-to-copy. Variables renders every type (string as text, number with themed variants, boolean, colour swatch), scrolls, and collapses.
            criteria:
              - woodcase-app.pen's outline shows definition, instance and slot marks
              - A string variable and a themed number variable render with their values
          - title: Bird's-eye artboard canvas
            desc: |
              The artboard strip becomes a zoomed-out canvas placing every artboard at its settled x/y from absoluteRects, with a minimum zoom and labels that do not scale away; click focuses. No packing fallback — artboards do not overlap by ruling.
            blockedBy: [viewer-bugs]
            criteria:
              - Artboards appear at their document positions and clicking one focuses it
              - A 40k-px spread stays legible at the minimum zoom
          - title: Follow mode and unread dots
            desc: |
              One Follow control — nobody, anyone, or a named actor from the log. Following moves the focused artboard to that actor's most recent write; never the theme. Manual navigation drops to nobody with a one-click resume. Unread dots per artboard, cleared on view, kept in localStorage.
            blockedBy: [viewer-bugs]
            criteria:
              - Following ana moves focus on her write and not on another actor's
              - A theme pin survives a followed write
              - An unwatched artboard shows a dot until viewed
          - title: Keyboard model and presentation mode
            desc: |
              Implement the key table in the plan; f enters presentation (chrome hidden, no overlays, selection kept), Esc leaves it or clears selection; form controls keep their keys. The JS and the browser test share the table.
            blockedBy: [viewer-bugs]
            criteria:
              - Every row of the key table has a browser test
          - title: Right pane tabs — Details and Export; code split view
            desc: |
              Tabs Activity / Details / Export. Details auto-selects on selection and lists the expanded node's attributes marked literal, $var (with resolved value) or override (with source). Export picks scale or max edge and a format among what render and generate support, downloading one artboard. Code split view shows generated code beside the render; language persisted in localStorage. Resizable panes horizontally and vertically.
            blockedBy: [viewer-bugs]
            criteria:
              - Selecting an overridden node shows the override marked with its source
              - Export at 2x PNG downloads an image twice the artboard's size
              - The code pane's language survives a reload
```

## Backlog

Whole-package code download: parked until someone asks; `generate` already writes the
files to a directory.

## Landed (2026-08-30, same day)

Every leaf above landed on `main` between `7c39d4f` and `d3358fa`; the root `5U5dD`
auto-closed. Suite: 2995 tests green at `d3358fa` (`swift test --quiet`). Integration
notes worth keeping:

- Two agents each grew `help design` past its 60-line cap; the topic was trimmed at
  integration and the `override` line lost its vendor mention there.
- The four viewer leaves each kept their JS and CSS in one delimited block, which made
  the merges mechanical — except that git split one block across two hunks, so a naive
  hunk-by-hunk union spliced the follow block into the keyboard block. The fix that
  worked: rebuild the file from `main`'s copy plus the branch's block taken verbatim.
- Two cross-leaf CSS collisions surfaced only under the full suite: follow's
  `[data-artboard] { position: relative }` un-placed the map's absolute boxes, and the
  right pane's `.v-canvas-head` let `.v-canvas`'s implicit `auto` column size to the
  map's 40 000-point plane. Both fixed at the source; the map's own test caught them.
- Verified with the format's own headless engine (`pen interactive`): icon library keys
  and the lucide name table have not diverged from ours; an unknown name is saved as-is
  and rendered as a `circle-question-mark` placeholder, where we draw nothing — issue
  `AuqQs`. Also filed: `gZusN` (add/undo drop an explicit empty `children`), `24YuI`
  (`cp` into an instance should turn nested props into overrides).
- Not done, by decision: `CLAUDE.md`'s own vendor references (Ben's call); thumbnails
  inside the map's boxes (cheap via `RenderCache.png(longestSide:)`, parked).
