# The build → compile → test loop: a baseline, and benches out of the test target

2026-10-21 (leaf `RnZvkU`; measured 2026-10-22). Ben, 2026-10-21: "I don't want compile
times to bring our velocity to a halt. The goal is to have a sane build -> compile -> test
feedback loop."

**Every figure here is provisional.** They were taken on an 8-core MacBook Air
(`MacBookAir10,1`) at load averages of 30 to 260. The load came from macOS services
(`timetattle`, `duetexpertd`) and up to three other agents building. Each figure has the
1-minute load before and after its step beside it. On this machine a load of 100 makes a
step several times slower than it would be on a quiet one. The integrator re-runs
`../Penumbra/scripts/loop-times` on a quiet machine. That script is the durable part of
this leaf; these tables are its first output.

## What happened

To time one function (GdTpYF), an agent ran
`swift test -c release -Xswiftc -enable-testing --filter BoardScalePatchProbe`. That
command optimizes the whole `WoodcaseTests` target to run one probe: 1,155 files, about
172k lines and about 22k `#expect`/`#require` macro expansions. One `swift-frontend` job
ran about 43 minutes at load 100–230, and a second about 23 minutes (session 42; quoted
from the leaf, not re-measured). Release-only measurements were in the wrong place.

## What changed

- **`WoodcaseBench`**, an executable target (`Sources/WoodcaseBench/`). It depends on
  `Woodcase` and `WoodcasePerfFixtures` and nothing else. Run it with
  `swift run -c release WoodcaseBench list`, then `… WoodcaseBench <name>`. Its benches
  were the suite's release-only, environment-gated probes and no-ceiling measurements:

  | Bench | Was |
  |---|---|
  | `board-scale-patch` | `BoardScalePatchProbe` |
  | `property-read-cost` | `PropertyReadCostProbe` |
  | `property-write-cost` | `PropertyWriteCostProbe` |
  | `node-tree-cost` | `PenNodeTreeCostProbe` |
  | `painted-extent-board` | `PerformanceBudgets.PaintedExtentBoardTests` (ran in every Debug suite run) |
  | `painted-extent-walk` | `PerformanceBudgets.PaintedExtentWalkTests` (ran in every Debug suite run) |
  | `component-loop-edit-cost` | `ComponentLoopEditCostProbe` |
  | `remote-apply-cost <board>` | `RemoteApplyCostProbe` |
  | `codegen-dump <dir>` | `CodeGenCorpusProbe` |

  Every bench prints `PROBE` lines with the median and p90 (`BenchClock`).

  Three benches changed as they moved:
  - `board-scale-patch` no longer times `EditableDocument.patchedNode(for:)`, which is
    internal. Making it visible to the bench means editing `EditableDocument`, which
    another leaf owns. Its other two timings, per-key `setting` and `previewNodes`,
    remain.
  - `property-write-cost` times only the library's write. The old "before" path,
    `PropertyWriteOracleTests.Oracle`, is a test oracle and stays in the suite.
  - The painted-extent benches report the median rather than the best run.

- **`WoodcasePerfFixtures`**, a library target that is not a product
  (`Sources/WoodcasePerfFixtures/`). It holds the fixtures that both the suite and the
  bench need: `SyntheticPenDocument` (and its editor board), `PerfBoardFixture`,
  `DeepDocuments` and `StackHighWater`, moved with `git mv` and made `public`. It also
  holds the new `PerfFixtureFile`, which finds `woodcase-app.pen` and
  `settings-mockup.pen` in the source tree. Why a target of its own:
  - The bench cannot `@testable import` and has no test bundle. Copying the generators
    would leave two copies to drift.
  - The generators are tooling, not library API. Making them public in `Woodcase` would
    put them in Penumbra's symbol graph.
  - A non-product target is invisible to consumers and costs about a dozen files to
    compile.

  The fixture files are read through `#filePath` rather than a second resource bundle,
  so the repository keeps one copy of each `.pen`. `PerformanceFixture.largestBundled()`
  still reads the test bundle. `DeepDocuments.mockupShaped` no longer uses the internal
  `PenTreeRewrite`: it prefixes ids with a short recursion over the mockup's board,
  which is 8 deep. `PerfFixturesTests` pins its shape.

- **One seam.** `TextInkCache` is now `package` (the class, `init`, `defaultCapacity`
  and `current`) so `painted-extent-board` can install a cache that keeps no ink. The
  library's public API is unchanged.

- **Kept in the suite**, because they are cheap and guard real regressions:
  - The `PerformanceBudgets` budgets: 16 tests, 19.6 s inside a 28.4 s
    `swift test --skip-build --filter PerformanceBudgets` (load 42→30).
  - The `*StackTests`: 31 tests, 19.3 s inside 21.5 s for
    `--filter "StackTests|StackHighWater"` (load 30→28).

  Both ran on 2026-10-22 08:10 on this branch's Debug build. Also kept: the counting
  tests `PaintedExtentInkCountTests` and `EditorBoardTests`. The budgets still confirm
  their release ceilings through `swift test -c release`, so that path still pays the
  whole-target compile; see "Not done" below.

