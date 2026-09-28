# Scripting host: second handoff, end of day

*2026-09-07, late. Handoff note. Status: point-in-time record, **superseded by [the trials handoff](2026-09-08-trials-handoff.md)**; it itself superseded [the first handoff](2026-09-07-scripting-host-handoff.md); a fresh session starts from `job orient` plus this file.*

## Where main is

Ten of the plan's thirteen leaves are on `main` (root `6vdq3j`). Landed this sitting, each integrated by squash-merge with the whole diff read and the full suite green over the merge:

| Commit | Leaf | What landed |
|---|---|---|
| `afa29ec` | — | Gotchas pruned; the first handoff's five loose follow-ups filed as issues |
| `4207c93` | `TyiIb1` | Imports on every route: the `import` batch line, `imports list/set/rm`, `doc.imports.set/rm`, and `NameInUse` — one library decision for "is this name still referenced" that `vars rm`, `doc.vars.rm`, `imports rm` and `doc.imports.rm` share; `RemedyDialect.script` |
| `ebdaa33` | `DESilx` | `woodcase js`: one transaction, guards at the door, the host as sink, a `Thread` watchdog, `ScriptRunReport` behind both output forms; a host bug fixed (a prelude refusal was located at the prelude's line); the plan transcript corrected in place |
| `38c04a1` | — | WoodcaseScripting grouped into Host/, Bridge/, Prelude/, Failures/, Predicate/; tests mirror, fixture under Support/ |
| `f174fb4` | `HNG9g4` | Write rows lead with the `doc` member (`ScriptWriteMember`); `woodcase help js` with the hand-written `.d.ts` held to `ScriptHost.members()` in both directions and every snippet run through the binary; `find` and `js` in the design primer within its budget |

Suite at `f174fb4`: 4065 tests in 422 suites, 54 s on a quiet machine (`swift test --quiet`). `swiftformat . --lint` clean.

Penumbra (`/Users/ben/git/Penumbra`, root `t4gsMa`) builds green against Woodcase `main` for the first time since 2026-08-29: `70fef57` hands `DocumentPipeline` Sendable values instead of the live document (leaf `9oPyCy`), `db10711` logs migration diagnostics on open (`WxrHuo`). Its unit suite is 500 tests. One leaf remains there, `zzxHpw` group transform parity.

## What is next, in order

1. **`nBUycj` — documentation and the README.** Unblocked. WoodcaseScripting.md in the DocC catalog with the contract, the `.d.ts` verbatim from `help js` (`Sources/WoodcaseCommandCore/Help/HelpTopic+Js.swift`), the transaction rules, errors that teach, the watchdog and the platform note; links from Woodcase.md, a "When the answer is a loop" section in WoodcaseEditor.md, the README bullet, and CLAUDE.md's documentation list. The `js` section of WoodcaseCLI.md is current and is the shipped contract.
2. **`ShQWa9` — the agent trial.** A Sonnet-class agent, a Quill-shaped task on a copy of a real file, `help design` and `help js` as its only teaching. Read the issues below first: two of them are traps the trial is likely to hit, and the trial's finding should say whether it did.
3. **`W9MdJV` — decide what the batch surface keeps**, from the trial's evidence.

## Issues filed this sitting (`job ls --issues`)

- `MSGsdo` — **`doc.tree()` rows are plain objects**, so `r.props['kind.fontSize']` is `undefined` under `js` where `find`'s Proxy would refuse. `help js` fences it (declares `properties` only); the fix is one Proxy for both routes. The trial agent will probably write `r.props` in a script, because `find` taught it.
- `ctvJct` — root-overlap warnings never reach `ScriptRun`'s timeline; the `js` verb prints them, a library caller cannot see them.
- `zgRA2q` — two simultaneous suites share `/tmp/pen-exports` and the font cache.
- `DpQmXu` — the wedged suite run, now with two samples and the experiment below.
- `gArj6O`, `Tdgxuz`, `KjvK46` — migrate outside the transaction, the write-then-read settle cost, NodeReport's folder.

## Findings and decisions of the sitting

- **`RemedyDialect` gained `.script`.** The script route had been passing `.batch`, and a script has no `--force`; `NameInUse.sentence(in:)` is the one place the three dialects diverge.
- **A `WriteReport` says what was touched, never what touched it.** That is why the member rides on the event, not in the report, and why `override` needed the column: it reports the instance.
- **The `.d.ts` is written by hand, not generated.** The prelude's table knows names, kinds and option keys; the reflection test buys what generation would have.
- **`doc.lint()` under `js` omits parse diagnostics.** `PenFileTransaction.run` has no diagnostics seam; `apply --dry-run` has the same gap. Recorded on `DESilx`'s closing note, not filed.
- **Penumbra's app target defaults to `MainActor`; extensions of Woodcase types do not inherit it.** In Penumbra's `project/gotchas.md`.

## The wedge experiment

Question: does a second `swift test` running at the same time reproduce the wedge (issue `DpQmXu`, two occurrences, both under three-way build load)? Three rounds on a quiet machine at `f174fb4`, one suite in the main checkout and one in a worktree, verbose logs in `local/wedge-experiment/round{1,2,3}-{a-main,b-worktree}.log`:

| Round | A (main) | B (worktree) | Overlap |
|---|---|---|---|
| 1 | passed, 72.6 s | passed, 50.4 s | A ran during B's cold build; B's tests ran alone |
| 2 | passed, 70.8 s | passed, 69.9 s | full |
| 3 | failed, 69.2 s (1 issue) | passed, 67.3 s | full |

No wedge, no stall over 30 s in any of the six runs. The one failure is `ViewerBrowserTests` "Selecting a node scrolls the outline to its row", the scroll-sensitive browser test `gotchas.md` (2026-08-30) already records as load-flaky. **Two overlapping suites alone do not reproduce it**; both real wedges had a third load source, an agent's `swift build` plus Penumbra's `xcodebuild`. That is consistent with [the August finding](2026-08-31-the-await-that-cannot-resume.md) that the face is contention-shaped rather than one shared resource. Two shared resources exist anyway and are filed as `zgRA2q`: `/tmp/pen-exports` and the font cache. Reproduce the table with the three round commands in the issue's note. Recommendation, adopted in the note: the integrator runs the suite verbose into a log rather than `--quiet`, so a wedge names its in-flight tests, which a sample cannot.

## Restart

`job orient` in `/Users/ben/git/Woodcase` picks `nBUycj`. Both checkouts are clean; no worktrees or agents remain. The saved memory in the assistant's project directory matches this file.
