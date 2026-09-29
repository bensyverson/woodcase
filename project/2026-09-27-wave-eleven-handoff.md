# 2026-09-27 — Handoff, wave eleven: the 0×0 frame, React against Pen, Penumbra catch-up

The eleventh integrator session, following [wave ten](2026-09-27-wave-ten-handoff.md). Start with `job orient`,
then this doc. Eleven Woodcase and Penumbra agents ran to completion (plus the first five, stopped mid-wave and relaunched from their trails) (at most five at once, `-j 3`; all Opus except one Sonnet).
Every one answered the brief-errors question, and several briefs were wrong in ways that mattered (below). Every
Woodcase merge went through a full or targeted `swift test -j 3` on the combined tree before it was pushed; the only
failures all wave were WebKit `__READY__` timeouts under load (all pass alone) and the `--follow` orphan test
(`jBvokK`, below).

## What landed

| Commit | Leaf | What |
|---|---|---|
| `b0c0922` | `55P02C` | `activity --follow` records its launcher before the first print: a real race (15/100 hung → 0/100 in a SIGSTOP repro), not a slow notice. **Not the whole story** — see `jBvokK` |
| `0ee3fad` | `MY1B1R`, `3n7gRZ` | React: `fit_content(N)`/`fill_container(N)` fallbacks, layout-none frames at 0×0, no `align-items: stretch` on a fitted frame (`ChildPlacement` drives pivot and sizing); meshes baked at `Options.meshRasterScale` (2x, cap 1024 px). 12 boards off the baselines. A 240×180 mesh's data URI grows ~5 KB → ~118 KB |
| `091cb64` | `nxLzvE` | The "14 minutes in `effectiveRefData`" was an **endless walk**: the test's `moveToAnotherRoot` made self-placing components and `TreeView` had no cycle rule. It now stops where `PenRefExpander` stops; each row settles its ref in one step. Equivalence test compares expanded rows (16.7 s) |
| `c746990` | `0IegsD` | `PenFontRegistry.registerFont(at:)` is the one registration API and moves the font generation only on `.added`. tirekick with two declared fonts, 20 write+tree rounds: 7.4 s → 2.8 s |
| `5e8a3fc` | `Jg0BOv` | **A sizeless `layout: none` frame settles at 0×0** (Ben's ruling): `fit_content` there is its fallback. Zero-area stroke band in CG and SwiftUI; `perSideRing`'s standardized-`CGRect` hole fixed; lint `collapsed-absolute-frame`; Pen-oracle fixture `render-sizeless-frames.pen` (CG 1.3–6.3 → 0.00–0.01). PenEngine.md's inferred union rule corrected in place |
| `eb2a33d` | `6vLFNQ` | Material Symbols glyph shapes: Core Text's **automatic optical sizing**, not the font build (Pen draws opsz 24 with only `wght`, read from Pen's own `getIconPath`). Off for icon fonts in CG and SwiftUI; gates tightened |
| `44f477b` | `8xg1Mt`, `qtWkxA` | Emitted names never shadow JS/web/React globals (`StringPage`, `TextComponent`); icon imports alias clashing names (three Material styles imported `VpnLock` three times — did not compile). The React harness loads the committed Google faces and every icon family: ten font-face boards 5–25 → 1.2–1.8 (better than CG), now in `ceilings` |
| `cb4da85` | `Iq14HI`, `n8SitJ` | Descendant-key and injected-node walks run from a work list (1.7–1.8 MB → <128 KiB stack); `TreeRow.overflowAxes` is an ordered array, so `tree --json` is deterministic |
| `7320cbb` + RapidPro `37c4063` + Penumbra `6c03081` | `rkYhcz`, `0Kcd1D` | **A turned node's unturned size rides on its layout rect** (`PenRect.unturnedSize`, `drawnSize`, `bounds`); the solver and the 45° re-layout fallback are deleted; `unturnedBox(of:rect:layoutRects:)` reads it (**breaking**: RapidPro and Penumbra's parity test updated). New public `PenLayoutEngine.canvasTransform(of:in:layoutRects:)` and a public `PlaneTransform` (`inverted()`, `cgAffineTransform`). Reported rects (`absoluteRects`, tree rows, root overlaps) stay plain bounds |
| Penumbra `d26c13c` | `zzxHpw`, `O0X2i7` | Penumbra already built against both libraries' main. The real bug: `AbsoluteRectBuilder` summed parent origins, so selection/hover/hit-test/drag missed group children and anything under a turned frame. It now calls `PenLayoutEngine.canvasRects`; drag reads resolved positions |
| Penumbra `24b25f6` | `TQTK6K` | Drag under a turned or flipped ancestor maps the canvas delta into the parent's space (move and Option-copy) |

