# 2026-09-28 — Handoff, wave thirteen: the fidelity plan closes; Woodcase's tracker is empty

The thirteenth integrator session, following [wave twelve](2026-09-28-wave-twelve-handoff.md). **Woodcase has no open
leaves**: the fidelity plan `LxFb4C` closed with `BpaSrF`, and the issue tree is empty. RapidPro and Penumbra are empty
too. Ben's next step is a review of the SwiftUI output; start there with `job orient` (it will report `target: null`)
and whatever Ben brings.

Six agents ran (five Opus, one Sonnet; at most five Swift agents at once, `-j 3`). Each one closed the small bugs it
found on its own branch before merge (Ben's rule this session, below). The combined Woodcase tree passed one full
`swift test -j 3` after all four Woodcase merges: 4140 + 1040 + 169 + 495 tests, no failures, no re-runs.

## What landed

| Commit | Leaf | What |
|---|---|---|
| `86dabba` | `ozlazY` | React and SwiftUI give a turned `fill_container` child its turned slot (`TurnedFillSizes`, fixed box when the container's numbers fix it, else a warning). `render-turned-fill.pen` from Pen's **settled** layout via the new `pen-oracle --settle`: CG 0.000–0.018, React 0.000–0.120, SwiftUI 0.000–0.117; `row-cross-fit-30` is the documented limit |
| `c155df0` | `BpaSrF` | Pen draws IBM Plex Sans from Google's variable face (gstatic v23); the suites now register it. The real gap was three Woodcase bugs: static families drew 500/600 one weight light (`PenFaceMatching`, CSS font matching by OS/2 weight class, in the renderer and the emitted SwiftUI); React put every text's first baseline a device pixel off Pen's whole point (margin pair; layout-text 1.8–4.4 → 0.80–1.50); a squeezed fill got 0 pt where Pen gives 1. `scripts/pen-font-audit`: 1,874 of 1,899 families agree, the rest is google/fonts catalogue drift. [The finding](2026-09-28-pen-font-faces.md) |
| `163784f` | `4fZZ38` | React draws inner shadows on SVG shapes and icons (SVG filter, 2.7–6.3 → 0.02–0.29); CG draws an icon's inner shadow; CG and SwiftUI clip a ring's inner shadow even-odd (19.97 → 0.39); a flat line's stroke paint lies over its band in every target (a kept divergence); stacked CSS backgrounds and blend names fixed; one warning per shadow (`InnerShadowRoute`) |
| `7dbca23` | `slxqjU` | `shot --extent painted` grows to whole pixels as Pen's export does; `ShotCommand` split; text and icon painted extents are their glyph outlines (Pen's `computeVisualLocalBounds`); public `ownInk(of:box:)` and `strokeBandContains(_:of:box:)`; `paintedExtent` per node over `woodcase-app.pen`: 39.1 ms, debug |
| RapidPro `fd35312` | `3Jg2Xd` | Culling reads Woodcase's `paintedExtent`; RapidPro's own computation is gone (layer blur now counts, fixing a tile-edge seam). Line-shadow test pinned (already true) |
| Penumbra `9409eda`, `771df2e`, `bebe73b` | `hhcyOb`, `Fs6Aeo` | Selection hits the turned box, then the true stroke band (Woodcase's `strokeBandContains`), inside the painted extent (`HitShape`); drag inverts Woodcase's `canvasTransform` |

## Ben's rulings this session

- **Close more leaves than we open; findings go back to their finder.** A small bug an agent reports is sent back to
  that agent to fix on its branch before merge, not filed; widen a running agent's leaf rather than mint a sibling.
  Written into the shared `delegation.md` (agents-md `4c5bfe8`: a fifth headline rule and a new step 6), synced
  into Woodcase, RapidPro (`3081459`) and Penumbra (`29172e8`).
- **Make it general, not Plex-only:** hence `scripts/pen-font-audit` over Pen's whole font table.
- **Keep behaviour that beats Pen** (standing, 2026-09-26) decided the flat-line ramp: Pen collapses a ramp across a
  zero-height line to a split or black; all three targets paint the ramp (PenInteroperability, *Kept Divergences*).
- **Font source:** no decision needed. The committed files' versions match Pen's pinned gstatic ones (0 differing
  advances over 9,472 codepoints); the note recommends an alias table for google/fonts' renamed families as a cheap hedge.

## Open, none filed (parked in the backlog, 2026-09-28)

- `layout-text-chips` keeps 2.64 in React: Pen seems to round auto-width labels up to a whole point; not measured.
- React's first-baseline correction covers top-aligned text only; middle/bottom and explicit `lineHeight` pitch are
  unrounded in CSS where Pen rounds.
- React and SwiftUI still give a squeezed fill 0 pt where the engine and Pen give 1.
- `paintedExtent` walks each node's subtree, so a caller that asks per node (RapidPro, Penumbra) measures text once
  per ancestor. 39.1 ms debug for 974 nodes; no before figure. Cache if it shows up in a profile.
- Text painted extents stay 2–15 px off Pen's (Core Text against Skia glyph metrics and line breaks).

## Traps hit this session

- **A bare `fatalError` from `swift test --quiet` was a compile error, not the disk** (gotcha rewritten): one agent
  lost two hours reading it as disk pressure and handed back a test file it believed compiled. Strip the colour
  codes before grepping a build log.
- **The disk really was low** (0.5–2.6 GiB free at times): five worktrees at ~1.7 GB each plus the main `.build`.
  Snapshot a finished agent's branch and remove its worktree at once; Finder's "Size" is logical bytes, use `du`.
- **An agent extracted Pen's 7 MB `index.js` into the repo root**; deleted at integration. Read `app.asar` in place
  or into scratch, never into the repo.
- **My own finding was wrong once** (a drag under a `ref` parent): the Penumbra agent showed a ref never parents
  nodes in the editable store. Question 7 cuts both ways.
- **`cd` into a worktree moves the session's working directory**; use `-C` and absolute paths.
