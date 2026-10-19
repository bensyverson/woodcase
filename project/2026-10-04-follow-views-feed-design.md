# 2026-10-04 — Following a file, agent views, and the agent change feed: design and plan

**Tasks:** `f7qT5M` "Follow a file and its activity in the library", `28joUe` "Agent view events", `NtYiGz` "Agent change feed" in [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md).\
**Source:** read-only research at Woodcase `f9105f3` by a subagent of Penumbra's main thread; decisions by the main thread under Ben's delegation (Ben ruled that Woodcase decides the feed's shape). None of this waits on `DocumentSession` (`rqBCLK`).

## Decisions (main thread, 2026-10-04)

1. **Forward ops go in the log** (`forward: [EditOperation]` on `ActivityEvent`). Values reconstructed after the fact can be wrong; rotation bounds the size.
2. **The feed's cursor auto-advances per identity and file**, with `--peek` and `--since` as overrides, so the verb literally answers "what changed since my last look".
3. **`lint` and `js` reads don't log views in v1** (lint touches every node; js needs its own hook).
4. **`activity --as` keeps its filter meaning**; `changes` is the agent-facing verb and the help points there.
5. **`DocumentSession`'s change value fills `forward`** with its applied ops beside the completed inverses; its merge conflicts can later land in the log as an optional `overrode` field the feed prints.

## Findings

- **`FileWatcher`** (`Sources/WoodcaseViewer/Files/FileWatcher.swift`) is a public actor, Darwin-only (`O_EVTONLY` :111, `makeFileSystemObjectSource` :114). **Re-arm bug:** `fired` cancels then calls `arm` (:137-138), which returns silently when `open` fails mid-rename (:111-112); the path leaves `sources` forever. Tests: `Tests/WoodcaseViewerTests/FileWatcherTests.swift` (no delete-then-recreate case).
- **`PresenceTracker`** (`WoodcaseViewer/Events/PresenceTracker.swift:14-69`) is a value fold of `ActivityEvent`s per identity, file-level only; `ViewerPresence` (:19-58) is the viewer's payload.
- **`ChangeCoordinator`** mixes log following, pending-by-path matching (`logged` :126-141, `attribution` 2 s window :187-201, `take` :204), adoption and SSE rendering. Only the ~30 lines of matching are reusable.
- **`ActivityReader.follow`** (`Files/ActivityReader+Follow.swift:28-185`) is a pull-polled value AsyncSequence with no task; it never ends and **doesn't expose its cursor**. Rotation is detected heuristically ("file shorter than my offset", `ActivityReader.swift:123-126`).
- **`ActivityEvent`** has no forward op; `ActivityRecorder.apply` (`ActivityRecorder.swift:91-128`) holds it and drops it. Unknown keys are ignored on decode, so adding one is backward-compatible; an unknown `op` skips the line.
- **Log invariants read `activity.jsonl` only:** `LogLineage` (newest revision = file revision), `ActivityUndo.reverse` (any foreign row is `blockedByOther`), `ChangeCoordinator.pending`. **A view row in that log would block undo** — views need their own file.
- **Read verbs take no identity** (`IdentityOptions` roles Attribution/Filter/Required). `woodcase activity` defaults `--as` to `$WOODCASE_AS` as a filter, has no `--since`, no exclude-self, no cursor, and `--follow` never ends.
- The library already handles Darwin and Glibc behind `#if` (`ActivityLog.swift:8-12`, `FileLock.swift`).

## Design

**Follow (new `Sources/Woodcase/Follow/`).**
- **`FileWatcher` moves into the library** with the same public API (the viewer imports Woodcase and compiles unchanged). Internal `FileWatchBackend`: Darwin kqueue on the file **plus** an `O_EVTONLY` source on the parent directory — a failed `open` puts the path in `missing` and the next directory event re-arms and reports it; Glibc inotify on the parent directory filtered by name (nothing to re-arm); a polling backend (`inode, size, mtime-ns`) everywhere as fallback. `deinit` cancels; a pull-mode `drain() -> [URL]`; `watchedCount` counts missing paths.
- **`ActivityCursor { inode: UInt64; offset: UInt64 }`**, string form `<inode-hex>-<offset>`. Rename keeps the inode, so a cursor into a rotated file resolves to the archive with that inode, reads it from the offset, then the live log from 0. `Follow.Iterator` exposes `cursor`.
- **`ChangeMatcher`**, a pure value type extracted from `ChangeCoordinator`: `logged(_:)`, `fileChanged(path, at:) -> Match?`, `expire(now) -> [Match]`, time injected. `ChangeCoordinator` delegates matching to it.
- **`PenFileFollower`**, a Sendable value `AsyncSequence` in `Follow`'s no-leak style: `PenFileFollower(file:, log:, from: .end | .cursor(ActivityCursor), matchWindow: 2s, pollInterval: 100ms)`. `Element`: `.changed(FileChange { revision?, events, unattributed })`, `.activity(ActivityEvent)` (log rows without a file change yet), `.viewed(ViewEvent)`, `.restarted`. Each tick drains a lazily created watcher (stopped in a box's `deinit`), reads `activity.jsonl` and `views.jsonl` from their cursors, and runs the matcher. Penumbra iterates it off the main actor.

