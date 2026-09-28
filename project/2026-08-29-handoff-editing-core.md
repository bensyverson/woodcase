# Handoff: editing core landed, CLI verbs and viewer next (2026-08-29)

Author: Claude (Fable 5), integrator for the day's two fan-out waves, written for the
next session at Ben's request. `job orient` points at the next target and its note
links here. Read `project/gotchas.md` first — it gained four entries today.

## What landed today (all on `main`, pushed)

Editing core, 7 of 8 leaves, one per squash commit — read each commit body, it is the
design rationale:

| Leaf | Commit | What |
|---|---|---|
| Revision tokens ifcGt | `508d0eb` | `revision(of:)`, `documentRevision` (FNV-1a 64 over canonical JSON), `apply(_:expecting:)` |
| Node addressing RIHeb | `89b04c4` | `NodeAddress`, `resolve(_:tags:)` → `ResolvedNodeAddress`, `namePath(of:)`, `#id` marker; id beats name at every segment |
| Property patch SjgDk | `5bc0e4c` | `EditOperation.setProperties`, throwing `NodePropertyCodec` (one path vocabulary; CRDT codec delegates), `+Shapes` table of expected value shapes |
| File transactions vseIb | `66fc1f0` | `PenFileTransaction.run/read`, `FileLock` with inode revalidation, canonical no-op writes |
| Settled tree view W11mR | `da0d7a2` | `Sources/Woodcase/Tree/`: `TreeView.rows`, `TreeFormatter.text/json`, `TreeReport` with revision |
| Activity log qoTVa | `779275c` | `Files/Activity{Event,Log,Reader,Recorder}`, `run(at:identity:log:_:)` overload |
| Batch applier Fmyjz | `aa7e64d` | `Sources/Woodcase/Batch/`: JSONL grammar (`BatchOperation.grammar`), cascade, atomic, retry, auto-placement |
| Consequence guards zF7AK | `a73cf53` | `componentHasInstances` / `overrideTargetNotFound`, `DeleteNode.Instances`, guards pre-flight in `applyLocal` |

Also: the viewer design prototype (signed off; `project/2026-08-29-viewer-prototype/`),
the `pen` CLI finding and `scripts/pen-oracle` (`167d82d`), `mae-check` merging
instead of replacing (`9b59ac3`), and three design notes listed below. Every leaf's
`job done` note carries the integration findings; `job show <id>` before touching
that area.

## Rulings made while Ben was away (all two-way; revisit freely)

- Revisions travel *beside* an op (`apply(_:expecting:)`), never inside `EditOperation`.
- `#<id>` is a general id-escape in addresses; the component root is not a path
  segment (`Nav/Label`, not `Nav/Button/Label`); the expanded instance root is keyed
  `<ref>/<component root id>` in layout but addressed as `<ref>`.
- `override` props are keyed by raw .pen names (what Pen stores in `descendants`),
  `set` props by `NodePropertyCodec` paths — two vocabularies, documented in the grammar.
- Activity identity is the plain `--as` string; a failed log append throws after the
  .pen is written, naming the log file (needs an exit code).
- `var`/`theme-axis` removal is not in the batch grammar (a dropped field must never
  be a silent delete); it belongs to the `vars` verb.
- `pen` is an oracle, never a test dependency (Ben's rule); fixtures it generates are
  committed.

## Ben's rulings (not two-way without asking)

- Viewer: Elementary (`sliemeobn/elementary` 0.8.1) for server-rendered components in a
  `WoodcaseViewer` target; real routes shipped hydrated; JS only for SSE swaps and
  the fading outline overlay. `project/2026-08-29-viewer-components.md` and the notes
  on leaves ExnBl/EnTjY carry the details (presence stack, Jobs avatar hash, theme
  picker per file axis, variables panel, columnar activity rows, tones).
- Push to origin after each integration.

## The next fan-out (file surfaces mapped)

`job orient` lands first on `applyLocal fails closed` (MuU12, the last Editing-core leaf,
small and self-contained — a good single-agent warm-up), then on **CLI verbs** (fq5Ze). The core is done, so the verbs are thin
adapters; carve by file:

1. **`tree` + `get`** (xXuLn) — new `TreeCommand.swift`, `GetCommand.swift`; reads via
   `PenFileTransaction.read`, `TreeView`, `TreeFormatter`. Needs the shared pieces below.
2. **`add cp set mv rm override`** (SLVVe) — one file per verb, all over
   `BatchApplier.apply` with a one-line batch plus `ActivityRecorder` for the events
   (see the Fmyjz done-note: the applier has no recorder hook; build events from
   `BatchLineResult.inverse`, or give the applier one — decide once, in the shared piece).
3. **`apply`** (sLTYX) — `ApplyCommand.swift`; `decodeJSONL` throws → exit 2.
4. **`vars`**, **`undo`**, **`activity`**, **`lint`**, **`shot`** — each its own file;
   `shot` reuses `ImageExporter`; `--grid/--outline` wait on the PixelPeeper leaf.
5. **Help that teaches** (hnJiX) and **the shared pieces** — pre-carve *before*
   fanning out, in one serial commit: `ExitCode` table (sleepy's, in
   `project/agents/cli-design.md`), `--as/$WOODCASE_AS` option group, `--json`, the
   `EditingError`/`PenFileError`/`BatchError` → message + exit-code mapping (start
   from `BatchErrorMessage`), and a `WoodcaseCommandTests` fixture-copy helper.
   Everything else contends on these.

Then **Server and file watching** (EnTjY) with the viewer target, then the page (ExnBl).
The PixelPeeper vision helpers (qh4W1) are cross-repo and independent — a candidate to
run alongside.

Open leaves filed today that are not on the critical path: `applyLocal fails closed`
(MuU12) and the suite flake (see `job ls`). The suite-speed leaf landed: the full
suite is ~16 s on a quiet machine (`project/2026-08-29-test-suite-speed.md`), and that
doc carries four concrete improvements for SleepyHollow's `PageHost` — a handoff to
`../SleepyHollow`, not a Woodcase leaf.

## Traps this session paid for

- Filtered `swift test --filter …` runs write a partial `performance/mae-test.csv`;
  `mae-check` now merges, but delete the file before a commit if in doubt.
- Never chain `swift test … ; git commit` — see gotchas.
- `git worktree remove` on a harness worktree needs `--force --force`; a leaf claimed by
  an agent needs `job release <id> --as <agent>` before `job done`.
- Briefs must cite `local/` by absolute main-checkout path (gitignored, absent in worktrees).
- The `EditingError` enum is the one file every core leaf touches: pre-carve its cases
  (done twice today) before any fan-out that needs new ones.
