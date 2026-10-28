# Handoff: outer shadows from content on every target (2026-10-28)

Follows [the bottles and 2.21 handoff](2026-10-28-bottles-and-2.21-handoff.md), whose items 1, 2 and 4 this session closed.

## Done

- **The two release-blocking flakes.** `1nZPfP` was a real crash, not load: `SwiftUIRenderBatch.runAsync` closed its log handle on return while a job `BoundedWait` had abandoned could still launch on it (uncaught `NSFileHandleOperationException`). The job now owns the handle and never launches once canceled; a test reproduces the crash on a quiet machine. `4yZOHq`'s timeout test asserts the slow download was canceled instead of a wall-clock bound (`418574d5`).
- **Outer shadows cast from content, as CG does (pen CLI 0.3.13), on every target** (root `yikOf8`):
  - RapidPro `a7abb2a` (`391iRf`): one offscreen silhouette, stencil-clipped; the analytic path stays for a childless or clipping filled rectangle. outer-frame-children 20.6 → 0.23.
  - SVG `2e40bb9a` (`Fq1RBB`): one filtered group per shadow; spread grows only the node's own path; fill-less text and icons cast their glyphs. render-shadows 1.08 → 0.15, render-group-shadows 1.16 → 0.21.
  - React `36a9aeb9` (`S1cB6z`): `box-shadow` where the fill paints and content provably stays inside (clip, flex flow, literal placement), `drop-shadow()` elsewhere. An opaque pure-black outer `box-shadow` is written `#010101`: WebKit paints the element's background over the solid core of a blurred `#000` shadow offset past its blur (repro: a lone div, `10px 14px 4px #000`; checked by the integrator's eye on the shots). outer-frame-children 20.56 → 0.04, filled-clipped 6.39 → 0.56.
  - SwiftUI (`guwOmM`, the commit after React): shapes cast their paint; a frame or group casts an inked copy of itself through `.penContentShadows`, except a filled frame that provably covers its content in Pen's layout under every theme combination (`SwiftUIShadowCover`), so ordinary cards keep `.penDropShadow` and the woodcase-app goldens carry no copies. The six gap boards now measure 0.03–0.30.
- **`KT1PbK` ruled (Ben):** Duplicate is a new design — fresh `fileToken`, no history; Save As unchanged. Recorded under H5 in Penumbra `project/2026-10-23-shared-history.md` (`ff246b7`); KT1PbK is now the Penumbra work item with three criteria.

## Next

1. `KT1PbK` (Penumbra): build Duplicate's fresh token and empty history; the leaf names the code path.
2. Issues: `b2qfxi` (merge-fuzz divergence at seed 65536), `kIssG7` (import prefixing skips effects), `D2dkrh` (sampler2D uniforms), `QiRFM9` (RapidPro draws no shadow spread), `mu0D0x` (the SwiftUI emitter ignores shadow spread, undocumented).
3. Before the next `scripts/release`: the release check runs the full suite, and this session's full runs still failed only on load timing — `PenFileTransactionTests`' lock timeout, `FileWatcherTests` and a WebKit 480 s limit, all passing alone (gotchas, *Under load*). Run the release on a quiet machine, or make those three load-proof first.

## Notes

- **Known approximations, accepted:** React assumes a flex child stays inside its frame (a fixed-width child wider than the frame breaks it); React's translucent-children (6.51) and translucent-fill-overhang (4.42) boards stay baselined with their reasons. SwiftUI lays out the document once per theme combination (at most 8, else no frame counts as covered) during an emit, only when some frame needs the check.
- Commit `.jobs/log/*.jsonl` changes freely (Ben, 2026-10-28).
