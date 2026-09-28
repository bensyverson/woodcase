# Handoff: what remains after the issue sweep

*2026-08-31. Written by the integrator at the end of the sweep session for whoever picks up the remaining issues — Ben plans to take `TCMmx` next session and wants the rest knocked out too. Read this after `job orient`; every claim here is verifiable in the tracker (`job show <id>` carries the full notes) or in the commits `9394777..6f619e7`.*

## Where the session left the repo

The concurrent-DX issue sweep is done: 15 issue leaves closed by seven worktree agents, integrated as eight commits on `main` (`9394777` icons/shot → `6f619e7` activity), suite green at 3242 tests, pushed. Three issue premises were corrected during the sweep — recorded on their leaves (`NHkOc`, `SWr75` retitled, `8kAHL`) — so **do not trust an issue description older than its last note**; read the notes.

`expVd` (metadata `_scroll` lint intent) closed before the session ended — integrated as `77a0f07`, which auto-closed `dN6XF`. The load-bearing fact behind the design (Pen.app drops unknown node keys on resave but preserves `metadata` verbatim) is recorded in `local/Pen-Schema-2.17.md`'s observed section, verified with `pen interactive --in … --out …` probes. One trap from that integration worth knowing: `TreeRow.init` gaining a defaulted parameter left SwiftPM linking a stale `WoodcaseViewerTests` object (`ld: symbol(s) not found`) — the gotcha filed this very session ("a public signature change can leave SwiftPM linking stale test objects") fired within hours; `touch` the test file naming the symbol and rebuild.

## The remaining issues, in the order I would take them

### 1. `TCMmx` — premise guards and the divergence echo (Ben's pick)

**Read [`2026-08-31-guards-and-echo.md`](2026-08-31-guards-and-echo.md) first** — the design was talked through with Ben and committed as `5a76473`; the leaves implement it, not a fresh design. Order is forced by the block edge: `DemV8` (Merkle content hashes on every read) → `2NW90` (`--guard` on writes, blocked on DemV8) → `pjupK` (the divergence echo on every write). `aPPZS` (spike: cost of routing CLI writes through the CRDT layer) is independent and disposable — an ephemeral verifier whose verdict lands as a note, no worktree ceremony needed.

**Check the design's premises before dispatching** — it predates the sweep, and the sweep changed the write pipeline underneath it:

- `ActivityRecorder.apply` now returns a **non-optional** `ActivityEvent` and unattributed writes log as `identity: ""` (`6f619e7`). Anything in the design that assumed a write might not be logged is stale.
- Batch/root placement now measures through `RootOverlap.roots(in:)` (the linter's pipeline), and `@tag/child` composes in addresses (`016774a`).
- Which component a nested ref places is now `effectiveRefData(of:insideInstances:)`'s answer (`be5e60b`) — if guards hash expanded content, hash through that seam, not the authored store.
- Every read verb already carries a revision (`rev` on `tree`, `--guard`'s natural anchor); `EditableDocument+Revision.swift` and `EditableDocument+Guards.swift` are the existing seams.

The divergence echo touches the write path *and* every write verb's output — that is one agent's surface, not a fan-out; the Merkle leaf is cleanly separable. Two agents at most, Opus for the guard semantics (fail-closed wiring reads like plumbing and isn't).

### 2. `vvxHi` — the Escape-to-map browser-test race

Method is in the issue and in [`2026-08-31-follow-is-a-value.md`](2026-08-31-follow-is-a-value.md): find what *records* the state Escape's assertion reads, and `waitFor` the recording, not the effect — a wait placed after a navigation can never rescue state the departed page failed to write. The dot-race fix in `ViewerFollowBrowserTests.unreadDotUntilViewed` (in `6f619e7`) is the worked example to copy. Small, Sonnet-sized, and worth doing *first* if you fan out — it is the last known baseline flake, and every integration in this session paid for it in rerun ambiguity.

### 3. `3uBxi` — the full-suite 0 %-CPU wedge (the real one)

The hard one. `8kAHL`'s follow rewrite fixed a genuine leak but **not** the wedge; the diagnosis correction matters more than any code from that leaf: a Swift task suspended at an `await` has no stack frames, so `sample` shows the *survivors*, not the culprit — an empty-of-our-code sample means "something is suspended; ask what it was waiting for." Two samples are preserved: one pair in the finding doc above, and the integrator's own wedged run at `local/wedge-samples/2026-08-31-integrator-run-46108.txt` (86 MB footprint, ~0 % CPU, live `com.apple.network.connections` queue, essentially no Woodcase frames).

Leads, strongest first: `HTTPServer.start(port:)` and `HTTPConnection` both `await` a `withCheckedContinuation` on a Network.framework state handler — a handler that never fires is an unresumable continuation and matches every observation; `project/gotchas.md` already records an un-root-caused `NWListener` `EINVAL` on the same seam (raw POSIX sockets did not misbehave — a possible escape hatch if the framework is the problem). Reproduces only under multi-agent build load; `scripts/soak-tests N --load 2` is the harness, and a stability claim needs a **loaded** soak, not a quiet one (standing ruling). Opus, and budget real time — this has eaten three wedged hosts across two sessions.

## Session mechanics that will save you time

- **The delegation pattern that worked**: briefs from the template in `project/agents/delegation.md`, every report answering "what in this brief is wrong?" — three issue premises fell to that question alone. Read agents' answers before their diffs.
- **Tell agents: no background test runs.** Three of seven agents this session stalled ending their turn to "wait" on a backgrounded `swift test` and needed a nudge; the brief line "run tests as plain foreground calls" prevents it.
- **Never pipe a gating command.** `swift test | tail` swallowed a killed run's exit status this very session and reported success on 22 bytes of output — the gotcha existed and it still bit. `swift test > log 2>&1; echo $?; tail log`.
- **Integration flow**: snapshot the worktree with hooks off, verify `git merge-base`, `merge --squash`, read the whole staged diff, suite, commit through hooks, close leaves, remove the worktree. Commit each squash before starting the next.
- **The claim guard blocks integrator notes on claimed leaves** — `--as <agent>` is the workaround; it misattributes, and it is on the Jobs feedback list, but it is what works today.

## Not issues, but open threads

- The Jobs issue-workflow field report sits uncommitted at `../jobs/project/2026-08-31-issue-tree-field-report.md`; its five suggestions are for the Jobs repo's own tracker.
- `scripts/mae-check` and the pre-commit hook were untouched by the sweep; nothing pending there.
