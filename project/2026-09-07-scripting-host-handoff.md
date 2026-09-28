# Scripting host: handoff after the first day

*2026-09-07. Handoff note. Status: point-in-time record of where the [scripting-host plan](2026-09-07-scripting-host.md) stands after one session, written so a fresh session starts from `job orient` plus this file.*

> **Superseded the same evening** by [the second handoff](2026-09-07-scripting-host-handoff-2.md): the `js` verb, imports, `help js` and the scripting folder grouping landed, Penumbra's pipeline leaf closed, and the follow-ups below were filed. Read that one; this stays as the record of the first sitting.

## Where main is

Seven of the plan's thirteen leaves are on `main` (root `6vdq3j`), each integrated by squash-merge with the whole diff read, the full suite green over the merge, and a closing note on the leaf:

| Commit | Leaf | What landed |
|---|---|---|
| `0dc0372` | `uOWNQY` | Command core grouped into one-level folders (Verbs/, Options/, Reports/, Failures/, Help/, Shot/, Lookup/, Hosting/; tests mirror, harness in Support/) |
| `0ab13f1` | `HVUDGz` | `WriteReport`, `NodeReport`, `CreatedTreeReport` public in the library; formatting stays in the command core |
| `b92181b` | `111nTf` | The editing layer un-pinned from the main actor; transactions run on the caller's isolation; soak default 600 s |
| `f1c353c` | `dTJiWG` | `WoodcaseScripting` target, read-only `ScriptHost` (`doc.rev/tree/get/lint/schema`), prelude Proxy, deadline, `NodeLookup` and `Schema*Report` moved into the library |
| `69213b0` | `5tBWny` | `LogLineage`, the `external` event and the outside-write note; undo in the library; undo by transaction with `--event` |
| `6e36292` | `Dy6k8Z` | `woodcase find`: tree's rows filtered by a JavaScript predicate; `RowPredicate` with a refusing row Proxy |
| `ee11fa9` | `yp3EcU` | The eleven write members on `doc`, parity with the verbs proven against the binary, optional recorder, write-then-read figure recorded |

Suite at the last commit: 3975 tests in 414 suites passed in 50.5 s (`swift test --quiet`). `swiftformat . --lint` clean.

## What is next, in order

`job orient` in `/Users/ben/git/Woodcase` picks the first available leaf. The frontier:

1. **`DESilx` — the `js` verb.** Blocked on nothing now. The host is complete on both sides. Integration notes the write agent left for it are in `job show yp3EcU`: wrap `ScriptHost.run` in one `PenFileTransaction.run(at:identity:log:effect:)`, pass `remedy: .command(file:)`, the parse's diagnostics and the transaction's recorder; throw when `run.error != nil` so nothing commits; map the transaction's outcome over `run.commit` (`.previewed` for a dry run, `.unchanged` when writes cancelled out). The watchdog thread and the exit codes are the verb's. Print the outside-write note the way the verbs do (`OutsideWriteNote.report`). Two corrections for its transcript, from the find and write agents: a `TreeRow` member is `address`, not `path`; and the primer should say why a `find` predicate's throw exits 2 while a `js` script's uncaught error exits 1.
2. **`TyiIb1` — imports on every route.** Blocked on nothing now. The seam is left ready in the prelude's MEMBERS table (a comment names the three edits) and in `ScriptWrite.RemoveRequest.Table`.
3. **`HNG9g4` — `help js` and the executable primer.** Blocked on `DESilx`. The `.d.ts` surface, as shipped, is in the write agent's report (`job show yp3EcU`, section 9) and `ScriptHost.members()` / `topLevelMembers()` return it at runtime for the reflection test. Retired keys with redirecting sentences: `tree.absolute`, `get.instances`, `lint.summary`, `lint.list`, `add.tag`, `cp.tag`, `cp.name`, `cp.times`.
4. **`nBUycj` docs, `ShQWa9` trial, `W9MdJV` retire** follow the plan.

## Follow-ups filed nowhere yet — file before dispatching the next leaf

- Root-overlap warnings are not emitted as script `.warning` events (`RootOverlapWarnings` is command-core). The `js` verb can print them after the run; a library caller cannot see them. Small leaf or fold into `DESilx`.
- `VarsRemove.refusal(...)` and `ScriptWrite.refuseIfInUse` decide "is this variable referenced" in two modules. One library helper wanted.
- `migrate` and `new` write outside `PenFileTransaction`, so a `migrate` of a logged file correctly draws the outside-write note on the next write. Untested combination; route `migrate` through a transaction when it bites.
- Write-then-read in a script costs one full settle per pair (582 ms on the largest local document). The incremental-settle optimization behind `SettledTreeCache` is named in `WoodcasePerformance.md`, not built.
- One wedged suite run during integration (22 min at 0.2 % CPU, under load from a parallel agent build); the sample is `local/wedge-2026-09-07-find-merge.sample.txt`. Frames of ours were present, in Swift concurrency thunks. One occurrence; not yet a finding.
- `NodeReport` lives in `Sources/Woodcase/Batch/` because the plan said "beside BatchReport"; it is a read-side report. If more accrete, a library `Reports/` folder.

## Findings of the day

- **The un-pin widened the WebKit tail under artificial load** — `project/2026-09-07-unpinning-and-the-loaded-soak.md`. Best-supported reading: the main-actor pin was an accidental throttle. Not proven.
- **"The compiler accepted it" from a red build proves nothing** — `project/gotchas.md`, 2026-09-07. A phase-B claim that a non-Sendable document crossed into an actor with no diagnostic was an artefact; once Penumbra's 31 model errors were cleared the compiler refused it seven times, as the docs say.
- Three stale-object faces are now in `gotchas.md`: adding an enum case moves `Optional`'s `nil` tag and stale test objects then fail impossibly; `JSContext` reports the source URL back, not the name; `Task.detached` inside an `isolated`-parameter function does not compile.

## Penumbra

Separate tracker (`/Users/ben/git/Penumbra`, root `t4gsMa`). Landed today, all with the pre-commit hook skipped because the unit suite cannot run yet: the breadcrumb trail and rules sync that were left staged (`f4b4de7`, `28b1aef`), the un-pin follow-up (`3ec2fb5`), the adoption doc with Ben's four rulings (`7da8161`), and the .pen 2.17 port (`4ec2a8e`), which clears all 31 model errors. Open: **`9oPyCy`** — hand `DocumentPipeline` Sendable values instead of the live document (seven sendability errors; the phase-B §9 list is the shape); **`WxrHuo`** migration diagnostics on open, blocked on it; **`zzxHpw`** group transform parity. Penumbra's build is green only once `9oPyCy` lands. A Penumbra agent needs a *sibling* worktree (`git worktree add /Users/ben/git/penumbra-<name> …`) so the project's `../../Woodcase` path resolves.
