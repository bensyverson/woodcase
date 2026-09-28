# Viewer previews: a catalog of states, served

2026-09-02. Ben's ask: the SwiftUI `#Preview` idea for the viewer's own UI — every
component in its illustrative states, on a page, so a person can sign off on a change and
an agent designing a component can see what it built. A sibling project of Ben's has the
same surface for its Go dashboard and its doc is the inspiration: an index of components,
one page per component with every state stacked, each state with a name and a sentence
saying what to look at, and a stable URL per state. Not a copy; the shape.

## What already exists

The viewer's `#Preview` is a **golden HTML file per component and state**:
`Tests/WoodcaseViewerTests/Fixtures/golden/` holds 34 of them, from `avatar-small.html`
to `page-dashboard.html`, each written by `ViewerGolden.check(component, named:)` with
`UPDATE_GOLDEN=1` and compared on every run. The states are declared as literals in the
`*PreviewTests.swift` files, built from the production prop types (`TreeRow`,
`ActivityEvent`, `FileListReport.Summary`, `ViewState`) with helpers in `ViewerGolden`
(`row(id:…)`, `identity(_:secondsAgo:)`, `clock`). `WoodcaseViewer.md` § *Components and
their previews* records this as the previews principle.

Count on 2026-09-02, from `ls Tests/WoodcaseViewerTests/Fixtures/golden | wc -l` and
`grep -rn ViewerGolden.check Tests/WoodcaseViewerTests`: 34 goldens, 32 call sites, in
eight test files (one call is parameterized over the three avatar sizes).

> Corrected 2026-09-02 by the catalog leaf: the first draft said 33 call sites; the
> count is 32.

So the enumeration exists. Two things are missing:

- **Nobody can look at it.** A golden is text. The review loop that does look —
  `sleepy shot` of a served page into `local/viewer-shots/`, sent to Ben — shoots a real
  file in whatever state it happens to be in. The states the goldens enumerate (a
  presence stack overflowing, a follow picker paused, a right pane with nothing in it)
  are reachable only by finding or arming a document that produces them, which is
  exactly why the sibling project built its canvas.
- **The declarations live in the test target.** The product cannot serve what only a
  test can construct, and a component's states are part of what the component *is* —
  they belong beside it, the way `#Preview` sits under the view.

## Design

One catalog, two readers. The states move out of the tests into the viewer target and
both the golden tests and a new host read them, so the picture a person signs off on and
the fixture the suite checks are the same declaration by construction.

### The catalog

In `Sources/WoodcaseViewer/Previews/`:

- `PreviewState`: a `slug` (the URL segment, stable enough to paste into a review), a
  `name`, a `note` saying what this state is *for* — what a reviewer should look at, or
  what went wrong here once (a state with no note is a picture with no caption), a
  `frame` (below), and the component to render, type-erased.
- `PreviewComponent`: a `slug`, a `title`, a `blurb`, the `source` file a reader goes to
  when something looks wrong, and its `states`.
- `PreviewCatalog.all`: the registry, one line per component. A new state is one literal
  in the component's own file and needs no registration.
- `PreviewFixtures`: the sample rows, identities, artboards and clock the states are
  built from — `ViewerGolden.row(…)` and friends, moved. A fixed clock, so a relative
  age renders the same every time.

Each component's states live in `Components/Previews/<Component>+Previews.swift` (the
`BaseType+Purpose.swift` rule) as a static `previews: PreviewComponent`. The state's
value is the **production prop type** and nothing else — a `TreeRow`, a
`FileListReport.Summary`, a `ViewState`. A preview-shaped twin would drift: it renders
states production cannot reach and misses ones it does, and then looks like coverage. The
sibling project learned that one the hard way and it is the rule worth carrying over
verbatim.

**Representative, not exhaustive.** The states are the ones worth looking at — empty,
ordinary, crowded, wrong, mid-flight — and there is deliberately no matrix generator.

