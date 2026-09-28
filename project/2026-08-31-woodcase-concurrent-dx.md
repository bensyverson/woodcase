# Five agents, one .pen: the concurrent-editing experience report

*2026-08-31. Compiled by the integrator (Claude, Fable 5) from the structured
feedback of the five agents that built
[the mobile viewer design](2026-08-31-mobile-viewer/design.md) — `kit` (Opus,
solo setup pass), then `nav`, `core`, `sheet` (Opus) and `activity` (Sonnet)
writing to `mobile-viewer.pen` simultaneously with no isolation beyond frame
ownership — plus the integrator's own friction. Verbatim agent reports are on
the leaves under job root `iR2OM`. Counts come from
`python3` over `.woodcase/activity.jsonl` filtered to the file; quoted errors
were hit live. This is the sequel to the Jobs mobile-dashboard report
(`Jobs/project/designs/…`, summarized in that repo) — same format, harder
workload.*

## The headline

**Concurrent multi-agent editing of one .pen file works today — but it is
lucky, not safe.** 457 logged operations (149 kit, 106 sheet, 97 activity,
81 nav, 24 core; 211 override / 135 add / 88 set), with the four design
agents fully interleaved over an ~8-minute window (14:50:09–14:58:32Z),
produced **zero lost writes, zero forced writes, and zero semantic
collisions**. All three genuine stale-revision failures (all `activity`'s)
were clean exit-3 refusals fixed by re-read-and-retry. What kept it safe was
the *social* contract — each agent stayed inside its own frames — plus
per-node revisions that never went stale. What the tool contributes is
coarser: the document revision moved constantly under everyone, one agent
rationally **disarmed `--rev` entirely** because guarding at document scope
under four writers means failing on edits that cannot collide, and a batch
can guard only its first line. The concurrency verdict and its fix are one
sentence: **reads need a subtree revision and writes need a guard on it**
(filed as TCMmx).

The other systemic result: the failure modes that cost real time were all
**silent**. Nothing that refused loudly cost more than a retry; everything
that accepted quietly cost minutes to an hour.

## What taught (all five agents, deduped)

- **`woodcase help design` is the right document.** Flex-first, the address
  grammar, the two property vocabularies, the read–write–verify loop — every
  agent named it; nobody opened the format spec.
- **Writes answering with the name → id tree** is the single best behavior in
  the CLI. A 40-node `apply` line returns 40 addressable ids; the next
  command needs no lookup.
- **Same-batch name resolution**: a `cp` line's new instance can be dressed
  by `override` lines later in the same batch, four levels deep, through
  nested refs. (Batch `@tag`s do *not* compose with a sub-path — 173Ys — so
  name paths are the composition mechanism.)
- **Errors that teach are real and load-bearing**: the ambiguous-name error
  lists candidates with full paths; the wrong-property error prints the whole
  accepted list (it is how the integrator learned `kind.width` vs
  `common.width` on a text node); the `override`-on-an-instance-root refusal
  names the exact next command.
- **`get --expand` vs `get`** — expanded versus stored — is the diff that
  cracks every override mystery.
- **Component `context` strings are load-bearing documentation.** `Sheet`'s
  "CHROME ONLY" note is the one fact that made the sheet screens buildable
  without a guess loop. (And when a context is wrong, it is a trap — see
  TDS-More below.)
- **Partial-failure `apply`** left the file coherent through a 38-line
  failure, and re-running the corrected batch was idempotent.

## What fought, ranked by what it cost

1. **The silent-acceptance class.** Five members, one shape — the tool takes
   the write, confirms it back, and the mistake surfaces only in pixels or
   never:
   - A literal `rootOverrides` key in a ref subtree becomes an override
     *named* `rootOverrides`; `get` echoes it back; `help schema ref`
     actively teaches the wrong key (**o8ahR** — the run's most expensive
     bug).
   - Repointing a nested ref's `ref` corrupts it to 0×0; restoring the
     original does not recover it, and the `ref=null` escape *stores* a
     `"ref": null` that later changes how sibling overrides render — the
     integrator chased a wrong current-tab on Activity down to that residue
     (**SWr75**).
   - Two agents created nodes both named `FL-TopBar`; no write warned, no
     lint fired, the address space quietly forked (**Gb9C7**).
   - Text `content` of `"$v-muted"` silently renders a color; no literal
     escape exists (**IAZIe**).
   - A write with no `--as` and no `WOODCASE_AS` mutates the file and logs
     **nothing** — the integrator's ~22 edits were invisible to the live
     dashboard, follow mode and history (**Ro6Z6**).
2. **Revision guards don't fit fan-out** (**TCMmx**, the concurrency
   finding above).