> **As built, 2026-10-10 (w-follow2, leaves `aN7raU`, `jWEnZ0`–`EkbLay`):** `PenFileFollower(file:log:from:matchWindow:pollInterval:backend:)` with `Start` = `.end | .beginning | .position(Position)`; `Position { activity, views }` replaces a bare `ActivityCursor` because the follower reads two logs. `.end` is resolved in the initializer — log end cursors plus the document's `stat` signature, compared once when the watcher arms — so a write between creating the follower and its first poll is not lost. `FileChange { events, changedAt }` with computed `isAttributed`, `revision` (newest row's; `nil` unattributed — the follower does not parse the file), `nodes`, `identities`, in place of a stored `unattributed`. `.activity` is a row whose change was not seen: history from `.beginning`/`.position`, or a row that waited out the window — which needed `ChangeMatcher.logged(_:path:at:)` and `expireEvents(now:)`, so a late row can no longer explain an unrelated later change. `ViewEvent` has `scope: Scope` (`.nodes | .subtrees`) in place of `subtree: Bool`; a plain `get` is `.nodes` (it prints the node without children), `get --expand`, `shot` and `render` are `.subtrees`. `NodeMark` gains `verb: ViewEvent.Verb?`.

**Presence.** `PresenceTracker`/`Presence` move into the library: `record(ActivityEvent)`, `record(ViewEvent)`; `Presence.Identity { name, order, lastSeen, changes, latestChange: NodeMark?, latestView: NodeMark?, files }`, `NodeMark { nodes (≤32, subject first), paths, revision, time, op? }` — one mark per batch. Rows with no nodes update `lastSeen` only. `cursorNode` = the newer of `latestChange`/`latestView`'s first node. `ViewerPresence` maps from it.

**Views.** `views.jsonl` beside `activity.jsonl`, never in it. Factor lock/append/rotate out of `ActivityLog` into an internal `JSONLinesFile`; add `ViewLog`, `ViewReader`. `ViewEvent { time, identity, file, verb, revision, nodes (≤64, as printed), subtree: Bool, covered: Int }`. Logged by `get` (node; with `--instances` the component and ref; subtree), `tree` (printed rows; `covered` = count), `find` (matches), `shot` (selection + outline targets; subtree), `render` (roots; subtree). A new identity role `Identity.Reader` ("records that you viewed these nodes; defaults to $WOODCASE_AS; with neither, nothing is logged"). Coalesce at write: skip when the newest row for (file, identity) has the same revision and a superset of nodes. Best-effort, after the read, outside the .pen lock; a failure never fails the verb (`ViewLogging.record` in CommandCore).

**The feed: `woodcase changes`.**

```
woodcase changes design.pen [--as claude] [--since <cursor>] [--peek] [--mine] [--wait <seconds>] [--json]
```

