# Teach the CLI what it already does

*2026-09-02. Claude (Fable 5.1) with Ben, planning from
[the Quill mobile run](2026-09-01-quill-mobile-agents-dx.md) and an audit of its claims against
the code (an Opus agent, this session; verdicts below). Sequel to
[guards and echo](2026-08-31-guards-and-echo.md), which answered the previous run.*

## The finding, restated

The Quill run produced a lint-clean 1,850-node design system and four Python generators
woodcase cannot read. The report blames a missing verb set; the audit says otherwise. **The two
most expensive problems were teaching failures**, not missing features:

- **D5 is false.** A `ref` *can* take children: `kind.slot` is in the format and the schema, and
  an instance replaces a slot frame's children through `descendants` today (verified live). What
  broke it is one sentence from the divergence check, which tells the writer *"the override is
  stored but nothing will read it"* because its accepted-key list omits `children`
  (`BatchApplier+Divergence.swift:186`) while the patcher honours it (`PenNodePatcher.swift:90`).
  That sentence is why `atoms` decided "refs are for leaves" and deep-built every composite.
- **The ref-in-`add` answer existed** in `WoodcaseEditor.md` and no agent found it, because
  agents read `help design` and `<verb> --help` and stop. Documentation that is not at the CLI
  surface does not exist for them.

Seven of the report's items are wrong or misdiagnosed (D5, D7, D17, the naming-worlds item,
`apply --replace-root`, the `--props` contradiction, the `\$` contradiction). A handful are real
bugs no doc can fix: `tree` and `lint` measure text in the fallback face because only `shot` and
`render` prepare fonts (D1/D2), the batch `cp` op refuses what the `cp` verb takes (D3),
`"parent":"document"` fails in a batch (D4). The rest is discoverability.

## Principles for this round

1. **Agents are given no skill.** Everything they need to use woodcase well, including how to
   build a component the codegen will recognise, must reach them through `help <topic>` and
   `<verb> --help`. DocC and README are for humans; the CLI teaches itself.
2. **Fix the message before the mechanism.** Where the feature exists and the tool denies it,
   the lie is the bug.
3. **Fewer verbs, not more.** Every feature below was chosen because it deletes agent-written
   code the teaching cannot. `set --match`, `arrange`, `find`, `measure` and a parameter
   language are parked (see the end).

## Decisions

**Slot filling stays "write `children` through `override`"**, taught in `help design` and
`help recipes`; no `fill` verb. For that to be honest, `tree --expand` must show the injected
children (it does not today) and `lint` must stop reporting `empty-fit-content` on a definition's
slot frame.

**Named parameters already exist: `_props`.** The `detail A` agent wanted an atom's author to
declare which descendants a consumer sets; codegen has read exactly that from
`common.metadata._props` (`{"label":"Body/Title"}`) since the React emitter shipped
(`ComponentAnalyzer.swift:236`). Nothing in the CLI teaches it and the editing verbs ignore it.
One declaration will serve both: `override` and `cp --each` accept a prop name as a key and
resolve it through `_props`. No new concept enters the format.

**Metadata gets deep keys.** `common.metadata` is a whole-object property, so setting `_role`
today silently drops `_props`. `common.metadata._role=button` merges one key. Without this the
codegen topic would be teaching a trap.

**`cp --each rows.jsonl` on `cp` only.** One copy per row; keys are exactly the argv keys `cp`
takes (`common.name`, `Chip/kind.fills`, and after the `_props` leaf, `label`); `{n}` keeps
working. `apply` is already the one-op-per-line form and does not grow a payload form. No
`--bind` templating.

**`duplicate-name` is scoped to siblings.** The resolver lets an address start at any node, so
two `Masthead`s under different parents cost one extra segment and the ambiguity error already
lists the candidates by full path. Only same-named *siblings* defeat every name path. The
document-wide check drove agents into `Masthead Top Row Title` naming; short names unique among
siblings are the taught style, and `cp --rename-prefix` is parked as a consequence.

