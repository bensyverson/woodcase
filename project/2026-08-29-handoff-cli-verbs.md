# Handoff: CLI verbs and viewer server landed, page and docs next (2026-08-29, evening)

Author: Claude (Fable 5), integrator. Continues `2026-08-29-handoff-editing-core.md`.
Ben's standing rulings for the unattended stretch still apply (push after each
integration; two-way decisions are the integrator's, logged as `job note`s).

## What landed (all on `main`, pushed; every commit body is the rationale)

| Commit | Leaf | What |
|---|---|---|
| `9282b71` | — | SleepyHollow followed as `branch: "main"` (Ben: owned repos use `branch: "main"`) |
| `8d52e7d` | MuU12 | `applyLocal` fails closed; guards once in `EditableDocument+Validate.swift`; two `applyMove` bugs fixed |
| `046861a` | umWuN | Shared CLI seams: exit-code table, `--as`/`--json`, `PenFilePath`, `CommandFailure` mapper, `main()` 64→2, applier `recorder:` hook, `CommandFixture` binary runner |
| `088d106` | Cv7KU | `activity` (fresh `$WOODCASE_HOME` = empty feed, exit 0) |
| `2db59a1` | xXuLn | `tree`, `get` (+ `PenParser.encodeForFile` over any Encodable) |
| `f40c4bf` | YwLJh | `shot` (`--grid/--outline` are usage errors until qh4W1's Woodcase half) |
| `1930e4f` | xqgcQ | `undo` (revision-exact; one documented heuristic after a passed undo) |
| `79d704c` | SLVVe | `add set cp mv rm override` (+ `BatchApplier.applyOne`) |
| `190e90b` | sLTYX | `apply` (+ `BatchLineResult.isRevisionConflict`, document-less `BatchErrorMessage.describe`) |
| `320164e` | vAEwr | `vars` (+ `EditableDocument.references(to:)`) |
| `9495d15` | odhm5 | `lint` (`Sources/Woodcase/Lint/`; `PenFileTransaction.read(diagnostics:)`) |
| `89d7b57` | EnTjY | `WoodcaseViewer` target: Network.framework HTTP/SSE server, watcher, render cache, endpoints; Elementary 0.8.1 exact; `PNGEncoder` lifted into the library |

Cross-repo: PixelPeeper `main` is at `ea8d47e` (pushed) with the overlay API
(`withGrid/withOutlines/withLabels`, source-coordinate labels). Woodcase does not
depend on it yet. `../SleepyHollow/project/2026-08-29-woodcase-harness-feedback.md`
gained sections 8–12 (uncommitted there; Ben's repo).

Suite: **2401 tests** green at `89d7b57`.

## In flight when the context was cleared

- **ExnBl (viewer page + `serve` verb)** — agent "pager" (Opus) dispatched in a harness
  worktree from `89d7b57`. If its worktree still exists under `.claude/worktrees/`,
  integrate it (snapshot with hooks off, `git merge --squash`, resolve the one-line
  `WoodcaseCommand.swift` subcommands conflict, full suite, commit, push, `job done`);
  if the harness reaped it, re-dispatch from the brief recorded as `job show ExnBl`'s
  claim (the brief text is not stored — rebuild it from the leaf, `vly5R`'s rulings,
  `EnTjY`'s done-note and `project/2026-08-29-viewer-components.md`).

## Next (wave 3 carve is a note on the root, oL33Z)

Four more agents were about to be dispatched, all disjoint from ExnBl:
- **hnJiX help that teaches** — `HelpCommand.swift` (`woodcase help design`), the
  bare-invocation primer in `WoodcaseCommand.swift`, each verb's `--help` reviewed
  against the tire-kick rules, a test that every `EditingError` message names a path
  and a next step. Touches every verb file's help text only.
- **2U9E0 performance budget** — benchmark under `swift test`, numbers in a new
  `WoodcasePerformance.md` (not `WoodcaseEditor.md`, which RXaYR owns).
- **qh4W1 Woodcase half** — `Package.swift` dep
  `.package(url: "https://github.com/bensyverson/PixelPeeper.git", branch: "main")`,
  wire `shot --grid/--outline` (flags only in `ShotCommand.swift`; note `withGrid`
  returns a *larger* image, so `--grid` exceeds `--max` by design — help must say so),
  snapshot test. The viewer's click-outline is JS per Ben's ruling, so nothing there.
- **RXaYR docs and install** — `WoodcaseEditor.md`, the verb table in `WoodcaseCLI.md`
  assembled from each leaf's done-note (every verb agent returned its doc rows and a
  paragraph in its report; the done-notes point at them), README, AGENTS.md docs list,
  backlog; `swift package experimental-install`.
- **QGISs suite flake** — run **alone**, last. New evidence: the wedge is not only
  CoreText; a `sample` today showed a WebKit `IPC::StreamConnectionWorkQueue` thread
  parked in `mach_msg`. Save the full `sample` to a file next time.

## Issues filed today

- `AzXzQ` — `EditableDocument.expandRef` leaves nested refs unexpanded.
- `vq4Lp` — root-level `cp` lands on its source (placement skips when x/y present).

## Follow-ups noted on leaves, not filed

`themes` should fold into `vars` (vAEwr note); `BatchErrorMessage` wants a dialect
parameter so `CommandRemedy`'s three rephrasings exist once (SLVVe); read verbs have no
`--library`, so a library-based file lints every import as `broken-ref` (odhm5);
`lint --json` carries no revision; `IdentityOptions`' shared `--as` help contradicts
`undo`, which refuses unattributed; an `undoes` link on undo events would remove undo's
one heuristic; one `@unchecked Sendable` (`ResumeOnce`, `HTTPServer.swift`) for Ben.

## Traps this stretch paid for

- **Cap every `swift test` at 5 minutes.** Two runs wedged at 0 % CPU (27 min and
  4½ min); `sample <pid>`, kill by pid, rerun — the rerun passes in ~25 s.
- Resolving the `WoodcaseCommand.swift` subcommands conflict with a regex once
  produced a nested `subcommands: [ subcommands: [` — rewrite the block, don't regex it.
- Removing a type in one branch (`ImageExporter.ExportError`) while another maps it
  (`CommandFailure`) merges clean and fails to build; `swift build` before the suite.
