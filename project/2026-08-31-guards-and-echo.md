# Content-hash guards and the divergence echo

*2026-08-31. Claude (Fable 5) with Ben, designing from the concurrent-editing
run's findings ([the DX report](2026-08-31-woodcase-concurrent-dx.md)). This
supersedes the original shape of issue TCMmx ("subtree revision guards"),
which is now the parent of this work.*

## The problem, restated

The four-writer run produced zero real collisions but proved the guard model
wrong for fan-out: the document revision churns under every writer, a batch
can guard only its first line, and one agent rationally disarmed `--rev`
entirely. Meanwhile every expensive failure was a **silent acceptance** — the
tool took a write, confirmed it back, and the mistake surfaced in pixels or
never (the `rootOverrides` swallow, `$`-content resolution, override of a
property no descendant sets, the superseded-tab residue).

Two mechanisms, complementary: a **guard** makes a moved premise fail loudly
*before* the write; the **echo** makes what actually happened visible *after*
it. Guards stay opt-in; the default remains apply-and-report, which is what
kept the four-writer run at zero spurious failures.

## 1. Content hashes on every read

Every node gets a Merkle-style content hash: `hash(node) = H(canonical
encoding of the node's own properties, ordered child hashes)`. Every read
surfaces it — a `hash` field on each `tree --json` row and on `get`'s answer,
beside the existing revision. Cached on the prepared document; recomputed
only along a write's spine.

Why hashes and not revisions or timestamps:

- **State-based, which is what a premise means.** "Has this changed since I
  looked?" — touched-and-reverted passes, correctly; a timestamp fails it.
- **Subtree pinning is one comparison.** A frame's hash covers everything
  under it, so "I read this whole frame and composed against it" is a single
  pin — the thing the original TCMmx asked for.
- **Replica-independent.** A hash of converged state is well-defined on every
  peer; a revision is replica-relative. Hashes survive the CRDT future
  unchanged.
- **Derivable from the file alone.** No log, no daemon, no history.

Per-node revisions stay — they are the existing contract and they worked
(the core agent's per-node revs never went stale in 40 minutes of four-agent
traffic). The hash joins them as the pin that guards take.

> **Correction, 2026-08-31 (pre-implementation premise check).** The contrast
> above is stale: the per-node revision the CLI already surfaces **is** the
> Merkle content hash this section specifies. `EditableDocument.revision(of:)`
> (`EditableDocument+Revision.swift`) computes FNV-1a over the node's
> canonical JSON encoding followed by each child's revision in order —
> state-based, subtree-covering, replica-independent, derivable from the file
> alone. `get` returns it (`NodeReport`), and every write report's
> `nodeRevision` is it. No replica-relative counter exists; only
> `documentRevision` churns document-wide, and a batch line's `rev` is checked
> at line-apply time (`BatchApplier`, first-edit-only `expecting`), which is
> the real source of the "a batch can guard only its first line" complaint.
> So part 1 adds **no new `hash` field** — the pin is the existing `rev`.
> What remains of the hashes leaf: a `rev` on every `tree --json` row, a
> revision cache on the document invalidated along a write's spine, and
> documenting the pin. Part 2's `--guard` keeps its full substance — its
> differences from `--rev` are *evaluation at transaction entry* and
> *ancestor scoping*, not the kind of token it takes.

