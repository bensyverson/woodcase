# Viewer & Editor: implementation plan

Drafted: 2026-08-29 by Claude (Fable 5) with Ben. Answers the brief in
[2026-08-29-viewer-editor.md](2026-08-29-viewer-editor.md); the agent-experience evidence is
in [2026-08-29-pen-mcp-tire-kick.md](2026-08-29-pen-mcp-tire-kick.md).

## Decisions

Each of these was discussed and settled; the why is one line, the details are in the
two linked docs.

1. **CLI first, one binary.** New verbs join `woodcase` beside `render`/`generate`/
   `themes`/`migrate`. Agents already have a shell; the `sleepy`/`job` conventions
   (structured output, meaningful exit codes, help that teaches) are the model. No MCP,
   REST or stdin protocol in Woodcase — Penumbra hosts the MCP over the same core.
2. **Stateless commands over a stateful file.** Each invocation opens → applies →
   writes atomically under an exclusive file lock. No daemon. What would justify one is
   recorded in `backlog.md`.
3. **Per-node revision tokens, not a CRDT, for concurrent agents.** `get`/`tree` return
   a subtree hash; mutating verbs accept `--rev` and fail loudly only when a node they
   touch has changed. Two agents on different frames never collide; two on the same node
   get an error instead of a silent last-writer-wins. The CRDT stays for Penumbra's live
   peers.
4. **Creation is declarative: `add` takes a .pen subtree.** The agent's own loops
   generate the JSON; we never interpret code. Small edits use `key=value` flags;
   batches are JSONL, one op per line.
5. **Batches apply what they can.** A failed op is skipped, ops that depend on it are
   skipped as *cascaded*, the file is written once with what succeeded, and the report
   has one line per op. `--atomic` opts into all-or-nothing. `apply --retry` re-runs only
   the failed lines.
6. **Nodes are addressed by name path or id**, resolved to ids at write time.
   Ambiguity is an error that lists the candidates; a match on nothing is an error, never
   a no-op. Nodes the CLI creates must be named; files we did not write may hold unnamed
   nodes, which `tree` flags.
7. **Reads see settled layout, in the same invocation as the write.** `tree` is one row
   per node — id, type, name, resolved rect, clip flag — the layout-aware view that
   replaces most screenshots. Every read and `shot` takes `--theme`.
8. **Consequential destruction is loud.** Deleting a component with instances refuses
   without `--detach`; the error says what would happen.
9. **Identity is `--as <name>`** (or `$WOODCASE_AS`), mapped to a `PeerID`. No
   registration. Every op appends one JSONL event — with its inverse — to
   `~/.woodcase/activity.jsonl`; that log is the dashboard, the "cursor", the feed other
   tools consume, and what `undo` replays.
10. **The viewer is `woodcase serve`**: a local web page over SSE that is both the
    cross-file dashboard and the artboard view, with an outline side panel and an
    activity feed. Click or select a node → the node is outlined in the render.
    Read-only; it does not compete with Penumbra.
11. **Vision helpers (grid, outline, labels) live in the `PixelPeeper` library** so
    `peep`, `sleepy` and `woodcase` share one implementation. Page/canvas coordinates
    are a scale parameter the caller passes.
12. **Install via `swift package experimental-install --product woodcase`**; a Homebrew
    tap is in `backlog.md`.

## Shape of the CLI

```
woodcase tree <file> [<node>] [--depth N] [--props] [--json] [--expand] [--theme k=v]
woodcase get  <file> <node> [--json] [--expand]
woodcase add  <file> <parent|document> -F subtree.json [--at N] [--as name]
woodcase set  <file> <node> key=value … [--rev H]
woodcase cp   <file> <node> <parent> [key=value …] [--at N]
woodcase mv   <file> <node> <parent> [--at N]
woodcase rm   <file> <node> [--detach]
woodcase override <file> <instance>/<path> key=value … | -F subtree.json
woodcase vars <file> [set name=value [--theme k=v] | rm name | axis add k=v,v]
woodcase apply <file> -F ops.jsonl [--atomic] [--retry <report>]
woodcase undo <file> [-n N] [--as name]
woodcase lint <file> [<node>] [--theme k=v] [--json]
woodcase shot <file> [<node>] --out x.png [--max PX] [--grid] [--outline <node>…] [--theme k=v]
woodcase activity [--follow] [--json] [--file F] [--as name]
woodcase serve [--port N] [<file>…]
```

