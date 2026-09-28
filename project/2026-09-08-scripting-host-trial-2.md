# What agents reach for unprompted: round two of the host trial, and the DX they reported

*2026-09-08. Research finding. Leaves `I5eTb8` (round two) and `e2VMoi` (the Nanoshoot greenfield run) under the [scripting host plan](2026-09-07-scripting-host.md). Sequel to [round one](2026-09-08-scripting-host-trial.md), which Ben asked a fair question about: was it unbiased? It was not, and this round was designed to remove the bias. Author: the integrator (Claude Fable 5.1), from four agents' running logs, final reports, activity logs and output files. Quoted sentences are the agents' or the tool's, verbatim. The client prototype is Quill; all data in the tasks is placeholder.*

## The question, restated

Round one's agent chose `js` for a task with a measurement in it, after a brief that told it to read `help js`, on data engineered to overflow, keeping a log that asked which route it took. Ben's ruling on the batch surfaces made the *retire* question moot — `apply` and `cp --each` stay because they are the wire form for shell scripts and workflows that do not want JavaScript. What remained was the interesting question: **what does the model reach for by instinct?** If `js`, the host was right to add. If the verbs, the model understands the primitives and picks the simpler one. Both are acceptable findings; this document records which one happened.

## Method

Three Sonnet agents in parallel, each on its own copy of the Quill mobile prototype in its own directory with its own activity log, none aware of the others. Every brief named `woodcase help design` and said `woodcase help` lists the other topics; **none named `js`, `find`, `apply` or `cp --each`**. The log asked for what they ran and why, not which route they chose. Each report ended with a five-part developer-experience section: the three costliest moments with the command and output, help gaps, proposed changes, confidence before verifying, and any code written outside the tool.

| Arm | Task | Whose home ground |
|---|---|---|
| A, control | Round one's task: a twelve-row "Companies List Pinned" from a data table, every row the original's height, long strings shortened with an ellipsis | the measurement makes it `js`-shaped |
| B, fan-out | A twelve-row "Meetings Today" from a data table, nothing overflows | `cp --each` |
| C, fixed list | Twelve unrelated edits from a written change request: renames, texts, a variable, a new variable, a removal, a move, a duplicate | `apply` |

A fourth run is reported alongside but is a different arm: **N, greenfield**, an Opus agent designing Nanoshoot mobile-first from an empty file, with `help js` named in its brief. It asks whether the host holds when there is nothing to copy from, not what an unprimed model reaches for.

`help design` itself does mention the two JavaScript verbs, in one paragraph: *"`find` is a question … `js` is a loop-shaped task: a program with a `doc` object … it can measure what it just made and throw rather than commit."* Every agent read that paragraph.

## What they reached for

| Arm | Routes, in order | `js`? | Code outside the tool | Log |
|---|---|---|---|---|
| A | `tree`/`get` reads; a hand-written 45-line `apply` batch (`cp` tagged, 8 `rm`, 36 `override`), dry-run then real; then `tree --expand` per tall row and single `override` writes until each fit | no | a Python one-liner to count string lengths | 56 events, 11 batches, no external |
| B | `cp` of the artboard with a rename; 3 `rm`; a 12-line Python script emitting a 24-line `apply --atomic` batch from the JSON | no | the generator script | 29 events, 5 batches, no external |
| C | twelve single verbs — `set`, `override`, `vars set`, `rm`, `cp` — each guarded by `--rev` and read back | no | a shell loop waiting for the binary to reappear | 13 events, 12 batches, no external |
| N | `apply` for flat tokens; a shell loop over `vars set --theme`; one `add` per screen with inline refs; `cp --each` for dashboard rows; `js` for the token board's data-driven rows and an overflow gate; `find` ×3 as standing checks | yes, where the shape was a loop | Python generating the JSON woodcase read via `-F` | 164 events, 50 batches, no external |

Every log's tail revision equals its file's revision; no agent touched a `.pen` file with anything but woodcase; every write was attributed.

**The instinct finding.** Unprimed, none of the three Sonnet agents opened `help js`, and none reached for `js` — including A, whose task had the measurement that makes `js` the primer's own recommendation, and who had just read the paragraph saying so. A did the measure-and-fix loop by hand: a batch to build, then ten individual writes and reads to fit four strings, committing each probe as its own transaction. Round one's same task, primed, was one transaction with a gate. So round one's `js` choice came from the brief, not from the model. The model's instinct on these tasks is the verbs and `apply`, with a small script to generate the batch when the data is a table.

