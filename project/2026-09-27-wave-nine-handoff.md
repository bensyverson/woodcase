# 2026-09-27 — Handoff, wave nine: SwiftUI packaging, the fidelity-gaps tree, React measured against Pen

The ninth integrator session, following [wave eight](2026-09-27-wave-eight-handoff.md). Start with `job orient`,
then this doc. The SwiftUI codegen tree (`n42KDh`) closed this wave; Ben then chose three tracks — **fidelity
gaps**, **incremental settle** and **consumer catch-up** — and the fidelity tree (`LxFb4C`) is where the work now
lives. Ben was away for most of the session and pre-authorized two-way decisions; they are listed below.

Every commit here went through a full `swift test -j 3 --quiet` over the combined tree before it was pushed. The
machine ran at load 100–200 with five agents building, so the suite's WebKit tests and time budgets failed
repeatedly on load alone; each such failure was re-run with `--filter` and passed. See *Traps*.

## What landed

| Commit | Leaf | What |
|---|---|---|
| `4f441c6` | `PRFPX5` | CG draws unfilled text/icons as nothing (`PaintRoute.nothing`); an enabled solid that does not parse still draws black, as Pen does. `render-text-unfilled.pen` pins 11 fill shapes (8.95 → 0.000) |
| `6c6438b` | `Dc3tN9` | SwiftUI churn guard: `swiftui-vocabulary.txt` (399 SDK paths, `@available`/`@only`), `SwiftUIVocabularyTests`, `swiftui-api audit` green at 26/26 and 18/15, `SwiftUIChurn.md` yearly checklist; four soft deprecations fixed |
| `721cd59` | `oozXCK` | SwiftUI packages bundle and register text fonts (`PenFonts`, from file URLs, on first use), regenerate `Package.swift` every run (**breaking**: don't edit it), `help codegen` covers SwiftUI, `SwiftUIPackageBuildTests` runs `swift build` on a real package |
| `0d4facd` | `cHuvso` | Text measured in one typesetting pass (proven equal over 54,432 cases); `PenTextLines` public |
| RapidPro `ee51b35` | `UzE2Ou` | TextRasterizer places lines through `PenTextLines`; explicit-lineHeight boards 0.38–0.91 vs CG (were 0.75–5.8) |
| `2b43927`, `75a879c`, `955a0b6` | — | [Fidelity-gaps inventory](2026-09-27-fidelity-gaps.md), its Pen-oracle fixtures, `scripts/png-mae`, the plan, Ben's rulings |
| `5b9c4fd` | `T5l1ul` | SwiftUI render batch: killed children name themselves (typed `ProcessOutcome`), 30-min deadline, `swiftc -j 3`. Typecheck dominates the batch; no split |
| `7144191` | `K68yo3`, `Wo6Vni` | One naming rule for pages and components (`CodeGenName`), pages disambiguated at the source; React unfilled text/icons `color: transparent` |
| `43f6158` | `onFiTm` | PenInteroperability.md's stroked-path "Pen bitmap offset" cause marked wrong (stale reference) |
| `9df1eb9` | `MdCEmo` | Root overlap measured from the roots alone (`EditableDocument.rootRects`, exact vs a full settle over 185 fixtures); instance roots now counted (bug). `set`: tirekick 836 → 289 ms; woodcase-app 416 → 352 ms release. Verb budget held at a measured 550 ms until `KXKtc7` |
| `3d55f33` | `DAmmQF` | Google fonts resolve per face (`PenFontFace`, CSS face matching from cached METADATA); bold/italic boards 7–16 → 2.2–2.7 |
| `e55c44b` | `ILBcZv`, `GInRSg`, `dYIzYU` | React icons painted with gradients/images via SVG paint servers; SVG shapes honour enabled fills; components numbered case-insensitively; `shader-not-drawn` lint + render/shot/React warnings |
| `a04ec23` | `nAuBKh` | Free nodes turn and flip about their x/y anchor (`freeRect`) in layout, CG and SwiftUI; `txt-rotated` 7.33 → 0.017 |
| `b52fb32` | `vXVtb1`, `5y8hO5` | WebKit harness names fonts by family; `ReactRenderWebViewTests` measures React on 221 renderer boards against Pen |
| `8f142c9` | `VMKixs` | Icons placed by font metrics (advance centred; hhea line box rounded at 14 pt); `icon-font-test` 5.25 → 1.24 |
| `d58e708` | `vVgtB2` | CG and SwiftUI draw text inner shadows (CG drew none); SwiftUI text boxes round up to whole points |
| `c573ade` | `46XAVC` | SwiftUI remote images via `AsyncImage` at draw time |
| `2d248ec` | `bLU8nV`, `Qfm8i8` | Per-side widths on sideless shapes stroke at the top width with the node's alignment (`PenStrokable.drawn(on:)`); React SVG fills painted; paths without a viewBox map their tight bounds |
| `5817d96` | `KXKtc7` | Instance overrides applied in memory (`PenNodeOverlay`, `AnyCodableDecoder`; the JSON merge stays as fallback and for refusal wording), proven identical over every fixture; the writer's per-line `Regex` replaced by a byte scan. `set` verb 386 → 166 ms in process (budget back to 200 ms), `tree` woodcase-app 268 → 153 ms, expand 104 → 25 ms (loaded, interleaved) |
| RapidPro `caec71e` | `ncjB79`, `PWxvg7`, `LT1v59` | Text/icon ink (topmost enabled solid; none draws nothing), `textAlignVertical`, icon placement — mirrors of Woodcase internals until `6fu79C` |

## Ben's rulings this session

- **MdCEmo:** (a) + (c) — measure roots without a full settle, and budget the verb as a caller sees it. (b), the
  skip heuristic, rejected.
- **Tdgxuz:** first parked, then un-parked ("perf: incremental settle"), to follow `KXKtc7`.
- **Next tracks:** fidelity gaps, incremental settle, Penumbra/RapidPro catch-up. Linux stays parked.
- **"Better than Pen":** don't chase parity where Pen is likely to catch up; classify every gap (Woodcase wrong /
  Pen bug kept on purpose / design call for Ben).
