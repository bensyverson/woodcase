# Viewer review feedback — 2026-08-30

Ben reviewed the viewer end to end against `local/viewer-demo/` on `woodcase serve`
(port 7333, build `2c00db0`) and delivered the punch list below. This doc is the
aligned version: each item was discussed, three open questions were decided, and the
whole set is filed as the `tasks:` block at the end (loaded with `job import`).

## Decisions made during the review

- **Root Files view becomes cards**, not rows — larger thumbnail, more recents
  visible. The thumbnail slot exists today but was never wired to an image.
- **Code becomes a tab in the right pane** (Details / Export / Activity / Code),
  retiring the vertical render+code split and its pane grip.
- **Activity history backfilled.** The feed was empty because the store moved from
  `~/.woodcase/` to per-repo `.woodcase/` on 2026-08-30 and the repo copy did not
  exist yet; the 13 historical events were copied over (`cp ~/.woodcase/activity.jsonl
  .woodcase/activity.jsonl`). The feed shows all recorded history, not
  since-server-start — this was a data location issue, not a display one.
- **Presentation mode (`f`) spec**: artboard background + rendered artboard and
  nothing else; a brief "Press f or Escape to exit" overlay flashes on entry; arrow
  keys navigate without leaving the mode.
- **Long selection titles front-truncate**, keeping the most specific tail of the
  path visible (`…/Fav Card 2/Pencil Image`, not `Home — Collection (Light)/Con…`).

## Root causes already suspected

- The instance/nested-component selection failures and the Details error
  `'224Gu/oqIX' names no node in this file` look like one bug: expansion id-paths
  (`Chi01/Lbl01`) not matching what the outline and details endpoints expect.
- Arrow-key navigation exiting `f` mode is a consequence of full-page reloads, not a
  bug of its own; it falls out of the client-side navigation work.

  > **Correction, 2026-08-30 (leaf lS7YE).** Half of this section's premise — and of
  > the client-side-navigation task below — was wrong, and the correction matters
  > because it points at a different fix. *Arrow keys* did reload: `stepArtboard()`
  > clicked the footer's step link and nothing intercepted it. *Outline row clicks did
  > not*: they have always been a `pushState` plus two fragment swaps. What made them
  > feel like reloads is that a swap replaces `#v-outline`, which **is** the scroll
  > container, so the panel came back at row one and `revealSelection()` then parked
  > the selected row against the bottom edge — the whole tree appeared to jump on every
  > click. The fix is to carry `scrollTop` across the swap, not to make the click
  > client-side; it already was.


- The `(?)` key hint "doing nothing" is because it is a `title`-attribute tooltip —
  it works only on hover, slowly. It becomes a real popover.

## Tasks

