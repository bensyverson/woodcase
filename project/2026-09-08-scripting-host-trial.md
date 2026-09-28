# The scripting host trial: one agent, one loop-shaped task

*2026-09-08. Finding. Leaf `ShQWa9` of [the scripting host plan](2026-09-07-scripting-host.md); the trial the plan ends with. Subject: a Sonnet-class agent. Observer and author: the integrator (Claude Fable 5.1), from the agent's own running log, its final report, the file's activity log and the committed run's `--json` report. Quoted sentences are verbatim; the client's prototype is referred to as Quill, as in [the Quill mobile report](2026-09-01-quill-mobile-agents-dx.md).*

## The question

The plan's premise is a claim about agent behaviour: given a loop-shaped task and every route — a verb, `cp --each`, `apply`, `find`, `js` — an agent stays inside the tool, and the activity log accounts for every byte the file changed by. The Quill run of 2026-09-01 was the counter-example that motivated the host: four agents, four Python generators woodcase could not read. This trial re-runs that shape with the host shipped.

## Setup

- **File**: a copy of the Quill mobile prototype (55 root artboards, 1,748 tree rows, 819 KB) in a scratch directory outside any repo, so the activity log was the file's own `.woodcase/activity.jsonl`, empty at the start. Starting revision `23e27d7807da5c3e`.
- **Data**: twelve companies as JSON — `name`, `value`, `meta` — with placeholder names, three of them long enough to wrap a row's title, and one whose *meta* line was the longest string in the set. That last one was not planned; it turned out to be the most informative row.
- **Task**, in product terms: add an artboard "Companies List Pinned" beside the existing "Companies List", same shell, whose list holds exactly those twelve companies as instances of the existing company-row component; every row the height of an original row; where a long string would wrap, shorten what the row *displays* with a trailing ellipsis; `lint` clean; `--as trial` on every write.
- **Teaching**: `woodcase help design` and `woodcase help js`, read in full first; any `--help` allowed. No access to the Woodcase repo or its docs, no web. Any tool it liked otherwise.
- **Record**: a running log the agent appended to before each command — the route, the reason, the command, and any sentence the tool printed with a verdict on whether it was enough.
- **Binary**: `woodcase` installed from `main` at `ed7df56`, so with `help js`, the shared row view (`MSGsdo`) and overlap events (`ctvJct`).

## What the agent did

| Step | Route | Why, in its words |
|---|---|---|
| Orientation | `tree`, `tree --expand`, `get --expand` | to find the shell, the row component and its three overridable descendants |
| Fonts | `shot` once | *"per the tool's own instruction"*, before trusting a height |
| Shell | `doc.cp('Companies List', null, { props: { 'common.name': 'Companies List Pinned' } })` in a `js` script | *"renaming it in the same call so there is never a moment with two roots named 'Companies List'"*; no `x`/`y` so it lands beside, per the primer's overlap rule |
| Trim to twelve | `doc.rm` ×8, descending | the copy carried twenty rows |
| Fan-out | `doc.override` per row, in the same script | **not** `cp --each`: *"fans a template over rows, but has no way to measure and branch"* |
| Measure | `doc.tree(address, { depth: 0 })[0].rect.height` after each write | *"READS SEE SETTLED LAYOUT"* |
| Fix | binary search on the ellipsis cut, per field, against that field's own single-line height | height is monotone in the string length |
| Commit gate | a final read of all twelve rows; throw if any is not the original's size | *"a measurement decides whether to commit at all"* |
| Rehearse | `js --dry-run --json` three times | a script this size *"is worth checking in one shot"* |
| Verify | `tree --depth 0`, `get` ×12, `lint`, `shot` | the read-write-verify loop |

**It never left the tool for the file.** No JSON parser, no `jq`, no text editor touched the `.pen`. Python appeared twice, both times to pretty-print the tool's own `--json` output — a formatting convenience it logged as such. `apply` and `find` went unused; `cp --each` was considered and rejected for the reason above.

**One transaction.** The whole build — copy, trim, sixty-four overrides including every probe of the search, the gate — committed as one `js` run: 74 events in the activity log, one batch id, all attributed to `trial`, revisions chaining from the first write to `2046de2101173a25`, which is the file's revision now. `undo` would reverse it as one step. The earlier rehearsals wrote nothing and logged nothing, as the contract promises.

**The result** is right. Twelve rows, each 370×62 like every original row, in data order; four fields shortened — three names and one meta line — each to the longest prefix that fits with an ellipsis; the shell reflowed by itself because every container is `fit_content`. The `shot` confirms it visually.

## Every sentence the tool threw

1. **`addressNotFound`**, on the first rehearsal. The agent had written `…/CO Company Row 1/Ledger Row Figure Value`, skipping two frames the way an id-suffixed address in `tree --expand` output does. The refusal:

   > *matches no node in this document; inside that instance the address is …/CO Company Row 1/Ledger Row Figure Body/Ledger Row Figure Line1/Ledger Row Figure Value (fMEWI/03oBW) — address it as `…`; a name path into an instance names every frame of the component's tree, and only an id may skip one*

   **Enough.** It named the corrected path and the rule. The agent fixed three addresses and moved on. This is the sentence working exactly as designed.