Contracts, shared by every verb: `--json` on every read; exit codes are `sleepy`'s table
verbatim (0 success / 1 clean negative / 2 usage / 3 conflict or timeout / 4 file error / 5
environment) so an agent learns one table across Ben's tools; a
mutating verb's output is the name → id map of what it created, as a tree; errors name
the node by path and say what to do next. `woodcase help design` and each verb's `--help`
carry the flex-first guidance an agent needs (root-level `add` without `x`/`y`
auto-places; children of a laid-out parent take no coordinates) so no external skill is
required.

Addresses: an id (`ALu8G`), a name path from any ancestor (`Dashboard/Header/Title`),
an instance path (`Orders/Value`), or a batch tag (`@hero`) for forward references
within one `apply`.

JSONL op grammar mirrors `EditOperation` with the addressing above; `add` ops carry a
`.pen` subtree as `node`. A report line is `{"line":11,"status":"failed|applied|
cascaded","error":…,"created":{…}}`.

Activity log: `~/.woodcase/activity.jsonl` (`$WOODCASE_HOME` overrides the directory),
one event per applied op: time, identity, file, op kind, node ids and name paths, the
inverse operation, the resulting file revision. `serve` tails it; `undo` replays inverses.

## Sequencing

Core editing (library) → CLI verbs → viewer, with the vision helpers a parallel,
cross-repo track that only `shot --grid/--outline` and the viewer's click-outline wait
on. Strict red/green throughout; every leaf below starts with failing tests. The
library work stays cross-platform (Foundation only); `shot` and `serve` are Apple-only
like `render`, because the renderer is CoreGraphics — `serve`'s HTTP/SSE server is a
minimal hand-written one on `Network.framework`, guarded with `@available`, rather than
a dependency (flagged here so it can be overruled before the leaf is claimed).

The viewer page is built only after a **design prototype in Pen** has been signed off —
a short visual design pass that doubles as a second agent-DX report.

## Handoffs to sibling repos

- **Penumbra:** the file is the truth. Penumbra must reload a `.pen` when it changes on
  disk (autosave or 3-way merge against unsaved edits); without that, agent edits and
  a live Penumbra session diverge. File in Penumbra's tracker when this plan's CLI lands.
- **PixelPeeper:** the vision-helper library API (grid, outline, labels over a
  `CGImage` with a coordinate scale). **SleepyHollow:** migrate `ShotGrid` to it.

## Not now

Recorded in `backlog.md` with their un-parking triggers: an MCP surface in Woodcase, a
daemon / warm host, a SQLite op-log sidecar, a native viewer app, Homebrew, a `diff`
verb, image-asset import.

