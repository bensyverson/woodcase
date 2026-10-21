# Batch property writes

*2026-10-21 · leaf GdTpYF · from Penumbra ffNVj2 (session 40)*

## Why

Penumbra's perf board showed `SessionAdapter.previewNodes()` costing ~4 ms of main thread
per gesture run, and traced it to `EditableDocument.patchedNode(for:onto:)`, which wrote a
`setProperties` patch one key at a time through `NodePropertyCodec.setting(_:at:on:)`. Each
of those writes captures the whole `common` or `kind` payload and decodes it again over the
new value (`PenNodeOverlay`), so a patch of N keys cost N passes.

## What changed

`NodePropertyCodec.setting(_:on:)` (`Sources/Woodcase/Editing/NodePropertyCodec+Batch.swift`)
writes a whole map: every plain `common.*` key in one overlay pass over `common`, every plain
`kind.*` key in one over `kind`. Any other key — `extras.*`, a natural path (`note.*`,
`codegen.*`, `common.locked`, `kind.blendMode`…), a `kind.effects` naming a spread, any key
of an instance or an unknown type, any key that would be refused — is written on its own in
its turn, after the plain keys before it are flushed, so keys that share storage land in the
per-key order. A pass that declines or throws is replayed key by key from where it began, so
the node and the refusal are exactly the per-key ones. `patchedNode(for:onto:)`,
`CRDTDocument.processLocalSetProperties` and `OpSequencer`'s drift assert use it.
`CostCounter.Work.payloadOverlay` counts overlay passes; `NodePropertyBatchCostTests` pins a
board's eight-key patch at two, and `NodePropertyBatchTests` holds the batch to the per-key
writes over one node of every shape in the bundled fixtures, in several dictionary orders.

## Figures

`WOODCASE_BOARD_SCALE_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter BoardScalePatchProbe`
(`Tests/WoodcaseTests/Performance/BoardScalePatchProbe.swift`): `PerfBoardFixture`'s artboard
(308 nodes) scaled 1.5× about its top-left corner — 308 `setProperties` operations, 474 keys.
Medians of 41 runs; the machine was shared with other agents' builds, so these are
provisional.

| Run | load (1 min) | `patchedNode`, every op | per-key loop, every op | `previewNodes(for:)` |
|---|---|---|---|---|
| before (per-key) | ~55 | 5.94 ms | 6.76 ms | 6.72 ms |
| after, run 1 | ~19 | 5.96 ms | 8.40 ms | 8.43 ms |
| after, runs 2–4 | ~15.5 | 4.16 / 4.31 / 4.25 ms | 6.23 / 6.18 / 6.06 ms | 5.06 / 4.99 / 4.70 ms |

Compare within a run: before, `patchedNode` *was* the per-key loop (5.94 vs 6.76 ms, the
same work); after, the batch costs **~31% less** than the per-key loop on the same machine
at the same moment (4.2–4.3 vs 6.1–6.2 ms in the quiet runs).

## What it does not fix

The perf board's scale writes only **~1.5 keys per node** (`kind.fontSize` ×165 — every text
writes just its size — `kind.height` ×63, `kind.gap` ×61, `kind.width` ×43,
`kind.cornerRadius` ×41, `kind.padding` ×41, `common.x`/`common.y`/`kind.strokeWidth` ×20).
So most nodes cost one overlay pass before and after, and that pass — capture every key of
the payload, run its `init(from:)` — is now most of what is left. Cutting further needs a
typed fast path for the numeric keys a scale writes (set `fontSize` on a `TextData` without
the `Codable` pass), which the leaf named as an alternative; it is not built here.
