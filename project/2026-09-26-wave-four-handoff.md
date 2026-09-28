# 2026-09-26 — Handoff, wave four: SwiftUI's first slice, blur and shadows, Pen's override-key rule

The fourth integrator session of the day, following [wave three](2026-09-26-wave-three-handoff.md). Start with
`job orient`, then this doc. **Ben's ruling for the next session: fix the suite wedge first** (`DpQmXu`, below), then
carry on with the SwiftUI plan and the parallel leaves.

## What landed (all pushed)

Woodcase, in order:

| Commit | Leaf | What |
|---|---|---|
| `21f1fd6` | `bpfpVZ` | Ben's four SwiftUI rulings recorded in the feasibility report; [the emitter plan](2026-09-26-swiftui-emitter-plan.md) imported under `n42KDh` |
| `631ea0b` | `jNpws2`, `4GVELx`, `sGWNUd`, `5jQhdY` | viewer: `connecting…`; a 520 px pinned selection-bar state (`PreviewState.pinnedWidth`); a clipped selection sheds rect and revision below 720 px; preview renders are real PNGs; the code panel includes imported components (`EditableDocument.materializeForGeneration()`, shared with `generate`) |
| `7aafe63` | `VaJSI3` | unknown keys survive in 8 nested structs (gradient stops, centre, size, shadow offset, variables, themed values, mesh vertices, connection endpoints); `override` and `cp` of a component are now held to the authoring check |
| `58ba398` | — | `rule:` gotcha: the briefing template's bare `job claim` expires under a working agent |
| `fbaea9f` | `pOTyJp` | `Sources/Woodcase/Geometry/`: CoreGraphics-free SVG parse (`PenPath`) and shape outlines (`PenShapeGeometry`); renderer calls unchanged; 380 MAE figures identical; two parser bugs fixed |
| `b180bf4` | `k759GF` | `pen-validate` fails on a non-empty validator error list; `--allow-unknowns`; `scripts/test-pen-validate` |
| `5bc90f2` | `erwfwh` | codegen seams: `StateTrigger` names states, `PropMapper.Value` is typed, `CodeGen/Paint/` holds the neutral paint decisions; React goldens byte-identical. **Breaking:** `StateTrigger` cases, `MappedProp.jsValue` → `value` |
| `3447766` | `dklpu4` | every snapshot MAE goes through PixelPeeper's `maeSteps` (0–255), bit-identical figures |
| `98046aa` | `ILYyZi` | override keys resolved by Pen's rule ([finding](2026-09-26-slot-override-keys.md)); banking.pen's 8 override findings were never stale and are gone |
| `f0be66b` | `4pVE75`, `2u6IsC` | `PenMetadata.type` optional (no fabricated `"unknown"` on round trip); the 5 ms wall-clock layout assert is a `PerformanceBudget` |
| `ce92ef5` | `kptCwf` | **SwiftUI first slice**: `SwiftUIEmitter`, `PenSupport.swift` template, `woodcase generate swiftui`, 28 goldens, a batch `swiftc` + `ImageRenderer` render test — 25 layout boards within CG + 1.0 (22 at 0.000), `render-text` baselined 3.17 |
| `76461b1` | `Gusv9b`, `W91Yf0` | background and layer blur: no flip, σ = radius/2, sRGB, CPU Gaussian (Core Image is gone — it needs Metal and silently did nothing without it); shadows in Pen's order, every outer shadow drawn, silhouette-cast and knocked out under the node. New 1.2.14 fixtures `render-background-blur.pen`, `render-shadows.pen` |

Other repos: PixelPeeper `48427f2` (`EightBitSteps`, `maeSteps`, `cropToOverlap`, `PixelImage(cgImage:width:height:)`);
RapidPro `c714050` (MAE in 8-bit steps, thresholds ×2.55); Penumbra `921aea3` (imports through `PenLibraries`, an
import-problems banner, and the incremental path no longer drops imported instances after an edit).

## Rulings this session (Ben)

1. **SwiftUI floor: iOS 26 / macOS 26 by default**; iOS 18 / macOS 15 only through `#available` in `PenSupport.swift`,
   never at the cost of the component code.
