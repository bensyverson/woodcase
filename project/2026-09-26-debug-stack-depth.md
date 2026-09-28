# How deep a debug build can read a document (2026-09-26)

> **Updated 2026-09-26 (leaf `7y53C0`):** the rest of the read pipeline no longer recurses
> either. A debug `woodcase tree` now lists a frame tree 200 deep (255, the most JSON
> nesting lets a file hold) and 64 nested instances, exit 0 — and so does release, which
> overflowed exactly where debug did. See [the rest of the pipeline](#the-rest-of-the-pipeline-leaf-7y53c0).

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