- **D1/D2:** ignore shaders and scripts for now — parked in [backlog.md](backlog.md); the warnings stay.
- **D3:** follow Pen's top width on sideless shapes (applied to ellipses, polygons, paths and lines).
- **D4:** SwiftUI remote images use `AsyncImage`.

## Two-way decisions made unattended

- **Dc3tN9 dispatched in parallel with its blocker** `oozXCK`, with `oozXCK`'s new APIs listed at merge.
- **The set-verb budget held a measured 550 ms ceiling** rather than a known-red 200 ms test, until `KXKtc7` brought it back to 200 ms the same day.
- **Shader warnings kept** after "ignore shaders" (cheap, honest; say so if unwanted).
- **D3 applied to polygons, paths and lines** as well as ellipses — same reasoning; lint explains it.
- **Kept on purpose (Woodcase better):** Pen draws its `help` placeholder for Material `expand_more` (Woodcase draws
  the icon); Pen draws a checkerboard for an unloadable image (Woodcase draws nothing).
- **React rotated-text boards baselined** on optical size once CG caught up (`34185c8`).
- **RapidPro mirrors Woodcase's ink and icon rules** until `6fu79C` makes them public, rather than editing
  Woodcase from a RapidPro agent mid-wave.

## Still open

- **Fidelity (`LxFb4C`):** `0M8jRo` React effects → `3Xbv46` React natural line height; `50MfO5` centred box
  strokes inside the box; `SctC0l` SVG line hangs; `cqBw2i` group union with negative offsets; `INL8Zi`
  `absoluteRects` under turned frames; `Jg0BOv` 0×0 `layout: none` frame (**classify first**, may be Ben's call);
  `BpaSrF` which Plex face Pen draws (run alone — it moves many gates); `QP5E24` SwiftUI themed numbers (last).
- **Issues:** `Tdgxuz` next (incremental settle; `KXKtc7`'s agent found parse, 64 ms, is now `tree`'s largest stage, and half of `set`'s overlap cost is Core Text typesetting the same texts twice — a text-size cache shared across settles would help both);
  `Gmh2sB` React `font-optical-sizing: none` (moves most React text baselines — do it before re-baselining);
  `dSwsw3` the 121 React baselines as a worklist; `8xg1Mt` JS-global names; `6fu79C` public ink/icon API;
  `rkYhcz` layout should carry unturned size; `6vLFNQ` Material glyph shapes; `oiUTFr` **re-measure every budget
  on a quiet machine** — nothing this wave was timed quietly; the synthetic `tree` budget has 1.09× headroom and
  the `set` verb 1.2×.
- **RapidPro (`iDXenh`):** `SdtjDG` glyphs half a pixel low (atlas flip?); `WJHlhu` gradient/image text.
- **Penumbra:** not started. First step is a build against Woodcase and RapidPro main to see what this wave broke
  (breaking: `RenderTextContent.color`/`lineHeight` optional, `GoogleFontResolver.resolve` per face,
  `EmitResult.fontFaces`, `PenMeshColor.init?(hex:)` gone last wave).

## Traps hit this session

- **Load made the suite lie, repeatedly.** At load 100–200: WebKit `__READY__` timeouts and frame-load
  interruptions, `ViewerBrowserTests` scroll, `ReactTransformStateWebViewTests`, and the `tree`/`set` time
  budgets at 3–5×. Every one passed re-run alone. The `tree` budget failed *before* `3d55f33` too, which is how
  load was told apart from a regression. Five Swift agents plus the integrator's own suite is the ceiling here.
- **Baselines measured on one branch go stale at merge.** The React sweep capped two boards at CG + 1.0; when the
  rotation fix improved CG, the cap fell under React (`34185c8`). And a board list shared by two sweeps
  (`SwiftUIRenderBoard`) pulls a new SwiftUI fixture into the React sweep with no baseline (`013ea12`). After
  merging a fixture or a CG improvement, run `ReactRenderWebViewTests` before the full suite.
- **Batch integration is faster:** commit each squash after reading it, then one full suite over the combined
  result (delegation.md step 7) — not a suite per squash at 30 minutes each.
- **`cd` in a Bash call moved the session's working directory** into a worktree once (reading the gaps doc);
  use absolute paths or `git -C`.
- **A RapidPro root auto-closes when its last leaf closes**, before follow-ups are added; add follow-ups first,
  or check `job ls` after.
- **Briefs were wrong in the usual places:** CG did not draw text inner shadows; "centred" per-side strokes follow
  the node's alignment; icon metrics round at 14 pt; the React harness floor was optical size, not the fallback
  font; the default SwiftUI floor is 26/26. Every agent answered the brief-errors question.