Read the way Ben framed it: the model understands the CLI primitives and reaches for the simpler one. `apply` in particular was the unprompted choice of two of three agents for anything with more than a handful of writes, and both praised it. B: *"set all 24 title/meta fields in a single transaction rather than 24 separate CLI calls."* A on its 45-line batch: *"dry-run first … all 45 lines applied cleanly."* What the verbs did not give A was atomicity across the fit loop — nothing bad happened, but eleven transactions where one would do is exactly the case `js` exists for, and a Sonnet agent reading `help design` did not connect the paragraph to its task.

**The greenfield finding.** The Opus agent, primed, used every route by shape and said why each time — `apply` for a fixed list, `add` with inline refs for a composed screen, `cp --each` for rows that differ by data, `js` where *"the shape is data … and I want the same run to read back what it built"*, `find` for standing checks. That is the primer's routing table executed as written, and it produced a twelve-screen, two-theme, lint-clean design in eighteen minutes. The host holds with nothing to copy from. Its one real bug was in the Python helper layer that generated its JSON, not in anything the tool did.

## Every sentence, and whether it was enough

Sentences the agents said told them what to do next: the `addressNotFound` refusal that names the full instance path and the rule (three agents, unanimous: *"excellent, self-sufficient"*); the `ambiguousAddress` refusal listing both candidates and the `#id` spelling; the `cp` placement note; the `clipped` warning that guesses a designed scroll and prints the `_scroll=vertical` command (*"the best sentence of the run"*); the document-revision conflict on `cp` into `document` (*"told me exactly what to do and why"*); the `--crop` refusal with the rect and the next command; the divergence notes on `$` values.

Sentences that were not enough, in the agents' words:

1. **`Error: Missing expected argument '<name=value>'`** on `vars set file.pen --accent=#e0561a` — two agents (C, N). *"Accurate, but never named the actual rule"*: a variable whose name starts with `--` needs a bare `--` separator after the other options. N renamed its whole token set to avoid it; C took three tries.
2. **`line 1 is not a batch operation: The given data was not valid JSON — run 'woodcase apply --help' for the grammar`** on a pretty-printed batch (N). *"Named the line and the fault, not the cause (an op may not span lines)."*
3. **`--props: no node in this listing has "kind.content". Property paths are prefixed — "common.name", "kind.content", "kind.fill".`** on `tree <ref> --props kind.content` (A, C). The row is a component instance with no children listed; the fix is `--expand`, and the sentence restates the path grammar instead. A: *"the single sentence in this whole session that didn't tell me what to do next."*
4. **`The predicate, line 1: Can't find variable: r`** on a `find` predicate written as an expression rather than an arrow function (N). *"Named the symptom rather than the shape it wanted."*
5. **`error unresolved-variable … still refers to '$30.00 · Unlock all photos →'`** (N) — exact and fixable, but it exposed that a leading `$` is forgiven in text content, refused through an instance override, and prints a literal backslash when escaped mid-string. *"Three behaviours for one character, split by which verb wrote it."*
6. **The font-fallback notice** — already issue `B0LkWL` from round one.
7. **`command not found: woodcase`** — three agents, not the tool's sentence: Ben reinstalled the binary while they ran. Each recovered (a retry, a poll loop, the release build in the checkout). Recorded so nobody hunts for it.

## Developer experience, synthesised

The verbatim reports are long; this is what they add up to, most-cited first. Each agent's full DX section is in its log directory's report and quoted where it carries the point.

**1. Sentences that name what broke, not the rule.** Items 1–4 above are one shape. The refusals the host and the editing layer write are consistently praised; the sentences that come from ArgumentParser or from a JSON decoder are the ones that fail. C's proposed fix for the first: *"add the `--` example for dash-prefixed variable names — the single most likely first-run stumble for anyone with `--`-prefixed tokens (which this whole file uses)."*

**2. A text node can vanish and nothing objects.** N: *"a text node with `textGrowth: fixed-width` and `width: fit_content` collapses to 0pt wide and renders '1' instead of '18 photos, ready to download'. Nothing in the tool objects — a zero-width text box isn't overflowing, isn't clipped, isn't short. Only the PNG caught it."* Three standing `find` queries and two `lint` passes missed it. That combination is never intentional, and it is a lint check.

**3. Measuring means writing.** A: *"there is no way to ask the tool 'how wide is this string in this box' without actually writing it and reading the settled rect back … a `--dry-run` on `override` does NOT help here — it only rehearses the write, no layout pass."* Round one's agent said the same and answered it with a binary search inside `js`; A, without `js`, paid a transaction per probe. Two answers exist and neither is small: a rehearsal that includes a layout pass, or a measure verb. The `js` route already gives a settled read after an uncommitted write, which is the thing A wanted — the gap is that A did not know to go there.