## Ben's rulings this session

- **`Mu4JsL` (React):** text inner shadow — keep idiomatic CSS, emit without it plus a generate-time warning, keep
  the boards baselined as a documented CSS limit. Group shadows — keep today's drop-shadow of painted content,
  documented, baselined; do not revive the SVG silhouette. Everything else on the leaf is a fix. Recorded on the leaf.
- **The Swift LSP plugin stays off for fan-out waves** (it typechecked every agent's edits at up to six cores).
- **Pause after this wave** to save context; handoff here.

## Two-way decisions made unattended

- React mesh rasters at 2x by default (the size cost above); callers can lower `meshRasterScale`.
- `Mu4JsL` sorting into fix / design call before asking Ben.
- The React font-face boards went to `ceilings` (React now beats CG there, and the suite's rule holds such a board
  to its own MAE).

## Still open

- **`BpaSrF`** (fidelity, the last open leaf of `LxFb4C`): which IBM Plex face Pen draws. **Run it alone** — it moves
  many gates; `layout-text-vertical-fill` and five React `.plexGlyphs` boards wait for it.
- **`Mu4JsL`** React effects and turned slots — ruled, ready to build: turned flex child's slot, angular gradients on
  SVG shapes/strokes, inner per-side borders shifting children, a stroke-less line drawing `currentColor`, inner
  shadow over the stroke, a 0×0 box's stroke band; plus the two CSS-limit warnings. **`AyTAji`** (Material weight
  200 to the React icon component) is small and sits in the same files.
- **`jBvokK`** `followStopsWhenOrphaned` still failed once each in two loaded full runs after `b0c0922`. Capture a
  failing run (follower's state, `sample` if alive) before theorizing.
- SwiftUI gap (on `Mu4JsL`'s note): `penDropShadow` casts from the shape only, so a stroke never casts a shadow.
- **Penumbra follow-up (no leaf: Penumbra has no issue tree yet — ask Ben before creating a root):** replace
  `DragController.canvasToParentMaps`' own ancestor composition with
  `PenLayoutEngine.canvasTransform(of: parentID, in: resolvedDocument, layoutRects:)?.inverted()`, linear part only
  (drop `turn(of:)` and `resolvedAncestors`; the call site in `CanvasView+Selection` has `layoutRects`).
- **RapidPro's main checkout** has uncommitted `agents` rules drift (`.agents.yaml`, `project/agents/*.md`, `.jobs/local.json`, and two untracked `.jobs.db.*` files) — the same refresh Penumbra had; not touched this wave. Ask Ben before committing it.
- **A design choice to review:** the unturned size lives *on* `PenRect` (optional, part of equality, encoded only
  when present) rather than in a parallel map, so every cache and copy carries it for free. The cost is that a rect is
  no longer just bounds; readers that report bounds call `.bounds`. Reversible if Ben prefers a separate type.

## Traps hit this session

- **Synthetic load outlives the agent.** Orphaned `yes` burners from a repro plus `sourcekit-lsp` pinned the Mac at
  load 70 and the wave was stopped (gotchas 2026-09-27). Every brief now says "never generate synthetic CPU load".
- **A stopped agent cannot be resumed**, but its worktree survives: condense its transcript into
  `<leaf>-predecessor.md` (`scripts/agent-trail`) and brief a fresh agent to continue from it and `git diff` (gotchas 2026-09-27). All five
  resumed without restarting.
- **Don't squash-merge into the main checkout while `swift test` runs there** — it aborts the build; snapshot the
  agent branch and merge after.
- **Penumbra's pre-commit hook builds against the Woodcase checkout**, staged merges included; commit Woodcase first.
- **Briefs were wrong often and usefully:** the `effectiveRefData` "cost" was a cycle; the `--follow` "slow notice"
  was a race; the Material "font version" was optical sizing; `mfold`'s "Pen draws black" was transparent; Penumbra
  "doesn't build" did. Keep asking question 7.
