# 2026-09-26 — Handoff, wave six: SwiftUI strokes, shapes and line height; deep documents; the page with a deadline

The sixth integrator session of the day, following [wave five](2026-09-26-wave-five-handoff.md). Start with `job orient`,
then this doc. Nine agents ran (Opus, bar one Sonnet), at most five at once, all integrated.

## What landed

Woodcase (all pushed; last `4b18073`):

| Commit | Leaf | What |
|---|---|---|
| `bd21f19` | `H7zKFC` | smart state defaults are typed `StateEffect`s (`dim`, `scale`, `fade`, `focusRing`, `ignoresPointer`); React spells them, byte-identical (pinned by `StateEffectCSSTests`: no golden holds `states.css`) |
| `20e8f73` | `c9pSVy` | SwiftUI half-leading under `lineHeight` (`PenLineBox`); the four lineHeight baselines and `render-text`'s are gone; new `render-text-line-height` fixture held to measured `ceilings` ([finding](2026-09-26-swiftui-line-height.md)) |
| `dd7866c` | `W0YLOb` | Ben's ruling on `caIi4g`: an override on an instance's own slot content is rewritten into the slot fill (verb, `apply`, JS agree; `slotFillRewrite` note; undo restores). The raw-operation guard stays for library/CRDT callers |
| `c95e6c3` | `7y53C0` | every walk of the read path is iterative — decode (`ChildDeferringDecoder`), flatten, materialize, resolve, font collection, layout (a resumable state machine per container), revision fold, index, absolute rects. 200-deep frames / 64 nested instances read in debug **and release** (release overflowed at 35 too) ([finding](2026-09-26-debug-stack-depth.md)) |
| `5cf0cdb` | `8diBUN`, `xl3KGL` | SwiftUI strokes (all alignments, per-side, paints, caps/joins; no dash exists in the format), shapes (page-private `Shape`s from `PenShapeGeometry`), icons (glyph outlines; fonts copied into `Resources/`). 72 boards within CG + 1.0, no baselines. A frame's clip now applies to children only |
| `119f9b3` | `aijbEO` | Pen fixture `render-group-shadows.pen` (7 boards, 1x/2x) |
| `58fd1f6` | `3X4Ef8` | 38 CG threshold sites at the margin rule `max(m × 1.5, m + 0.25)` ([rule](2026-09-26-mae-margin-rule.md)) |
| `4b18073` | `QZ41uc` | page-call deadlines retired from the tests (SleepyHollow keeps them); the pool drops an abandoned host; `sleepyhollow` pinned to `45fe6df` |

RapidPro: `fe80a3a` blur and shadows at Pen fidelity (`SG9c4D`, 22 cases at 0.00–0.31); `3df12cb` group shadows from
descendants' silhouettes (`aijbEO`, `RenderGeometry.group` — Penumbra does not switch on it); `501d229` demo compiles
and is compiled by the suite (`u1vYQA`); `5ce6be7` 82 thresholds at the margin rule (`3X4Ef8`).

SleepyHollow: `45fe6df` every page call has a deadline the host keeps (`callBudget`, 60 s), a resume-once
`PageCall`, `abandonedCall` for pools (`QZ41uc`). Committed by Ben with `--no-verify` (see traps).

## Still open from this wave

- New leaves: `sH43HM` SwiftUI groups (blur2/blur3 baselines), `hwCwvs` register Inter in the test process, `xrqqge`
  measure layout/parse speed after the iterative rewrite (quiet machine), `WBOels` why render-strokes-and-paths scores
  5.1 in both CG and SwiftUI, `SGjFZi` CG group shadows as Pen casts them, `0qUbof` group inner shadows in both
  renderers, `PqG17l` SleepyHollow's macOS 27 WebKit stderr notice, `yLvS0c` SleepyHollow archive/cookie deadlines.
- `wXirUH` carries a note: designer transform deltas are still CSS strings (`NodeDiffer.encodeTransform`).

## Next

1. `FPHQQ5` SwiftUI components and pages — unblocked by strokes and shapes; then `PhTQsf`, `wXirUH`, `rlSTe9`.
2. `sH43HM` SwiftUI groups, `SGjFZi` + `0qUbof` group shadows (CG first; RapidPro already matches Pen's outer shadow).
3. `ZCCotT` regenerate old pen-oracle layout.json; `hwCwvs` Inter in tests; `PqG17l` so SleepyHollow can commit again.
4. Quiet-machine measurements: `gh42Xb`, `U7wvkV`, `Tdgxuz`, `xrqqge`.

## Traps hit this session

- **Five agents is still heavy**: load reached 90–190. Three WebKit tests fail under that load and pass alone (gotchas).
- **A forked helper ignores "research only"** — it edited, committed and invented a cause (gotchas, `rule:`).
- **SleepyHollow's hook cannot pass on macOS 27**, and the auto-mode classifier refuses `--no-verify`; Ben runs it.
- **Briefs were wrong in the usual places**: "debug only" (release overflowed too), "13 pt" (26), "groups have no geometry in
  RapidPro" (they were rects), "dash" (none in the format), "use `PenOverrideKeyResolver`" (it skips own slot content).
  Every agent answered the brief-errors question usefully; keep asking it.

## Status at pause

Every agent is integrated and every worktree removed. Woodcase, RapidPro and SleepyHollow `main` are pushed. The last
full Woodcase suite (with SleepyHollow `45fe6df`) passed: 494 + 3,413 + 163 + 1,017 tests, known issues only; RapidPro's
passed at 671. RapidPro's main checkout still has pre-existing uncommitted `.agents.yaml` / `project/agents/*` edits that
are not this session's.