- Excludes self by default; requires an identity (`--as` or `$WOODCASE_AS`). `--mine` includes your own rows.
- Cursor stored per (identity, file) in `.woodcase/cursors/<identity>.json` under `FileLock`, advanced each run unless `--peek`; `--since` overrides. The first run starts at the log's end and says so. Text ends with `cursor <token>`; JSON is `{file, revision, cursor, since, unlogged, changes: […]}`.
- `--wait N` blocks until a foreign change or N seconds, then exits.
- If `LogLineage` says the file diverged, print "changed outside woodcase since rev X — re-read".
- `ActivityChangeSummary` pairs `forward` with `inverse`: property ops become `[{path, key, old, new}]` (whole-struct ops diffed with `PropertyDiff`); moves and inserts get one-line forms; rows grouped by `batch`. Example: `16:31  ben  set  Home/Hero/Title  kind.content: "Welcome" → "Welcome back"`.

> **As built, 2026-10-19 (w-feed, leaves `aBelQG`, `VHd5im`, `MYXL44`):** the library type is `ChangeFeed` (`Sources/Woodcase/Feed/`) with `read(from: .stored | .cursor(c))`, `wait(from:timeout:pollInterval:)` and `save(_:)`; the verb is a thin adapter. `ActivityChangeSummary(event)` holds one row (`time, identity, file, op, revision, batch, changes`), each `Change` `{kind, node, path, key, old, new, parent, index, descendant}` with a computed `line`; `nil` old/new means absent, distinct from JSON `null`. A whole `updateCommon` reads its changed keys from the **granular** inverse a session records, and diffs with `PropertyDiff` only when the inverse is itself whole (pre-2026-10-04 rows); keys a write left unchanged are dropped. Rows are not regrouped by batch — they arrive in log order, which already keeps a batch together, and each row carries its `batch`. Text rows print `HH:mm:ss` (as `activity` does), not `HH:mm`. The cursor store is `ActivityCursorStore`, `cursors/<percent-encoded identity>.json` = `{canonical path: token}` in the log's home (so `$WOODCASE_HOME/cursors/` under the override, `<bundle>/.woodcase/cursors/` for a bundle). JSON is `{file, identity, revision, since, cursor, origin, restarted, unlogged, changes}`; `origin` is `stored | since | first-look`, `unlogged` is `{since, found}` or `null`. **`--wait` does not use `PenFileFollower`:** the feed reads the document under its shared lock, which a write holds from file write to log append, so lineage is exact and the matcher's 2 s window is not needed; it polls the log tail and the file's `stat`. A `--wait` with nothing by the deadline exits **3** (cli-design: "no answer" is 3), the cursor still printed and saved.

## Plan: follow (`f7qT5M`)

