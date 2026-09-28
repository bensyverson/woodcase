# Four agents, one phone .pen: the Quill mobile experience report

*2026-09-01. Compiled by the integrator from the verbatim reports of the four agents that built
`/Users/ben/git/quill/prototype/mobile.pen`: `atoms` (leaf doaRZ, 3 artboards, ~1,100 nodes,
64 reusable components, run first and alone), then `lists` (leaf 7cm10, 5 artboards, 637 nodes),
`detail A` (leaf EN6MN, 3 tall artboards, up to 402×5175) and `detail B` (leaf 5r14k, 2 artboards,
~470 writes) running **in parallel on the same file in one checkout**, each owning its own root
artboards, coordinated by nothing but the per-command lock and a naming convention. All four were
told to use `woodcase` exclusively, none had seen it before, and all four worked from the built-in
help alone. Result: **~1,850 nodes, 13 root artboards, `lint` clean, in one session.** Quoted
commands and errors are the agents', verbatim. Sequel to
[the five-agent concurrent report](2026-08-31-woodcase-concurrent-dx.md): same format, different
surface. That run tested concurrency; this one tested whether the verb set can express a component
library.*

## The headline

**Concurrency is settled; composition is now the open question.** Three agents wrote one file for
two hours with zero lock failures, zero corruption, zero `--rev` conflicts and zero collisions, each
reporting it independently. That is strictly better than 2026-08-31, which had three genuine exit-3
refusals, and nothing about concurrency cost anyone time. What cost time is that **woodcase has
verbs for one node and no verb for twenty nodes with twenty different payloads**, so all four agents
closed that gap with a program: 867, 445, 479 and 350 lines of Python emitting JSON or JSONL for
`add` and `apply`. The tool got a lint-clean 1,850-node design system out of four models that had
read only its help text, which is a high bar cleared. The cost is that the deliverable is four
Python generators woodcase cannot read, lint or attribute.

> **Correction, 2026-09-02.** The audit that followed this report disagrees with its
> framing: the biggest cost was not a missing verb but a false message (D5) and answers that lived
> where agents do not read. See [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md).

# 1. The author's question: did they write code, why, and which verbs remove the need

**All four did.** None of them wanted to.

| agent | code | shape | emitted |
|---|---|---|---|
| atoms | 867 lines Python (its §5 says "~900"; its appendix counts 867) plus a 3-line `rebuild.sh` | helper functions over a JSON dict | 3 `add` subtrees |
| lists | 380-line builder, 40-line measuring harness, 25-line fitting loop | data tables plus a `place()` emitter | 5 JSONL batches for `apply` |
| detail A | 470-line builder plus a 9-line PIL cropper | `ref()`/`frame()`/`text()` emitters over a 40-entry atom-id table | 3 `add` subtrees |
| detail B | ~350 lines across three files | op emitters plus four design-level builders | 430 JSONL lines for `apply` |

## 1.1 The five reasons, merged

**(a) Repetition with a per-item payload.** All four. 15 meeting rows and 20 company rows (`lists`);
24 form rows, 7 group titles, 3 checklist lines (`detail A`); six update blocks of 13 nodes and
twenty bullets of 3 nodes, *"~250 of my ~430 operations"* (`detail B`); 24 colour swatches by 4
fields and 17 type-ramp rows by 7 fields (`atoms`). `cp --times N` exists and **not one of the four
used it once**, for the same reason each time. `detail A`: *"It cannot vary the content, which is
the only thing that differs between my rows."*

**(b) No design-level vocabulary for a parameterised component.** `detail A`: *"there is no way for
the atom's author to declare its parameters. So every consumer of the atom re-derives which of the
12 descendant ids are the two you actually set."* It kept a 40-entry hand-maintained id table at the
head of its generator and calls that table *"a symptom"*. `detail B` arrived from the other side:
*"a `reusable` node that must be filled is a spec in a prose comment, and every author rebuilds
it."* `lists` calls it a missing concept rather than a missing verb: page scaffolding is *"a
non-visual layout preset"* the format has no word for.

**(c) The rebuild loop, because `set` edits exactly one node.** `atoms`: *"Changing the dot pitch
touched ~30 nodes; changing the ghost button's padding touched 5 … **Once a from-scratch rebuild is
cheaper than a targeted edit, you need a program that can emit the whole file.**"* `lists` rebuilt
all five boards four times; `detail B` rebuilt each board twice. See §8 for the disagreement about
whether any verb should try to remove this reason.

**(d) `apply`'s `cp` op refuses the path-keyed overrides the `cp` verb accepts.** A bug, not a
missing verb, and the run's most expensive one (D3). Every instance placement became 1+N lines:
*"roughly 180 extra JSONL lines out of 430"* (`detail B`), a board that went *"from 27 ops to 68"*
(`lists`). `detail B`: *"it is the reason I wrote a code generator."*

**(e) Needing rendered text widths.** Three of four, each independently building the same
workaround: a throwaway `.pen` used as a ruler. `lists`: *"one `fit_content` text node per candidate
string, `tree --json`, read the widths, trim, repeat. That is an absurd thing to have to build."*
`atoms` did it twice and shipped a `DOT_PITCH = 5.97` constant into a client's repo as a result,
*"a maintenance liability I have deliberately created for someone else."*

## 1.2 Ranked: what would have deleted the most code

