# The expanded tree read that never ended

2026-09-27 · leaf nxLzvE

## What was reported

`IncrementalSettleEquivalenceTests` (commit d859a51) compared `doc.tree()` rows
*without* instance expansion, because with `expandInstances: true` a debug run spent
14+ minutes inside `EditableDocument.effectiveRefData(of:insideInstances:)`. The
suspicion was the per-chain-element recursion in that function — a JSON round trip per
element, re-derived for every row.

## What it was: a cycle, not a cost

No fixture *as authored* is slow. `scripts/tree-expand-times` over all 208 fixtures
(`woodcase tree --json --expand`, debug build) finished every file; the slowest took
1.13 s, 31 s in all, at load 60–70 — the figures are only good for "nothing hangs".

The hang was the test's own `moveToAnotherRoot` write. It moves the first node that has
a parent into the first other root frame, and in many fixtures that puts an instance of a
component inside that component (or builds a mutual pair). `PenRefExpander` stops at a
`ref` naming a component already on its chain and leaves it as written; the tree walk
had no such rule, so it listed `Inst/Self/Self/Self/…` for ever. A depth-limited probe
(depth 30) confirmed it: 21 fixtures hit the limit after that write, in 6–80 ms each.
A component with two self-references would make the endless walk exponential too.

`effectiveRefData` was a victim, not the cause — it ran on every row of an endless
walk. It was still wasteful: each row re-settled its whole enclosing chain, recursively,
with an array copy per level, and a 200 000-element chain crashed a debug test process
with a stack overflow (`EffectiveRefTests.aLongChainDoesNotRecurse`, red before the fix).

## The fix

- `EditableDocument.componentPlacement(of:onChain:)` mirrors the expander's
  `resolveChain` step for step: a payload naming a component on the chain places
  nothing, and alias links join the chain. `componentRootID(of:)` is its empty-chain case.
- `EditableDocument.effectiveRefData(of:enclosedBy:)` settles one step from the
  enclosing payload; `effectiveRefData(of:insideInstances:)` is now a loop over it.
- `TreeView` carries an `InstanceScope` — the enclosing payload and the chain's
  components — down its work list, so a circular `ref` is one row with no children,
  as the expansion made it, and each row costs one step however deep it sits.
- `IncrementalSettleEquivalenceTests` now compares rows with `expandInstances: true`.

## Figures

All in a debug build (`swift test -j 3 --filter IncrementalSettleEquivalenceTests`), with other agents' builds
running; `uptime` load in brackets.

| What | Before | After |
|---|---|---|
| `IncrementalSettleEquivalenceTests`, rows expanded | did not finish (14+ min, reported by d859a51) | 16.7 s [29.9 → 36.6] |
| `IncrementalSettleEquivalenceTests`, rows not expanded | — | 16.0 s [40.1 → 32.2] |
| `scripts/tree-expand-times --timeout 60` (208 fixtures) | 31.0 s [60–70] | 16.2 s [26.9] |

The sweep figures differ by load, not by the change. Row output is identical before and
after for all 208 fixtures once `overflowAxes` order is normalised (see below); the
sweep saved each file's JSON and a comparison script checked them.

## Found on the way

`TreeRow.overflowAxes` is a `Set`, and its synthesized `Codable` prints it in hash
order, so `woodcase tree --json` for a row overflowing both axes prints
`["horizontal","vertical"]` in one run and the reverse in the next (9 of 208 fixtures
differ run to run). `tree-expand-times --out` sorts it when saving; the CLI does not.