2. **The font-fallback notice**, on every read:

   > *woodcase: font "Libre Franklin" is not installed and not in the font cache; text in it is measured in SF Pro. Run `woodcase render` or `woodcase shot` once to download it.*

   **Not enough — and wrong about the cause.** The agent did what the sentence said and the notice came back on the next read. The download had succeeded; the cache is `~/Library/Caches/com.bensyverson.woodcase/fonts/`, and the harness sandbox's read allowlist names `~/Library/Caches/woodcase`, a different directory. So every sandboxed call fell back to SF Pro silently, with a sentence that says "not in the cache" for a cache that is there and unreadable. The agent left the documented loop to diagnose it — a filesystem `find`, then every remaining call with the sandbox off — and was right to. Two consequences, one for each side of the seam:
   - The notice conflates *absent* with *unreadable*, and names no path a reader could check. Filed as issue `B0LkWL` below.
   - The sandbox allowlist is wrong on this machine, which means **every sandboxed `tree` measurement in every session to date has been in SF Pro**. The brief for this very trial said "59 pt at 370 wide"; the real figure is 62. The agent caught it and read the baseline from the file rather than trusting the brief. Fixing the allowlist is a one-line settings change for Ben; until then, `project/gotchas.md` carries it.

3. **`scriptError`**, from the agent's own gate: *"Stark Foundry" cannot be shortened to fit a 62pt row*. Not a tool sentence, but the most instructive moment of the run. A thirteen-character name that could not be shortened to fit is a wrong model, not a wrong string; the agent dumped the rehearsal's `events` timeline, saw the search run to `S…` without fitting, wrote two probe scripts (dry-run, against the untouched original), and found that the row's *meta* line had wrapped — row height is the sum of two independent line heights, and it had been searching the aggregate. The host gave it everything it needed: the timeline of every intermediate write, a rehearsal that costs nothing, and settled reads. What it did not have was any way to ask *which text wrapped*; it inferred that from geometry, which is what `tree --expand` is for and what it used.

## What the log says

| | |
|---|---|
| Events | 74 — `add` 1, `set` 1, `rm` 8, `override` 64 |
| Batches | 1 |
| Identities | `trial` only |
| External events | 0 |
| Log tail revision | `2046de2101173a25` |
| File revision now | `2046de2101173a25` |

Every byte is accounted for; criterion met. Two things worth knowing about the shape of the log:

- **`doc.cp` of a root logs as `add` plus `set`** — the copy is planned as an add of the decoded subtree and the `common.name` in `props` as a set on it. The transcript row says `cp`; the log says what the planner did. Not wrong, but a reader walking the log for "the copy" finds an `add`.
- **Every probe of the search is an event.** Sixty-four overrides produced thirty-six final values; the other twenty-eight are candidates the search rejected a moment later. That is what an append-only log is, and `undo` treats the batch as one step regardless — but `woodcase activity` reads as noise for a script-written batch, and its default view shows the most recent 50 rows, which for this run was the tail of the overrides and none of the structure. Not filed: it is the event-stream principle doing its job, and a collapsed view is a display question for when someone needs one.

## Cost

The committed run took 18 s wall-clock from its first override to its last on a 1,748-row document: about 73 writes and about 80 settled reads, each read paying a full settle. Three rehearsals paid the same. That is issue `Tdgxuz` (write-then-read settles the whole tree) with its first real-world number; tolerable here, and the shape of script that would make it intolerable — a fit loop over hundreds of rows — is now easy to imagine. The agent's whole session was 14 minutes and 52 tool calls, most of them reads.

## Verdict on the premise

The premise held, for one agent on one task. Given a loop-shaped edit and every route, the agent reached for `js` as soon as it read that a measurement could decide a commit, used it for the fan-out as well as the fit because the two were one loop, never touched the file with anything else, and produced one attributed, undoable transaction. The one time it stepped outside the tool's loop was the harness's fault, not the tool's, and it said so.

Two limits on the evidence. One agent is one agent; the Sonnet tier was chosen to be the population the tool is for, but a single run cannot say what a population does. And the task was chosen to fit `js` — the greenfield Nanoshoot trial (leaf `e2VMoi`, its finding to come) asks the other question, whether the host holds when there is nothing to copy from.

## For the batch-surface decision (`W9MdJV`)

`cp --each` and `apply` were available, taught, and unused; `find` was unused because the task asked no question. That is consistent with "a program subsumes both" and equally consistent with "this task had a measurement in it, so of course it did". The plan's default is to keep everything, and one trial in which the verb-side surfaces were *considered and declined for a stated reason* is not evidence that they are dead weight — it is evidence the primer routes correctly. **Recommendation: keep every surface; revisit after the greenfield trial**, which is the one where an agent might prefer twenty `apply` lines to a program.

## Issues filed from this trial

- `B0LkWL` — the font-fallback notice says "not in the font cache" when the cache directory exists and cannot be read, and names no path; a reader who follows its instruction sees the same notice again.

## Reproduce

The scratch workspace is not in the repo. The shape is: copy a `.pen` with a twenty-row list of component instances into an empty directory beside a `companies.json`; install `woodcase` from `main`; brief a Sonnet-class agent with the task paragraph above and the two `help` topics; afterwards, `woodcase activity <file> --json | wc -l`, compare the last event's `revision` with `woodcase tree <file> --depth 0 | head -1`, and `grep -c external`.