2. **SwiftUI mesh: always native `MeshGradient`**, folds included; lint warns.
3. **SwiftUI output: a SwiftPM package.**
4. **SwiftUI layout: always idiomatic stacks** — "what matters more is intent" than pixel perfection.
5. **A SwiftUI kit catalog** (asked whether SwiftUI gets the React kit page): yes, as leaf `0QZeR3` — `#Preview` per
   state, a `Catalog` view, a `swift run <Name>Catalog` target (integrator's shape; Ben may drop the executable).
6. **Tighten MAE thresholds** "to the degree reasonable, if we're scoring well" — leaf `3X4Ef8`, RapidPro first.
7. **The suite wedge is the first job after this handoff**, and agents' suite runs get a 10-minute watchdog.

## Decisions made under standing permission

1. Woodcase keeps depending on PixelPeeper by GitHub URL, branch `main`; RapidPro keeps `../PixelPeeper`.
2. Penumbra's import-problems banner kept (Penumbra had no on-screen warning idiom; one file and one line to drop).
3. `pen-validate --allow-unknowns` matches the *shape* of an error, not a filename list.
4. `PreparedDocument.parsed` renamed `generationSource` (breaking, one internal reader).
5. SwiftUI's first slice writes a minimal write-once `Package.swift` so the floor has a home and the output builds.
6. The 5/255 edge tolerance at σ = 4 px @1x is accepted: Pen fits σ ≈ 4.24 there; Woodcase keeps the exact Gaussian
   (the "more correct than Pen" ruling). Documented in `PenRendering.md`.
7. Claims re-taken with `4h` for agents whose 30-minute claims had lapsed mid-work.

## Open questions for Ben

- **Neutral smart state defaults** (blocks `wXirUH`, SwiftUI states): `RoleStateMapping.smartDeltas` holds CSS-shaped
  values nothing emits; React writes its own CSS. How should hover/press/focus defaults be represented for both targets?

## Next

**First: the wedge (`DpQmXu`).** A full run sat at 0 % CPU for 36 min today; the sample
(`local/wedges/2026-09-26-Gusv9b-sample.txt`) holds only the `ChangeCoordinator` → `ActivityReader.Follow` poll loop —
the suspended-await face in gotchas. Plan on the leaf: a per-test `.timeLimit` on async and browser suites so a hang
fails and names itself, then find the unresumed `await` and give it a deadline we own.

Then, in parallel where file-disjoint:

| Leaf | What | Notes |
|---|---|---|
| `zl2U6G`, `8diBUN`, `OBkh9G`, `xl3KGL` | SwiftUI paints, strokes, effects, shapes/icons | all touch `PenSupport.swift`: carve its sections per leaf first |
| `US7HZU` | SwiftUI text-in-flex fixtures | the stack-negotiation risk is untested: every layout fixture is rectangles |
| `cAUDcr` | Linux build | `PenRect` and ~30 Rendering files import CoreGraphics; the SwiftUI emitter also calls statics in CoreText files |
| `PJwhm2` | deep nesting overflows a debug task stack | Woodcase and Penumbra debug builds |
| `MFvCPv` | override keys lint accepts that nothing applies | |
| `Sus1Pt` | one gradient map | `frameTransform` rebuilt on `GradientGeometry` |
| `3X4Ef8` | tighten MAE thresholds | Ben's ruling above |
| `SG9c4D` | RapidPro blur and shadows to Woodcase's rule | fixtures in Woodcase |
| `9cFOhp` | per-side `strokeWidth` extras | public shape change across rendering, codegen, RapidPro |
| `U7wvkV`, `gh42Xb`, `Tdgxuz` | measurements | quiet machine only |

## Traps hit this session

- **A bare `job claim` lapses under a working agent** (30 min, extended only by writes). Brief `job claim <id> 4h`.
- **A backgrounded suite with no watchdog cannot tell a wedge from slowness.** macOS has no `timeout`; use
  `perl -e 'alarm 600; exec @ARGV' swift test …` and log to a file. Real runs: ~1 min quiet-ish, ~3 min at load 200,
  11 min worst at load 280.
- **An agent waiting on its own background command re-notifies** each time it wakes and settles again; that is not a
  recurring task. `ps` shows what it is actually running.
- **The `$TMPDIR` split bit again**: a file written sandbox-off was not found sandboxed. Write scratch to the absolute
  scratchpad path.
- **Merging into main while `swift test` builds there aborts the run**: review the branch in place
  (`git -C <wt> diff main...HEAD`) and merge after the suite finishes.
- **The "142/144 fixtures validate clean" figure (wave three) was wrong**: the check missed `Invalid ref` and
  `Cannot import` errors. With the fixed script, 136/149 pass (139 with `--allow-unknowns`); the rest fail on purpose.