**`shot` keeps its default.** It already prints `scale=`, `rect=` and `pixels=`. The help gains
one sentence (pass the vision model's edge limit as `--max`) and `--crop x,y,w,h` becomes the
tiling primitive. `--json` returns every rect it drew, outline targets included, which also makes
D1 self-diagnosing.

**Overriding an instance root** (backlog 2026-08-30, D6, §9.7): a workflow has now asked, which
was the un-park condition. Proposed shape: `override <instance> <prop>=<value>` with no
descendant path writes `rootOverrides`; `set <instance>` keeps writing the ref node. One
address, two verbs, no `Card1/<component id>` form. Confirmed by Ben 2026-09-02; the interface
detail is the integrator's.

> **Correction, 2026-09-02, at integration.** Root overrides take `kind.*` keys only. The format
> reserves every `common.*` key on a ref for the instance itself, so `opacity` stored there would
> read back as the instance's opacity. `override Card1 opacity=0.5` is therefore the tested
> *refusal*, naming `set Card1 common.opacity=0.5`; `override Card1 width=200` is the working form.
> The leaf's first criterion was written against the wrong key and was passed on the kind form.

## Tracks

Leaves are grouped by file surface. Track A is correctness and is dispatchable now. Track B
is the small feature set. Track C is the teaching pass and is blocked on the leaves it
documents, so that help text never describes a message or flag that has not landed.

### A. Correctness

- **A1 Slot filling honoured end to end.** `children` joins the divergence check's accepted set
  (or the check consults the patcher's contract); the "does not set `enabled`" divergence becomes
  an informational line, since adding a property is the sanctioned variant idiom; `tree --expand`
  renders injected children; `lint` exempts a definition's slot frame from `empty-fit-content`.
- **A2 One font path.** `tree` and `lint` prepare fonts before measuring, with the diagnostic
  collector; `shot` passes the collector it drops today (`ShotCommand.swift:272`). The fallback
  warning the resolver already emits reaches stderr on every verb. If a read must stay offline,
  it says so rather than reporting a measurement in a face the render will not use.
- **A3 Batch parity with the verbs.** The `cp` op splits path-keyed props the way the verb does
  (`CopyCommand.swift:332` into `BatchApplier.planCopy`); `"parent":"document"` is accepted in
  a batch as `help design` teaches; `apply` takes `--guard` on argv; `-F /dev/null` reads as
  empty (`Data(contentsOf:)`, not `FileManager.contents`).
- **A4 Override messages and `--unset`.** `override --unset <key>` removes an override; the
  null-write warning inverts (warn when the definition sets the key, stay quiet when it does
  not); the near-miss for a path into an instance suggests the instance path (`Inst/Body/Title`),
  not the definition's copy.
- **A5 Small CLI fixes.** `--version`; flush stdout before the `--props` advisory on stderr; one
  stderr line when `.gitignore` is touched.
- **A6 Lint calibration.** `duplicate-name` reports duplicate *siblings* only; a new
  `text-overflow` check when a fixed-size text box cannot show its content (both numbers exist:
  `PenLayoutEngine.swift:675`, `PenTextRenderer.swift:62`).

### B. Features that delete agent code

- **B1 `tree --absolute`.** Absolute rects on the text form and an `absRect` key on `--json`,
  from `PenLayoutEngine.absoluteRects` which `shot` already uses. Closes gotcha "rects are
  parent-relative" from the CLI side.
- **B2 `shot --json` rects and `--crop`.** `--json` lists every rect it drew, outline targets
  included, in the node's own space; `--crop x,y,w,h` renders a sub-rectangle; help gains the
  vision-model sentence.
- **B3 `cp --each`.** Generalises `--times` (`CopyCommand.swift:254` substitutes `{n}` into root
  and descendant path props): one copy per JSONL row, row keys are argv keys.
- **B4 Metadata deep keys and `_props` in the editing verbs.** `common.metadata.<key>=<value>`
  merges one key; `override` and `cp --each` accept a prop name declared in the component's
  `_props`; `get <definition>` prints its `_props` as the parameter list.
- **B5 `get --instances`.** Exposes `EditableDocument.instanceIDs(ofComponent:)`
  (`EditableDocument+Replace.swift:127`), which `rm` already uses.
- **B6 Instance root overrides.** The decision above, once confirmed: `override <instance>
  <prop>=<value>` writes `rootOverrides`; the candidate list and `resolve` agree.
- **B7 `--dry-run` on the write verbs.** Settle, lint, print, roll back, on `add`, `apply`,
  `cp`, `rm`, `set`, `override`. Last, because everything above changes what it would print.

### C. Teaching

- **C1 `help design` and the verb help.** Naming: short names unique among siblings, an address
  may start at any unique ancestor, the ambiguity error names the fix. Components: overrides are
  keyed by the definition's child *ids* so renaming children is free and `replace` on a live
  definition drops overrides it does not carry forward (`replace --help` currently promises the
  opposite); `enabled=false` on an instance descendant is the variant mechanism; a `ref` may be
  written inline in an `add` subtree; a slot frame's children are replaced from the instance.
  Values: `kind.lineHeight` is a multiple of `fontSize`; `\$` escapes a literal `$`. Reads:
  `get --expand` is the bulk content read; `--props` takes a comma list; coordinates are
  parent-relative unless `--absolute`. Loop: `activity` is step four; `undo` is per writer; a
  guard suits a short structural batch, not a session-long gate. Foot: "see also `<verb>
  --help`". `help recipes` gains a slot-filling and a `cp --each` example. `WoodcaseEditor.md`
  moves in step.
- **C2 `help codegen`.** What the React emitter recognises: `reusable`, top-level non-reusable
  frames as pages, `{Name}:{state}` siblings, `_role`, `_props`, `_action`, `_bind`, `_states`;
  how an instance's overrides map to props, and that an unmapped override makes the emitter
  inline the component. Pointer from `help design` and from `generate react --help`.
- **C3 Codegen readiness in `lint`.** A `_props` path that does not resolve, an unknown
  `_role`, an instance whose overrides no prop covers. `lint --list` prints every check with its
  one-line doc so agents can discover them.
- **C4 Correct the report in place.** D5, D7 and D17 get marked block quotes saying what was
  wrong; the `--props` and `\$` contradictions are resolved; sections 7 and 8 are moved before 9.

### Parked (added to `project/backlog.md` with this plan)

`cp --rename-prefix` (dissolves under A6; un-park if agents still ask), `woodcase measure`
(un-park if agents still build rulers after A2 and B1), `set --match` (a second address grammar;
one agent explicitly did not want one), `arrange`/`pack` (`mv` plus a `set common.x` batch),
`find`/`query` (`tree --json --absolute` through `jq`), a parameter language beyond `_props`,
format asks (dashed strokes, rich runs, document-level style defaults), exempting instances from
`duplicate-name` (moot under A6), a `shot` default-scale change.

## Plan

```yaml
tasks:
  - title: Teach the CLI what it already does (Quill DX follow-up)
    desc: |
      The Quill mobile run (project/2026-09-01-quill-mobile-agents-dx.md) built a 1,850-node design system and four Python generators. An audit found the costliest problems were teaching failures: a false divergence message denied slot filling that works, and the answers agents needed were in DocC where agents never look. This tree fixes the real bugs, adds the few features that delete agent code, and moves the curriculum to the CLI surface. Design: project/2026-09-02-teach-the-cli-what-it-does.md. Strict TDD on every leaf; a doc leaf carries help-text snapshot tests where they exist.
    labels: [quill-dx]
    children:
      - title: Slot filling honoured end to end
        ref: slots
        desc: |
          The divergence check (BatchApplier+Divergence.swift:186) reports "the override is stored but nothing will read it" for a `children` override on a slot frame, because its accepted-key list omits `children` while PenNodePatcher.swift:90 honours it. Make the check agree with the patcher. Demote the "does not set X in Component — the override adds the property" divergence to an informational line: adding `enabled`/`opacity` is the sanctioned variant idiom. `tree --expand` must render the children an instance injects into a slot frame; `lint` must not report `empty-fit-content` on a definition's `kind.slot` frame. Regression tests first for all four. Design: project/2026-09-02-teach-the-cli-what-it-does.md §A1.
        criteria:
          - A children override on a slot frame prints no divergence and the patched tree renders the injected children
          - An override that adds enabled or opacity to a descendant prints an informational line, not a divergence
          - tree --expand prints the injected slot children under the instance
          - lint reports no empty-fit-content on a definition's slot frame
      - title: One font path for every verb
        ref: fonts
        desc: |
          Only shot, render and the viewer call GoogleFontResolver.prepareFonts, so tree and lint measure text in SF Pro even when the font is cached on disk (D1: tree and shot disagree on text metrics). The resolver already emits "Font 'X' could not be resolved; will fall back" (GoogleFontResolver.swift:107) but ShotCommand.swift:272 passes no collector (D2). Prepare fonts on tree and lint before measuring, pass the collector on every verb so the warning reaches stderr, and if a read is offline say so on stderr rather than report a measurement in a face the render will not use. Test with a fixture whose font is disk-cached and one whose font cannot resolve. Design §A2.
        criteria:
          - tree and shot report the same text width for a Google-font fixture with the font cached
          - Every verb prints the fallback warning on stderr when a font cannot resolve
          - A measurement taken in a fallback face is labelled as such
      - title: Batch parity with the single-node verbs
        ref: parity
        desc: |
          The apply `cp` op puts op.props straight into setProperties (BatchApplier+Create.swift:117) and so refuses path-keyed overrides the cp verb splits (CopyCommand.swift:102, 332) — D3. A batch `add` rejects "parent":"document" (BatchOperation+Codable.swift:75) although AddressArgument maps it to nil and help design teaches it — D4. apply takes no --guard on argv though every other write does (§9.4). -F /dev/null fails because FileManager.contents returns nil for a char device (ApplyCommand.swift:188) — D19. Fix all four so the op and the verb share one assignment path. Design §A3.
        criteria:
          - An apply cp line with a Path/kind.content key applies exactly as the cp verb does
          - A batch add with parent "document" creates a root node
          - apply accepts --guard on argv with the same semantics as set
          - apply -F /dev/null is an empty batch, not an error
      - title: Override messages and --unset
        ref: override-msgs
        desc: |
          `override x=null` writes a null instead of removing the override, and valueRules says "clears the property" generically (PropertyAssignment.swift:56) — §9.3. Add `override --unset <key>` and invert the warning: warn when the definition sets the key (destructive), stay quiet when it does not (no-op). The near miss for a step-skipping name path into an instance offers the definition's own copy; say instead that a path into an instance names every frame of the definition's tree and suggest the instance path — D7. Design §A4.
        criteria:
          - override --unset removes the descendant override and get shows it gone
          - override x=null warns only when the definition sets x
          - A step-skipping name path into an instance suggests the full instance path
      - title: Small CLI fixes
        ref: trivia
        desc: |
          --version on the root command (CommandConfiguration sets none, D18). Flush stdout before TreeCommand.warnAboutEmptyColumns writes its stderr advisory so the two streams do not interleave inside a table (D17; the report misdiagnosed this as a wrong stream). One stderr line when a write edits .gitignore (D16). Design §A5.
        criteria:
          - woodcase --version prints the package version
          - The --props advisory never appears inside a table row when both streams go to one terminal
          - Touching .gitignore prints one line naming the entry added
      - title: Lint calibration — sibling duplicates and text overflow
        ref: lint-cal
        desc: |
          duplicate-name (DocumentLinter+DuplicateNames.swift) flags every same-named pair in scope, but the resolver lets an address start at any node, so only same-named siblings defeat every name path. Scope the check to siblings; the finding's advice stays. Add a `text-overflow` check: a text node with fixed width/height whose measured content does not fit renders nothing silently (D8; PenLayoutEngine.swift:675 skips measurement, PenTextRenderer.swift:62 drops lines that do not fit). Design §A6 and the duplicate-name decision.
        criteria:
          - Two same-named nodes under different parents produce no duplicate-name finding
          - Two same-named siblings produce one finding naming both
          - A fixed-box text node whose content overflows produces a text-overflow finding naming the overflow in points
      - title: tree --absolute
        ref: tree-abs
        desc: |
          tree rects are parent-relative (gotchas.md "PenLayoutEngine rects are parent-relative") while shot uses PenLayoutEngine.absoluteRects (ShotCommand.swift:283); three agents re-derived absolute coordinates by walking parents (D13). Add --absolute to the text form and an absRect key to --json rows, from the same function shot uses. Document the convention in tree --help. Design §B1.
        criteria:
          - tree --json rows carry absRect equal to shot's rect for the same node
          - tree --absolute prints document-space rects
      - title: shot --json rects and --crop
        ref: shot
        desc: |
          shot --json carries only the root rect; --outline targets and the drawn rects are not reported, so an agent cannot locate what it sees (D9's real ask). Return every rect drawn, outline targets included, in the node's own coordinate space with the existing point = (pixel − gutter)/scale + origin contract. Add --crop x,y,w,h in that same space so a tall board can be tiled for a vision model. Add one help sentence: pass the model's edge limit as --max and use the printed pixels= to decide whether to tile. Default scale is unchanged. Design §B2 and the shot decision.
        criteria:
          - shot --json lists a rect for every --outline target with its id
          - shot --crop renders exactly the requested sub-rectangle and reports its origin
          - shot --help names --max as the vision-model edge limit
      - title: cp --each
        ref: each
        desc: |
          cp --times N substitutes {n} into root and descendant path props (CopyCommand.swift:73, 254) but cannot vary content per copy, so all four agents wrote generators for rows with per-item payloads (~300 lines; report §1.2 #1). Add --each <rows.jsonl>: one copy per row, keys are exactly the argv keys cp takes (common.name, Chip/kind.fills, Name/kind.content), {n} still substituted, --at placement as today. No --bind or template syntax. The batch cp op gains the same field. Design §B3 and the --each decision.
        criteria:
          - cp --each with three rows makes three copies whose named descendants carry each row's values
          - A row key that names no descendant fails the whole cp before any write, naming the row and key
          - The apply cp op accepts an each array with the same semantics
      - title: Metadata deep keys and _props in the editing verbs
        ref: props
        blockedBy: [each]
        desc: |
          common.metadata is a whole-object property, so `set … common.metadata='{"_role":"button"}'` drops _props and every other key (WoodcaseLint.md warns about this). Add common.metadata.<key>=<value> as a merge of one key, and --unset for one key. Codegen already reads common.metadata._props as prop name → descendant name path (ComponentAnalyzer.swift:236); make override and cp --each accept a declared prop name as a key, resolved through the component's _props, and make `get <definition>` print the _props as its parameter list. This is the named-parameter concept the detail A agent asked for; nothing new enters the format. Design: the _props decision and §B4.
        criteria:
          - set common.metadata._role=button leaves _props intact
          - override Inst label=Hi resolves label through the definition's _props to the right descendant
          - cp --each accepts prop-name keys alongside path keys
          - get on a reusable node lists its _props with the descendant each maps to
      - title: get --instances
        ref: instances
        desc: |
          "Who instances this component?" has no read, though EditableDocument.instanceIDs(ofComponent:) exists and rm uses it (EditableDocument+Replace.swift:127; report §9.6). Expose it as get <definition> --instances, text and --json, each row carrying the instance's address, id and rev. Design §B5.
        criteria:
          - get --instances lists every ref whose target is the definition, by address and id
          - --json carries id, address and rev per instance
      - title: Instance root overrides
        ref: root-overrides
        desc: |
          Parked 2026-08-30 (backlog "Addressing an instance's root as an override target") until a workflow asked; detail B did (D6, §9.7): set names override for the property and override names set, and neither writes kind.rootOverrides. Shape, confirmed by Ben 2026-09-02: `override <instance> <prop>=<value>` with no descendant path writes rootOverrides; `set <instance>` keeps writing the ref node; no Card1/<component id> address exists, and the override-target-not-found candidate list stops printing one. Design: the instance-root decision and §B6.
        criteria:
          - override Card1 opacity=0.5 writes kind.rootOverrides and the render reflects it
          - set and override error messages for an instance root each name the working command
          - The override candidate list never prints an address resolve refuses
      - title: --dry-run on the write verbs
        ref: dry-run
        blockedBy: [slots, parity, each, props, root-overrides]
        desc: |
          Asked in both DX runs (2026-08-31 #2, D15). On add, apply, cp, rm, set and override: run the transaction to the point of settling, print what the real write would print including divergences and the post-state tree, run lint on the result, and roll back without touching the file or the activity log. Last in the tree because every earlier leaf changes what it prints. Design §B7.
        criteria:
          - A --dry-run write leaves the file, revision and activity log byte-identical
          - Its output equals the real write's output apart from the revision line
          - Lint findings the write would introduce are printed
      - title: help design and the verb help
        ref: teach
        blockedBy: [slots, fonts, parity, override-msgs, lint-cal, tree-abs, shot, each]
        desc: |
          The curriculum, at the surface agents actually read. help design gains: naming (short names unique among siblings; an address may start at any unique ancestor; the ambiguity error names the fix); components (overrides are keyed by the definition's child ids, so renaming children is free and replace on a live definition drops overrides it does not carry forward; enabled=false on an instance descendant is the variant mechanism; a ref may be written inline in an add subtree; a slot frame's children are replaced from the instance); values (kind.lineHeight is a multiple of fontSize; \$ escapes a literal $); reads (get --expand is the bulk content read; --props takes a comma list; rects are parent-relative unless --absolute); the loop (activity is step four; undo is per writer; a guard suits a short structural batch, not a session-long gate); and a "see also <verb> --help" foot. replace --help stops promising overrides survive; override --help and add --help carry the examples; schema's lineHeight row says multiplier. help recipes gains a slot-filling and a cp --each recipe. WoodcaseEditor.md moves in step. Every claim here must already be true in the code, which is why this leaf is blocked on the others. Design §C1.
        criteria:
          - help design covers naming, id-keyed overrides, variants, inline refs, slot filling, lineHeight, the $ escape, get --expand, coordinates and the loop
          - replace --help states that id-keyed overrides the new definition does not carry are dropped
          - help recipes has a worked slot-filling example that runs clean against a fixture
          - WoodcaseEditor.md matches help design on every point above
      - title: help codegen
        ref: codegen-help
        blockedBy: [props]
        desc: |
          Nothing in the CLI says how to build a component the React emitter recognises, so consumers rely on outside knowledge. A new help topic: reusable marks a component; top-level non-reusable frames are pages; {Name}:{state} siblings are state variants; common.metadata carries _role (ComponentRole values), _props (prop → descendant path), _action, _bind and _states; an instance's descendant overrides map to props through _props, and an override no prop covers makes the emitter inline the component with a diagnostic. Set metadata with the deep-key form. Pointers from help design and generate react --help. PenCodeGen.md is the human-side source; keep the two in agreement. Design §C2.
        criteria:
          - help codegen lists every metadata key ComponentAnalyzer reads, with the deep-key set command for each
          - help design and generate react --help point to it
          - A component built by following the topic alone emits a typed props interface
      - title: Codegen readiness in lint, and lint --list
        ref: codegen-lint
        desc: |
          Three things codegen chokes on silently: a _props path that resolves to no descendant, a _role outside ComponentRole, and an instance whose overrides no declared prop covers (the emitter inlines it). Add a check for each with the fix in the message. Add lint --list, printing every LintCheck with its one-line doc, so agents can discover the rules; and lint --summary, a count per check. Design §C3.
        criteria:
          - An unresolved _props path, an unknown _role and an unmapped instance override each produce a finding naming the fix
          - lint --list prints every check id with a one-line description
          - lint --summary prints one row per check with a count
      - title: Correct the Quill report in place
        ref: errata
        desc: |
          Per the documentation practice, a wrong documented cause is corrected in place as a marked block quote. D5 (refs cannot take children — false; the divergence message was the bug), D7 (name paths into an instance work; only the near-miss text was wrong), D17 (the advisory is already on stderr; the interleave was buffering) and the naming-worlds item in §9.7 get corrections; the --props and \$ contradictions in §8 are resolved against the code; sections 7 and 8 move ahead of 9. Design §C4.
        criteria:
          - D5, D7, D17 and the naming-worlds item carry a marked correction under their headings
          - Sections are in numeric order
```