> **Second correction, 2026-08-31 (found at DemV8's integration).** "A
> frame's hash covers everything under it" is false wherever the subtree
> contains a component instance: a `ref` stores the component's id and its
> overrides, not the component, so a definition edit moves the definition's
> rev and the document's while every instance's rev — and every ancestor
> above one — stays put. A guard pinned on a frame of instances would pass
> over exactly the change it exists to catch. **Decided (Ben, same day):
> fold the resolved definition's rev into a ref's rev through
> `effectiveRefData`** — the rev becomes a rendered-premise pin, and a
> definition edit moves every instance's spine. Lands with leaf `2NW90`
> (full consequences in that leaf's decision note); the docs shipped in
> `ede8705` describe the authored-only reality until it does.
>
> **Landed with `2NW90`, with one addition.** `revision(of:)` folds
> `revision(of: refData.ref)` into a ref's hash, cycle-guarded, and a revision
> computed by cutting a cycle is not memoized — which is what keeps the token
> independent of which node was asked for first. The addition: folding the
> *authored* `ref` alone is not enough for an instance that has **repointed** a
> nested ref. The repoint is authored on the outer ref's own props, so changing
> it moves that ref's rev — but the component it repointed *at* is never named
> by the authored payload, so an edit to that component would have moved
> nothing. A ref's hash therefore also folds every component id a `ref` key in
> its own `descendants` map names. Invalidation is the pragmatic one: the
> revision cache is dropped wholesale exactly when the expansion cache is
> (`expansionCanDepend(on:)` — a ref, a component, or a node inside one), which
> is provably the only condition under which a fold-in edge can move.

## 2. `--guard`: an opt-in premise assertion

A write may pin what it reasoned about: `set … --guard <hash>` on the single
verbs, `"guard": <hash>` per line in `apply`, each optionally scoped —
default the operation's target, or any named ancestor
(`"guard": {"node": "Files", "hash": …}`) to assert about the whole subtree
the caller read.

**Semantics: "unchanged *by anyone else* since my read."** Guards are
evaluated at transaction entry — the moment the file lock is taken. Under the
single-writer lock every foreign write strictly precedes entry, and a batch's
own earlier lines run after it, so self-edits are exempt by construction:
line 30 may guard a frame that line 3 legitimately changed, and the guard
still answers the question the caller asked. (This is the property the run
showed plain revs cannot express — nav guarded 1 line of 36 because its own
batch would trip the rest.)

A failed guard is a typed refusal in the house error style: the node by path,
the pinned and current hashes, who wrote in between (from the activity log,
when it says), and the next command — re-read and re-derive. Exit code per
the conflict row of the house table.

> **Shipped, 2026-08-31 (leaf `2NW90`).** The grammar is `--guard <rev>`,
> `--guard <node>=<rev>` and `--guard document=<rev>`, repeatable; in a batch,
> `"guard": REV`, `{"node":ADDR,"rev":REV}` or an array of either. One
> `BatchGuard` type crosses the seam. `BatchApplier.checkGuards` is the door,
> called as the first statement of every write verb's transaction body and of
> `apply`'s — never inside `perform`, which is what makes entry-time evaluation
> true rather than aspirational. A guard naming a `@tag` is refused (nothing a
> line creates exists at entry), a `var`/`theme-axis` line's guard must name
> what it pins, and a `--retry` checks only the lines it re-runs. `who wrote in
> between` is the last logged event touching the pinned node's
> `revisionCoverage` — the fold-in set, so a definition edit is attributed to
> the frame guard it tripped.

## 3. The divergence echo

Every write line reports three-way: **requested → applied-as → superseded or
dropped**. When the three agree, the line is exactly today's
(`line 4  applied  Outline Sheet/OS-Body  nIW0H`) — the report stays quiet in
the common case. Only divergence earns detail, stated as *interpreted*
semantics, never a raw echo of the stored form (plain echo-back is proven
insufficient: `get` faithfully confirmed the swallowed `rootOverrides` key
back to the agent that wrote it). Divergences include:

- a value coerced or resolved: `content "$v-muted" resolved as a variable
  reference — write \$v-muted for the literal` (IAZIe's class);
- an override targeting a property the definition's descendant does not set
  (o8ahR's quieter sibling);
- a structural consequence: reattachment, a cleared key, a dropped line;
- later, a merge outcome: `applied, then superseded by core's later set on
  the same property` — the CRDT report channel rides the same rail.

`--json` carries the full post-state node per line for callers that diff
themselves.

## Relation to the CRDT layer

Merge-and-report *is* the CRDT behavior surfaced for agents: convergence
without failures, plus the visibility a human gets from watching the canvas
and an agent only gets from the report. The layer exists (`CRDTDocument`
shadowing `EditableDocument`: LWW property maps, RGA lists, Kleppmann
tree-move, op log, vector clocks — `CRDTArchitecture.md`), and routing CLI
writes through it would let a batch composed against a stale read be merged
over intervening history rather than path-resolved against whatever is
current.

> **Correction, 2026-08-31 (spike aPPZS, no-go).** The merge claim above is
> narrower than stated: merging over intervening history applies only to
> id-addressed ops, and the CLI's grammar is name-addressed, resolved at
> line-apply time (`BatchApplier+Plan.swift`) — a name-addressed batch is
> path-resolved against current state whether or not writes route through the
> CRDT layer. The spike's verdict (full note on leaf `aPPZS`): no-go for now;
> routing is blocked on the concurrent-override clobber (one LWW register for
> the whole `kind.descendants` map) and on the absence of CRDT-side rollback
> for a half-applied batch line. Parked in `project/backlog.md` with the
> un-park conditions. Parts 1–3 proceed unchanged, as this section predicted. Guards then generalize from hash-compare to "no foreign ops
concurrent-or-later than my read clock" — the same contract, history-based.
The spike leaf below answers what routing costs before that decision is made;
nothing in parts 1–3 waits on it, and nothing in them is discarded by it —
hashes and the echo are the pieces that survive either way.

## Tasks

```yaml
tasks:
  - title: Merkle content hashes on every read
    ref: hashes
    desc: |
      hash(node) = H(canonical props encoding, ordered child hashes), cached on the prepared document, recomputed along a write's spine. Surfaced as `hash` on every `tree --json` row and on `get`'s answer, beside the revision. Two processes reading identical state print identical hashes. WoodcaseEditor.md documents the pin. Design: project/2026-08-31-guards-and-echo.md.
    criteria:
      - Every tree --json row and get answer carries the node's hash
      - Identical subtree states hash identically across processes
      - A property edit changes the hash of the node and its ancestors only
  - title: --guard on writes, evaluated at transaction entry
    ref: guards
    blockedBy: [hashes]
    desc: |
      Opt-in premise assertion: --guard <hash> on single write verbs, "guard" per apply line, scoped to the target or a named ancestor. Evaluated at file-lock entry so a batch's own earlier lines never trip a later line's guard. A failed guard names the node, both hashes, the intervening writers when the activity log knows them, and the next command. Unguarded behavior unchanged. Design: project/2026-08-31-guards-and-echo.md.
    criteria:
      - A guarded write refuses when a foreign write moved the pinned subtree, naming both hashes and the next command
      - A later line's guard passes when only earlier lines of the same batch changed the subtree
      - Guards are absent by default and nothing changes for unguarded writes
  - title: The divergence echo on every write
    ref: echo
    desc: |
      Every write line reports requested -> applied-as -> superseded/dropped; agreement prints today's line, divergence prints the interpreted meaning (coercion, variable resolution, override of an unset property, structural consequence). --json carries the post-state node per line. Covers the silent-acceptance classes IAZIe and o8ahR's warning half (o8ahR's rejection half stays its own issue). Design: project/2026-08-31-guards-and-echo.md.
    criteria:
      - requested == applied prints exactly the current report line
      - A resolved $-content and an override of an unset property each print an interpreted divergence
      - --json carries the post-state node for every applied line
  - title: 'Spike: what routing CLI writes through the CRDT layer costs'
    ref: crdt-spike
    desc: |
      Planning leaf, note-only outcome, no production code. Answer three questions in a note on this leaf: (1) do the CLI verbs reach EditableDocument.applyLocal today, and where do they diverge from the CRDT path; (2) what does persisting the op log and clocks beside a plain .pen cost, and can the no-daemon, file-is-just-a-file property survive it (checkpoints/snapshots exist in the layer); (3) go/no-go recommendation for merge-and-report routing, with the echo leaf as the report channel. Design context: project/2026-08-31-guards-and-echo.md.
    criteria:
      - A note on this leaf answers all three questions with file/symbol references
```
