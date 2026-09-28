# Handoff: viewer page, help, budgets and the issue waves (2026-08-29 → 30)

Author: Claude (Fable 5), integrator. Continues `2026-08-29-handoff-cli-verbs.md`.
Ben stepped away mid-session with a standing ruling: two-way, safe decisions are the
integrator's, logged as `job note`s, reported at the stopping point. This is that report.

## What landed (all on `main`, pushed; every commit body carries the why)

| Commit | Leaf / issue | What |
|---|---|---|
| `0797d76` | qh4W1 | `shot --grid/--outline` through PixelPeeper (`branch: "main"`); `ShotOverlay`, `ShotTargets`, golden PNG |
| `25419e7` | hnJiX | Bare-invocation primer; `woodcase help design`; `RemedyDialect` retires `CommandRemedy`; `IdentityOptions<Role>`; `ThemeOption` |
| `05625f7` | 2U9E0 | Performance budgets under `swift test` (min-of-5, release ceilings verbatim, ×2.5 debug); `PenNodePatcher` no longer re-serializes a subtree (tree 365 → 196 ms release) |
| `6b63240` | RXaYR | `WoodcaseEditor.md`, `WoodcaseCLI.md` verb table + sections, README install + loop, backlog ×4 |
| `f04e92f` | — | `ResumeOnce` on `Mutex`, no `@unchecked Sendable` |
| `06f2e40` | ExnBl | The viewer page (21 Elementary components, 3 pages, 5 fragments, golden previews, SleepyHollow browser test) and `woodcase serve` |
| `4842afc` | cfRJv | `render`/`themes`/`generate` on `PenFilePath`; `CommandFailure`'s no-document overload renders through `BatchErrorMessage` |
| `e154128` | 920dR | Most-specific-first route matching (`Route.Specificity`); `ViewerPages` holds page routes only |
| `4c8309e` | wlAte | `shot` renders definitions and instances (`EditableDocument.expandedID(of:)`); `--outline` in the right coordinate frame |
| `93dd088` | AzXzQ, vq4Lp | Editing-layer expansion delegates to `PenRefExpander` (parity-pinned); root-level `cp` auto-places (`RootCoordinates`) |
| `3919f94` | lp7r8 | One `ExpansionCache` invalidation rule at the mutation choke points, before/after readings |
| `3bb9386` | urmCm | `PenLayoutEngine.absoluteRects` is the one canvas-space walk; the viewer lists component definitions as artboards |
| `60e90d3` | ZXLpp | `PenInputPath` (file-or-directory); `migrate` exits 4 for a missing path or a failed migration |
| `d7bdce2` | F1HiZ | Property shapes generated from the decoders (`PenPropertyShape`, `PenDecodingFailure`); `PenFills`/`PenEffects` raise the array's own error |
| `9247385` | hihz8 | `PenParserError` carries the URL; `DecodingReason` + `ParserFailureMessage`; one sentence on every verb |

Suite: **2610 green at `d7bdce2`** on a clean full run; `9247385` was verified on split
evidence because the suite became unstable that night (below).

## Landed after the table was written

- **`2cb6819` QGISs.** The "flake" was four problems: `EditableDocument.ancestors(of:)`
  had no visited set and walked a transiently cyclic parent map (mid-batch in
  `applyRemote`) to a **40 GB out-of-memory kill** — the "silent exit 1"; eight-way
  font resolution blocked every cooperative thread in `fontd`'s synchronous XPC — the
  "CoreText/WebKit wedge", now serialized by `FontRegistryGate`; `activity --follow`
  had no parent watch (`ParentProcessWatch`, `ChildProcess` test helper); viewer test
  budgets measured `@MainActor` demand (now 60 s). Performance budgets are advisory
  under debug (fail at 4×), strict on release or `WOODCASE_BUDGET_STRICT=1`. Ten quiet
  and five loaded soaks green (`scripts/soak-tests`); finding in
  `2026-08-30-suite-stability.md`. Lesson: a quiet soak alone would have shipped the wedge.