> Ruling 2026-09-02, after the first review pass: **a state that renders nothing is not a
> preview.** Three were declared because DESIGN.md names the case (a kind mark on a node
> with no role, a theme picker on a file with no axes, the artboard stepper on a file with
> one artboard); each produced an empty box and a question. What they assert is a markup
> fact, and a picture is the wrong instrument for a fact — the behaviour tests hold it.
> They were removed. Eight booleans are already 256 states; the catalog shows the ones a
> reviewer can grade.

> Ruling 2026-09-02, in the same round: **a state that renders the same picture as its
> neighbour is not a preview either.** `id-chip/outline` (the chip wearing a caller's
> extra class) and `pane-grip/rows` (the horizontal seam) each varied only an attribute,
> and drew a picture indistinguishable from the state above it. Both were removed with
> their goldens; the markup claims they stood for are held by `OutlinePreviewTests` and
> by the `artboard-page` / `map-page` goldens, which render the horizontal grip in
> place. The catalog is 38 components, 83 states.

### The frame

A component alone on a blank page is the wrong picture: an outline panel is 280 px wide
in production and a right pane sits against the window's edge. So a state names the
frame it is shown in, and the frame is a production width from the stylesheet:

| frame | what it is | example |
|---|---|---|
| `strip` | an atom on one line, at its natural size | avatar, live badge, id chip, kind mark |
| `leftPane` | the outline column | `OutlinePanel`, `ArtboardOutline` |
| `rightPane` | the activity/details/export/code column | `ActivityFeed`, `DetailsPanel` |
| `canvas` | the render column | `RenderRegion`, `ArtboardMap` |
| `topBar` | the full-width chrome strip | `TopBar`, `SelectionBar` |
| `page` | a whole page, in its own `ViewerDocument` layout | `DashboardPage`, `EmptyPage` |

The frames are a short section of `ViewerStylesheet` and a paragraph of `DESIGN.md`. The
catalog page renders every non-`page` state *inside* a `ViewerDocument` of the ordinary
kind, so the stylesheet, the script and light/dark are the real ones; a `page` state is
served whole, as the page it is.

### The host

Three routes, registered in `ViewerPages` so `woodcase serve` carries them, and a verb
that serves only them:

| route | what it serves |
|---|---|
| `GET /preview` | the index: every component, its blurb, its state count, its source |
| `GET /preview/{component}` | the canvas: every state stacked, each under its name and note, each with an anchor |
| `GET /preview/{component}/{state}` | one state alone, whole page — what `sleepy shot` opens |

```text
woodcase preview                      the index, on the next free port from 7333
woodcase preview outline-panel        straight to one component's canvas
woodcase preview --list               the catalog and every state's URL, on stdout
woodcase preview --list --json        the same for an agent
```

`preview` is `serve` with no files: the same `ViewerServer`, an empty file index, no log,
no watcher. It prints the URL alone on stdout the way `serve` does, takes `--port` and
`--open`, and needs nothing on disk — no `.pen`, no `.woodcase/`. `serve` gets the routes
too because a person already looking at a file should not have to start a second process
to check a component. The index and the canvas are themselves components, with previews.

### What it is not

- **Not a second renderer.** A state's markup comes from the same component, the same
  `ViewerDocument`, the same stylesheet and script production serves.
- **Not a pixel-diff harness.** The goldens are the regression test, and they test
  markup. There is no screenshot comparison; every state has a stable URL, so that door
  stays open, and `scripts/mae-check` already knows how to walk through it if wanted.
- **Not a proof of the derivation.** A clean canvas says the component renders its
  states right, not that the server produces those states from a document. The
  integration tests keep that job.

### The golden tests afterwards

`ViewerGolden` stops holding fixtures and becomes one parameterized test over
`PreviewCatalog.all`: for every component and every state, render, compare with
`Fixtures/golden/<component>/<state>.html`, bless with `UPDATE_GOLDEN=1`. The 34 existing
goldens are renamed to the catalog's slugs and re-blessed; the diff after the rename must
be **empty**, which is how the move proves it carried every state verbatim. The behaviour
tests in the same files (a chip carries `data-copy-id`, four identities cap at three) stay
where they are — they test behaviour, not pictures.