`job import` each block with `--parent` (this file's first block imports directly; extract the others).

```yaml
tasks:
  - title: "FileWatcher in the library, with backends and the re-arm fix"
    ref: f-watch
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, Follow. Move WoodcaseViewer/Files/FileWatcher.swift into Sources/Woodcase/Follow/ (FileWatcher*.swift) with Darwin, Glibc and polling backends; delete the viewer copy. Regression test for delete-then-recreate first."
    criteria:
      - "A delete-then-recreate write is reported and later edits are too, on the Darwin and polling backends"
      - "The library builds on Linux and the inotify backend passes the same suite (or the Linux run is documented as not possible here)"
      - "The viewer's FileWatcherTests pass unchanged after the move"
  - title: "ActivityCursor and rotation-safe resume"
    ref: f-cursor
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, ActivityCursor. Files/ActivityReader*.swift."
    criteria:
      - "A cursor taken before rotation resumes with no gaps or repeats"
      - "Follow.Iterator exposes the cursor after each event"
  - title: "ChangeMatcher extracted from ChangeCoordinator"
    ref: f-match
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, ChangeMatcher. Sources/Woodcase/Follow/ChangeMatcher.swift; WoodcaseViewer/Events/ChangeCoordinator.swift delegates."
    criteria:
      - "Matcher tests with injected time cover in-hand, late-arriving and expired events"
      - "ChangeCoordinatorTests pass unchanged"
  - title: "Node-level PresenceTracker in the library"
    ref: f-presence
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, Presence. Move PresenceTracker into Sources/Woodcase/Follow/; the viewer maps Presence to ViewerPresence."
    criteria:
      - "A batch yields one latestChange with its subject node first"
      - "Identity order is stable by first appearance"
      - "The viewer's presence payload is byte-identical"
  - title: "PenFileFollower"
    ref: f-follower
    blockedBy: [f-watch, f-cursor, f-match, f-presence]
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, PenFileFollower. View events plug in with 28joUe's last leaf. Penumbra's contract leaf 'follow a file, its activity and agent views' tests exactly the first two criteria."
    criteria:
      - "Following a fixture yields an attributed .changed event with node ids after `woodcase set --as claude`"
      - "It keeps following through a delete-then-recreate write"
      - "Cancelling the consuming task leaves no source or task alive"
```

## Plan: views (`28joUe`)

```yaml
tasks:
  - title: "JSONLinesFile, ViewLog, ViewReader and ViewEvent"
    ref: v-log
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, Views. Sources/Woodcase/Files/. Shares ActivityCursor (f7qT5M 'ActivityCursor and rotation-safe resume')."
    criteria:
      - "ActivityLog tests pass unchanged after factoring out JSONLinesFile"
      - "views.jsonl rotates on its own"
      - "A same-revision subset read is coalesced away"
  - title: "Reader identity and view logging in tree, get, find, shot and render"
    ref: v-verbs
    blockedBy: [v-log]
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, Views (Identity.Reader, ViewLogging.record). WoodcaseCommandCore verbs and options."
    criteria:
      - "An attributed tree or get records nodes and revision; an unattributed read records nothing"
      - "A failing views write does not fail the verb"
      - "The read verbs' PerformanceBudgets still hold"
  - title: "Invariant guards for view events"
    ref: v-guard
    blockedBy: [v-verbs]
    desc: "Design: project/2026-10-04-follow-views-feed-design.md. Tests only."
    criteria:
      - "set, then an attributed tree, then undo still undoes"
      - "LogLineage stays current after attributed reads"
      - "ChangeCoordinator attribution is unchanged by view rows"
  - title: "The follower and presence consume views"
    ref: v-follow
    blockedBy: [v-verbs]
    desc: "Design: project/2026-10-04-follow-views-feed-design.md. Blocked also by f7qT5M's PenFileFollower leaf. Penumbra's contract tests the first criterion."
    criteria:
      - "A .viewed event arrives with node ids and revision after `woodcase get --as claude`"
      - "Presence sets latestView from it"
```

## Plan: feed (`NtYiGz`)

```yaml
tasks:
  - title: "Forward ops on ActivityEvent"
    ref: n-forward
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, decision 1. Files/ActivityEvent*.swift and Files/ActivityRecorder.swift (record the op it already holds). DocumentSession's CLI leaf also edits ActivityRecorder later; land this first."
    criteria:
      - "Every recorded row round-trips forward"
      - "Old lines decode with an empty forward"
      - "The undo, lineage and viewer suites are unchanged"
  - title: "ActivityChangeSummary"
    ref: n-summary
    blockedBy: [n-forward]
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, the feed. Library type pairing forward with inverse."
    criteria:
      - "A whole-struct updateCommon yields only the changed keys with old and new values"
      - "mv, add, rm, override and var each have a one-line form"
  - title: "woodcase changes and the cursor store"
    ref: n-verb
    blockedBy: [n-summary]
    desc: "Design: project/2026-10-04-follow-views-feed-design.md, the feed. Blocked also by f7qT5M's ActivityCursor leaf. Follow project/agents/cli-design.md."
    criteria:
      - "It lists only others' changes with new values, and its cursor resumes with no repeats"
      - "--wait returns on the first foreign change or at the timeout"
      - "A diverged file reports unlogged changes"
  - title: "Agent docs and the feed contract script"
    ref: n-docs
    blockedBy: [n-verb]
    desc: "woodcase help recipes (the edit, react, resume loop), WoodcaseActivityLog.md sections for forward and views.jsonl, AGENTS.md. Write ../Penumbra/scripts/contracts/agent-feed.sh as an integration note for Penumbra's main thread (do not edit Penumbra). Criterion 'Ben's Penumbra edits appear attributed' is proved with --as ben now; real Penumbra edits depend on ZEAWVY — note it."
    criteria:
      - "The feed contract script passes against a scratch .pen"
      - "The recipe shows the edit, react and resume loop"
```
