# 2026-09-26 — Handoff, wave five: the wedge bounded, SwiftUI paints and effects, a flat-stack expander

The fifth integrator session of the day, following [wave four](2026-09-26-wave-four-handoff.md). Start with
`job orient`, then this doc. Main is pushed through `223122a`; the full suite passed on it (5,013 tests, 0 failures, the expected known issues only).

## What landed (all pushed)

Woodcase, in order:

| Commit | Leaf | What |
|---|---|---|
| `57fd3a0` | — | pre-carve: the SwiftUI emitter copies every `CodeGen/SwiftUITemplates/*.swift` into `Support/`, so each concern adds `PenSupport+<Concern>.swift` |
| `25ee7f2` | `cAUDcr` | the Linux build moved to [the backlog](backlog.md) (Ben: not a priority) |
| `1f0e63d` | `9cFOhp` | `PenStrokeWidth.perSide(Sides)` keeps unknown keys. **Breaking**; RapidPro `5d290a9` and Penumbra `47ed0af` follow |
| `8d8ed71` | `OBkh9G` | SwiftUI effects, transforms, node blend modes (`PenSupport+Effects.swift`); the render test runs over `SwiftUIRenderBoard.all` |
| `ff04c15` | `US7HZU` | eight `layout-text-*` Plex fixtures, all within CG + 1.0, no baselines; auto text is `.fixedSize()`; `pen-oracle` reads layout after the export ([finding](2026-09-26-swiftui-text-in-flex.md)) |
| `a9303d8` | `Sus1Pt` | one gradient map: `frameTransform(in:)` is built on `GradientGeometry.affineComponents`; 72 MAEs byte-identical |
| `d73ce6b` | `DpQmXu` | every call into a test page has a deadline; `BoundedWait` abandons non-cancellable jobs; 8-minute `.hangGuard` on 32 suites ([finding](2026-09-26-the-page-that-never-answers.md)) |
| `ad81290` | `zl2U6G` | SwiftUI gradients, images, stacked fills, paints on text (`PenSupport+Paint.swift`); render-transforms-and-effects gates at CG + 1.0 (0.31, CG 0.89) |
| `223122a` | `PJwhm2`, `MFvCPv` | `PenNode.Kind` is `indirect` (272-byte nodes); expansion walks iteratively (`PenTreeRewrite`), 16 nested instances 3.9 MB → 100 KB of debug stack; override keys follow Pen: nested-instance paths handed down, own-slot-content keys dropped / refused / linted ([finding](2026-09-26-debug-stack-depth.md), [override keys](2026-09-26-slot-override-keys.md)) |

## Rulings this session (Ben)

1. **Neutral smart state defaults are typed effects** — a named, target-neutral effect per state (dim, scale, focus
   ring) that React spells as CSS and SwiftUI as modifiers. New leaf `H7zKFC` carries it; `wXirUH` is blocked on it.
2. **The wedge runs first in priority but in parallel** with file-disjoint leaves.
3. **Linux build backlogged.**
4. **At most five Swift agents in parallel**, each with `-j 3`, dispatch staggered — after ten cold builds
   kernel-panicked the machine at 17:54 (gotchas, 2026-09-26).

## Decisions made under standing permission

1. The expander refuses an `override` on content an instance wrote into its own slot
   (`EditingError.overrideOnOwnSlotContent`, naming the slot to rewrite) rather than redirecting it. **This retires a
   documented feature** (`woodcase override Inst0/Note0 content=Hi` on `slot-fill.pen`) — see the open question.
2. Unplaceable override keys are dropped as Pen drops them, except bare ids and paths through a ref the instance
   repoints (`RefRepointCommandTests` needs that).
3. Test-side deadlines on `PageHost` rather than a SleepyHollow change mid-wave (follow-up `QZ41uc`); `BoundedWait`
   is duplicated in two test targets until then.
4. Effects: background blur is a Material plus a warning; shadow spread is not emitted (the 2.19 format has none).
5. Paints: images ship as package resources loaded through `Image(penResource:bundle:)`; stops interpolate in
   device colour space.

## Open questions for Ben

- **Own-slot-content overrides** (decision leaf `caIi4g`): should `woodcase override <instance>/<own slot content> …` be rewritten into the
  slot's `children` (keeping the old convenience, producing files Pen honours) instead of refused?

## Parked agents (stopped by the panic, not resumed per Ben's pause)

Their worktrees are kept; claims released. Resume by briefing fresh (the old transcripts died with the session) and
pointing at the worktree, or delete the worktree and start over.

| Leaf | Worktree | State |
|---|---|---|
| `H7zKFC` typed state effects | `.claude/worktrees/stateeffects` (`wt/stateeffects`, base `57fd3a0`) | one new test file, `StateEffectCSSTests.swift`; no source yet |
| `3X4Ef8` tighten MAE thresholds | `.claude/worktrees/thresholds/{Woodcase,RapidPro}` | RapidPro: 26 test files with thresholds edited, unverified; Woodcase untouched. Leave blur/shadow thresholds to `SG9c4D` |
| `SG9c4D` RapidPro blur and shadows | `.claude/worktrees/rpfx/{Woodcase,RapidPro}` | two new RapidPro test files (`BackgroundBlurFixtureTests`, `ShadowFixtureTests`); no renderer change yet |

Rebase each on current main first: `PenStrokeWidth` changed shape (`1f0e63d`) and RapidPro has `5d290a9`.

## Next

1. The three parked leaves above (file-disjoint; at most five agents).
2. SwiftUI strokes `8diBUN` and shapes/icons `xl3KGL` — now unblocked by paints and effects; both touch
   `+Shape`, so one agent or a carve. Strokes must draw above `.penInnerShadow`, and its leaf carries the three
   stroked-shadow baselines to retire. Then components `FPHQQ5`.
3. New leaves from this wave: SwiftUI text line placement under `lineHeight` (n42KDh), `ZCCotT` regenerate
   pre-fix `pen-oracle` layout.json, `QZ41uc` deadlines inside SleepyHollow, `7y53C0` debug stack beyond the
   expander.
4. Measurements (`U7wvkV`, `gh42Xb`, `Tdgxuz`) — quiet machine only.

## Traps hit this session

- **Ten cold builds panicked the Mac** (watchdog timeout); every agent died mid-work. Five agents, `-j 3`, staggered.
- **The perl alarm leaves `swiftpm-testing-helper` orphaned** at 0 % CPU; find it by pid and kill it (gotchas).
- **A `--quiet` suite killed by its watchdog tells you nothing**; run the integrator's suite verbose into a log.
- **A natural wedge recurred on a pre-fix branch** (paints, sample `local/wedges/2026-09-26-paints-viewer-sample.txt`);
  the fixed main has since run green twice with no stall. If a run stalls on the fixed base, the fix missed a path.
- **Unsynced agent branches conflict in the SwiftUI render test**: the effects agent reshaped it into a board list.
  Tell a running agent what landed under it before it reports (paints did this well).
