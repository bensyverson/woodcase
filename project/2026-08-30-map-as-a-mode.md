# The bird's-eye map as a mode, not a band

*2026-08-30. Author: Claude (Fable 5) with Ben, after reviewing the first viewer
captures from [the agent-first plan](2026-08-30-agent-first-cli-and-viewer-plan.md).*

## What was wrong with the first version

The map landed as a replacement for the artboard strip: a 150-point band above the
render, permanently. Sharing the pane with the artboard made the boxes tiny — at fit
zoom on a wide file every box is under 24 px and unlabeled — and the code toggle,
placed in the same flex row, rendered as a full-height column. Ben's picture was
different: the bird's-eye is a *view you click into*, and clicking a box reveals the
full artboard.

## The shape

**Two canvas modes.** The canvas pane shows either the map or one artboard.

- The map is the landing view for a file with more than one artboard; a single-artboard
  file skips straight to its artboard. The map fills the pane: each box is a real
  low-res render (the render cache already caps PNGs by longest side) with the name
  beneath it, KindMark badge, unread dot and edit markers visible on the thumbnail.
- The artboard view has **no band** — the render gets the whole pane. Navigation lives
  in what already exists: the breadcrumb (`Files / woodcase-app / Home – Collection`,
  where the file name is the link back to the map and carries a map glyph and an
  unread dot when something changed elsewhere), the selection footer (gains
  `‹ 3 of 5 ›` prev/next controls), and the keys (←/→ step artboards, Esc selects the
  selection's parent, then its parent, up to the root, then the map). In map mode ←/→/↑/↓ move between boxes and
  Enter drills in.
- Follow mode drills into whichever artboard was just touched, as now. The
  `#v-tabs` fragment and route go away; the map is a page state, not a strip.
- **On the map page the Outline lists the artboards** (Ben, after the first draft):
  one row per artboard in document order, with the same KindMark, rect and id chip a
  node row has; a click drills in, and ↑/↓ in map mode move one focus ring through the
  rows and the boxes together. The node outline returns in artboard view.
- The code toggle moves out of the canvas into the right pane's tab bar beside Export
  (a control, not a tab), and the code pane's own header keeps the language picker.

## Tasks

```yaml
tasks:
  - title: The bird's-eye map as a mode
    desc: |
      Design in project/2026-08-30-map-as-a-mode.md; read it first. Two leaves with distinct file surfaces; the code-toggle leaf is small and can land first.
    labels: [agent-first]
    children:
      - title: Map view and artboard view as two canvas modes, with thumbnails
        desc: |
          The canvas pane shows either the bird's-eye map (landing view when the file has more than one artboard; full pane; each box a low-res render from RenderCache with name, KindMark, unread dot and edit markers) or one artboard with no band above it. Single-artboard files land on the artboard. Breadcrumb file name links back to the map with a map glyph and an unread dot; the selection footer gains prev/next artboard controls; keys: in map mode arrows move between boxes and Enter drills in, in artboard mode Esc goes up to the map before clearing selection. Follow drills into the touched artboard. Retire the #v-tabs fragment and route; update WoodcaseViewer.md and the goldens. Browser tests for landing rules, drill-in, back, prev/next, Esc, and that follow still moves.
        criteria:
          - A two-artboard file lands on the map and a one-artboard file lands on its artboard
          - Clicking a box opens that artboard with no band above the render
          - The breadcrumb returns to the map and the footer steps prev and next
      - title: Move the code toggle into the right pane's tab bar
        desc: |
          The code split-view toggle leaves .v-canvas-head (which goes away with the band) and becomes a control at the end of the right pane's tab bar beside Export, styled as a toggle not a tab; the code pane header keeps the language picker. Golden updated; browser test that the toggle opens and closes the split view.
        criteria:
          - No code toggle renders in the canvas pane
          - The tab-bar toggle opens and closes the code pane
```
