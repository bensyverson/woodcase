# Kicking the tires on Pen's MCP (2026-08-29)

Author: Claude (Fable 5), at Ben's request, as input to the Viewer & Editor design in
[2026-08-29-viewer-editor.md](2026-08-29-viewer-editor.md). A companion to the March
report in [2026-03-26-Gemini-DX.md](2026-03-26-Gemini-DX.md), which is now dated:
the MCP has changed shape since.

**Session.** A scratch copy of `~/Local/Pen/new.pen` opened in Pen.app as
`local/tirekick.pen`; eight `execute` calls building tokens, a `Metric` component, a
dashboard screen with four instances, a bar chart from layout, and three deliberate
failure probes. Pen.app never saved, so the on-disk file is untouched — the session
existed only in memory. Reproduce with `mcp__pencil__read_skill` (`execute.md`) and the
snippets below.

## What the MCP is now

Not Gemini's `I()/U()` string DSL. `execute` runs a JavaScript snippet with
`Insert/Copy/Update/Replace/Move/Delete`, a `Get` that takes a **visitor** with resolved
`bounds` and a `problems` flag ("partially clipped"), `Print` for compact rows,
`TakeScreenshot`, `Export`, `SetVariables`. Names are accepted as `descendants` keys and
in instance paths (`instanceId/Value`). A failed snippet returns an `editId`, and the
retry is a find/replace patch against the failed text. Every call returns a
name → id map for what it created.

## What worked well — steal these

1. **Loops over the format.** The bar chart was one call: an array, a `for`, three
   `Insert`s per column, `fill_container` widths. No pixel guessing.
2. **Name → id map in every response.** I never had to ask for an id I had just
   created.
3. **Names as override keys.** `Update("nX914/Value", {fill:"$accent"})` worked and was
   stored as the id (`JisvK`). Resolve names at write time, store ids.
4. **`Get` visitor with bounds + `problems`.** Structural verification without a
   screenshot: one row per node, ~40 chars each.
5. **Precise errors.** `/margin unexpected property` named the op and the key.
6. **`edits` retry.** Fixing one token instead of resending a 20-line snippet is a real
   token saving — and it teaches the agent to fix, not regenerate.
7. **Materialized instance is small.** `Get(ref, {resolveInstances:true})` was 463
   chars for a two-child card. Expansion is cheap to show; don't fear it.

## What bit me — design against these

1. **Same-call reads are pre-layout.** `ctx.bounds` and `TakeScreenshot` in the call
   that created the nodes reported nonsense (Title at y=50 inside a 33px header, all
   "fully clipped", a blank image). A fresh call was correct. *Rule for Woodcase: a read
   after a write must see settled layout, in the same invocation, always.*
2. **Globals don't persist across calls** despite the docs saying `id = Insert(...)`
   does. `metricId` was undefined on the next call; I recovered from the printed map.
   *Rule: don't promise session state you can't keep; make the id map the contract.*
3. **Screenshots are ~400 px wide with no size control.** "9,431" vs "9,481" is
   unreadable; `Export(…, {scale:2})` to disk was the only way to actually see it.
   *Rule: `shot --max <px>` and node-scoped shots, like `sleepy`.*
4. **Batch = full rollback**, still. One bad property in op 2 of 3 lost ops 1 and 3.
   *Rule: apply what can be applied, cascade-skip dependents, report per op;
   `--atomic` opt-in.*
5. **Deleting a component with live instances silently detached all four** into plain
   frames. No error, no warning. Defensible as a product choice; indefensible silently.
   *Rule: destructive-by-consequence ops refuse without `--detach`/`--force`, and say
   what would happen.*
6. **The tool won't show its own docs until a file is open** (`get_app_state` and
   `read_skill` both error). *Rule: help is always available.*
7. **The per-call "created nodes" list is flat and gets long** — the chart printed 36
   lines of `"Value": …` / `"Bar": …` with no structure. *Rule: print created nodes as
   an indented tree, deduplicating repeated names under their parent.*

## Second round: copy, slots, nested instances, variables

Probed after the first write-up, at Ben's prompting.

- **Nested instance paths and slot replacement work and are elegant.** A component
  (`ActionCard`) holding an instance of another (`IconButton`): `Update(inst/action/
  Caption)` overrode the caption two levels down, and `Replace(inst/Body, {...})` swapped
  a slot for a new subtree whose children were then `Insert`ed normally. The stored
  override is exactly the format's own `descendants` map with an object replacement.
  This is the shape our `override` verb should have; `EditableDocument` already has it.
- **`Copy` with name-keyed `descendants` silently did nothing.** The docs say names are
  accepted; `{"Title": {content: …}, "Footnote B": {enabled: false}}` on a copied
  screen left both untouched, with no warning — the copy just succeeded. Worse than an
  error: I only caught it by re-reading. *Rule: an override that matches nothing is an
  error naming the candidates, never a silent no-op.*
- **Post-call "issues detected" can be spurious.** After the slot call it reported
  three "collapsed size" problems; the next call's resolved bounds showed a healthy
  880×144 card. The warnings also referred to my *JavaScript variable names* (`card`,
  `slot`), not node names. *Rule: diagnostics come from settled layout and name nodes
  by path.*
- **`resolveVariables` resolves to one implicit theme** with no way to ask for another;
  the only route to "show me dark mode" is duplicating the screen with literal colors —
  which is what I did. *Rule: every read and shot takes `--theme`, as `render` already
  does.*
- `Get` with `resolveInstances` prints expanded ids as full paths
  (`SAjDU/B0M8B8/uKX6O`) that feed straight back into `Update`. Good pattern: a
  materialized read should hand back addresses that write.

## Consequences for the Woodcase editor

- The JS-snippet shape is *better than I assumed* for bulk creation: agents write loops
  well. But it drags in an interpreter, a sandbox and a DSL surface to document. The
  same leverage is available from **`add` taking a .pen subtree** (the agent's own
  language, generated by whatever loop it likes in its own shell) plus **JSONL batches**
  for edits. Keep the interface declarative; leave the looping to the caller.
- The visitor's `bounds`/`problems` output is the model for `woodcase tree`: id, type,
  name, resolved rect, and a clip/overflow flag per line.
- Name-path addressing, write-time resolution to ids, and the name → id map on every
  mutating response are non-negotiable.
- The four rules above (settled reads, per-op batches, loud destructive ops, always-on
  help) go straight into the plan's acceptance criteria.