```yaml
tasks:
  - title: Woodcase Viewer & Editor
    labels: [viewer-editor]
    desc: |
      Agent-first CLI editing of .pen files and a read-only live viewer. Decisions and the verb set are in project/2026-08-29-viewer-editor-plan.md; the agent-experience evidence is in project/2026-08-29-pen-mcp-tire-kick.md. Read both before claiming. Strict TDD on every leaf.
    children:
      - title: Editing core
        desc: |
          Library-level pieces the CLI is a thin consumer of. All in Sources/Woodcase/Editing (or a new Editing/Agent-facing folder, one type per file), Foundation-only, DocC at 100%.
        children:
          - title: Path-based property patch operation
            ref: patch
            desc: |
              EditOperation.updateKind replaces a node's whole kind; agents want to set one property. Add a `setProperties` operation carrying a [String: AnyCodable] keyed by the same property paths LWWPropertyMap already uses ("kind.width", "common.name"), applied through PenNodePatcher-style merging, with an inverse, dirty-tracking classification via ChangeCategory, and CRDT emission as per-path LWW writes. Unknown keys and type mismatches are typed EditingErrors naming the key.
            criteria:
              - setProperties on a rectangle's fill leaves every other property untouched and round-trips through materialize()
              - An unknown property key fails with an error naming the key and the node
              - The CRDT emits one LWW write per path and two peers converge
          - title: Node addressing
            ref: address
            desc: |
              A resolver from an address string to a node id: id, name path from any ancestor ("Dashboard/Header/Title"), instance path into a ref's expanded tree ("Orders/Value", resolved to the component child id for storage in descendants), and a within-batch tag ("@hero"). Ambiguity is a typed error carrying every candidate as an id plus its full name path; no match is a typed error that lists near misses (same leaf name elsewhere). Also a name-path formatter for the reverse direction, used by every error message and by tree output.
            criteria:
              - Each of id, name path, instance path and tag resolves in a fixture with nested refs
              - A duplicate name yields an ambiguity error listing all candidates with full paths
              - A miss yields an error that names near misses
          - title: Revision tokens
            ref: rev
            desc: |
              A stable hash per node subtree (properties, children order, descendant hashes) and one for the document, computed from the flat store and exposed on EditableDocument. A mutating operation may carry an expected revision for each node it touches; a mismatch is a typed conflict error naming the node and both revisions. Document-level revision is what the activity log records.
            criteria:
              - Editing a child changes the ancestors' revisions and no sibling's
              - An operation with a stale expected revision fails with a conflict naming the node
              - Revisions are stable across encode/decode of the same file
          - title: Batch applier
            ref: batch
            desc: |
              Applies an ordered list of operations (the JSONL grammar in the plan) to an EditableDocument in memory: each op resolves its addresses (including @tags created earlier in the batch), applies, and records a per-op result; a failure skips the op and marks every later op that references its tag or target as cascaded; independent ops continue. The result is a report (line, status, error, created name→id tree). Atomic mode discards everything on the first failure. Also the retry: given a prior report, re-run only its failed and cascaded lines.
            blockedBy: [patch, address, rev]
            criteria:
              - A batch with a bad op in the middle applies the independent ops before and after it
              - An op referencing a failed op's tag is reported as cascaded, not failed
              - Atomic mode leaves the document unchanged after any failure
              - Retry re-applies exactly the failed and cascaded lines
          - title: File transactions
            ref: file
            desc: |
              PenFileTransaction: open a .pen under an exclusive advisory lock (flock on the file), parse, hand an EditableDocument to a closure, write the result atomically (temp file + rename, same directory) in the canonical form migrate already writes (sorted keys, two-space indent), release. A held lock is waited on with a bounded timeout, then a typed error. Unchanged documents do not rewrite the file (mtime stays).
            criteria:
              - Two concurrent transactions on one file serialize; neither loses the other's edit
              - Output bytes for an unchanged document are identical to the input
              - A lock held past the timeout fails with a typed error, not a hang
          - title: Consequence guards
            ref: guards
            desc: |
              Operations whose consequence exceeds their target refuse without an explicit flag and explain: deleting a reusable node that has instances (lists them; `detach` applies detachRef to each first), an override or descendant patch that matches no node in the component (error, never a silent no-op, with candidates), moving a node into its own subtree. Each guard is a typed EditingError with the information the CLI needs to print the remedy.
            criteria:
              - Deleting a component with two instances fails naming both; with detach it succeeds and both are plain frames
              - An override addressed to a nonexistent descendant fails listing the component's overridable nodes
          - title: Settled tree view
            ref: treeview
            desc: |
              A TreeRow model and formatter: for a document (or subtree), one row per node with id, type, name (or an unnamed marker), resolved layout rect in the parent's space, and a clip flag (partially/fully outside its parent), computed from PenLayoutEngine after variable resolution for a chosen theme; optional expansion of refs with path addresses ("SAjDU/B0M8B8/uKX6O") that resolve back through the addresser; optional property columns; depth limit; and a JSON form. This is the read that replaces most screenshots.
            blockedBy: [address]
            criteria:
              - Rows for a fixture match its known layout rects and flag a deliberately overflowing child
              - Expanded rows carry path addresses that the resolver accepts
              - Unnamed nodes are marked and named nodes are shown by name path
          - title: Activity log
            ref: activity
            desc: |
              An append-only JSONL event log at ~/.woodcase/activity.jsonl ($WOODCASE_HOME overrides the directory), one event per applied operation: timestamp, identity (PeerID name), absolute file path, op kind, node ids and name paths touched, the inverse EditOperation (from EditableDocument+Inverse), document revision after. Written by the file transaction on commit. A reader that tails it (with an offset) and filters by file and identity, for the CLI and the viewer. Rotation at a size threshold.
            blockedBy: [file, rev]
            criteria:
              - Every applied op in a batch produces exactly one event with the resulting document revision
              - The tail reader resumes from an offset without re-reading
      - title: CLI verbs
        desc: |
          Sources/WoodcaseCommand grows one command file per verb, each a thin adapter over the core: no decisions in the adapter. Conventions from the plan: --json on every read, the sleepy-style exit codes, name→id tree on every mutation, errors that name the path and the remedy, --as/$WOODCASE_AS. Tests in WoodcaseCommandTests drive the commands against fixture copies in a temp directory.
        blockedBy: [Editing core]
        children:
          - title: tree and get
            desc: |
              `woodcase tree <file> [<node>]` prints the settled tree view; --depth, --props, --json, --expand, --theme. `woodcase get <file> <node>` prints one node as .pen JSON (or expanded), with its revision. Output must be the outline of what an agent should read first; the default is rows, not JSON.
            criteria:
              - tree on a fixture prints one row per node with rect and clip flag; --json is machine-parseable
              - get prints the node's revision alongside its JSON
          - title: add, cp, set, mv, rm, override
            desc: |
              The single-op verbs. `add <parent|document> -F subtree.json` inserts a .pen subtree (generated ids, names required — an unnamed node in the subtree is a usage error that suggests naming; a root-level add without x/y is auto-placed in empty space to the right of existing roots); `set <node> key=value…` with typed value parsing (numbers, colors, $variables, fill_container, JSON for objects) and --rev; `cp <node> <parent> [key=value…]` duplicates a subtree with fresh ids (copying a reusable node makes an instance, as Pen does) and applies overrides to the copy — descendant overrides by name path resolve against the copy, never silently; `mv`, `rm --detach`, `override <instance>/<path>` with flags or a subtree. Each prints the name→id tree of what it created and appends to the activity log.
            criteria:
              - Each verb has a green test and a usage-error test whose message names the remedy
              - A root-level add without coordinates lands in empty space, not at 0,0
              - cp of a screen with a name-path override retitles the copy and leaves the original untouched
              - A stale --rev exits 3 with a conflict message naming the node
          - title: apply
            desc: |
              `woodcase apply <file> -F ops.jsonl [--atomic] [--retry report.json]` over the batch applier. The report goes to stdout as one line per op; --json emits the full report. Exit 0 if every op applied, 1 if any failed or cascaded, 3 on conflict.
            criteria:
              - A mixed batch exits 1 with per-line statuses and the file holds the applied ops
              - --retry with the previous report re-runs only the failed lines
          - title: vars
            desc: |
              `woodcase vars <file>` lists variables and theme axes; `vars set name=value [--theme mode=dark]` adds or updates (typed by value: color, number, string; themed values per axis, registering a new axis value on the fly as Pen does); `vars rm name` refuses while any node references it unless --force; `vars axis add mode=light,dark`. Over the existing variable and theme EditOperations.
            criteria:
              - Setting a themed value on a fresh axis creates the axis and both values
              - Removing a referenced variable fails naming the referencing nodes
          - title: undo
            desc: |
              `woodcase undo <file> [-n N] [--as name]` replays the inverse operations of the last N activity-log events for this file (by this identity, or any with --all) through a file transaction, appending undo events of its own. Refuses with a conflict if the file revision no longer matches the event's recorded revision — undo never guesses.
            criteria:
              - add then undo restores byte-identical file content
              - undo after another identity's later edit on the same node exits 3 and explains
          - title: lint
            desc: |
              `woodcase lint <file> [<node>]` runs the pipeline's PenDiagnosticCollector (missing fonts, broken refs, unresolved variables) plus layout checks from settled layout: text without fill, fill_container inside a fit_content parent on the same axis, fit_content with no children, a child clipped by its parent. One line per finding naming the node path; exit 1 when findings exist; --json.
            criteria:
              - Each check has a fixture that trips it and a clean fixture that does not
              - Findings name nodes by path and the settled-layout checks agree with tree's clip flag
          - title: shot
            desc: |
              `woodcase shot <file> [<node>] --out x.png --max PX --theme k=v` renders a node or the whole document through the existing pipeline (reusing ImageExporter), scaled so the longest side is at most --max (default 1600) and printing the effective scale so coordinates can be mapped back. --grid and --outline <node>… are wired once the PixelPeeper helpers land (see the vision-helpers leaf); until then they are usage errors naming that leaf.
            criteria:
              - A node shot's pixel size respects --max and the printed scale maps back to layout points
              - --theme changes the rendered colors on a themed fixture
          - title: activity
            desc: |
              `woodcase activity [--follow] [--json] [--file F] [--as name]` over the log reader. Human form is one line per event (time, identity, verb, path); --follow tails.
            criteria:
              - activity --file prints only that file's events; --follow prints a new event within a second of its write
          - title: Help that teaches
            desc: |
              `woodcase help design` (flex-first rules, naming, addressing, batch tags, the read-write-verify loop) plus each verb's --help with one worked example, all authored from the tire-kick note's rules. Error messages are reviewed against a checklist: name the node by path, say what happened, say the next command. A test asserts every EditingError maps to a message containing a remedy.
            criteria:
              - Every EditingError case renders a message that names a node path and a next step
              - help design fits in one screen and is referenced from the top-level --help
          - title: Performance budget
            desc: |
              Speed is non-optional. A benchmark test over the largest fixture (and a synthetic 5k-node document) with budgets on a release build: tree under 300 ms, a set transaction (open, apply, write) under 200 ms, shot of one artboard under 1 s warm. Measured with the existing performance/ tooling; the numbers and the command that reproduces them go in WoodcaseEditor.md.
            criteria:
              - The benchmark runs under swift test and fails when a budget is exceeded
              - The measured numbers and the reproducing command are recorded in the doc
      - title: Vision helpers in PixelPeeper
        desc: |
          Cross-repo. Add to the PixelPeeper library product (../PixelPeeper) a small overlay API: grid with labelled ticks, outlines around rectangles (default or given color), and labels, drawn onto a CGImage with a caller-supplied scale between image pixels and source coordinates. Woodcase then depends on the PixelPeeper library (a pinned GitHub revision, not a path) and wires `shot --grid/--outline` and the viewer's click-outline through it. sleepy migrates its own ShotGrid to the shared code afterwards (its own repo, its own job). This leaf is the Woodcase half: the dependency, the wiring, and a snapshot test.
        blockedBy: [shot]
        criteria:
          - shot --outline Dashboard/Header draws a box at the node's layout rect at every --max
          - shot --grid labels match layout points, not pixels, at scale 2
      - title: Viewer
        desc: |
          `woodcase serve [--port N] [<file>…]` — a local, read-only web viewer. Apple-only like render; a minimal HTTP/1.1 + SSE server on Network.framework with no dependency. Watches the given files (or every file seen in the activity log) with a DispatchSource/FSEvents watcher, re-renders changed artboards through a warm pipeline (fonts, layout cache), and pushes updates over SSE. One page: a file/artboard list (the dashboard: last change, by whom, from the activity log), the artboard image, an outline side panel from the tree view, and an activity feed. Selecting a row in the outline or clicking the image outlines that node in the render via the shared helper and shows its name path and id for handing to an agent. The JSON and SSE endpoints the page uses are the API other dashboards consume; document them.
        blockedBy: [Editing core, activity]
        children:
          - title: Viewer design prototype
            labels: [decision]
            desc: |
              A short visual design pass before any viewer HTML: the page in its states (dashboard with several files, one artboard with the outline panel and activity feed, a selected node outlined, empty state). Designed in Pen via its MCP — recording a second agent-DX note in project/ as a by-product — and rendered to PNG for review. Ben signs off on the prototype; the viewer page is built to it.
            criteria:
              - Prototype PNGs for each state are filed in project/ with the Pen file
              - Ben has signed off, recorded as a note on this leaf
              - A second DX note exists with rules for the CLI where the session found new ones
          - title: Server and file watching
            desc: |
              The HTTP/SSE server, the file watcher, the warm render cache, and the JSON endpoints (/files, /files/{id}/tree, /files/{id}/artboards/{id}.png, /events). Tests drive it in-process with URLSession.
            criteria:
              - Editing a watched file produces an SSE event and a fresh PNG within a second
              - Endpoints are documented and return JSON that matches the tree view's --json form
          - title: Viewer page
            desc: |
              The single HTML page served inline: artboard view, outline panel, activity feed, click-to-outline. No build step, no framework; plain JS over the endpoints. A SleepyHollow test (already a test dependency) loads the page, edits the file, and asserts the image updates and the outline appears.
            blockedBy: [Server and file watching, Vision helpers in PixelPeeper, Viewer design prototype]
            criteria:
              - Selecting a node in the outline shows an outline in the render and its name path
              - A file edit updates the artboard without a reload
      - title: Documentation and install
        desc: |
          DocC articles WoodcaseEditor.md (verbs, addressing, batches, revision tokens, activity log, the agent loop) and WoodcaseViewer.md (serve, endpoints); WoodcaseCLI.md gains the verb table; README gains the two doc links and the experimental-install line; AGENTS.md's docs list updated; backlog.md carries the not-now items.
        blockedBy: [CLI verbs, Viewer]
        criteria:
          - Both articles exist, build under generate-documentation, and are linked from README
          - swift package experimental-install --product woodcase produces a working binary
```
