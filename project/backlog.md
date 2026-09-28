# Backlog

Work decided against, parked rather than dropped in silence. Nothing here is scheduled or blocking — active work lives in `job`. Read it before proposing something that sounds novel; it may already have been weighed and parked.

- **One dated H2 per item:** what it is, why it's parked, and *what would un-park it*.
- **Delete an item when it lands, or when it stops being plausible.** A long list is one nobody reads.
- **Something parked that turns out to be needed becomes a task in `job`** — move it, don't work it from here.

Format: one dated H2 per entry, a headline, then what it is, why it's parked, and the trigger that would revive it.

---

## 2026-08-29 — An MCP surface in Woodcase

Penumbra's vision doc makes Penumbra the MCP host over the same core; a second one in the Woodcase CLI would duplicate it. Un-parked if agents need MCP without Penumbra running — then a thin wrapper over the `apply`/`tree`/`shot` core, not a new capability set.

## 2026-08-29 — A daemon / warm host for editing

Stateless CLI transactions over a locked file are sufficient for local agents (see the viewer-editor plan). A daemon earns its keep only if: someone holds unsaved state that must merge live; presence needs sub-second fidelity; peers are remote (Penumbra's relay is that daemon); or per-call startup on large files makes `shot` slow — in which case `serve`, which already keeps a warm cache, grows into it.

## 2026-08-29 — SQLite op-log sidecar

The activity log is JSONL per user. A SQLite sidecar per file becomes worth it if the log needs queries beyond tail-and-filter, or if the CRDT op log needs durable local persistence for offline peers.

## 2026-08-29 — Native viewer app

`woodcase serve` covers the artboard view and the dashboard in one page. A native SwiftUI viewer (SPM executable, or an .app for file-type association — which Penumbra already claims) is worth it only if latency or zoom quality in the browser falls short.

## 2026-08-29 — Homebrew tap

`swift package experimental-install` is the install for now. A tap with a build-from-source formula once the binary name and verbs settle.

## 2026-08-29 — `woodcase diff`

`NodeDiffer` exists in CodeGen and could print a node-level diff of two .pen files. Parked because canonical, sorted-key JSON already diffs well in git. Un-parked if agents or reviewers need semantic diffs (moved subtrees, changed overrides) that a text diff obscures.

## 2026-08-29 — Image-asset import in the editor

`add` with an image fill just references a path. Parked until a workflow needs assets copied or embedded alongside the .pen (the `.wood` bundle question from the editing-architecture doc).

## 2026-08-29 — `woodcase shot --watch` (preview PNG rewritten on every change)

The `pen` CLI's `--enable-preview` writes `~/.pencil/latest-preview.png` after each
change, which is a viewer for agents without a browser. `serve` covers the human case;
a `--watch` on `shot` (re-render on file change, same watcher as `serve`) is a ten-line
adapter once the server leaf's watcher exists. Un-park when an agent workflow actually
wants a PNG instead of `tree` — the tire-kick note says structural reads beat pixels.

## 2026-08-29 — A whole-kind type swap does not converge through the CRDT

Found by the setProperties agent (leaf SjgDk): `PropertyDiff.diffKind` emits
`"kind.type"` for an `updateKind` that changes a node's type, but no codec can apply
it — the receiving peer still holds the old kind, so every `kind.*` write from the
swap is dropped too, and two peers can permanently disagree about a node's type.
Pre-existing; `updateKind`'s territory. Un-park when Penumbra's live sessions
actually change node types (today its editing surface doesn't), and fix it by
replicating a type change as a `CreateNode`-style whole-node write rather than
per-path LWW.

## 2026-08-29 — Fold `themes` into `vars` and retire the verb

`woodcase vars` prints everything `woodcase themes` does — the axes block is a strict
subset of its output — so the two now say the same thing in two places, and a reader
has to learn which. Parked because retiring a verb is a surface change beyond the leaf
that noticed it (vAEwr), and `themes` predates the editing verbs, so something outside
this repo may already call it. Un-park when the verb set is next reviewed as a whole,
or the first time the two outputs disagree; the change is to delete `ThemesCommand` and
`ThemeFormatter` and point `themes` at `vars`, keeping the name as an alias only if
something is found to depend on it.

## 2026-08-29 — `--library` on the read verbs

`render` resolves library imports with `--library`; `tree`, `get`, `lint` and `shot` do
not. A document whose components live in an imported library therefore reads as if
every instance were broken — `lint banking.pen` reports 5 `broken-ref` findings that
are really unresolved imports, and `tree` shows those instances with a zero rect.
Parked because the import resolver needs a library *set* threaded through
`PenFileTransaction`, which every read verb shares, and no agent workflow has yet asked
for it. Un-park the first time someone lints or reads a real library-based document and
has to be told the errors are not real — then add `--library` to the shared read path
once, not per verb.

> **Un-park condition met, 2026-09-26 (leaf `koyac9`).** The docs re-capture linted `banking.pen` and had to be
> told its 5 `broken-ref` and 19 `override-target-not-found` errors were imports. Two corrections to the premise
> above: `render --library` does not work either — `LibraryResolver` keys each library by its file name without
> extension (`kit.lib`) while `PenImportResolver` looks it up by the import path as written (`kit.lib.pen`), so the
> import is silently skipped and the PNG is byte-identical with and without the flag — and the document already
> names its libraries in `imports`, relative to itself, so a flag may not be needed at all. The design is waiting
> on a ruling; see the note on `koyac9`.

> **Un-parked and built, 2026-09-26 (leaves `koyac9`, `ukfIU2`).** Ruling (Ben): no flag. Every read loads the
> libraries the document's own `imports` name, relative to the file, once, in `PenFileTransaction`, as
> non-persisted read context on `EditableDocument` (`PenReadContext`); `tree`, `lint`, `shot`, `render`,
> `generate`, the viewer and scripts all expand through `EditableDocument.expanded(for:)`. `--library` and
> `LibraryResolver` are retired. Resolution mirrors Pen — sibling only, one level, `pencil:` is Pen's bundled
> set — see [the finding](2026-09-26-pen-import-resolution.md). Nothing about this entry is parked any more;
> it stays as the record of why the read path changed.

## 2026-08-29 — A revision on `lint --json`

Every other read hands back the document revision, so a caller can lint, decide, and
write with `--rev` in one handshake. `lint --json` prints a bare array of findings and
no revision, so that caller has to run `tree --json` as well. Parked because the fix
changes the JSON shape from an array to an object — a breaking change to an output
nothing consumes yet — and there is no consumer to break. Un-park when the viewer or
an agent loop actually chains lint into a guarded write; wrap the array as
`{"findings":[…],"revision":"…"}` then, in one go, rather than adding a sibling field
later.

## 2026-08-29 — An `undoes` link on undo events

`woodcase undo` carries exactly one heuristic: once its backwards scan has passed an
`undo` event, a candidate whose revision does not match is *assumed* to be one that
undo already reversed, and is stepped over rather than treated as a conflict. The cost
is that on a file that has ever been undone, tampering from outside the log surfaces as
"nothing left to undo" (exit 1) instead of a stale conflict (exit 3). The precise fix
is a new `ActivityEvent` field linking an undo event to the event it reversed, which
makes the scan exact and deletes the latch. Parked because it is a wire-format addition
to the log, and the log's field names are a contract other tools read. Un-park when the
log format is next revised for another reason, or when a real workflow is misled by the
imprecise message.

## 2026-08-30 — Addressing an instance's *root* as an override target

`EditableDocument.overridableDescendantKeys(ofComponent:)` includes the component root
itself (`"CardC"`), because Pen's patcher matches it like any other node — so
`EditingError.overrideTargetNotFound` can print a candidate id, `Card1/CardC`, that
`resolve` refuses. Resolving it would give an instance root two addresses that store an
edit in different places (`Card1` writes the ref node, `Card1/CardC` writes a
`descendants` entry), and Pen already has `rootOverrides` for that job. Parked because
no read prints `Card1/CardC` as a row address and no workflow has asked to override an
instance root; the addressing fix of 2026-08-30 deliberately stops the deep id-step at
the component root's *children*. Un-park when `override` grows a way to write
`rootOverrides` — decide then whether the root's address is `Card1` with a flag or
`Card1/<component id>`, and make the candidate list and `resolve` agree either way.

## 2026-08-30 — Pre-warming the dashboard's file-card thumbnails

`RenderCache.warm` renders every artboard at the default 1600-pixel cap; the dashboard's
file cards ask for their cover at 480, which is a different cache key, so the root page's
*first* paint renders one small image per file on demand. Warming that cover alongside
the full-size artboards was implemented and then removed: with it, `swift test` failed
`ViewerBrowserTests.selectionScrollsTheOutlineToItsRow` on its fresh-load leg in 2 of 2
full runs, and passed 3065/3065 without it (`swift test --quiet`, this worktree,
2026-08-30) — one extra render per file per change holds the `RenderCache` actor long
enough to delay a page that is waiting on it. The cheap half of the pipeline is all a
cold thumbnail costs, because `prepare` is already warm, so the on-demand path is not
slow; it is only not instant. Un-park when `RenderCache` grows a way to run warming
behind foreground requests rather than in front of them — a second, lower-priority lane,
or yielding between renders — at which point the same measurement is the acceptance test.

## 2026-08-31 — Repointing a `ref` more than one instance deep

An instance can repoint a `ref` in its *own* component (`override Sht01/Tab01 ref=CurC`),
and as of leaf SWr75 that settles, addresses and round-trips correctly. A `descendants`
key with a `/` in it — `Tab01/Inner`, naming a ref one level further down — cannot: the
expander applies simple keys before it recurses and slash keys *after*, by which point
the inner `ref` has already been replaced by its component, so writing `ref` there is a
silent no-op. It is not corrupting (the merged key decodes away against the expanded
node's own `type`), just ineffective, and no design has asked for it yet — every variant
in the mobile-viewer kit is one level deep. Making it work means distributing cross-ref
overrides down into each nested ref's own `descendants` map *before* recursion instead of
patching prefixed ids afterwards, which changes `PenRefExpander` for every existing file
and every React golden; refusing it instead needs a new `EditingError` case and a message
in `Sources/Woodcase/Batch/`. Un-park when a real design needs a two-deep variant, or when
the expander is being reworked for another reason — then do the distribution, because it
is the version the format's own key grammar implies.

## 2026-08-31 — Routing CLI writes through the CRDT layer (merge-and-report)

The guards-and-echo design left open whether CLI writes should route through
`EditableDocument.applyLocal` so a batch composed against a stale read merges over
intervening history instead of failing or path-resolving. Spike aPPZS answered no-go
for now (full note with file/symbol references on that leaf, 2026-08-31): the seam
itself is one call site (`ActivityRecorder.apply` → `apply(_:expecting:)`, with
`applyLocal(_:expecting:)` its existing twin that degrades to `apply` on a non-replica),
but routing today would be a net regression — 45% of the four-writer run's traffic was
`override`, and the CRDT layer stores an instance's whole `kind.descendants` map as one
LWW register (`PropertyDiff.swift`), so concurrent overrides of *different* descendants
silently lose one side; there is also no CRDT-side rollback for a half-applied batch
line (`OperationLog` only truncates by consensus), and persisting the sidecar doubles
every write with a snapshot rewrite that scales with document size. The merge also buys
less than assumed: the CLI grammar is name-addressed and resolves at line-apply time,
so only id-addressed batches would merge. Un-park when a second concurrent writer that
is *not* a CLI process exists (Penumbra live editing, a viewer session) — and land the
two prerequisites first: per-descendant override registers
(`kind.descendants.<id>.<prop>`), and CRDT-side rollback (a retract on `OperationLog`,
or plan-then-commit logging). The concurrent-override clobber, which Penumbra's day-one
multiplayer hits regardless of routing, is its own entry below (it was issue `jrDh3`;
backlogged 2026-08-31 on Ben's call).

Standing constraint from Ben (2026-08-31), binding on whatever un-parks this: **no two
competing concurrent-editing models.** One source of truth (the .pen file plus its
activity log) and one write contract (changes land through the file lock and are
logged); a CRDT replica is an access pattern on top of that contract — it saves through
the lock and reconciles foreign activity events into itself before writing — never a
parallel authority beside it. Guards stay defined on content hashes (pure state), which
mean the same thing to a stateless CLI transaction and a live replica. The door this
closes: Penumbra saving its replica to disk without taking the lock and ingesting the
log first.

## 2026-08-31 — Per-descendant CRDT override registers (the concurrent-override clobber)

`CRDTDocument.processLocalOverrideDescendant`
(`Sources/Woodcase/Sync/CRDTDocument+LocalProcessing.swift`) merges an override into the
ref's `descendants` map and diffs the whole map to the single path `kind.descendants`
(`PropertyDiff.swift`) — one LWW register. Two peers concurrently overriding *different*
descendants of the same instance therefore don't merge: the later timestamp wins the
entire map and the earlier peer's overrides vanish silently. Found by spike aPPZS
(2026-08-31) and verified in source; overrides were 45% of the four-writer run's traffic,
so this is the common case, not a corner. The existing
`CRDTOverrideConvergenceTests.concurrentOverridesLWW` asserts only convergence, not
survival — no test covers two different descendants. Fix direction from the spike:
per-descendant property paths (`kind.descendants.<id>.<prop>`) so each descendant
override gets its own register; concurrent writes to the same descendant+property stay
LWW. TDD: start red with peer A overriding Tab01 and peer B overriding Tab02 on one
instance concurrently, exchange ops, assert BOTH survive on both peers. Parked because
nothing exercises the CRDT layer concurrently today — the CLI is a stateless
single-writer through the file lock. **Un-park when Penumbra's live editing (or any
second live replica) starts up** — it hits this on day one, and it is also the first of
the two prerequisites the CLI-routing entry above names. Was tracked as issue `jrDh3`;
canceled to the backlog 2026-08-31 on Ben's call, full history on that task.

## 2026-09-02 — Parked from the Quill DX round

Decided against in [teach the CLI what it does](2026-09-02-teach-the-cli-what-it-does.md);
one line each, with what would revive it.

- **`cp --rename-prefix old=new`.** Asked by both editing agents to escape `duplicate-name`
  on a deep copy. Dissolves once the check is sibling-scoped, since a copy's descendants are
  never siblings of the originals. Un-park if agents still ask after that lands.
- **`woodcase measure`.** Three agents built a ruler `.pen` because `tree`'s text widths were
  measured in the fallback face. Un-park if agents still build rulers after `tree` prepares
  fonts and reports absolute rects.
- **`set --match <selector>`.** A second address grammar; one agent said explicitly it did not
  want one. `cp --each` and `apply` cover the bulk cases. Un-park on a third independent ask.
- **`arrange` / `pack`.** `mv` plus a `set common.x` batch does it and layout settles once.
  Un-park if a re-space batch proves unsafe under a concurrent writer.
- **~~`find` / `query`~~ — un-parked 2026-09-07, and shipped.** Parked as "`tree --json
  --absolute` through `jq`". What un-parked it was not speed: it was
  [the scripting host](2026-09-07-scripting-host.md), which gives a predicate somewhere to
  run without inventing a selector grammar. `woodcase find <file> [<address>] <predicate>`
  takes a JavaScript arrow function over `tree`'s own rows and prints the ones it keeps in
  `tree`'s own bytes. The jq route is unchanged and still the answer for reshaping a report;
  `find` is the answer for asking one question and branching on it.
- **A parameter language beyond `_props`.** The format carries nothing for it; `_props` in
  `common.metadata` is the declaration and now serves the editing verbs too. Un-park if Pen
  adds component properties to the format.
- **Format asks: dashed strokes, rich text runs, document-level style defaults.** `dashPattern`
  was deliberately dropped in the 2.17 migration; the dotted-rule pain was a symptom of the
  font bug. Un-park only if Pen re-adds them.
- **Exempting an instance from `duplicate-name` when named as its definition.** Moot under the
  sibling scope.
- **A `shot` default-scale change for tall boards.** `pixels=` is printed on every run and
  `--crop` is the tiling primitive; the default stays a longest-edge cap of 1600.

## 2026-09-02 — Per-field `_props`, so two props can read one descendant

Today a prop's type is inferred from the node its path names (`ComponentAnalyzer.inferPropType(from:)`), so two `_props` entries on one descendant always read the same field and are always ambiguous; `lint` reports the pair under `codegen-prop-path` and `PropMapper` keeps the first by name (commit e4683c7). The lookup is already one-to-many, so a `label` reading a text node's content and a `tint` reading its fill is one declaration change away: let a `_props` value carry the property suffix `get` already prints in its resolved form (`Body/Title/kind.fills`), and infer the type from the field rather than the node. Parked because it is a feature, not a fix: it changes a declaration Pen files carry and nobody has needed it. Un-park when a real component needs two readings of one node.

## 2026-09-08 — Retiring the verb-side loop surfaces (`cp --each`, `apply`) now that `js` exists

The scripting host plan left open whether `cp --each` or `apply` would go unused once `js` and `find` shipped, and whether the primer would be simpler without them (leaf `W9MdJV`). Ben ruled to keep every surface, and the reason is not agent preference at all: `apply` and `cp --each` can be built into shell scripts and workflows that do not want to involve JavaScript — a JSONL file a pipeline emits, a Makefile step, a CI job. They are the tool's wire form for *other programs*; `js` is for a program that runs inside the transaction. An agent choosing `js` for everything is an acceptable finding and a validation of the host; an agent choosing `cp --each` shows it understands the primitives. Evidence so far is [the round-one trial](2026-09-08-scripting-host-trial.md), where one agent declined `cp --each` for a stated reason on a task with a measurement in it. **What would revive it:** several trials in which agents given a pure fan-out or a fixed edit list still reach for `js` *and* report the verb-side routes as confusing rather than merely unused — a primer-complexity cost, not just idle surface.

## 2026-09-26 — A Linux build of Woodcase

Woodcase does not build on Linux (leaf `cAUDcr`, canceled into this entry): `Models/PenRect.swift` imports CoreGraphics for `cgRect`, and about 30 `Rendering/` files import CoreGraphics unconditionally. The SwiftUI emitter also calls a few statics that live in CoreText files. The fix is to fence the CG renderer behind `canImport(CoreGraphics)`, or split it into its own target, and move `cgRect` into a Rendering extension. Then prove it with a Linux build (a Docker Swift image or CI). Parked by Ben: Linux is not a priority right now, and the work touches most of `Rendering/` while other leaves are editing it. Until it lands, the "cross-platform library" claim in the Swift rules is aspirational for this repo, and new code should still avoid adding CoreGraphics outside `Rendering/`. **What would revive it:** a Linux consumer (a server-side renderer, CI on Linux, or a request to run the SwiftUI goldens there), or a quiet stretch in `Rendering/` that makes the fencing cheap.

## 2026-09-27 — Running shader fills and script nodes

Pen runs a shader fill (GLSL ES 1.00 with `@resolution`, `@time`, `@sdf`, `@backdrop` and image samplers) and a script node's JavaScript, headless and deterministically; every Woodcase target draws both as nothing (MAE 11.7–159 on `render-shader-fills.pen`, 30.6 on `render-script-node.pen`). [The fidelity-gaps inventory](2026-09-27-fidelity-gaps.md) (F1, F2, D1, D2) costs the options: a CPU GLSL evaluator for CG (L), live WebGL in React (M), a baked raster in SwiftUI, and expanding script nodes through `WoodcaseScripting`. Leaves `LqkHEF`, `Rk5xQw` and `OQnc7Z` were canceled into this entry. Parked by Ben ("ignore shaders and scripts for now"); what stays is phase 1, a warning wherever Woodcase does not draw a shader (leaf `dYIzYU`). The fixtures and their Pen exports are committed, so the work can start from measurements. **What would revive it:** real documents that use shaders or scripts, or a consumer (Penumbra, RapidPro) that has to show them.

## 2026-09-28 — Chasing the last sub-point text differences between React and Pen

Three residuals are left after leaf `BpaSrF` put React's first baseline on Pen's whole point: `layout-text-chips` drifts about 2 pt left over a row of four auto-width chips (React 2.64, CG 0.75), which fits Pen rounding each auto-width label's width up to a whole point where CSS keeps it fractional; the baseline correction covers top-aligned text only, and an explicit `lineHeight` pitch stays unrounded in CSS; React and SwiftUI give a squeezed `fill_container` 0 pt where the engine and Pen give 1 (`minimumFillMain`). Ben looked at the chips board side by side (2026-09-28) and ruled it "tiny": past this point the work is chasing one text engine's rounding against another's, case by case. The likely fixes are small (a whole-point width on auto-width labels, the same margin pair for middle and bottom alignment, a 1 pt minimum on emitted fills), each needing a `pen-oracle` probe to confirm Pen's rule first. **What would revive it:** a real design where the drift is visible — a long row of chips or tabs, a dense table — or a user report of text misaligning against Pen.