**4. `vars set` on a name that exists says nothing.** C caught that my change request called `--warn` "new" when it existed with nine references, only because it ran `vars list` defensively first: *"if I'd trusted the word 'new' … I'd have silently reflowed 9 existing UI elements."* Its fix: `vars set` on an existing name prints the old value and the reference count. (The brief's error was mine.)

**5. No bulk route for the token layer.** N: *"17 colours × 2 options is 34 process launches through a shell loop because `apply`'s `var` op only takes the flat `{type,value}` shape. The token layer is the first thing you write in any design file, and it is the one part of the tool with no bulk route."*

**6. Filling existing rows from data.** B: *"a bulk-override mechanism for existing nodes analogous to `cp --each` (which is only for placing new copies) — I ended up hand-rolling a JSONL `apply` batch."* Its proposal is `override --each rows.jsonl`. This is the one place round two's instinct data argues for a *verb*: two agents copied a whole list and then populated its rows, and `cp --each` does not fit that shape because the rows already exist.

**7. Small message fixes.** The `cp` placement note names the source, not the new name given in the same call (B, C). `get --json` nests the node under `"node"`, which cost B a loop (documented in the `.d.ts`, not in `get --help`). `--props` on a bare ref should say `--expand` (A, C).

**8. Wanted, needs a product conversation.** A grid fan-out for `cp --each` (N); `note` nodes drawn on a components sheet so specimens carry captions (N); a collapsed `activity` view for a script-written batch (round one).

**Confidence.** All four said the same thing about when they trusted the file: not after the write's echo, but after reading it back, and most of all after the `shot`. C: *"the write's own echoed name/rect answers a lot."* A: *"low-to-moderate before verification."* B: *"the render … was the strongest confirmation since it's what a person would actually judge."* The read-write-verify loop is being followed as taught; what would shorten it is the layout-aware rehearsal in item 3.

## Actionable work

The block below is in `job schema` form so it can be loaded with `job import --parent 6vdq3j` once Ben has read it. It holds only what needs no product-level discussion. Not in it: a measure verb or layout-aware `--dry-run`, `override --each`, grid fan-out, drawn notes, a collapsed activity view, and any change to which routes exist. The font-cache move and the fallback notice are not in it because they are already leaf `JcgJGO` under root `RgmG2h`, which is also where this block would import. Imported 2026-09-08 under root `RgmG2h` on Ben's word, after two dry-runs.

```yaml
tasks:
  - title: A lint check for text that collapses to zero width
    desc: |
      A text node with `textGrowth: fixed-width` and `width: fit_content` settles to 0pt
      wide; the render shows one glyph and `lint`, three overflow/clip `find` queries and
      the divergence notes all stay silent, because a zero-width box is neither overflowing
      nor clipped. The Nanoshoot agent shipped it past a clean lint and found it only in the
      PNG — the one item in this list that let a wrong design through every check the tool
      offers, which is why it is first. Add a check (`collapsed-text`) that fires when a
      text node's settled width or height is zero while its content is non-empty, with the
      remedy naming the growth and width pair. Finding:
      project/2026-09-08-scripting-host-trial-2.md, DX item 2.
    labels: [dx, lint]
    criteria:
      - "A fixture with the collapsing pair lints with one `collapsed-text` finding whose remedy names both properties"
      - "The Nanoshoot design file at /Users/ben/git/nanoshoot/design/nanoshoot-mobile.pen still lints clean after its fix"
  - title: One rule for a leading `$` across content, override and escaping
    desc: |
      Text content forgives a bare `$name` that matches no variable and keeps the literal;
      the same string through an instance override is an `unresolved-variable` error; and
      escaping it as `\$` mid-string prints a literal backslash. Three behaviours for one
      character, split by which verb wrote it (Nanoshoot N, three prices). The rule to adopt
      everywhere is content's rule exactly: forgive a `$name` **only when no variable of
      that name exists** in the document, so a `$name` that matches a real variable still
      resolves — or still lints as unresolved when it is themed away — as it does today;
      this must not become a way to hide a genuine dangling reference. Make the escape
      consume its backslash on both routes, and say the rule once in `override --help`.
      Finding: DX item 5 of project/2026-09-08-scripting-host-trial-2.md.
    labels: [dx, editing]
    criteria:
      - "The same `$30.00` string written as content and as an override lints identically and renders identically"
      - "A `$name` naming a real variable written through override still resolves, with a test proving forgiveness did not widen"
      - "`\\$` mid-string renders as `$` through both routes, with tests on each"
  - title: Teach the `--` separator where a dash-prefixed variable name meets ArgumentParser
    desc: |
      `woodcase vars set file.pen --accent=#e0561a` fails with `Missing expected argument
      '<name=value>'` because the parser reads the assignment as an option. Two agents hit
      it (round two C, Nanoshoot N); one renamed its entire token set to avoid it. Fix in
      two places: `vars set --help` and the variables section of `help design` show the
      bare `--` separator with an example, and the parse failure for a value that looks like
      `--name=value` says the rule rather than the missing argument (BareOptionValue.filled
      is the existing pre-parse seam). Finding: project/2026-09-08-scripting-host-trial-2.md,
      DX item 1.
    labels: [dx, cli, scripting]
    criteria:
      - "`vars set --help` and `help design` each show `-- --name=value` with an example, held by the topic tests"
      - "`woodcase vars set f.pen --x=1` prints a sentence naming the `--` separator, with a CLI test"
  - title: "`vars set` on an existing name says so"
    desc: |
      `vars set` is add-or-change and prints the same outline either way, so a request to
      "add" a variable that already exists silently recolours every reference (round two C:
      `--warn`, nine references, caught only by a defensive `vars list`). On an existing
      name, print one line naming the old value and the reference count before the outline,
      in both text and `--json`. Finding: DX item 4 of
      project/2026-09-08-scripting-host-trial-2.md.
    labels: [dx, cli]
    criteria:
      - "`vars set` over an existing variable prints its previous value and reference count; a fresh one does not"
  - title: Five message fixes from round two
    desc: |
      (1) `tree <ref> --props kind.content` on a bare instance says the property grammar;
      when every row in the listing is a ref with no children shown, say `--expand` (A, C).
      (2) The `cp` placement note names the source when the copy was renamed in the same
      call; name the copy (B, C). (3) The `apply` refusal for a line that is not valid JSON
      says the grammar; when the line is a fragment of a multi-line object, say one op per
      line (N). (4) A `find` predicate written as a bare expression fails with `Can't find
      variable: r`; when the text is not a function and evaluating it throws a reference
      error on a bare identifier, say that a predicate is a function of one row, `r => …`
      (N). (5) `get --help` says that `--json` nests the node under `node` beside
      `revision`, which today only the `.d.ts` in `help js` says (B). Finding: DX items 1
      and 7 and sentences 3 and 4 of project/2026-09-08-scripting-host-trial-2.md.
    labels: [dx, cli]
    criteria:
      - "Each of the four sentences has a CLI test asserting the new wording, and `get --help` names the `node` key"
  - title: Batch `var` op takes the themed value shape, and `vars set` takes several pairs
    desc: |
      Themed colours cannot go through `apply`: the `var` op refuses anything but
      `{type,value}`, so a 17-colour, two-option token layer is 34 process launches through
      a shell loop (Nanoshoot N). Let the op carry the themed form `vars set --theme`
      accepts, and let `vars set` take several `name=value` pairs in one call. Finding: DX
      item 5 of project/2026-09-08-scripting-host-trial-2.md. Extends WoodcaseBatches.md.
    labels: [dx, batch]
    criteria:
      - "A batch line sets a themed variable and the divergence echo shows both options"
      - "`vars set f.pen a=1 b=2` writes two variables in one transaction"
  - title: "`help design` hands a measure-and-fix loop to `js` in one sentence"
    desc: |
      This is the one item in the list with a stance rather than a fix. Round two's control
      agent read the primer's paragraph on `js` and still did its measure-and-fix loop as
      eleven transactions of single writes and reads; under Ben's framing that is an
      acceptable instinct, but eleven transactions where one would do is a real cost to the
      user. The paragraph describes `js`; it does not say *when a loop of writes and reads
      is what you are about to do, that loop is a `js` program*. One sentence in the
      read-write-verify section of `help design`, in that shape, plus the same in
      WoodcaseEditor.md's "When the answer is a loop". It is a nudge, and only a third round
      with an unprimed agent says whether it worked. Finding:
      project/2026-09-08-scripting-host-trial-2.md, the instinct finding.
    labels: [dx, docs, scripting]
    criteria:
      - "`help design` says in the loop section that a repeated write-then-measure is a `js` program, held by DesignTopicClaimsTests"
```

## What this round did not settle

One agent per arm is still one agent per arm; the pattern across three is consistent but not a population. The instinct finding says Sonnet does not reach for `js` unprompted on these tasks after reading `help design` as it stands; it does not say whether one more sentence in the primer changes that, which is why the last task above exists and why a third round after it would be cheap. And the greenfield arm ran primed and on Opus, so it says the host holds under a designer who knows it is there, not what an unprimed designer does.

## Reproduce

Copies of the Quill prototype, one per arm, each in an empty directory with its data file (`companies.json`, `meetings.json`, `changes.md`); `woodcase` installed from `main` at `fe9265a`; the three briefs as described under Method; afterwards `woodcase activity <file> --json | wc -l`, compare the last event's `revision` with `woodcase tree <file> --depth 0 | head -1`, and grep the log for `external`. The Nanoshoot design and its shots are at `/Users/ben/git/nanoshoot/design/`, uncommitted there.