| # | feature | proposed spelling | asked by | code it deletes |
|---|---|---|---|---|
| 1 | N copies with N payloads | `cp <file> <src> <parent> --each rows.jsonl` (optionally `--bind path={field}`) | **all four**, independently, in three spellings | atoms ~110 lines plus 58 lines of tables moved to data; lists *"the bulk of the code"*; detail A *"~60% of my generator"*; detail B no code at all for its bullets and update rows |
| 2 | rendered text metrics as a read | `woodcase measure <file> --font F --size N --weight W --text S [--max-width N --ellipsis] --json` | lists, detail B, atoms | lists' 40-line harness, 25-line fitting loop and ruler `.pen`; atoms' ~15 magic numbers and 2 probe artboards; detail B's `dots()` constant |
| 3 | parameterised components (named params, and a slot that can hold a ref) | `woodcase def slots <file> <comp> label=<id>.content …`, then `cp … --set label=City`; `{"type":"ref","params":{…}}` in an `add` subtree | detail A (its #1), detail B (its #3), lists, atoms | detail A's id table and ~90 minutes; detail B's 6 update blocks and 7 checklist lines rebuilt locally |
| 4 | document `enabled=false` as the variant mechanism | a **VARIANTS** section in `help design`, an example in `override --help` | atoms (its #1 by ratio), detail A (asked for it, not knowing it exists) | atoms ~180 lines: `form_row` 64, `update_block` 45, `button` 18, `rail` 11, `mark` 11, `toggle` 10, `tickbox` 8, `pill` 7, `tag` 6 |
| 5 | document that a `ref` may be written inside an `add` subtree | one paragraph in `help design` and `add --help` | detail A (found by guessing) | detail A: *"'one `cp` per instance, ~90 commands' into three `add` commands for three whole artboards"* |
| 6 | fix `apply`'s `cp` props (D3) | no new surface: route the op through the verb's assignment path | lists, detail B | detail B ~180 JSONL lines and its `place()` helper; lists ~40 lines and half of every batch |
| 7 | a dry run on the write verbs | `add\|apply … --dry-run`, printing the settled tree and lint, writing nothing | atoms, lists, detail A | not lines but cycles; lists: *"would have collapsed my four rebuild cycles to one"* |
| 8 | slice a tall render | `shot … --slice <points>` writing `out-01.png…`, and/or `--crop x,y,w,h` | detail A | detail A's 9-line PIL cropper, *"and every agent after me pays it again"* |
| 9 | a broadcast edit | `set <file> --match 'name:Button * Text' kind.fontSize=14`, printing the match count | atoms | zero lines directly; removes *the reason the generator exists* |
| 10 | re-run a batch over an existing root | `apply … --replace-root "Meeting Candidate Update"` (rm, re-apply, keep x/y) | detail B, lists (as `pack` / `--at-x`) | detail B's `rm`+`apply`+recompute-x loop; lists' five hand-computed `set common.x=` calls |
| 11 | copy with rename | `cp … --rename-prefix "Pre "="Gate "`, or `--prefix` on a deep copy's descendants | detail A, detail B | detail A's whole board-3 generator path; detail B's two extra lines per copy |
| 12 | document-level style defaults | a `defaults` block, or `vars` past colour so `"fontFamily":"$--sans"` resolves | atoms | atoms' `txt()` helper, repeated across ~600 text nodes |

Example invocations, as the agents proposed them (1 twice, because the two spellings differ):

```bash
woodcase cp mobile.pen "Swatch" "Tok Colours Body" --each colours.jsonl --as atoms
#   colours.jsonl, keys exactly as the cp verb takes on argv, one object per copy:
#   {"common.name":"Swatch --paper","Chip/kind.fills":"$--paper","Name/kind.content":"--paper"}

woodcase cp design.pen "Ledger Row" "Meetings List/Rows" --each rows.jsonl \
  --bind common.name='Row {i}' \
  --bind 'Ledger Row Body/Ledger Row Line1/Ledger Row Title/kind.content={title}' --as lists
#   rows.jsonl: {"title":"Acme Project Connect","meta":"Jul 31 · 10:29 AM · …"}

woodcase measure design.pen --font "Libre Franklin" --size 14 --weight 600 \
  --max-width 277 --ellipsis -F strings.txt --json
# → [{"text":"Acme + Globex - VP of Supply Chain Search","width":366.0,"fits":false,
#     "truncated":"Acme + Globex - VP of Supply Chain S…","truncatedWidth":277.0}]

woodcase def slots <file> "Update Block Proposed" \
    field=Upd/Head/Field.content  mark=Upd/Head/Mark.ref  now=Upd/Now/Value.content
woodcase cp <file> "Update Block Proposed" @upd --set field=State now=Illinois

woodcase shot design.pen "Meeting Screening Gated" --out board3.png --scale 1.6 --slice 900
woodcase set mobile.pen --match 'name:Button * Text' kind.fontSize=14 --as me
```

## 1.3 Two discoveries: a feature that exists undocumented, and one nobody mentions

**`override <instance>/<child> enabled=false` already expresses structural variants.** `atoms` found
this *while writing its own report*, having spent ~180 lines reimplementing it in Python:

```bash
woodcase set  design.pen Row common.reusable=true --as me
woodcase cp   design.pen Row document common.name=Copy2 --as me
woodcase override design.pen Copy2/Refusal enabled=false --as me
#   Copy2/Refusal does not set enabled in Row — the override adds the property
#   rather than replacing a value

woodcase tree design.pen Row            # frame Row     0,0 300x81
woodcase tree design.pen Copy2 --expand # ref   Copy2   0,0 300x59
                                        #   text Refusal   -      <- no rect at all
```

81 to 59: a disabled child leaves layout entirely and `tree` prints `-` for its rect. `atoms`:
*"That is the variant mechanism … A superset definition plus `enabled=false` covers every one of my
eleven form-row states, all three update-block states, the two mastheads, both checklist lines, and
both action bars. **The defect is documentation, not capability.**"* It also flags that the
divergence line woodcase prints *"reads like a mild complaint about something unusual, when it is in
fact the sanctioned idiom."* `detail A` independently asked for this exact feature, not knowing it
exists, and rebuilt four rows by hand for want of it. `atoms` is even-handed about the ergonomics
(a superset definition switching six of ten children off *"is not obviously more readable than a
function with keyword arguments"*), but it propagates, and it is already in the tool.

**A `ref` with a `descendants` map can be written directly inside an `add` subtree.** `detail A`
calls this *"the single biggest win of the build and I found it by guessing"*:

```json
{"type":"ref","name":"Plain Page Head","ref":"40AEk",
 "descendants":{"yO3SC":{"content":"Alex Rivera and Sam Chen"},
                "uDTGV":{"content":"","height":0}}}
```

*"It does work, it accepts descendant overrides in the same write, and it turned 'one `cp` per
instance, ~90 commands, plus an `override` per tweak' into **three `add` commands for three whole
artboards**."* `woodcase schema ref` documents the shape; `help design` and `add --help` never say
an `add` subtree may contain refs. `lists` and `detail B` used `apply` batches of `cp`+`override`
pairs instead and never learned it, which is most of what D3 cost them.

## 1.4 The reframing: the goal is not "no code"

`atoms` pushes back on the author's stated goal, and it is the sharpest paragraph in the four
reports:

> **the goal should not be "an agent never writes code" — it should be "the code an agent writes is
> a flat list of `woodcase` invocations."** My generator is not bad because it is Python; it is bad
> because it is Python that *builds `.pen` JSON*, which means it reimplements your document model in
> a second language, and every fact about the design lives in a file that woodcase cannot read,
> lint, or attribute.

Its answer to "should woodcase absorb the generator" is **no**, framed as the report's strongest
praise: *"The generator worked because the file format is plain canonical JSON, the CLI is stateless
with no session or daemon, and `add` takes a whole subtree on stdin … Do not add a templating or
scripting layer; you already have the right composition seam."* The other three converge on that
seam. `lists` wants its deliverable to become *"`rows.jsonl` plus one command anybody can"* rather
than a Python script only it can re-run, and names **derivation** (sorting, pluralising, truncating)
as the residue that belongs outside a design tool. `detail A` and `detail B` say they would write
**no** Python for a job this size given features 1, 2, 3 and 8; `atoms` says it would still write
~150 lines for arithmetic alone, and thinks that is correct.

# 2. The concurrency experiment

Running three agents at once was the point, so: it was uneventful, which is the result.

- **The lock held.** `lists`: *"Three agents wrote one `.pen` for two hours with zero conflicts, zero
  corruption, and no coordination beyond 'don't touch each other's roots'. Not one command failed on
  the lock."* `detail B`: *"several hundred writes, zero corruption, zero retries. Not one `--rev`
  conflict, because I guarded my own root rather than the document."*
- **Root auto-placement composed.** All three name it unprompted; `detail B` quotes the line it
  relied on, `Meeting Candidate Update was placed at x 5278, y 0, clear of the artboards already
  there`. `lint` never reported an overlap.
- **Guards worked as the 2026-08-31 design intended.** `detail B` calls the subtree-rev property
  *"correct and load-bearing for multi-agent work"*, so TCMmx appears to have done its job.
  `detail A` names the residual gap: *"a root-level `add` cannot express 'I don't care what else
  changed'. It already behaves that way, but a reader of the help cannot tell."*
- **The one cross-agent cost was lint scope, and both remedies already exist.** `detail A`: *"`lint`
  exiting 1 on warnings from another agent's root meant I could not use `woodcase lint && woodcase
  shot` as a gate."* `lint <file> <node>` takes a subtree argument and `--severity error` restores
  the `&&` idiom, both in `lint --help` (`Sources/WoodcaseCommandCore/LintCommand.swift:53,59`). The
  previous run's Vw5kC ask has shipped; this is discoverability, the shape of §4's last bullet.
- **Information flowed between agents through the file itself.** The middot warning `atoms` left in a
  `Tokens/Build Notes` node was read and acted on by both detail agents, as the 2026-08-31 report
  claimed of `context`.

# 3. Defects, deduplicated

Severity is the compiler's, reconciled across reports. "Known" cites the woodcase doc that carries
it already.

### D1: `tree` and `shot` disagree about text metrics. **Blocking. All four. NEW.**

The extreme case, from `atoms`: `IBM Plex Mono "·"` at `fontSize: 10` measures **3.09pt** per glyph
in `tree` and paints **5.97pt**.

```bash
cat > /tmp/dot.json <<'JSON'
{"type":"frame","name":"T","layout":"vertical","width":402,"height":200,"padding":16,"gap":4,
 "fill":"#fcfbf9","children":[
  {"type":"rectangle","name":"Ref370","width":370,"height":3,"fill":"#b3261e"},
  {"type":"text","name":"D60","content":"············································································",
   "fontFamily":"IBM Plex Mono","fontSize":10,"fontWeight":"400","fill":"#20241f","width":"fit_content"}
]}
JSON
woodcase new /tmp/dot.pen --as me
woodcase add /tmp/dot.pen document -F /tmp/dot.json --as me
woodcase tree /tmp/dot.pen T          # D60 reports 186pt wide  (60 x 3.09)
woodcase shot /tmp/dot.pen T --out /tmp/dot.png --scale 2   # the dots reach ~358pt
```

This is a **layout-correctness** bug, not a rendering nit. `atoms` had a node `tree` places inside
its row and the renderer places off the image:

```
$ woodcase tree mobile.pen "Card Sentence L2"
text     Card Sentence Glyph            201,0 18x14      <-- tree says x=201, inside the row

$ woodcase shot mobile.pen "Card Sentence L2" --out /tmp/x.png --outline "Card Sentence Glyph"
--outline Card Sentence Glyph (SFg9W) is at 384.0,37.0,15.0,14.0 in layout points, clear of the
rendered node i1cwc at 0.0,37.0,370.0,35.0 — the box would fall off the image.
```

The other three hit the same disease at board scale, and **their readings of the magnitude
disagree**:

| agent | node | `tree` | `shot` | its reading |
|---|---|---|---|---|
| lists | Meetings List | 402×1429 | 402×1465 | *"+2pt per two-line text block … systematic … cosmetic"* |
| detail A | three boards | 1278 / 5151 / 5175 | 1303 / 5220 / 5245 | *"25pt, consistently … it is not a constant, it scales with content"* |
| detail B | three boards | 2503 / 3269 / 1095 | 2543 / 3310 / 1101 | *"~1.5% … I have no way to tell which number to quote"* |
| atoms | proportional faces | | | *"disagree by ~3–15%"*; the middot is *"the extreme case"* |

Only `atoms` takes a side: *"5.97pt is the correct metric (0.6em, IBM Plex Mono's real advance). So
`tree`'s measurement is the wrong one."*

**A mechanism worth checking, from the source rather than from any report.**
`GoogleFontResolver.shared.prepareFonts(for:)` is awaited by `shot` (`ShotCommand.swift:272`),
`render` (`RenderCommand.swift:90`) and the viewer's `RenderCache` (`RenderCache.swift:351`), and by
nothing on the `tree` or `lint` path. If that is the cause, `tree` measures in the fallback face and
`shot` in the real one, which matches every sign in the table (shot always larger), matches the
middot being the worst case, and makes D1 and D2 the same bug. Confirm before designing a fix: an
offline `tree` cannot be made correct by sharing a measurement path alone. Asks converge on one
measurement path for `tree`, `lint` and `shot`; failing that, a lint rule for a painted rect that
differs from the settled one (`atoms`, `detail A`), or `tree --help` saying which number is
authoritative (`detail B`).

### D2: fonts fall back silently, and the Claude Code sandbox triggers it. **Blocking. atoms. Trigger NEW; disease class KNOWN.**

Under the default Bash sandbox, `Fraunces`, `Libre Franklin` and `IBM Plex Mono` all resolve to a
system sans. Same file, same command, sandbox disabled, all three render correctly. Both runs exit 0
and print the identical `scale=2.0 rect=… pixels=804x400`.

```bash
# sandboxed:   woodcase shot fonttest.pen T --out a.png --scale 2   -> everything is Helvetica
# unsandboxed: same command                                         -> Fraunces serif, Plex Mono
```

`atoms`: *"an agent that 'verified fonts' in one mode will confidently mis-render in the other —
which is exactly what happened: my briefing carried a verified ruling that these three families
render by name, and it was false in the mode I was running in."* Second-order: *"layout is measured
in the fallback, so a sandboxed `tree` returns wrong widths and a sandboxed `lint` is checking a
different document than the one that ships."*

Known: the class is on record in
[Google Fonts never actually registered](2026-08-30-font-registration-from-data.md), the same silent
fallback to SF Pro, found by Ben and fixed for the data-registration path. That the sandbox
reproduces it, almost certainly by blocking the fetch `prepareFonts` performs, is new, and the
sandbox is the default mode every Claude Code agent now runs in. Asks in the agent's order: **a
stderr warning naming the family and its substitute**; `woodcase fonts --check <file>`; a non-zero
`lint` on an unresolved family. The third needs a decision, since `lint --help` currently justifies
the opposite (*"Fonts are not checked … lint stays offline"*).

Related and unresolved (`atoms`, NEW): **no italic Fraunces.**
`{"fontFamily":"Fraunces","fontStyle":"italic"}` renders upright, so does `"Italic"`, and
`{"fontFamily":"Fraunces Italic"}` falls back to a sans, *"which is worse than upright serif — it
silently changes the family."* Three attempts, three exit-0s, no diagnostic. One atom ships drawn
wrong because of it.

### D3: `apply`'s `cp` op refuses the path-keyed overrides the `cp` verb accepts. **Blocking. lists, detail B. NEW.**

The most expensive defect of the run by both agents' ranking. The verb works:

```
$ woodcase cp prototype/mobile.pen "Section Head" "MU Attendees" \
    common.name="TST C" "Section Head Line/Section Head Title/kind.content=ATTENDEES" --as detailb
TST C  Jl6UD                                                       # works
```

The identical operation through `apply` is refused:

```
$ cat t.jsonl
{"op":"cp","source":"Section Head","parent":"MU Attendees","props":{"common.name":"TST B","Section Head Line/Section Head Title/kind.content":"ATTENDEES"}}
$ woodcase apply prototype/mobile.pen -F t.jsonl --as detailb
line 0  failed   Section Head/Section Head Line/Section Head Title/kind.content is not a
                 property of a ref — #zjINX accepts nothing: it is not in this document
```

`lists` hit it on all 8 of its components in its first batch (8 failed, 13 cascaded, 6 applied),
same error, different transient id (`#ZEF5Z`). Both note that `apply --help` **asserts the behaviour
the code refuses**: *"props are the same paths, applied to the copy, never to the source."*
`detail B`: *"Both path forms fail, with and without the component root's name as the first segment,
so there is no form to discover by experiment."*

The error text is a defect of its own, filed separately by `lists`: the id it names is the copy that
was then abandoned. `detail B`: *"It reads like a corruption report; it is actually 'I parsed your
key as a flat property name'."* `lists` bisected against the `cp` verb to decode it. Cost: 1+N lines
per placement, ~180 extra JSONL lines out of 430 (`detail B`), a board from 27 ops to 68 (`lists`),
and *"one conceptual act across two lines that can now half-fail"*. Fix both propose: route the op
through the verb's assignment path, choosing `override` or `set` per target as the verb does.

### D4: `apply`'s `add` rejects `"parent":"document"`. **High. lists, detail B. NEW.**

```
{"op":"add","parent":"document","node":{"type":"frame","name":"Board", …}}
→ line 0  failed   document matches no node in this document — check the path,
                   or point it at the `@tag` of an earlier line that creates it
```

`help design` lists `document` under ADDRESSES as valid *"where a parent is expected"* and
`add --help` says *"or `document` for the document root"*, while `apply --help` says only *"omit it
to act on the document root"*. Cost: a 57-line batch cascaded to nothing (`lists`); a 155-line
batch, 0 applied, 1 failed, 154 cascaded (`detail B`). Adjacent to NHkOc from the last run, not the
same bug. Fix: accept it as a synonym.

### D5: a `ref` cannot take children, and no slot is documented. **High. All four. KNOWN.**

> **Correction, 2026-09-02.** This finding is wrong, and it was the most expensive sentence in
> the run. A `ref` *can* take children: `kind.slot` is in the 2.17 format and in the schema, and
> an instance replaces a slot frame's children through a `children` entry in `descendants`,
> nested refs with their own overrides included. Verified live during the audit. What every agent
> hit was the divergence check's message "*the override is stored but nothing will read it*",
> printed because its accepted-key list omits `children` while the patcher honours it. The lie was
> the bug; the capability was never missing. Fix and teaching in [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md) (leaves "Slot filling
> honoured end to end" and "help design").

Known: the [2026-08-31 report](2026-08-31-woodcase-concurrent-dx.md) format-level findings,
*"Instances take no new children, so a container component is chrome only"* and *"`kind.slot` looks
like the intended answer and is documented nowhere the CLI teaches."* Second confirmation, now
costing structure rather than convenience: `atoms` shipped its `Card Panel` **with a prose note
telling downstream agents to rebuild it by hand** (*"a component library with a hole in it"*);
`detail A` re-drew four rows of ~12 nodes because the atom it needed was the atom it had plus a red
asterisk; `detail B` rebuilt six update blocks locally because a slot could not hold a ref, *"the
one place my boards deviate most from 'instance the atoms'"*; `lists` would have made `Page Column`
an atom. Second-order damage: burned by this, `atoms` generalised to *"refs are for leaves"* and
deep-built every composite in Python, which is part of why it did not find `enabled=false`.

### D6: `set` and `override` each name the other for a property neither will set. **High. detail B. KNOWN, parked.**

```
$ echo '{"op":"set","target":"MU Will 1","props":{"kind.alignItems":"start"}}' > a.jsonl
$ woodcase apply prototype/mobile.pen -F a.jsonl --as detailb
line 0  failed   kind.alignItems is not a property of a ref — … accepts `common.context`, …,
                 `kind.descendants`, `kind.ref`, `kind.rootOverrides`

$ echo '{"op":"override","target":"MU Will 1","props":{"alignItems":"start"}}' > b.jsonl
$ woodcase apply prototype/mobile.pen -F b.jsonl --as detailb
line 0  failed   MU Will 1 is a node of its own (…/MU Will/MU Will 1), not a node inside a
                 component instance — use `{"op":"set","target":"MU Will 1",…}`;
                 only a path that steps through a ref can be overridden
```

*"`set` says use override; `override` says use set, by name, in the message. It is a closed loop."*
`kind.rootOverrides` is listed as accepted and is undocumented in `help schema`. Cost: seven
checklist lines rebuilt as local frames, 28 nodes, to avoid one property. Known: backlog,
*2026-08-30 — Addressing an instance's root as an override target*, whose un-park trigger is *"when
`override` grows a way to write `rootOverrides`"*. `detail B` is that trigger arriving.

### D7: `override` by name path into an instance fails where an id path works. **Medium. detail A. PARTLY KNOWN. Contradicted by lists.**

> **Correction, 2026-09-02.** `lists` was right. A name path into an instance works when it
> names every frame of the definition's own tree (`Inst/Body/Title`); `detail A` skipped a frame
> and got a near miss that offered the *definition's* copy, which is the whole defect. Verified
> live. The near-miss text is fixed under [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md).


```
$ woodcase override prototype/mobile.pen \
    "Pre G3 R2 Desired salary (low)/Row Prefilled A Value" 'content=\$120,000' --as detaila
Pre G3 R2 Desired salary (low)/Row Prefilled A Value matches no node in this document;
nodes with that name: Row States/.../Row Prefilled A Value (NvOPz) — run `woodcase tree` ...

$ woodcase override prototype/mobile.pen \
    "Pre G3 R2 Desired salary (low)/NvOPz" 'content=\$120,000' --as detaila
Meeting Screening Prefilled/Pre Card Panel/Pre G3 R2 Desired salary (low)  Gj03g   # ok
```

`detail A` concludes name paths into an instance do not work at all, and that *"two of the three
places a reader looks are wrong"*: `help design` shows `Orders/Value`, `override --help` repeats it,
only `tree --help` says "by id path". **`lists` contradicts this**, having overridden deep name paths
all session (`@row/Ledger Row Body/Ledger Row Line1/Ledger Row Title`). The likely reconciliation is
finding #4 of the 2026-08-31 report, *"a path must name every frame of the definition's own tree"*.
If so the capability is fine and **the error message is the whole defect**, since it offers the
definition's own copy as the near miss. `detail A` calls it *"the only place woodcase told me
something untrue about my own file."*

### D8: `textGrowth` fixed boxes render nothing. **High, because silent. atoms. NEW.**

`"textGrowth": "fixed-width-height"` with a height too small for the content *"renders nothing at
all, not clipped-with-part-visible, nothing"*, while `tree` reported a healthy `370x13` node and
`lint` was clean. The mirror case, `"fixed-width"`, reports one line's height and paints two, so the
overflow lands on whatever is below: `"Jordan Lee"` in Fraunces 17 at `width: fill_container` in a
98pt frame reports `98x21` and paints two lines. Ask: a lint rule for content that does not fit its
fixed box. The tool knows both numbers.

### D9: `--outline` refuses off-image nodes. **Medium. atoms. KNOWN AS A DECISION, contested.**

```
--outline Card Sentence Glyph (SFg9W) is at 384.0,37.0,15.0,14.0 ..., clear of the rendered node
i1cwc at 0.0,37.0,370.0,35.0 — the box would fall off the image.
```

`atoms`: *"A node that has escaped its parent's box is precisely the bug I am trying to see. Refusing
to draw the box is the tool declining to show me the defect."* The refusal is nonetheless what
exposed D1, because it prints the render's real coordinates. Known and deliberate:
[2026-08-30-handoff-viewer-issues.md](2026-08-30-handoff-viewer-issues.md), *"`--outline` on a node
outside the shot is a usage error (never a silent no-op)."* `atoms` contests it: draw it clamped with
a caption, or add `--pad <points>`. Its stronger ask is `shot --json` returning every rendered rect,
which *"would turn an accident into a tool"*.

### D10: any content string starting with `$` is read as a variable reference. **Medium. lists, detail A. KNOWN (IAZIe); the reports disagree on whether it is fixed.**

```
error unresolved-variable  …/Pre G3 R2 Desired salary (low) (Gj03g)  still refers
to `$120,000` after variable resolution: no variable of that name is defined for
this theme.
```

`lists` says *"There is no documented escape."* `detail A` says the opposite and used it: *"The
escape (`\$120,000`) is documented in `schema`'s footer."* `detail B` was taught it by a divergence
line on a write. Read together, the escape exists and `lists` did not find it, so IAZIe is at least
partly fixed and what remains is discoverability plus `detail A`'s design question: *"resolve
`$name` only where the property's type is a variable-capable non-string … an undefined `$120,000`
should be stored as text with a warning, not stored as a dangling reference."* It also notes lint is
all that stands between this and shipping: *"a design that only lints clean by accident is one
`lint` skip away."*

### D11: `duplicate-name` and instancing fight each other. **Medium. lists, detail B; praised by atoms. NEW feedback on a check that shipped after the last run.**

The check is new since 2026-08-31 (ask #3 there, issue Gb9C7) and all three agents who met it call
the message excellent. The interplay is the problem. **An instance can never keep its component's
name** (`lists`): `cp` names the copy after the source, so `Meetings List/Masthead (6UuiF)` collides
with `Atoms/…/Masthead (ze6B4)` and every ordinary placement is lint-dirty, eight warnings on its
first board. It prefixed every node on every board (`MTG`, `MTGF`, `MTGE`, `ENT`, `CO`) to escape,
and proposes either a disambiguated default copy name or exempting an instance whose name equals its
definition's. **A deep `cp` keeps its children's names** (`detail B`): four warnings, and with no
`--rename-children` it passed `common.name` per child, *"two more lines per copy, entirely
mechanical."* `atoms` had hand-prefixed all 64 components *"on faith"* against a problem it assumed
was unchecked, and found the check only while writing its report.

### D12: `lineHeight` is a multiplier and `schema text` does not say so. **High, because silent. detail B. NEW at the CLI surface.**

`woodcase schema text` gives `kind.lineHeight  lineHeight  number | $number`. Every other length in
the schema is points, so `detail B` wrote `lineHeight: 23` for 15pt Fraunces and woodcase
multiplied: **the board settled at 4754pt instead of 2503**, with no warning, no lint entry, no
divergence sentence. The semantics are right and documented elsewhere in this repo
([codegen notes](2026-03-28-codegen-swiftui.md) call it a multiplier); the CLI's schema line is the
gap. Ask: `number (multiple of fontSize)`, plus a lint rule for a line box more than ~4× its font
size.

### D13: `tree --json` mixes coordinate spaces. **Medium. lists, detail A, detail B. PARTLY KNOWN.**

Depth-0 rows carry the root's absolute canvas x, deeper rows are parent-relative, and an instance's
descendants are in *definition* coordinates. No flag distinguishes them and neither `tree --help`
nor `help design` names the convention. `lists` wrote a bounds check and got *"189 false positives
out of 190 nodes"*; `detail B`'s first "is anything past x=402?" script produced `-5262`. Known as an
engine fact (gotchas, 2026-08-29, *"`PenLayoutEngine` rects are parent-relative"*), undocumented at
the CLI. Asks: `--coords absolute|relative`, an `absRect` key, or one sentence in `tree --help`.
`detail B` adds that `overflowAxes` is the right check and does work.

### D14: `rm` plus re-`add` marches a rebuilt root rightwards. **Medium. lists, detail B. NEW.**

Three rebuild cycles moved `lists`' boards from x=6282 to x=11302 and left *"a 2610pt hole in the
middle of the canvas that no verb offers to close"*, closed by hand with five computed
`set common.x=` calls. `detail B` hit the same, notes `replace` keeps position and it should have
used it, and asks that `rm` of a root at least print the x/y it frees. Other asks: `--at-x` or
`--reuse-space` on a root add, a `woodcase pack` that reflows roots with the 100pt gutter, or
`apply --replace-root <name>`.

### D15: no `--dry-run` on the write verbs. **Medium. atoms, lists, detail A. KNOWN.**

Known: ask #2 in the [2026-08-31 report](2026-08-31-woodcase-concurrent-dx.md). Re-asked from three
angles. `atoms` wants `add --dry-run` to settle and print what `tree` and `lint` would say, its loop
having been rebuild, lint, shot, look, ~20 times; `lists` applied a 66-line batch to discover 8
invalid lines and says a dry run *"would have collapsed my four rebuild cycles to one"*; `detail A`
notes every cycle mutates a file two other agents are writing.

### D16 to D19: minor, one line each

- **woodcase edits the repo's `.gitignore`** (atoms; KNOWN and deliberate, specified in
  [the agent-first plan](2026-08-30-agent-first-cli-and-viewer-plan.md)). The behaviour is
  defensible and the comment is well written, but an agent under "touch no repo file but your own"
  spent a `git diff` and a `git log` working out whether it had broken that rule. Ask: print one
  line when you do it, and offer `--no-gitignore`. *"Do it once, loudly, rather than never
  mentioning it."*
- **A `--props` advisory is printed inside a table row** (detail B; PARTLY KNOWN, 173Ys), breaking
  column alignment for the rest of the table, and it is the only signal that `kind.fill` is wrong
  without giving the right spelling, `kind.fills`. `lists` files the same behaviour as a severity
  complaint: on a collapsed ref it reads as a failure when it is a hint that `--expand` was
  forgotten. Fix: stderr, or after the table.

> **Correction, 2026-09-02.** The advisory already goes to stderr, after the table. What the
> agents saw was stdout buffering: the table was still in the buffer when the stderr line was
> written, so on a shared terminal it landed mid-row. The fix is a flush before writing stderr,
> not a change of stream. Under [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md) ("Small CLI fixes").

- **No `--version`** (atoms, lists; NEW). `woodcase --version` answers `Error: Unknown option
  '--version'`; the best identification available was the binary's size and mtime plus the
  `"version": "2.17"` format string. *"An agent writing a bug report cannot say which woodcase it
  hit, and neither can the person reading the report six weeks later."*
- **`-F /dev/null` is rejected** (detail B; NEW): `Cannot open /dev/null: no such file, or not
  readable.` An empty batch is a reasonable no-op probe.

# 4. Friction and documentation gaps

- **Two property vocabularies.** All four, and the previous run. `set`/`cp` take `kind.content`;
  `override` and `add` subtrees take `content`. `detail B` sharpens it into a broken workflow:
  *"`get` returns raw keys … the natural workflow, `get` a node I like, edit the JSON, feed it to
  `set`, does not work, because `get`'s own output is in the vocabulary `set` refuses. `fill` vs
  `fills` is the sharpest edge: they differ by one letter and mean the same thing in different
  rooms."* All four propose the same fix, and `atoms` notes the precedent exists inside `cp`, which
  already translates when the copy is an instance.
- **`cp`'s override paths are rooted at the copy, and `help design` implies otherwise.** ADDRESSES
  teaches *"a path of names, from any ancestor"*, true for addressing and false for `cp` props.
  `atoms`: *"One sentence in `cp --help` — 'the path is the full path from the copied node, not a
  suffix' — closes this."* `lists` wants the clause in `help design`: you may **start** at any
  ancestor, not **skip** levels.
- **`fill_container(200)` is undocumented outside a lint message**, and **`lint`'s checks are not
  enumerable** (`lint --help` describes them in prose but names no check **ids**, though `--exclude`
  takes ids and `LintCheck.swift` holds a clean 15-case enum). `atoms` engineered around
  `duplicate-name` for a whole session without knowing it existed, and learned `fill_container(200)`
  only because a warning suggested it: *"The lint taught me a language feature."* Ask: `lint --list`,
  and the fallback form in the schema's value grammar.
- **`get` has no depth and `--props` takes one path.** `lists` ran a 15-node `for` loop of `get`
  calls to learn the atom set. (`detail B` shows a comma-separated `--props` being parsed, so the two
  reports differ; see §8.) Related: overriding a descendant needs its full structural path, so
  `lists` typed addresses like `Sort Line Default Line/Sort Line Default Value/Sort Line Default
  Value Text`. Ask: `tree <ref> --expand --paths`.
- **Small documentation gaps.** `"reusable": true` works in an `add` subtree and no example shows
  it; the schema table prints codec paths beside `.pen` keys without saying which column an `add`
  subtree wants; `shot --outline` echoes the node's id path rather than the address passed; there is
  no vocabulary for a deliberate spacer frame, though `detail A` explicitly asks that
  `empty-fit-content` not be "fixed" into false positives.
- **Agents stop reading at `help design`.** `detail A`'s own diagnosis, filed against itself after
  retracting a complaint: *"Both are a signal that `help design` is doing so much work that agents
  stop at it. A 'see also `<verb> --help`' line at the end of `help design` would have caught me."*
  The same shape produced its lint-scope complaint (§2) against two flags that already exist.

# 5. Wished-for features

| feature | asked by | note |
|---|---|---|
| Dashed and dotted strokes (`strokeDash: [on, off]`) | atoms | ~30 nodes in this file are middot text standing in for `border-bottom: 1px dotted`, and that hack is what exposed D1. `dashPattern` was **deliberately dropped** in the [2.17 migration](2026-08-29-pen-2.17-migration.md) because Pen cannot produce it, so this is a format question. |
| Flex wrap (`"wrap": true` on a horizontal frame) | atoms, detail B | `atoms`: *"the single highest-value layout feature missing."* Its card sentence is five hand-chosen line breaks that go wrong the first time the copy changes. `detail B`: wrap plus spans *"would delete ~60 lines of my generator."* |
| Per-span text styling (rich runs) | atoms, detail B | One text node is one family, size and fill; real UI copy is not. Also a format question: rich text was removed in 2.17. |
| `shot --slice <points>` or `--crop x,y,w,h` | detail A | 5,175pt is 8,392px at scale 1.6. *"A tool whose whole review loop is 'look at the PNG' should not hand back a PNG nothing can display."* |
| `shot --json` with every rendered rect | atoms | Turns the `--outline` refusal accident into a debugger, and makes D1 self-diagnosing. |
| `woodcase fonts --check <file>` | atoms | Names each family a document asks for and whether it resolved. |
| `set --match <selector>` | atoms | *"Deletes ~0 lines directly and removes the reason the generator exists."* |
| `cp --rename-prefix` | detail A | A copied 557-node root shares every name with its source, so *"every subsequent address is ambiguous."* |
| `lint --list`, `--version` | atoms, lists | See §4 and D18. |
| A lint for a node that renders outside its parent | atoms, detail A | `clipped` covers the settled-rect case; nothing covers a render-versus-settle disagreement. |

# 6. What to keep

Each named unprompted by two or more agents.

- **The three-document help system.** `atoms`: *"the best thing about this tool, and it is not close
  … `--help` → `help design` → `help recipes` → `schema <type>` → `<verb> --help` got me from cold to
  building without a single guess about grammar."* `detail A`: *"The help is the manual, and it is
  genuinely sufficient. I never went looking for docs outside the tool."* Specifically: `help design`
  teaches the model rather than the flags, and its root-placement sentence meant three of four agents
  *"never thought about artboard placement once"*; `help recipes` is runnable and was lifted
  verbatim; **every verb's `--help` carries a worked example**, and `cp --help`'s nested-key example
  is what told `detail A` nested overrides existed at all.
- **Error messages that name the near misses and hand back the working address.** All four. `atoms`:
  *"It told me the rule I had got wrong and handed me the working address in the same breath. This is
  the standard the rest of the errors should be held to; most already are."* `detail B` keeps the
  shape even where the advice is wrong: *"`kind.alignItems is not a property of a ref — … accepts
  common.context, …` is how an error should read."*
- **`lint`, and warnings that carry the fix.** `atoms` ran it after every one of ~20 rebuilds *"and
  it never gave me a false positive"*. `detail A`: *"`lint` earned its keep in one line"*, catching
  the `$120,000` capture nothing in the render showed. Keep the habit of naming the node path **and**
  the value.
- **`tree` as the read.** All four. Type, name, settled rect and id per row, the revision in the
  header, and **every row's address is one any other verb accepts**, which `lists` calls the property
  that makes the tool scriptable. `detail A` checked *"~90% of the build from `tree` alone."* `lists`
  singles out `--expand` printing `Name +2` for a ref's override count.
- **Whole-subtree `add` with nested `children`.** `atoms`: *"three JSON files, three roots, three
  commands … the difference between a tractable generator and a nightmare; **do not deprecate this in
  favour of batch-only**."* `detail A` used it in place of `apply` entirely.
- **`apply`'s batch protocol where it is used.** `@tag` forward references (`detail B`: *"the best
  thing in the tool … a 196-line batch that creates a whole artboard is one command"*), the per-line
  report, and cascade attribution: *"No other batch tool I have used explains a skip by naming the tag
  that was never minted. Keep it, and keep `--retry <report.json>`."*
- **Variables, including alpha.** `atoms`: *"`vars list` shows a live reference count per variable.
  This is the mechanism that lets me hand a component library to three downstream agents and be
  confident none of them writes a stray hex."* Colour alpha composites correctly over every ground,
  *"the whole reason the file is faithful rather than approximate"*. `detail B` singles out the
  divergence sentences on a write as *"cheap, unprompted, exactly the fact I wanted."*
- **`shot --scale` beating `--max`** (three of four used it as their real review tool), **the lock and
  the no-daemon model**, **root auto-placement**, **`lint` printing nothing on success**, **the
  exit-code table**, and **`context` as an inter-agent channel**.

# 7. The merged top ten

Ranked by time saved across the four agents, not by size of change.

1. **Make `apply`'s `cp` accept path-keyed props**: two agents' worst defect, ~220 generated lines
   and two restructured batch designs. (§3 D3)
2. **One text-measurement path for `tree`, `lint` and `shot`**: the only correctness bug that
   undermines the read-write-verify loop; check whether `prepareFonts` on the read path is the whole
   of it. (§3 D1)
3. **`woodcase measure`**: three agents each built a throwaway `.pen` as a ruler, and it makes D1
   diagnosable by anyone. (§1.2 #2)
4. **`cp --each <rows.jsonl>`**: the one verb all four proposed independently, turning the repetitive
   80% of a screen into a data file plus one command. (§1.2 #1)
5. **Parameterised components, and a slot that accepts children including a ref**: all four; today an
   atom's interface is its anatomy plus a prose note. (§3 D5, §1.2 #3)

> **Correction, 2026-09-02.** The slot half already works (see D5). The parameter half
> exists too: `common.metadata._props` has been the React emitter's prop declaration since it
> shipped, and the editing verbs now learn to read it under [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md).

6. **Document `enabled=false` as the variant mechanism**: one paragraph, ~180 lines of
   already-written Python deleted, best value-to-effort ratio in the run. (§1.3)
7. **Document that a `ref` may be written inside an `add` subtree**: zero code, and the difference
   between 3 commands and 90 for a screen full of instances. (§1.3)
8. **Warn on stderr when a `fontFamily` does not resolve**: one line, and the sandbox makes silent
   fallback the default mode every agent now runs in. (§3 D2)
9. **`--dry-run` on `add` and `apply`**: three of four here plus the last run; every failure they hit
   was knowable before a byte was written. (§3 D15)
10. **`shot --slice`**: a 5,175pt board is unreadable at `--max` and undisplayable at `--scale`, so
    every agent building a long page writes the same cropper. (§5)

Nearly free, and each cost someone real minutes: say `lineHeight` is a multiplier in `schema text`
(D12); accept `"parent":"document"` in `apply` (D4); name the coordinate convention in `tree --help`
(D13); add `--version` and `lint --list` (§3 D16-19, §4); announce the `.gitignore` edit (§3 D16-19);
one sentence in `cp --help` about override paths being rooted at the copy, and a "see also `<verb>
--help`" line at the foot of `help design` (§4).

> **Amended after the second wave (§9), which covers three editing agents.** Two entries outrank
> items on the list above, so the ten now reads: **1** `apply` `cp` path-keyed props, **2** one
> text-measurement path, **3** `woodcase measure`, **4** `cp --each`, **5** parameterised components
> and slots, **6 (new)** *document that overrides are id-keyed, and that `replace` on a live
> definition silently drops the overrides whose ids it does not carry forward* (§9.1), **7** document
> `enabled=false`, **8** document `ref`-in-`add`, **9 (promoted from §1.2 #11)** `cp --rename-prefix`
> (§9.5), **10** warn on an unresolved `fontFamily`.
>
> Why each moved. **The id-keying documentation enters at 6** because it is the same class as items 6
> and 7 above, a fix that costs a paragraph against a feature that already works, but its absence
> causes silent loss of overrides across 242 instances rather than wasted typing, and it actively
> misled a brief written from this document's own §§1 to 8. **`cp --rename-prefix` enters at 9**, one
> place higher than the first amendment put it, on `fixes2`'s exact figure: one root of 78
> descendants copied produces **78 `duplicate-name` warnings**, and clearing them cost a 10-line
> scratch script, a generated 78-line `apply` batch issued by id, and a re-lint, for what one flag
> does inside the original `cp` (§9.5). That is four of seven agents, the top item of both editing
> agents that copied a root, and the only entry on this list with a measured cost that recurs on
> every single use. It passes the `fontFamily` warning, which stays at 10: cheaper to build, but its
> measured cost was one agent's ~25 minutes rather than a tax proportional to subtree size.
>
> Displaced, and neither weakened: **`--dry-run`** moves to 11, now also covering `rm --dry-run`
> (§9.4); **`shot --slice`** moves to 12 and is the stronger for it, with four independent asks
> (detail A's `--slice`, `fixes`' `--rect`/`--clip`, `detailc`'s "legible by default", and `fixes2`'s
> `--crop`, which adds the best argument of the four: a **junction** is where two nodes meet and is
> therefore not a node, so `shot <node>` cannot frame the most common kind of review finding, §9.7).
> New and just outside: `get <definition> --instances` (§9.6), `override --unset` with the null
> warning inverted (§9.3), `activity --since <rev>` in the documented loop (§9.4), and a `find`/`query`
> read verb (§9.7). One item escalates rather than moves: D13 was filed as "name the coordinate
> convention in `tree --help`" and is now four agents asking `tree` to **emit** absolute rects, since
> half of `fixes2`'s sweep script re-derives what the layout engine already computed.

# 8. Where the reports disagree

Recorded rather than resolved.

- **The size and shape of the `tree`/`shot` gap** (D1): *"+2pt per two-line text block, cosmetic"*
  (`lists`) against *"25pt, scales with content"* (`detail A`) against *"~1.5%"* (`detail B`) against
  *"3–15% on proportional faces"* and 93% on the middot (`atoms`). Only `atoms` says which side is
  wrong.
- **Whether a `$` literal has an escape** (D10): `lists` says none is documented; `detail A` says
  `\$120,000` is in `schema`'s footer and used it; `detail B` was taught it by a divergence line.

> **Resolved, 2026-09-02.** `\$` is documented in `schema`'s footer; `detail A` was right.
> It is now also in `help design` under [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md).
>
> **Correction, 2026-09-02, later the same day.** The finding's premise is also stale: a bare
> `$name` in *text content* that names no variable in the document is restored as a literal,
> draws, and lints clean. Only a name the document defines substitutes, and only non-text
> properties keep a dangling reference. So `content=$120,000` never needed the escape;
> `content=$--price` does when `--price` exists. Verified against the binary by the teaching
> leaf; `help design` now states the real rule.

- **Whether a name path can address into an instance** (D7): `detail A` says only the id works,
  `lists` used deep name paths all session. Probably the every-frame-must-be-named rule from the
  2026-08-31 report, in which case the defect is the error message.

> **Resolved, 2026-09-02.** The every-frame rule; see the correction under D7.

- **Whether the rebuild loop is a tool gap** (§1.1c): `atoms` says a targeted edit should be made
  cheaper than a rebuild (`set --match`, real definition propagation); `lists` and `detail A` say
  regeneration from a declarative source is the correct answer to design iteration and no verb should
  try to remove it.
- **Whether `--props` takes a list**: `lists` asks for comma-separated paths as a missing feature,
  `detail B` shows `--props kind.content,kind.fill` being parsed. One of them is on a different
  build, which is the `--version` point.

> **Resolved, 2026-09-02.** It takes a comma list on every build; `detail B` was right and
> no build difference was involved. `help design` now says so under [the follow-up plan](2026-09-02-teach-the-cli-what-it-does.md).

- **Internal to `atoms`**: its §5 calls the generator "~900 lines", its appendix counts 867.

# 9. Second wave: editing in place

*Appended later on 2026-09-01, after §§1 to 8 were written, from three more agents who **edited**
the file rather than building it: `fixes` (leaf GOb0A) revised seven reusable definitions under 242
live instances, renamed children, re-pointed twenty list rows onto a new atom, reverted a margin
convention on four boards and deleted a root; `detailc` (leaf HvqRq) replaced two 5,000pt roots with
four paged boards built from another agent's root chrome, ~130 writes, concurrently with `fixes`;
then `fixes2` (leaf KrcRl) applied four review rulings in a round-two pass over the finished 15-root
file. Numbered 9 because §§7 and 8 already existed; placed here because the ranking below now
accounts for it.*

**Headline: editing an existing file is a different tool from building one, and the verbs are
further along than the documentation.** None of the three wrote a build generator, a first for this
file: `detailc` notes *"The three agents who worked on this file before me each shipped a
`*-build.py`; my record is nine hand-written JSONL batch files that read as a plain account of what
was done. I take that as evidence the verb set is close to sufficient."* The code that remains is
all read-side or rename-side, and §9.6 maps every line of it onto a missing verb. What broke was
knowing which verb is safe.

## 9.1 Revising a live definition: `replace` is the wrong verb, and the docs imply the opposite

> **Correction to the brief `fixes` was given.** That brief (written from the build agents' reports,
> which are §§1 to 8 of this document) told it to `replace` component subtrees and to *"KEEP every
> existing child NAME stable, or the overrides the screen boards wrote against those paths break"*.
> **That premise is false, and backwards.** `fixes` read the file before acting and found:

```json
"descendants": { "uDTGV": {"content": "", "height": 0},
                 "yO3SC": {"content": "Alex Rivera and Sam Chen"} }
```

**An instance's `descendants` map is keyed by the definition's child IDs, not by names.** So
renaming a definition's children is free, and `replace`, which frees the ids it swaps out and mints
new ones for anything you do not write an id for, is the operation that actually breaks overrides.
`fixes` states the missing sentence:

> Rebuilding a reusable component with `replace` silently drops every override any instance wrote
> against a child whose id the new subtree does not carry forward.

It wants that in `woodcase replace --help` in bold, next to *"Rebuilding a reusable component is the
point of the verb, and every instance follows the new contents"*, because *"as written, that sentence
reads as a promise that instances survive."* This is the same underlying fact that surfaced in the
first wave as D7 (a name path into an instance failing where an id path works): ids are the
addressing currency inside an instance, and two of the three places a reader looks say otherwise.

The house idiom `fixes` recommends instead, with three cases it verified:

* add a child: `cp` or `add` into the definition (existing ids untouched)
* change a child: `set` on that child
* rename a child: `set common.name` (overrides are id-keyed, so this is safe)
* remove a child: `rm`

`cp "Provenance Mark A" "Update Block Proposed Head"` put a ref to one component *inside another
component's definition* in one command, and *"nested overrides through two instance hops resolve"*.
Renaming the whole `Row Required` definition and its 12 descendants (14 `set` lines in one `apply`)
while an instance on another board pointed at it left that instance *"with both of its overrides,
rendering identically"*, verified by shot. Renaming `Pager Newer`/`Pager Older` did the same.

## 9.2 `override … enabled=false` in production: confirmed, and still undocumented

The variant idiom §1.3 found by accident is now used deliberately. `fixes` applied it to a tag row
that had grown a sixth chip: *"One line per instance, no variant component, no duplicated subtree,
and the instance renders byte-identical to what it drew before I added the sixth chip. This is
genuinely better than the Figma-style 'make a variant' workflow, and it composes with the id-keying
above: the `enabled` entry survives a rename of the node it points at."* It knew to write it only
because its brief said so, and files the same documentation gap: `enabled` is absent from
`override --help`'s examples, and `help schema` lists `common.enabled` under the *codec* vocabulary
while `override` takes the raw `enabled`. Its proposed line: *"removing a child from one instance's
layout is `override <instance>/<child> enabled=false`"*, because *"it is the answer to the most
common question an editor has."*

`fixes2` is the third confirmation and the cleanest run of it: the ruling *"the first row after a
section head drops its top rule"* went out as one `apply` batch across seven boards, *"first try, no
surprises. Layout reflowed by exactly the 1pt the rule occupied."* Its complaint is about the
**severity of the note woodcase prints back**, once per line, on every one of them:

> `…/Attendee Row Top does not set enabled in Attendee Row — the override adds the property rather
> than replacing a value`

*"That is a true and useful statement, but it is emitted at a severity that reads like a warning,
once per line, for what is the single most idiomatic thing you can do to an instance. I stopped and
re-read the batch report twice to be sure nothing had failed."* Ask: suppress it for `enabled` and
`opacity` specifically, or demote it to something visibly informational, *"because adding a property
the definition never set is the normal case for a variant."* This is the same observation `atoms`
made in §1.3 from the other end (the line *"reads like a mild complaint about something unusual,
when it is in fact the sanctioned idiom"*), now with a cost attached: two re-reads of a clean
seven-line report.

## 9.3 `override <prop>=null` writes a null; it does not remove the override. **High. fixes. NEW.**

Four boards carried `{"op":"override","target":"MTG Footer/Footer Body","props":{"padding":[16,16]}}`
and `fixes` wanted the definition's own `padding: [16,0]` back. `help design`'s *"null clears one"*
reads as "remove the override"; it writes `{"padding": null}` into the `descendants` map, which
clears the property on the merged node, so the footer lost the definition's padding and **went from
63pt tall to 31pt.**

```
woodcase override f.pen Inst/Body padding='[16,16]' --as a   # add an override
woodcase override f.pen Inst/Body padding=null --as a        # intent: drop it
woodcase get f.pen Inst --json                               # -> {"padding": null}, not {}
```

The warning that exists is **inverted relative to the risk**. It fired on the harmless node and
stayed silent on the destructive one:

```
Meetings List Filtered/MTGF Masthead/Masthead Brand does not set padding in
Masthead — the override adds the property rather than replacing a value
```

That printed for `Masthead Brand`, where the definition sets no padding and null is a no-op, and did
not print for `Footer Body`, where the definition does set padding and null destroyed it. Asks, in
the agent's order: a way to **delete** an entry (`--unset padding`, or a token like
`padding=@default`); reverse the warning; say in `help design` what null means for `override`
specifically, since it currently documents null once, for `set`, *"where 'clears the property' is
the whole truth."* Cost beyond the wrong render: with no delete, the only exit is retyping the
definition's value, so `fixes` left four redundant entries that *"will silently stop tracking the
definition if the definition ever changes. I left four such entries in this file and I am not happy
about them."*

## 9.4 Two writers, one canvas: nothing tore, and nothing warned

The concurrency result is again clean at the storage layer and again unhelpful at the workflow
layer. `detailc`: *"A second agent rewrote the atoms I was instancing throughout. Not one torn
write, not one lock error."* Per-command locking held for a sixth agent in a row.

What happened above it: `detailc` deleted `Meeting Screening Prefilled` and `Meeting Screening
Gated`, which `fixes` had just insetted and re-ruled, and re-laid out every root's x including two
`fixes` had moved. `fixes`: *"44 writes, all thrown away. Nothing warned me. Every one of my writes
succeeded; I only noticed because a `shot` came back with an unexpected `rect=` x-origin."* It calls
that the right default for guard-less writes and names the real gap:

- **The document revision is useless as a coordination token in the one case you want one**, because
  it is stale within seconds under a second writer. The per-node rev is the right granularity, but
  *"there is no cheap way to ask 'has anyone else touched anything since rev X?'"*
- **`activity` already answers this and is not in the loop documentation.** `fixes` did not reach for
  it until it sat down to write its report. Ask: a fourth step in `help design`'s THE LOOP, *find out
  what changed under you*, plus `activity <file> --since <rev>` or `--by-others <name>`. *"For a
  multi-agent harness that is the missing verb in the loop, not `undo`."*
- **`undo` is unusable in a shared file**, not because it misbehaves but because its concurrency
  semantics are unstated: *"`undo --as fixes` implies it only reverses mine, but the help does not
  say whether it skips another author's intervening edits or refuses. I could not risk finding out on
  a file with four agents' work in it."* It took a `cp` backup of the whole file instead. One
  sentence in `undo --help` fixes this.
- **Every dimension read in a shared file is a timestamp, not a fact** (`detailc`): `Meeting
  Candidate Update` was 2503pt when read and 2516pt when shot, purely from the other agent's atom
  edits. *"Anything an agent reports as a dimension in a shared file needs the revision beside it."*
- **The guard both wanted does not exist.** Told correctly never to `--guard document=`, `detailc`
  still wanted document scope for its final twelve-line root re-space, because *"the set of roots and
  their positions has not changed"* is exactly the premise to assert. Ask: **`--guard roots`**,
  pinning root identity and x/y but not subtree content, so two agents can re-space and edit content
  concurrently. As it stands it re-read `tree --depth 0` immediately before writing and accepted the
  race.
- **An ordering hazard with no guard rail** (`detailc`): every `cp` of content out of a doomed board
  had to happen before the `rm` of that board, and *"nothing in the tool knows or warns about that"*.
  Ask: `rm --dry-run` printing the subtree it would take. Related, from `fixes`: `rm` of a root
  reports the id and rev but says nothing about what it orphaned; *"a line like `detached 10 instances
  of 7 components` would have told me, without a second read, whether any definition just went to
  zero instances, which is exactly the question you ask before you edit that definition."*
- **One thing to keep, and to document because it is not obvious**: a twelve-line `set common.x`
  re-space batch produced **no** transient `artboard-overlap` warnings even though intermediate states
  overlapped, *"because layout settles once at the end. That is the right behaviour and I would
  document it, because it makes reordering safe."*

> **Partly answered by `fixes2`, later the same day.** The gap above is real for a long session of
> scattered content edits, but not for the case that actually hurt: `fixes2` put
> `{"node":"document","rev":"…"}` on line 0 of its own re-spacing batch and reports *"checked once at
> entry, is exactly the primitive a multi-agent file needs — and the earlier session's note that 'two
> writers re-spacing roots at once got no warning' is answered by it. I used it and it cost nothing."*
> So `detailc`'s wished-for `--guard roots` may be unnecessary: a document guard is cheap precisely
> when the batch is short and structural, and expensive only when it gates a session's worth of
> unrelated content edits. The remaining defect is discoverability plus one inconsistency `fixes2`
> hit: **`apply` takes guards only as a line field, while every other write verb takes `--guard` on
> the command line.** It typed `--guard` first and got `Unknown option`.

## 9.5 `cp --rename-prefix`, the number one ask of two editing agents

Copying a whole root is *"the highest-leverage verb in the tool for multi-board design work"* and its
value is not typing saved: *"it was fidelity to a ruling I did not have to re-interpret."* Ben had
ruled that masthead, footer and card panel sit inside the 16pt gutter, and copying the board that
already did it means *"my four boards cannot drift from that ruling."* The tax:

```
woodcase cp mobile.pen "Meeting Candidate Update" document common.name="Screening Page 1 of 5"
woodcase lint mobile.pen
→ ~90 × "warning duplicate-name  … shares the name "MU Page" with … ; a bare-name address for
   "MU Page" now matches both. Rename one, or address either directly by id"
```

`cp`'s path-keyed props are keyed by the source path and land on the copy, which retitles one child
and does not scale to a subtree, so a lint-clean acceptance criterion cost *"24 hand-written `set
common.name` lines per board, ordered deepest-first so the paths stayed valid, and `sed` to derive
the other three boards."* `--rename-prefix MU=S1` on `cp`, or a `common.namePrefix` prop, *"removes
four files and about a hundred lines of JSONL."*

**`fixes2` then measured the cost exactly**, on one root of 78 descendants copied to make its gated
state board. `cp <root> document common.name=…` *"did exactly the right thing structurally: fresh
ids, refs followed, one command."* Then `lint` printed **78 `duplicate-name` warnings, one per
descendant**, because `cp` keeps names verbatim. What it cost, as it tabulated it:

| step | cost |
| --- | --- |
| `cp … --json` and parse the created tree | 1 command + 1 throwaway script (10 lines of Python) |
| generate 78 `{"op":"set","target":<id>,"props":{"common.name":"S1G …"}}` lines | the same script |
| `apply` the batch | 1 command, 78 report lines |
| re-`lint` | 1 command |

*"So: one flag's worth of work turned into a generated 78-line batch and a scratch script. The
rename itself is mechanical and total: every child got the same prefix substitution."* It notes the
rename was only possible because `cp` answers with the name-to-id tree and `--json` gives it
machine-readably, *"the right design, and what made the rename possible at all. Please keep it."*
Its own spelling of the fix is `cp --rename-prefix S1G` or `--rename 's/^S1 /S1G /'`, *"which would
have kept the whole operation inside woodcase instead of round-tripping through JSON and Python."*

Second-order, and its own ask: **78 correct warnings are a wall.** *"They name both ids and tell you
the fix. As a wall they are close to useless: I could not see whether anything else was wrong in the
document until I had cleared them."* Ask: `lint --group-by rule`, or a one-line roll-up such as
`duplicate-name: 78 (all under Screening Page 1 of 5 Gated)`, *"so a real problem can surface next
to a mass-produced one."*

Fourth and loudest ask for this feature: `detail A` and `detail B` filed it in the first wave
(§1.2 #11), and it is now the **top item of two separate editing agents**, one of them with an exact
per-use figure.

## 9.6 Did any of them write code

**`fixes`: yes, three times, all read-side, and each maps to a missing read.**

1. `json.load` on the file to find every instance, its definition and its override map, *"because
   there is no verb for 'who instances this component?' `tree --expand` walks into instances but will
   not tell you, for a definition, where its instances are. Before you edit any atom in a 242-instance
   file, that is the first question."* Ask: **`woodcase get <definition> --instances`, or a `refs`
   column on `tree`.** This is its #1 request after the id-keying documentation.
2. Generating a 100-line `apply` batch (rm 20 rows, cp 20 instances, 60 overrides) from data it had
   scraped out of the rows it was replacing. *"The batch itself was a pleasure: one write, one
   transaction, one report."* The scraping existed only because of (1) and because there is no bulk
   content read; `tree --props kind.content` truncates.
3. Cropping PNGs, for want of `shot --rect/--clip`.

It explicitly did **not** need code to author subtrees: *"`add -F file.json` with ids left out, and a
`ref` written inline as `{"type":"ref","name":"…","ref":"<id>"}`, is a good authoring surface. That
inline-ref trick is not documented anywhere; I only tried it because a previous agent had found it.
Document it."* That is §1.3's second discovery propagating agent to agent rather than through the
help, which is the argument for documenting it.

**`detailc`: almost none**, and both exceptions map onto its own defects: `python3 -c "print('·'*56)"`
three times to generate dotted-rule strings, and `sed` to derive three scaffold batches by prefix
substitution.

**`fixes2`: ~90 lines across three scripts, and it maps each one to a verb**, which is the tidiest
statement of the gap anyone has filed:

| script | what it did | verb that would kill it |
| --- | --- | --- |
| `KrcRl-scan.py` | absolute-position sweep for colliding hairlines | `tree --json`/`--absolute`, or a `find` verb |
| rename generator | 78 `set common.name` lines from the `cp` report | `cp --rename-prefix` |
| PNG croppers | cut a 804×6644 board render down to the 200pt I cared about | `shot --crop x,y,w,h`, or `shot <node> --context 100` |

The sweep is the interesting one, because it is a *review* task rather than an authoring one: the
ruling was *"find every place a section head's rule sits on top of a row's own top rule, anywhere in
the file"*. With no query verb it ran `tree --expand > file.txt` (2,944 rows) and wrote a 50-line
parser that *"recovers indentation depth, accumulates absolute x/y down the tree, and reports every
pair of ≤2pt-tall rectangles within N points of each other in the same column."* It found the 7 real
collisions and 2 false positives, *"and it also let me prove the sweep was complete rather than
clicking through 15 boards, which is the whole point."* Its verdict on what it needed:

> Half my script is re-deriving what the layout engine already computed. `shot` prints `rect=` in
> absolute document coordinates; `tree` prints relative. Pick one, or offer both. … What I
> emphatically did *not* need was a selector language; I needed the geometry in a shape a pipe can
> eat.

## 9.7 New and sharpened defects

- **`override` on an instance root refuses and names a fix that cannot work** (`detailc`), the other
  face of D6:
  ```
  {"op":"override","target":"Board/Page/My Page Head","props":{"uDTGV":{"content":"","height":0}}}
  → failed  …/My Page Head is a node of its own (…), not a node inside a component instance —
            use `{"op":"set","target":"…/My Page Head",…}`; only a path that steps through a ref
            can be overridden
  ```
  *"`My Page Head` is a ref. The advice is wrong for this case: `set` cannot write a descendant
  override."* The working form steps into the instance and names the descendant with raw props:
  `{"op":"override","target":"Board/Page/My Page Head/uDTGV","props":{"content":"","height":0}}`.
  Distinguish this from D6 before fixing either: `detailc`'s case has a working form the message
  fails to name, while `detail B`'s (a layout property on the ref root itself) has none. Cost: one
  failed line plus one cascaded `mv` in each of four scaffold batches.
- **The middot makes the whole atom library measure-dependent** (`detailc`, sharpening D1). The
  `Row *` atoms are `fill_container` and resize correctly from a 370 measure to 338; the dotted rule
  inside them is a `fit_content` text of 61 middots calibrated to 370, so it *"paints 26pt past the
  panel's right padding, straight through the card edge."* Repro: instance any `Row Prefilled A`
  inside a `fill_container` frame narrower than 370 and `shot --outline` the row. Fixed by overriding
  `content` to 56 dots on 13 instances, *"for what should be one atom property."* Both agents ask for
  a first-class dotted rule (`type: "rule"`, `style: "dotted"`, `width: fill_container`) or honest
  U+00B7 advance measurement, *"which would make the atom library measure-independent, which is the
  real prize."* `fixes` adds: if `tree --props` could report a painted advance, *"the whole class of
  'shorten the rule by five dots' edits becomes arithmetic instead of a screenshot loop."*
- **`shot` is illegible by default on a phone board** (`detailc`, NEW): `woodcase shot mobile.pen
  "Screening Page 1 of 5" --out b.png` answers `scale=0.697 rect=…,402,2295 pixels=280x1600`. *"A
  402-point-wide phone board renders 280 pixels wide, and it is the most common thing anyone will
  shoot in a mobile design file."* Ask: cap by scale rather than long edge, or default to 1:1 under
  some width. Compounds D9 and detail A's `--slice`.
- **No bulk content read**, now asked by five of six agents independently. `detailc` ran `get` about
  thirty times, some in shell `for` loops; `fixes` needed the same; `lists` asked for `get --deep` in
  the first wave. *"The previous agents on this file each dumped an 'atoms-content.txt' by hand for
  the same reason: three of us solved this independently."* Ask: `tree --json --content`, or
  `get --recursive`.
- **No `arrange`/`pack` for roots** (`detailc`, reinforcing D14): *"Four different agents on this one
  file have each hand-computed the same `502` (402 wide + 100 gap) and hand-assigned every x. That
  arithmetic belongs in the tool: `woodcase arrange mobile.pen --pitch 502 --order <names…>`."*
- **Two naming worlds in one schema** (`detailc`, minor NEW): `kind.alignItems` takes
  `"start" | "center" | "end"` while `kind.justifyContent` takes those plus `"space_between" |
  "space_around"`; one is CSS flexbox spelling and the other is not. It guessed `"flex_start"` once.

> **Correction, 2026-09-02.** Not a defect. Both enums are snake_case and neither is CSS
> spelling; `alignItems` simply has fewer values than `justifyContent`. The guess of
> `"flex_start"` was the agent's.

- **`apply`'s report cannot distinguish lines that resolve to the same node** (`fixes`): three
  overrides on one instance print the same path three times. Ask: echo the op name.
- **`tree` gives no absolute rects, and this is now four agents** (`fixes2`, escalating D13 from
  "name the convention" to "emit the number"). *"Half my script is re-deriving what the layout engine
  already computed. `shot` prints `rect=` in absolute document coordinates; `tree` prints relative.
  Pick one, or offer both."* Ask: `tree --json` with absolute rects, or an `--absolute` flag on the
  text form.
- **No query or value-search read** (`fixes2`, NEW). *"A `find` / `query` verb. Even a crude one
  would have done it: `woodcase find design.pen --type rectangle --height '<=2'` → rows with absolute
  rects. Everything else is `sort` and `awk`."* The same wish in miniature: `vars` reports that
  `--fail` has 19 refs but not **where**, so `vars --where <name>` *"would be cheap and would have
  saved me a second pass."*
- **`shot` cannot frame a junction** (`fixes2`, NEW, and the sharpest argument in the crop cluster).
  *"`shot <node>` is exactly right when the thing I want has a name. But a junction, where two nodes
  meet, is by definition not a node, and it is precisely what a review ruling is usually about ('the
  double line under Attendees'). Today the only way to see a junction is to render the common
  ancestor, which for a 3300pt board is a 6600px PNG I then crop in Pillow."* Ask: `shot --crop
  x,y,w,h` in the rendered node's own coordinate space, or `shot A --and B` boxing the union of two
  nodes plus padding.
- **`lint` has no way to group or summarise a mass-produced finding** (`fixes2`, NEW): see §9.5.
  Ask: `lint --group-by rule`, or a roll-up line.

## 9.8 Their ranked top fives, as filed

`fixes`: (1) say that overrides are id-keyed, and warn that `replace` on a live definition breaks the
ones whose ids it does not carry forward; (2) a way to find a definition's instances
(`get --instances` / `tree --refs`); (3) let `override` delete an entry (`--unset`) and invert the
null warning; (4) put `activity` in the read-write-verify loop with `--since <rev>`; (5) document
`undo`'s concurrency semantics, and add `shot --rect/--clip`.

`detailc`: (1) `cp --rename-prefix old=new`; (2) fix the `override`-on-an-instance error message;
(3) a first-class dotted rule node or correct U+00B7 advance; (4) `shot` legible by default; (5) bulk
content read. Honourable mentions: `arrange`/`pack`, a root-scoped guard, `rm --dry-run`, and a
one-line summary from a clean `lint`.

`fixes2`: (1) `cp --rename-prefix <s>` (and/or `--rename <from>=<to>`), *"the single highest-value
fix"*, because copying a root *"is how you make a state board, and today it is guaranteed to leave
the document lint-dirty in proportion to the subtree's size"*; (2) absolute rects out of `tree`;
(3) `shot --crop`, or a two-node union framing; (4) a `find`/`query` read verb, with `vars --where`
as its miniature; (5) quiet the "does not set `enabled`" note, and give `lint` a grouped or
summarised mode *"so 78 instances of one mass-produced warning do not bury a real one"*.

`fixes2` also files the clearest short list of what to keep: `apply` batches with per-line status and
cascade semantics; **guards**, used successfully (§9.4); the refusal that lists every property a node
does accept, *"that one message replaced a trip to `schema`"*; and `shot --scale`, *"good that it
enlarges where `--max` refuses to."* Its one papercut on the keep list is the vocabulary axis §4
already names, with a third spelling added: *"`get` prints the property as `fill`, `add` accepts
`fill`, and `set` requires `kind.fills`. Three spellings of one thing across three verbs."*

## 9.9 Where the second wave disagrees with the first

- **What `lint` should print.** Three positions, all defensible. `detail B` praised silence on
  success: *"Exit code carries it; no ceremony."* `detailc` wants the opposite: *"`lint` clean is
  indistinguishable from `lint` not running. A one-line `0 problems in 1,742 nodes` would let an
  agent report 'lints clean' as evidence rather than as an absence."* `fixes2` wants the same
  treatment at the other end of the range, a roll-up when one rule fires 78 times. One `--summary`
  flag, or a count line on stderr, satisfies all three.
- **Whether guarding at document scope is workable under concurrency.** `detailc` was told never to
  `--guard document=` and agreed, accepting a race on its final re-space; `fixes2` did exactly that,
  on line 0 of a batch, and reports it *"cost nothing"* (§9.4). Not a contradiction so much as a
  missing distinction the help should draw: a document guard is cheap for a short structural batch
  and unusable as a session-long gate.
- **Whether `duplicate-name` is calibrated correctly** (D11). The first wave split on whether `cp`
  should disambiguate copy names; `detailc` adds the data point that one root copy produces ~90
  warnings, which makes the check's current behaviour a blocking cost rather than a nuisance.
- **What `replace` is for.** §1.2 #10 and D14 proposed `apply --replace-root` and `replace` as the
  idempotent rebuild primitive, on the build agents' reading. `fixes` shows that on a *reusable
  definition* it is the dangerous verb. Both can be true, since one targets a root with no instances
  and the other a definition with 242, but the help does not distinguish them and should.