3. **Lint has no scope and no intent.** Whole-file-only lint under fan-out
   means every agent greps shared output and justifies other people's
   findings (**Vw5kC**); `clipped` cannot express "this scrolls", so the nav
   agent shrank thumbnails and abandoned a scrolling grid *to satisfy the
   linter* (**dN6XF**). The SNEpH false positive (fixed mid-run, bec675d)
   compounded it: ten error-severity noise lines on a file whose correct
   overrides are `$v-*`.
4. **The override-path grammar undersold.** A path must name *every frame of
   the definition's own tree* (`Row/OR-Body/OR-Name`, never `Row/OR-Name`);
   the sheet agent lost 38 batch lines to it even though its brief carried
   the warning, because "every step" is ambiguous between instance steps and
   definition frames. The failing error contains the fix — but 38 times,
   ungrouped.
5. **Paper cuts**: bare `tree --props` errors instead of defaulting (173Ys);
   batch root-`add`s skip auto-placement while `apply --help` claims
   otherwise (NHkOc, 100+ overlap warnings on the kit's first batch); `shot`
   cannot enlarge a 22pt component for review (5QrVm); `cp` over the
   installed binary earns a signatureless SIGKILL (harness — gotchas has it).

## What's missing, ranked by how much of this session each would have saved

1. Subtree revisions and a write/batch guard on them (TCMmx).
   > **Superseded, same day:** the design conversation that followed this
   > report replaced subtree revisions with Merkle content hashes plus an
   > opt-in `--guard` evaluated at transaction entry, and a divergence echo
   > on every write — [the design](2026-08-31-guards-and-echo.md); TCMmx now
   > parents that work.
2. `apply --dry-run` — validate a subtree against a shared file without
   writing; it would have caught o8ahR's shape instantly.
3. `lint <file> <node>`, plus duplicate-name findings and a scroll/clip
   intent (Vw5kC, Gb9C7, dN6XF).
4. Rejection of the silent classes at the write: a literal `rootOverrides`
   key, a repointed nested `ref`, an override on a property the descendant
   lacks.
5. "What can I override here": `get <instance> --overridable`, and an
   effective post-override tree (`tree --expand-refs`). Today the discovery
   path is raw JSON with `jq`/python — the CLI loses exactly where
   components get interesting.
6. An identity requirement (or empty-identity logging) so no write can skip
   history (Ro6Z6).
7. Small: `shot` multi-theme in one call; `--scale`; a grouped error when N
   batch lines fail identically; a literal `\$` escape; `x:"center"`.

## Format-level findings (not the CLI's fault)

- **A ref's target cannot vary per instance**, so any component that
  contains refs is a fixed picture — the kit's `Ticker` could not serve two
  rosters and every screen composed its own from `TickerDot-*` atoms.
  `kind.slot` looks like the intended answer and is documented nowhere the
  CLI teaches. Component *variants* (TabPill vs TabPill-Current) plus the
  repoint bug (SWr75) make "which variant is current here" genuinely
  inexpressible today; both sheet agents styled variants by hand.
- **Instances take no new children**, so a container component is chrome
  only and every body is a sibling frame — workable once `Sheet`'s context
  said so out loud.
- **Alpha over a themed color** has exactly one idiom (a flat two-stop
  gradient with stop opacity); everyone needed it, nobody guessed it —
  the kit agent found it and the briefs propagated it.

## Briefing lessons (ours, not the tool's)

The agents' "what is wrong with this brief" sections earned their place:
assign a **name prefix** per agent the way frames are assigned (the FL-
collision was a briefing failure, not just a tool gap); check the kit's
actual state before writing specifics into a brief (a slot number that the
kit contradicts, a "neutral" component that ships with markers on); and when
two rules collide (theme-variables-everywhere vs literal identity hex), the
brief should name the winner rather than hand the agent the contradiction.
A live "definition fixes go back to the kit owner mid-session" channel would
have saved three agents rediscovering TDS-More's 1-point-too-narrow overflow
label.

## Issues filed from this run

SNEpH (lint false positive — **fixed**, bec675d) · o8ahR · Gb9C7 · IAZIe ·
SWr75 · dN6XF · Vw5kC · TCMmx · 173Ys · NHkOc · 5QrVm · Ro6Z6 · vOJbc (serve
never adopts a late file) · KBINH (zero-artboard 404) — the last two found
by the human watching `serve` during the run.

## What to keep exactly as it is

The verb set and the no-daemon model, names as addresses, mandatory names on
`add`, the per-line `apply` report with created ids, same-batch name
resolution, errors that name the node and the next command, per-node
revisions from `get`, and `context` on components. Four agents shipped
sixteen lint-clean themed screens into one shared file in under an hour of
wall clock; the tool's core loop is right.