- **`20c5cbf` Kvliv.** Honors a supplied node id on `add` (Ben's ruling), generates
  omitted ones, refuses collisions (`SubtreeIDPlan`, `PenID.isValid`,
  `EditingError.invalidNodeID`); fixes a latent `cp` bug (a copied instance kept
  pointing at the original component); `BatchError.couldNotGenerateIDs` retired.

- **`b82cf8f` HgtJR.** `resolve` accepts the id-path a read prints for a node at any
  depth inside an instance (it stepped a ref onto the component root's direct children
  only — not an instance-nesting bug, a skipped-container bug); name paths of deep
  descendants now name the containers their key skips.
- **`81284cc` aZADN.** `WoodcaseCommandCore` library + a one-file `WoodcaseCommand`
  shim, so `swift test -c release` runs. Diagnosis: `@main` on an async entry emits the
  module-less `async_Main`, coalesced under `-O` between the test runner and the
  executable (`2026-08-30-two-mains-in-one-test-bundle.md`; `PackagingTests` is the
  tripwire). Release budgets assert verbatim (`--filter Performance`); the *full*
  release suite is blocked by `euSPm`, a pre-existing `CTFont` over-release in
  `PenTextMeasurerFontCacheTests` that only `-O` exposes.

  > **Corrected 2026-08-30.** Not a `CTFont` over-release, and not in `Sources`: a
  > Swift 6.3.3 optimizer bug releasing a declared-but-unassigned `var` in the test
  > suite's own helper. Fixed; the full release suite runs. See
  > [the finding](2026-08-30-release-only-ctfont-sigtrap.md).

Suite: **2685 green at `81284cc`** (+1 intentional known issue).

## Queued

- ~~`euSPm`~~ — done 2026-08-30. It was not a `CTFont` over-release but a Swift
  optimizer bug in the test helper; see
  [the finding](2026-08-30-release-only-ctfont-sigtrap.md).
- Follow-ups noted on leaves, not filed: the 22 `defer { Task { await bench.stop() } }`
  viewer teardowns; `PixelImage.makeCGImage()` upstream; the `shot` budget's
  `keepReusables`; whether AGENTS.md's "FooBarCore + FooBarCommand" rule should name the
  `WoodcaseCommandCore` + `WoodcaseCommand` shape.

## For Ben's eyes (not blocking)

- **The viewer page's design sign-off.** A demo server is running:
  `http://127.0.0.1:7333/` over copies in `local/viewer-demo/` (gitignored), with
  edits by `ben` and `claude-a` on `batch → Canvas`. Kill it by port, not `pkill`.
- `--outline` on a node outside the shot is a usage error (never a silent no-op).
- The `shot` performance test still expands with `keepReusables: false`, so its budget
  measures fewer nodes than the verb lays out — decide whether the budget tracks the verb.
- The PixelPeeper upstream nicety (`PixelImage.makeCGImage()`) is deferred; `ShotOverlay`
  rebuilds the bitmap itself.

## Decisions made while Ben was away (all two-way, logged on the leaves)

`Route.Specificity` is public; a failed `migrate` is exit 4 (not 1); a `cp` with only
`common.x` in props gets placed-`y` (props are the only authorship); the viewer treats a
reusable definition as an artboard (matching `shot`/`tree`; `render` still strips them);
`ExpansionCache` invalidates whole, from one rule; the version-gate remedy does not
suggest `migrate` (it fails through the same gate); `python3 -m json.tool` is the
"inspect the JSON" remedy.

## Traps this stretch paid for

- **Killing a wedged test helper orphans its children.** `woodcase activity --follow`
  survives and then makes later lock-budget tests miss. `pgrep -fl 'woodcase activity'`
  after a kill, and kill those by pid too.
- **Background `swift test` runs were stopped externally twice** ("killed" with no
  actor). Run the suite in the foreground with the 600 000 ms cap.
- **A `--filter`/`--skip` run is not a full run here** — it dies silently (see QGISs).
  Until that is fixed, only the plain `swift test --quiet` verdict counts.
- A worktree agent's "based on `0158471`" in its report was wrong twice; `git merge-base
  main <branch>` said `06f2e40`/`93dd088`. Verify, don't read.
- `##"…"##` for any Swift raw string holding a `"#RRGGBB"` colour.