- **The rule**, in `AGENTS.md`'s head: never time code with `swift test -c release`; use
  `WoodcaseBench`.

## Woodcase: before and after

Command: `WOODCASE_DIR=<checkout> ../Penumbra/scripts/loop-times woodcase`, which builds
into a fresh `--scratch-path` and deletes it afterwards. The "touch" step touches
`Tests/WoodcaseCommandTests/Failures/CommandFailureTests.swift`, the first test file in
path order, and rebuilds. "Before"
is the base commit `e3b5ab08`, exported with `git archive` into a scratch directory
(sources only, 97 MB) so it could build beside the worktree. "After" is this branch's
uncommitted tree at the same base. Toolchain: Swift 6.4 (swiftlang-6.4.0.34.1). No sleep
during any step (`pmset -g log`).

| Step | Before, 2026-10-22 07:50 | After, 2026-10-22 07:13 |
|---|---|---|
| cold `swift build --build-tests` | 553.3 s (load 49.5→115.9) | 659.4 s (load 61.3→100.0) |
| warm (no change) | 6.1 s (115.9→97.7) | 9.2 s (100.0→96.8) |
| touch one test file | 16.7 s (97.7→79.7) | 36.7 s (96.8→83.5) |
| `swift test`, wall | 516.1 s (79.7→74.5) | 977.3 s (83.5→172.4) |
| `swift run -c release WoodcaseBench list`, cold | n/a: no bench; the only path was `swift test -c release` (one job about 43 min, above) | **464.1 s** (172.4→56.3) |
| the same, warm | n/a | **2.7 s** (56.3→50.9) |

How to read it:

- **The release loop is the win.** A cold optimized build now compiles `CZstdDecode`,
  `Woodcase`, `WoodcasePerfFixtures` and `WoodcaseBench`, and nothing from any test
  target (checked in the bench log). A re-run after a change to the library costs only
  that build, and a re-run with no change costs 2.7 s.
- **The Debug columns differ by load, not by code.** The after run's test step ran while
  load doubled (83→172). Moving nine probes out of a 1,155-file target changes its
  compile by well under a percent. The suite lost 7 tests in all (6,598 → 6,591,
  including 2 new ones), which is where the Debug wall time went. That includes the two
  painted-extent measurements, which had been running in the serialized
  `PerformanceBudgets` chain in every Debug run.
- **Woodcase's test targets dominate its cold build.** RapidPro's cold build compiles the
  Woodcase library too, and took 124 s at load 17–26 (see below). Woodcase's cold build
  took 553–659 s at load 50–116. Even after allowing for the higher load, most of
  Woodcase's cold build is its test targets. That is where a further cut would come
  from: fewer `#expect` expansions, the slow-to-type-check bodies below, or a split of
  `WoodcaseTests`.