## Plan

Three leaves in sequence-then-parallel, and a fourth that is the point of the whole thing.
A new root, because no open tree holds the viewer's UI work; Ben asked for this on
2026-09-02.

```yaml
tasks:
  - title: Viewer previews — every component's states, served
    desc: |
      The viewer's #Preview is a golden HTML file per state, declared in the tests and
      visible to nobody. Move the state declarations into the viewer target as a
      catalog, keep the goldens as the regression side of it, and serve the catalog
      as an index of components and a canvas per component, so a person can sign off
      on a change and an agent can look at what it built. Design and rules in
      project/2026-09-02-viewer-previews.md; read it first.
    labels: [viewer, previews]
    children:
      - title: The catalog, with every existing state moved into it
        ref: catalog
        desc: |
          PreviewState, PreviewComponent, PreviewCatalog and PreviewFixtures in
          Sources/WoodcaseViewer/Previews/. Every state ViewerGolden.check names today
          moves verbatim into Components/Previews/<Component>+Previews.swift, with a
          slug, a name and a note. ViewerGolden becomes one parameterized test over the
          catalog, goldens renamed to <component>/<state>.html. The state's value is
          the production prop type, never a preview-shaped copy. Frames are declared
          but not yet styled: that is the host leaf's.
        criteria:
          - Every one of the 34 existing goldens has a catalog state, and the re-blessed goldens differ from the old ones only in path
          - No *PreviewTests.swift file calls ViewerGolden.check directly; one catalog-driven test covers them all
          - Every state has a note
      - title: The host — /preview routes, the preview verb, frames in the stylesheet
        ref: host
        blockedBy: [catalog]
        desc: |
          GET /preview, /preview/{component}, /preview/{component}/{state} in
          ViewerPages; PreviewIndex and PreviewCanvas components (with previews of their
          own); the frame widths in ViewerStylesheet and a Previews paragraph in
          DESIGN.md; `woodcase preview` in WoodcaseCommandCore as serve-with-no-files,
          with --list, --list --json, --port and --open; WoodcaseViewer.md and
          WoodcaseCLI.md. A browser test proves one state page renders through the
          real stylesheet in both colour schemes.
        criteria:
          - "`woodcase preview --list --json` prints every component and every state with its URL, and exits 0 with nothing on disk"
          - Every state URL renders the state inside the frame it declares, through the real stylesheet and script
          - Both `woodcase serve` and `woodcase preview` answer /preview
      - title: The states no golden ever had
        ref: gaps
        blockedBy: [catalog]
        desc: |
          Audit Components/ against the catalog and add the representative states that
          are missing, with notes. Known gaps on 2026-09-02: LiveBadge in all three
          ConnectionStates; IdChip copied; KindMark in every kind; EditMarker;
          SelectionBar long and short; KeyboardHint; PaneGrip; EmptyPage and
          FileEmptyPage; the unread dot on a crumb and on a file card; RelativeAge at
          each boundary. Representative, not exhaustive; a state that exists only
          under the script (a copied chip, a dropped stream) is declared by setting
          the attribute the script would set. Touches only +Previews.swift files and
          goldens, so it runs beside the host leaf.
        criteria:
          - Every component under Components/ appears in the catalog with at least one state
          - Every new state has a note saying what to look at
      - title: First review pass over the whole catalog
        blockedBy: [host, gaps]
        desc: |
          Shoot every state with sleepy into local/viewer-shots/, light and dark, and
          look at them: this is the pass the previews exist for. Every defect found is
          filed as an issue with the state's URL; nothing is fixed in this leaf. Then
          send the contact sheet to Ben for sign-off.
        criteria:
          - Every state in `preview --list` has a shot in both schemes
          - Every visual defect found is an issue naming the state URL
```
