# How deep a debug build can read a document (2026-09-26)

> **Updated 2026-09-26 (leaf `7y53C0`):** the rest of the read pipeline no longer recurses
> either. A debug `woodcase tree` now lists a frame tree 200 deep (255, the most JSON
> nesting lets a file hold) and 64 nested instances, exit 0 — and so does release, which
> overflowed exactly where debug did. See [the rest of the pipeline](#the-rest-of-the-pipeline-leaf-7y53c0).
>
> **Updated 2026-10-17 (leaf `a1p6vh`):** comparing, hashing, encoding, freeing and
> inserting a tree no longer recurse either. Penumbra's Debug app had crashed comparing an
> eight-level mockup: synthesized `==` took 563 KB of stack on it. See
> [the node's own walks](#the-nodes-own-walks-leaf-a1p6vh-2026-10-17).

Author: Claude (Opus), leaf `PJwhm2`. Found by `ILYyZi`: `woodcase tree` (debug) on an
instance of `Scr03 → Mid01 → Scr01 → Ins0A → InsB` exited 138 with no output — "Thread
stack size exceeded" on a cooperative-pool thread (512 KiB), inside `PenRefExpander`.

## The cause

A debug build gives every value temporary its own stack slot, and a `PenNode` was
**1256 bytes** — its `Kind` enum inline was 992, the size of its largest payload
(`FrameData`). Every walk over the tree was recursive, a few frames per level, and each
frame held several nodes, kinds and payloads. `scripts/stack-frames` (new; reads the
prologue of every matching function in a binary) measured, on the debug `woodcase`:

| Function | Stack reserved per call |
|---|---|
| `PenNode.init(from:)` | 38,608 |
| `PenRefExpander.prepareInstance` | 34,592 |
| `PenLayoutEngine.layoutFlexContainer` | 33,584 |
| `TreeView.walk` | 28,880 |
| `PenVariableResolver.resolveKind` | 23,664 |
| `PenRefExpander.mapChildren` / `PenNodePatcher.mapChildren` | 14,208 each |
| `PenNodePatcher.applyOverrides` | 12,032 |

```
scripts/stack-frames .build/debug/woodcase 'PenRefExpander|PenNodePatcher|^PenNode\.init' --top 20
```

So the expander overflowed about eight tree levels deep (four nested instances), and the
**parser** about twelve: a plain frame tree 25 deep crashed `woodcase tree` too, before
any instance was involved. Under `lldb` the command ran on the 8 MiB main thread and
passed, which hid it.

## What changed

- **`PenNode.Kind` is `indirect`.** A node is 272 bytes, a kind 8. This shrinks every
  recursive walk over nodes, not only the expander's: `PenNode.init(from:)` fell to
  2,080 bytes, `layoutFlexContainer` to 11,904, `TreeView.walk` to 7,440.
- **`PenNode`'s Codable dispatches each payload in a generic helper**
  (`PenNode+KindCoding.swift`), so one frame no longer reserves a slot for all sixteen
  payload types.
- **The expander does not recurse.** `PenTreeRewrite` rewrites a tree top-down from an
  explicit work list; expansion, `prefixIDs`, `PenNodePatcher.applyOverrides`, slot-content
  patching and the override hand-down all use it, and `buildRegistry` and the
  `PenOverrideKeyResolver` builder walk work lists of their own. Definitions are stripped
  in the same pass, so no expanded tree is built only to be freed.

Measured with `StackHighWater` (tests; paints a thread's stack and reports how much the
work overwrote), debug, `swift test --filter PenRefExpanderStackTests`:

| Expansion | Before | After |
|---|---|---|
| 16 nested instances, 6 frames each (108 levels) | 3,922,456 B | 99,864 B |
| a plain frame tree 200 deep | 6,531,552 B | 21,760 B |
| 8 vs 32 nested instances | — | 98,200 B vs 99,864 B |

The expansion's stack use no longer grows with the tree; the ~100 KB is the fixed cost of
one instance's preparation (JSON round trips in the patcher, the resolver). Freeing a
tree still recurses — Swift has no hook to stop it — at roughly 800 bytes a level in
debug, so a caller that drops a 600-level tree on a task thread would still overflow.

`woodcase tree` end to end, debug — the documents `TreeDeepNestingTests` generates, at
other depths, run as `.build/debug/woodcase tree <file>` (frames) and
`.build/debug/woodcase tree <file> Top --expand` (instances); exit status:

| Document | Before | After |
|---|---|---|
| frame tree 25 deep | 138 | 0 |
| frame tree 30 / 35 deep | 138 / 138 | 0 / 138 |
| 12 nested instances, 1 frame each | 138 | 0 |
| 14 / 16 nested instances, 1 frame each | 138 / 138 | 0 / 138 |

## What still limits a deep document

> **Updated 2026-09-26 (leaf `7y53C0`):** all three are fixed, and the list was
> incomplete: flattening into the editable store, materializing it back, font-family
> collection, the revision fold, `SettledTree`'s index and the absolute-rect walk recursed
> too, and font collection (7 KB a level) is what killed the verb once the others were
> gone — it only runs when the document has a font resolver, so no in-memory test saw it.
> See below.

The expander is done; the rest of the verb's pipeline is not, and each of these is a
recursive walk with a large debug frame. In order of the depth at which they fail:

1. **Parsing.** `FrameData`'s synthesized `init(from:)` reserves 7,648 bytes and sits on
   the stack for every level while its `children` decode — a frame tree ~35 deep.
2. **Variable resolution.** `PenVariableResolver.resolveNodeWithInheritedTheme` /
   `resolveKindWithInheritedTheme` recurse per level (8,128 + 3,056 bytes and closures);
   the deeper nested-instance documents above now fail here.
3. **Layout and the tree walk.** `PenLayoutEngine.layoutFlexContainer` (11,904) and
   `layoutSubtreeImpl` (6,960) recurse through flex containers; `TreeView.walk` (7,440).

`PenTreeRewrite` fits the variable resolver directly (the inherited theme is the
context). Layout is recursive by nature and would need an explicit post-order. Neither
was in this leaf's brief, and the variable resolver is contended; both are filed for a
follow-up rather than done here.

## The rest of the pipeline (leaf `7y53C0`)

Author: Claude (Opus), leaf `7y53C0`, 2026-09-26.

Every walk `woodcase tree` makes now runs from a work list on the heap. Per stage:

| Stage | Was | Now |
|---|---|---|
| Parsing | `PenNode.init(from:)` → payload's synthesized decoder → `[PenNode]` → … | Each node decodes **shallow**: a frame's or group's payload gets a `ChildDeferringDecoder`, which answers `[]` for `children` and sets the array's decoder aside; `PenNode.decodedTree(from:)` walks those arrays from a stack. `FrameData`'s own `Codable` is untouched. |
| Flattening, materializing | `flattenNode`, nested `materializeNode` | work lists (`EditableDocument.flatten`, `materializeNodes`) |
| Variable resolution | `resolveNodeWithInheritedTheme` ↔ `resolveKindWithInheritedTheme` | `PenTreeRewrite`, the inherited theme as the context |
| Font collection | `collectFontFamilies(from:into:)` | work list |
| Layout | `layoutNode` ↔ `layoutFlexContainer` / `layoutAbsoluteContainer` | a resumable state machine per container (`AbsoluteLayout`, `FlexLayout`: measuring → filling → arranging → absolute children) on an explicit stack of `LayoutFrame`s; scratch maps are indexed stores; every measurement and rect write happens in the recursive order |
| Revisions | `foldedRevision` | `RevisionFold` frames; each node is still finished and memoized before its next sibling starts |
| Listing | `TreeView.walk` | pre-order work list of `Visit`s |
| Settled index, absolute rects | recursive | work lists |

No stage runs on a bigger thread: every walk here is ours, and a work list was always
possible, so no concurrency seam was needed.

### Measured

`StackHighWater`, debug, `swift test --filter TreePipelineStackTests` (bytes of stack; the
"before" column is `main` at `936a89d` with the new tests, the "after" this leaf). The
documents are `DeepDocuments.frameTree(depth: 200)` and
`DeepDocuments.nestedInstances(depth: 32, frames: 1)`.

| Stage (test) | Frame tree 200: before → after | 32 nested instances: before → after |
|---|---|---|
| Parse (`parsing`) | 3,137,824 → 121,600 | 60,912 → 39,040 |
| Flatten into the store (`flattening`) | 759,184 → 10,992 | 17,232 → 10,992 |
| Expand an editable document (`expanding`) | 825,520¹ → 154,200 | 99,800 → 99,800 |
| Resolve variables (`resolving`) | 2,616,944 → 47,472 | 883,488 → 47,472 |
| Collect font families (`collectingFonts`) | 1,417,184 → 8,056 | 461,344 → 8,056 |
| Lay out (`layingOut`) | 3,355,232 → 54,920 | 1,096,744 → 67,320 |
| Settle — expand, resolve, lay out, index (`settling`) | 3,355,712 → 154,560 | 1,097,224 → 99,896 |
| List, revisions included (`listing`) | 1,506,888 → 43,104 | 551,768 → 71,704 |
| Whole read, parse to rows (`wholeRead`) | 3,372,960 → 155,488 | 1,098,104 → 100,776 |

¹ Measured with only materialization reverted to its recursive form.

What is left is not a walk of ours:

- **Freeing a tree** — compiler-written, one call per level, about 770 bytes a level in
  debug: 154,560 bytes to free the 200-deep parsed tree. It is the deepest point of
  expanding (which frees the materialized tree), settling and the whole read, so those
  tests get half a task's stack; the walks get a quarter.

  > **Fixed 2026-10-17 (leaf `a1p6vh`):** a container's kind now lives in a class whose
  > `deinit` takes the subtree apart from a work list; freeing a 5,000-deep chain uses
  > under 6 KB. "No hook to stop it" was true of the struct, not of the tree.
- **Foundation's JSON scanner** — 118,192 of the parse's 121,600 bytes: a
  `JSONDecoder` decode of `{version}` alone from the same bytes, measured the same way.
- **JSON nesting** — Foundation refuses input nested past 512 arrays and objects, so a
  file cannot hold a frame tree deeper than 255: `woodcase tree` exits 4 ("not valid
  JSON") at 256.

Deeper *expanded* trees are possible — nested instances multiply depth — and one about
650 levels deep would still overflow on being freed. Nothing in the read walks it
recursively any more.

The walks now cost a fixed frame each, whatever the depth — the largest in debug are the
layout driver's `layoutNode` (22,192 bytes) and `begin` (21,040), `FlexLayout.advance`
(13,376) and `PenNode.decodedTree` (10,112):
`scripts/stack-frames .build/debug/woodcase 'decodedTree|FlexLayout|PenLayoutEngine\.(layoutNode|begin)' --top 10`.

Outside the read path, recursion remains and was not audited: `EditableDocument.flattenAndInsert`
(3,632 bytes a level, the edit path's insert), synthesized `Equatable` on nodes (release
`FrameData.__derived_struct_equals` is 4,560), encoding a deep subtree (the write path and
the patcher's JSON round trips), and CodeGen's own tree walks.

> **Updated 2026-10-17 (leaf `a1p6vh`):** all but CodeGen are fixed, and the list missed
> two more on the insert path — `validateNoDuplicateIDs` and `collectInsertedIDs`. The
> per-level costs above understated equality: synthesized `==` is five frames a level,
> about 68 KB in debug and 8 KB in release. See
> [the node's own walks](#the-nodes-own-walks-leaf-a1p6vh-2026-10-17).

### `woodcase tree`, end to end

Exit status of `woodcase tree <file>` (frames) and `woodcase tree <file> Top --expand`
(instances, one frame per component), on documents from `scripts/deep-pen frames <n>` and
`scripts/deep-pen instances <n>` — the ones `TreeDeepNestingTests` generates. Before is
`936a89d`; debug built with `swift build --product woodcase`, release with
`swift build -c release --product woodcase`.

| Document | Debug before | Release before | Debug after | Release after |
|---|---|---|---|---|
| frame tree 30 / 35 | 0 / 138 | 0 / 138 | 0 / 0 | 0 / 0 |
| frame tree 50 / 100 / 200 | 138 / 138 / 138 | 138 / 138 / 138 | 0 / 0 / 0 | 0 / 0 / 0 |
| frame tree 255 / 256 | — | — | 0 / 4 | 0 / 4 |
| 14 / 16 nested instances | 0 / 138 | 0 / 0 | 0 / 0 | 0 / 0 |
| 24 / 32 / 64 nested instances | 138 / 138 / 138 | 0 / 0 / 138 | 0 / 0 / 0 | 0 / 0 / 0 |

**Release was not fine.** It overflowed on the same frame tree as debug, in the parser —
the crash report's stack is `PenNode.init(from:)` → `specialized PenNode.Kind.decoding` →
`JSONDecoderImpl` over and over. In release `specialized static PenNode.Kind.decoding(_:from:)`
reserves 7,776 bytes and `specialized PenNode.FrameData.init(from:)` 5,280
(`scripts/stack-frames .build/release/woodcase 'PenNode|FrameData' --top 20` on `936a89d`),
so the generic-helper split of leaf `PJwhm2` does not survive optimization. The flat decode
takes both off the per-level path.


## The node's own walks (leaf `a1p6vh`, 2026-10-17)

Author: Claude (Opus), leaf `a1p6vh`. Found by Ben: unchecking a drop shadow on a
top-level frame of the settings mockup (Penumbra `project/mockups/2026-10-17-settings`,
eight levels deep, now `Tests/WoodcaseTests/Fixtures/settings-mockup.pen`) crashed the
Debug app — "Thread stack size exceeded" in synthesized `PenNode ==`, called from
Penumbra's `IncrementalExpansion.changedRoots`. Synthesized `==` was five frames a level;
on that mockup alone it reached **563,368 bytes** of stack in debug, past a task's 512 KiB.

### What changed

- **`==` and `hash(into:)`** (`PenNode+Equatable.swift`) compare and hash each node
  shallow, then its children, from a work list of sibling arrays. A childless kind goes
  to its synthesized `==`; a container's payload has `children` taken out of a copy and
  the copy goes to the payload's synthesized `==`/`hash`, so no payload field is named
  and none can be forgotten. `PenNode`'s own four properties are named; a layout test in
  `PenNodeEqualityTests` fails if a fifth appears. Two shortcuts with `Array`'s own
  semantics: two containers sharing storage, or two childless kinds sharing an
  `indirect` box, are equal without reading further.
- **Freeing** (`PenNode+KindStorage.swift`): a node whose kind holds children keeps it in
  a `SubtreeOwner` class, whose `deinit` moves each uniquely held child's children onto a
  work list before the child is released. A childless node keeps its kind inline.
- **Encoding** (`PenNode+TreeEncoding.swift`): each node is encoded shallow and its
  `children` array is filled from a work list through `superEncoder()`, mirroring
  `decodedTree(from:)`. The wire format is unchanged (`PenNodeTreeEncodingTests`).
- **Inserting**: `flattenAndInsert`, `collectInsertedIDs` and `validateNoDuplicateIDs`
  use work lists; insert now shares `flattenSubtree(_:parentID:)` with `init(from:)`.
- `PenNodePatcher` also lifts a node's children when the patch replaces them, so the
  overlay never reads, and the round trip never encodes, a subtree it is about to drop.

### Measured: stack

`StackHighWater` bytes, `swift test --filter PenNodeTreeCostProbe` with
`WOODCASE_TREE_COST_PROBE=1` (debug), and the same with
`-c release -Xswiftc -enable-testing` (release). "Before" is `main` at `74ed6066`, run
before this leaf's source changes (debug 13:16, release 13:45); "after" this leaf.
*chain* is a 255-frame chain, *mockup-shaped* the mockup's first board nested 245 times
(253 deep, ~10,800 nodes, unique ids) — both `DeepDocuments+InMemory.swift`.
`PenNodeDeepTreeStackTests` holds each to a quarter of a task's stack (encoding: half).

| Walk | Debug before → after | Release before → after |
|---|---|---|
| `==`, settings mockup (8 deep) | 563,368 → 85,128 | 68,384 → 16,496 |
| `==`, chain / mockup-shaped | 17,554,624 / 17,431,128 → 70,928 / 85,128 | 2,122,928 / 2,106,784 → 14,848 / 16,496 |
| hash, chain / mockup-shaped | 8,519,080 / 8,457,152 → 35,096 / 39,984 | 1,110,096 / 1,102,336 → 7,536 / 8,912 |
| encode to JSON, chain / mockup-shaped | 2,934,672 / 2,912,792 → 234,560 / 232,784 | 1,851,600 / 1,842,800 → 234,224 / 232,448 |
| free, chain 255 | 196,384 → 5,840 | 151,160 → 2,368 |
| free, chain 5,000 (`freeingFarDeeperThanAFile`) | 3,840,496 → passes (< 131,072) | 2,960,208 → passes |
| insert, chain | 1,076,416 → 42,480 | 707,432 → 10,336 |

What is left is Foundation's: an encode's ~230 KB at 255 levels is `JSONEncoder` turning
its value tree into text, recursively, about 460 bytes per level of JSON nesting (two per
tree level), the same in debug and release. An encode of the same nesting through nested
containers alone, with no `PenNode` in it, used more (317,088 bytes at 255, debug; a
throwaway test, not kept).

### Measured: time

Medians of 9 runs, milliseconds, same probe. Times on this shared machine move with load,
so each row says when. **Release, fair A/B** — `main` and this leaf built side by side
and run interleaved twice (15:12–15:13, load ~6), with an earlier cut of this leaf
(payload shells compared field by field, no kind-box shortcut; the shipped version was
faster in debug and, in an earlier interleaved run, equal in release within noise):

| Walk | Release before | Release after |
|---|---|---|
| `==` settings mockup | 0.129 / 0.142 | 0.177 / 0.165 |
| `==` woodcase-app | 0.317 / 0.325 | 0.385 / 0.375 |
| `==` synthetic 5,000 nodes | 2.14 / 2.13 | 2.83 / 2.81 |
| `==` chain 255 | 0.089 / 0.088 | 0.108 / 0.105 |
| hash synthetic 5,000 | 1.82 / 1.81 | 2.08 / 2.05 |
| encode synthetic 5,000 | 40.0 / 39.8 | 39.9 / 39.3 |
| free synthetic 5,000 | 0.459 / 0.450 | 0.716 / 0.716 |
| insert mockup-shaped | 39.5 / 40.6 | 24.8 / 23.5 |

So on two trees that share **no** storage — separately parsed — the work-list `==` is
about a quarter slower than the synthesized one, and freeing about half again as long
(0.26 ms more per 5,000 nodes). That is not the case Penumbra pays for: it compares two
materializations of one flat store, which share every childless node's `indirect` box,
and there the kind-box shortcut skips the payloads. In the final release run (16:49, load
~12, so every figure is inflated): settings mockup materialized twice 0.169 ms against
0.329 ms parsed twice; woodcase-app 0.165 against 0.608. `main` was not measured on the
materialized pair; it has no such shortcut, so it pays the parsed-twice cost.

Debug, the final build (16:26–16:27, load 30–70), against `main` measured at 14:29–14:30
(load ~6): settings mockup `==` 0.93–1.01 (materialized 0.67–0.75) against 0.63; synthetic
16.2–17.2 against 11.8; chain 0.45 against 0.29. Comparing payload fields by name instead
was 70% slower in debug (chain 0.89) and no faster in release, so it was dropped.

### CodeGen still recurses

Not changed here; measured with a throwaway `StackHighWater` test emitting a page of a
frame chain *n* deep (`ReactEmitter.emit` / `SwiftUIEmitter.emit`, `PageAnalyzer`):

| Depth | React debug | SwiftUI debug | React release | SwiftUI release |
|---|---|---|---|---|
| 25 | 1,126,440 | 843,968 | 167,536 | 269,424 |
| 50 | 2,246,040 | 1,664,472 | 325,936 | 536,080 |
| 200 | 8,963,640 | 6,539,296 | 1,276,336 | 2,083,824 |

About 45 KB a level for React and 33 KB for SwiftUI in debug (6.4 and 10.4 KB in
release): a debug emit overflows a task's 512 KiB about 11 (React) or 15 (SwiftUI) levels
deep, a release one about 80 or 50. Each emitter builds a node's code from its children's,
with per-node context (indentation, parent layout, slots, instance scope), across some
190 files; making them iterative is a refactor of its own, not this leaf's.