- **Both test steps exited 1 on load flakes**, all listed in `project/gotchas.md`
  (WebKit time limits, `FigmaImageFetcherTests`' timeout, `SwiftUIRenderBatch.runAsync`,
  `PenFileTransactionTests`' lock timeout). WoodcaseCommandTests (1,212),
  WoodcaseScriptingTests (171) and WoodcaseViewerTests (485) passed in both runs.
  - One failure was not one of those flakes. In the before run, `PenPaintedExtentsTests`
    "Every node's extent from one walk equals paintedExtent's", fixture
    `geometry-probe`, failed 8 times at load about 80. The same test passed in the
    other two runs. It needs a leaf to find out whether it is a race in the shared ink
    cache.
- An earlier before run, 2026-10-22 06:35 at load 40→216, read: cold 1,287.4 s, warm
  11.1 s, touch 47.8 s. Its test step (737.4 s) is void: under `--scratch-path` the
  command tests could not find the built `woodcase` and failed in 1.2 s. `loop-times`
  now sets `WOODCASE_BINARY`.

## The slowest-compiling test files

Command:

```sh
swift build --build-tests --scratch-path <fresh> \
  -Xswiftc -Xfrontend -Xswiftc -warn-long-function-bodies=200 \
  -Xswiftc -Xfrontend -Xswiftc -warn-long-expression-type-checking=200
```

This was a cold build at load 140–260 (2026-10-22 06:50–07:05, 901.6 s). It flagged 194
bodies or expressions over 200 ms, 74 of them in tests. At that load every figure is
several times what a quiet machine would read, so use the order, not the milliseconds.

Worst test files, by the summed time of their flagged bodies:

| File | Flagged | Worst | Cause | Fix |
|---|---|---|---|---|
| `WoodcaseTests/PostItLookTests.swift` | 25.1 s | `inkByBrightness()` 12.6 s; two `#expect`s 6.3 s each | `#expect([a, b, c].allSatisfy { $0.red == 0 && … })`: an untyped array literal and a three-way `&&` closure inside the macro | typed `[PenHexColor]` and a typed closure |
| `WoodcaseTests/PenTextInlinePaddingTests.swift` | 5.1 s | `midLine()` 2.6 s; five `#expect`s about 0.6 s each | `#expect(try abs(#require(a) - #require(b) - 3) < 0.001)` | one typed `shift(_:) -> Double` helper |
| `WoodcaseTests/PenImagePlacementTests.swift` | 4.5 s | `coverSheared()` 2.3 s | `120 * 256 / (76.8 * 76.8 + 128 * 128).squareRoot()`, all literals | split, `let width: Double` |
| `WoodcaseTests/PenParserTests.swift` | 3.1 s | eleven bodies of 0.2–0.4 s | long but plain | left alone |
| `WoodcaseTests/Figma/FigmaImportShapeTypeTests.swift` | 3.0 s | `computedStar()` 1.5 s | `#expect(points.map(\.y).max().map { abs($0 - 100) < 0.01 } == true)` | `let bottom: Double = try #require(…)` |
| `WoodcaseCommandTests/Verbs/GetInstancesTests.swift` | 2.5 s | 1.3 s | `#expect(rows.map { $0.split(…).map(String.init)[1] } == [...])` | typed `let ids: [String]` |
| `WoodcaseTests/PenFaceMatchingTests.swift` | 2.7 s (in the macro expansion) | `@Test(arguments:)` generator | an inline literal of `(Double, [Double], Double)` tuples | `static let cssCases: [(Double, [Double], Double)]` |

After the fixes, an incremental rebuild with the same flags (242.1 s, load about 180)
flagged none of the seven files.

The worst compile in the package is in the library, not the tests:
`IconFonts/PhosphorCodepoints.swift` (about 10 s twice) and
`MaterialSymbolsCodepoints.swift` (about 7 s twice). Each is a generated
`[String: UInt32]` dictionary literal of 4,000–5,000 entries, already typed. They
recompile only when the library is built cold. Fixing them means changing
`scripts/generate-icon-codepoints.py`, for example to a resource read at first use. Not
done here (see "Not done").

## Penumbra and RapidPro

`scripts/loop-times rapidpro penumbra`, from the Penumbra worktree `p-loop`, which builds
against Woodcase and RapidPro main through the worktree folder's symlinks:

2026-10-22 09:00–09:15, load 9–26, 54 GB free, no sleep in any step:

| Step | RapidPro | Penumbra |
|---|---|---|
| cold build (`swift build --build-tests` / `xcodebuild build-for-testing -testPlan Penumbra`), Woodcase library included | 124.0 s (load 17.0→26.4) | 510.9 s (18.1→23.8) |
| warm (no change) | 5.4 s (26.4→22.1) | 12.2 s (23.8→16.9) |
| touch one test file (RapidPro only) | 24.2 s (22.1→16.2) | — |
| tests, warm: `swift test` / the hook's `xcodebuild test … -only-testing PenumbraTests -testPlan Penumbra` | 56.7 s (16.2→19.2): 1,226 tests, 1 failure | **123.4 s** (16.9→8.8), TEST SUCCEEDED |

These are the quietest figures in this doc. The one RapidPro failure,
`PostItsFixtureTests` "Each post-it matches CG over its painted extent" (PiN08,
`crop.maeSteps.value < postIt.limit`), failed in both runs. It is a RapidPro-against-
Woodcase-main result, not a load flake, and not from this leaf.

Two earlier runs, 08:11–08:57, are void:

- RapidPro: 132.1 s cold and 2.3 s warm are valid. The touch build hit a source-control
  conflict marker that was briefly in RapidPro main's
  `RapidProRenderer+ImageArrival.swift`, so its touch and test figures are void.
- Penumbra: 333.2 s cold (load 42→126) and 6.8 s warm are valid. The test step, 2,186.7
  s with four failures, spanned a lid-close sleep at 08:21 and is void.
  - That run's `loop-times` did not print SLEPT, because pmset had not written the
    sleep to its log yet. The script now checks `kern.sleeptime` first.

## Not done, and why

- **The release budgets still go through `swift test -c release`.** `PerformanceBudget`
  states every ceiling for a release build, and its failure note says to confirm with
  `swift test -c release --filter Performance`, which still compiles the whole test
  target. To avoid that compile, the budget bodies and `PerformanceBudget`/`Sample` would
  have to move into a shared target that a `budgets` bench runs. That is a separate
  design question, proposed as a follow-up leaf.

  > **Done 2026-10-22 (leaf `GYWxMW`).** The budgets, their samples and their pipelines
  > live in `WoodcasePerfFixtures`; `swift run -c release WoodcaseBench budgets` confirms
  > them, and the failure note names it. `SetVerbTests` and `ComponentLoopTests` have no
  > bench (see DocC `WoodcasePerformance.md` ▸ Benches).
- **`patchedNode` timing** (see `board-scale-patch` above).
- **The icon codepoint literals** (above).
- **Stale doc comments in tests this leaf may not touch.** `PropertyReadCostTests`,
  `PropertyWriteCostTests` and `NodePropertyBatchCostTests` still name the old probe
  types; they belong to the `NodePropertyCodec` leaf.