```yaml
tasks:
  - title: Viewer review polish (2026-08-30)
    desc: Umbrella for Ben's 2026-08-30 end-to-end viewer review. Each leaf is grouped by the surface it touches; the full context and decisions are in project/2026-08-30-viewer-review-feedback.md.
    labels: [viewer, review-2026-08-30]
    children:
      - title: Fix selection and details for nodes inside component instances
        ref: selection-correctness
        desc: Clicking an element inside an instance of a component selects nothing in the Outline, even though the Outline shows the component's whole tree. The same happens one level deeper — a component containing another component. And the Details pane sometimes rejects a real selection with "'224Gu/oqIX' names no node in this file". These look like one root cause — expansion id-paths ("Chi01/Lbl01") not agreeing between the render overlay, the outline rows, and the details endpoint. Two adjacent tab-state bugs live in the same files and belong here — when a node is selected the right pane shows Details but the Activity tab stays highlighted, and clicking the Details tab then LOSES the selection ("Select a node — in the outline or on the render — to see what it carries") while the node stays outlined on the render.
        criteria:
          - Clicking a node inside a component instance selects the matching outline row
          - Clicking a node in a nested child component selects the matching outline row
          - Details never reports "names no node" for a node reachable from the outline
          - The highlighted right-pane tab always matches the pane being shown
          - Clicking the Details tab with a node selected keeps showing that node's details
      - title: Client-side selection and navigation without page reloads
        ref: client-side-nav
        desc: Arrow keys and outline clicks currently force a full page load, which makes keyboard navigation slow, jumps the Outline scroll position on every click, and throws the viewer out of presentation mode. Progressively enhance — server-rendered pages keep working with JS off, but with JS the selection, outline highlight, details pane and artboard switch update in place. Clicking the area outside the artboard should clear the selection (also client-side).
        criteria:
          - Arrow-key artboard navigation updates in place with no page load
          - Outline clicks select in place and preserve the outline scroll position
          - Clicking outside the artboard clears the selection
          - With JS disabled the server-rendered navigation still works
      - title: Presentation mode shows only the artboard
        ref: presentation-mode
        blockedBy: [client-side-nav]
        desc: Pressing f currently shrinks the render to oblivion and leaves blank chrome. It should show the artboard background and the rendered artboard, nothing else, with a brief "Press f or Escape to exit" overlay flashed on entry. Arrow keys keep working and stay in the mode (the exit-on-arrow bug is the page reload, fixed by client-side-nav). Add a fullscreen icon button in the top bar next to the key hint so the mode is discoverable without the keyboard.
        criteria:
          - f shows only the artboard on its background, correctly sized
          - An exit-hint overlay flashes on entry and fades
          - Arrow keys navigate artboards without leaving the mode
          - A top-bar button enters the mode
      - title: Scope the Outline to the showcased artboard
        desc: With an artboard loaded, the Outline lists every artboard, component and instance in the file; it should show only the tree of the showcased node. Drop the x/y and w/h columns from outline rows — they are noise there and live in the Details pane — but keep them on the artboard list shown before a selection. Replace the tiny text disclosure triangles with a small SVG glyph (shared with the Variables pane).
        criteria:
          - The outline shows only the showcased artboard's tree
          - Outline rows carry no x/y or w/h; the pre-selection artboard list still does
          - Disclosure triangles are SVG and comfortably clickable
      - title: Variables pane title and expanded-variable redesign
        desc: Left-align the Variables pane title next to the disclosure triangles. The expanded single-variable view is unattractive — an indented floating label and bullet list. Redesign as a tabular format under a disclosure triangle; for color axes show a swatch beside each hex value (mode=light shows its color, not just #FFFFFF).
        criteria:
          - Pane title is left-aligned beside the disclosure control
          - An expanded variable renders as a table of axis rows
          - Every color value in the expansion carries a swatch
      - title: Code becomes a tab in the right pane
        desc: Retire the vertical render+code split and its pane grip; Code joins Details / Export / Activity as a right-pane tab. Decision from the 2026-08-30 review — one fewer vertical pane, less horizontal squeeze.
        criteria:
          - Code renders as a right-pane tab with the existing target picker
          - The split view and its grip are removed
      - title: Map view hover and glyph polish
        desc: The artboard hover outline uses a color that gets lost on light artboards — use the selection color instead. The kind glyphs inside Component/Instance bubbles should be larger relative to the bubble and perfectly centered both axes.
        criteria:
          - Hover outline uses the selection color
          - Bubble glyphs are visibly larger and optically centered
      - title: Root Files view as cards with live thumbnails
        desc: The file list reserves a thumbnail slot that never gets an image; wire it to a real artboard render. Replace the rows with a card grid — decision from the 2026-08-30 review — so thumbnails are larger and more recent files fit.
        criteria:
          - Each file card shows a rendered thumbnail
          - Files render as a card grid, most recent change first
      - title: Top bar brand, key hint and title truncation
        desc: The brand becomes just "woodcase" and links to the site root, which removes "Files" from the breadcrumb. The (?) key hint is a title-attribute tooltip today, which reads as doing nothing — make it a real popover. Long selection titles overflow their box — front-truncate so the most specific part of the path stays visible. Drop the "click a node to outline it" caption under the render. And the connection indicator lies when the connection drops — it goes amber but still reads "live"; the label must change with the state, "disconnected" when the SSE stream is down.
        criteria:
          - Brand reads "woodcase" and links to the root; breadcrumb loses "Files"
          - The key hint opens a popover on click
          - Selection titles front-truncate
          - The click-a-node caption is gone
          - A dropped connection reads "disconnected", not an amber "live"
```
