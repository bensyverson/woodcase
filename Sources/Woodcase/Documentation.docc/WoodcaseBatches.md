# Batches

Apply many edits in one pass, and find out exactly which ones landed.

## Overview

A batch is JSONL: one ``BatchOperation`` per line, applied in order by
``BatchApplier``. It is how an agent makes a dozen coordinated edits without a
dozen round trips — and, with a one-element array, it is also the path every
single mutating verb takes, so a `set` behaves the same alone as it does on
line 11 of a file.

Two properties make a batch usable by something that cannot see the document:

- **Addresses, not ids.** Every operation names its nodes with a ``NodeAddress``
  — an id, a name path, a path into a component instance, or a `@tag` naming
  what an earlier line created. A whole batch can be written before a single id
  exists.
- **It applies what it can.** A line that fails changes nothing and does not
  stop the batch. Rolling everything back by default would punish a typo on
  line 11 with the loss of lines 1 through 10.

```swift
let operations = try BatchOperation.decodeJSONL(text)
let report = BatchApplier.apply(operations, to: document, identity: PeerID(rawValue: "ben"))

for line in report.lines where line.status != .applied {
    print("line \(line.line): \(line.error ?? "")")
}
```

## The grammar

``BatchOperation/grammar`` is the single source of truth for the wire format —
print it rather than restating it. In outline:

| Verb | Line |
| ---- | ---- |
| `set` | `{"op":"set","target":ADDR,"props":{PATH:VALUE},"rev":REV,"guard":GUARD}` |
| `add` | `{"op":"add","parent":ADDR,"node":SUBTREE,"at":N,"tag":NAME,"rev":REV}` |
| `replace` | `{"op":"replace","target":ADDR,"node":SUBTREE,"rev":REV}` |
| `cp` | `{"op":"cp","source":ADDR,"parent":ADDR,"at":N,"tag":NAME,"props":{…},"each":[{…}],"rev":REV}` |
| `mv` | `{"op":"mv","target":ADDR,"parent":ADDR,"at":N,"rev":REV}` |
| `rm` | `{"op":"rm","target":ADDR,"detach":BOOL,"rev":REV}` |
| `override` | `{"op":"override","target":ADDR,"props":{NAME:VALUE},"rev":REV}` |
| `var` | `{"op":"var","name":NAME,"value":VARIABLE}` |
| `theme-axis` | `{"op":"theme-axis","name":NAME,"options":[STRING]}` |
| `import` | `{"op":"import","alias":ALIAS,"path":PATH}` |

Every line takes `rev` and `guard`; only `set` shows both, to keep the shapes
readable.

`var`, `theme-axis` and `import` each *add or change* what they name; none of them
removes it. An optional payload would turn a dropped field into a silent delete, and a
dropped variable or import breaks what refers to it without failing anything. Removal
is `woodcase vars rm` and `woodcase imports rm`, which refuse while something still
references the name — see ``NameInUse`` — and take `--force`.

### One `var` line, every theme option

A `var`'s `value` is what the `.pen` file stores — `{"type":TYPE,"value":VALUE}` — and
`VALUE` is either one value or the themed list the format also takes: one
`{"value":V,"theme":{AXIS:OPTION}}` per option, plus an optional entry with no `theme`
as the fallback the resolver falls back to. So a two-mode token is one line, and a
seventeen-colour token layer is seventeen lines through one `apply` rather than
thirty-four process launches:

```jsonl
{"op":"var","name":"--accent","value":{"type":"color","value":[{"value":"#e0561a","theme":{"mode":"light"}},{"value":"#ff8a5c","theme":{"mode":"dark"}}]}}
{"op":"var","name":"--surface","value":{"type":"color","value":[{"value":"#ffffff","theme":{"mode":"light"}},{"value":"#141414","theme":{"mode":"dark"}}]}}
```

A themed line **registers what it pins**, by the rule `vars set --theme` states and
through the same ``ThemeAxisRegistrar``: an axis the document lacks is created, an option
an axis lacks is appended — appended, never reordered, because an axis's first option is
the one that is active when nothing pins it. So a `var` line never needs a `theme-axis`
line before it, and a batch can no longer leave a document whose variables are
conditioned on a `mode` its `themes` table does not have.

The line replaces the variable's **whole** value, so write every variant you mean to
keep. Merging one option into what is already there is the verb —
`woodcase vars set design.pen --accent=#ff8a5c --theme mode=dark` — which takes several
`name=value` pairs in one transaction, with `--theme` and `--type` applying to each.

Because a `var` line acts on no node, its status line says only `document`. A themed one
therefore carries a `note` beneath it echoing every option's value and any axis it grew;
`--json` carries the same under the line's `divergences`.

Omitting `parent` means the document root, and so does writing `"document"` — the
same word `woodcase cp design.pen Home document` takes on the command line, decided in
one place so a batch and a verb cannot disagree about it. A root node genuinely named
`document` is still addressable as `#<id>`, which is the trade a literal always asks
for.

### One `cp` line, many copies

`each` makes one copy per row instead of one copy. Each row is the same kind of property
map `props` is, laid over it — so a value every copy shares is written once in `props`
and a row overrides what it needs — and `{n}` in any value becomes the 1-based row
number:

```jsonl
{"op":"cp","source":"Chip","parent":"Board","props":{"Label/kind.fills":"#333"},"each":[{"common.name":"Chip 1","Label/kind.content":"Draft"},{"common.name":"Chip 2","Label/kind.content":"Shipped"}]}
```

`at` walks with the rows, `rev` guards the first copy only, and the line takes no `tag`
— a tag names one node, and this makes several; address them by the `common.name` their
rows gave them. Every row's name-path key is resolved against the **source** before the
first copy is written, so a bad key refuses the whole line, naming the row, with nothing
created. It is `woodcase cp --each rows.jsonl` with the rows inline.

### Two property vocabularies

`set` and `cp` take ``NodePropertyCodec`` paths: `"common.name"`,
`"kind.width"`, `"kind.fills"`. An `override` is *stored* under raw .pen property
names — `"content"`, not `"kind.content"` — because a ref's `descendants` map is
written that way and storing anything else would make the file disagree with what the
format stores. The asymmetry is in the storage, not in what a line may write: a path an
`override` is given is translated to the raw key on the way in, so a caller can write
whichever vocabulary is at hand. Addressing a `set` inside an instance is still refused
with a message pointing at `override`, and the reverse is refused too — those are about
*where* the write lands, which no translation can decide.

### Creating nodes

An `add` carries a .pen subtree. Ids in it are optional: a node that writes one
keeps it, and a node that writes none is given a fresh one — ``PenSubtreeDecoder``
marks what the author left out and ``SubtreeIDPlan`` settles the rest. So a batch
can name a node it is about to create (`{"id":"hero", …}`) and address it by that
id in a later line, and a batch that would rather not think about ids can leave
them all out and read them off the report. A supplied id must be one the format
allows — a non-empty string with no `/`, since `/` separates the segments of an
address — and must not already be in the document or appear twice in the same
subtree; either way the line fails with ``EditingError/duplicateNodeID(id:)`` or
``EditingError/invalidNodeID(id:)`` and changes nothing.

A `replace` reads its subtree the same way, with one addition: an id the *replaced*
subtree holds today is free to reuse, because that subtree goes away with the line.
The root's own id is the target's whether it is written or not — a different one is
refused with ``BatchError/replacementIDMismatch(address:supplied:kept:)`` rather than
quietly ignored — and so the target keeps its id, its parent and its index among its
siblings while everything under it changes. Rebuilding a reusable definition is fine
and every instance follows; changing the definition's root *type* while instances
point at it is refused with
``EditingError/componentTypeChange(componentID:from:to:instanceIDs:)``.

A `cp` is the exception: it draws every id afresh, because a copy that kept its
source's ids would collide with the source. Refs *inside* the copied subtree follow
the copy; a ref pointing at a component outside it still points there.

Every node in an `add` or `replace` subtree must have a `name`, because an unnamed node cannot
be addressed by path — by the next line, or by the next agent to open the file. A
`cp` has no such requirement: its source may come from a file we did not write.

Copying a **reusable** node makes a `ref` to it rather than duplicating it,
which is what Pen does when you place a component. Duplicating the definition
would leave the document with two components where the author wanted one.

### Placement

A root-level `add` or `cp` with no coordinates of its own is placed
``RootOverlap/margin`` points to the right of the rightmost root, aligned with the
topmost one. Roots are artboards on an infinite canvas, and an agent has no way to
know what is already out there. Because the placement clears every existing root's
settled right edge, an auto-placed root cannot intersect one, whatever order the
roots were declared in. A node added to a laid-out parent takes no coordinates at
all — its parent positions it.

A root written *with* coordinates is placed exactly where it says, even on top of
another root. That is allowed — a caller mid-edit may be about to write again — but
it is said out loud: the write prints one ``LintCheck/artboardOverlap`` line on
standard error naming both roots and the `x` that would clear them, `--json` carries
the same line in the report's `warnings`, and `lint` reports the pair until it is
resolved. See ``RootOverlap``.

What counts as "of its own" — `RootCoordinates` in the applier — differs by op. An `add` carries a subtree the author wrote, so a subtree declaring
*either* `x` or `y` is left alone. A `cp` carries the source's coordinates,
which describe where the *source* sits and say nothing about where the copy
belongs — so a root-level `cp` is placed whatever the source declared, and would
otherwise land exactly on top of it. A caller who wants the copy somewhere in
particular passes `common.x`/`common.y` in the copy's `props`: those are applied
after the insert and win outright, on the axis they name.

## Statuses

Each line comes back as one ``BatchLineResult`` with a ``BatchLineStatus``:

- ``BatchLineStatus/applied`` — it ran, and the document changed. The result
  carries what it created and the ``BatchLineResult/inverse`` that undoes it.
- ``BatchLineStatus/failed`` — it was attempted and rejected. Only this status
  means "this line is wrong". A line that expands into several edits is rolled
  back if any of them fails, so a failed line never leaves half an edit behind.
- ``BatchLineStatus/cascaded`` — it was never attempted, because a line it
  depends on failed.

A line cascades when it names a tag a failed line declared, when it addresses
something a failed line would have created, or when it targets a node a failed
line was targeting. Cascading propagates: a line skipped this way poisons its
own tag in turn.

The distinction is the whole point of the report. Twenty `failed` lines say
twenty things are wrong; one `failed` and nineteen `cascaded` say one is.

## The divergence echo

A status says whether the line ran. ``BatchLineResult/divergences`` says whether what
ran is what was asked for — the third term of the write's three-way report, alongside
the status and the line as it was written. It is empty for the ordinary line, so the
report stays exactly as terse as it was; a ``WriteDivergence`` is printed only when the
stored form means something other than the plain reading of the line, and says what it
means rather than echoing the stored bytes back. ``BatchLineResult/node`` rides with it
for a caller that would rather diff the result than re-read it.

Divergences are decided while a line is planned, from the operation and the document as
it stands, so a single verb through ``BatchApplier/applyOne(_:to:recorder:)`` and the
same edit as a batch line report identically. A single verb's own answer is
``WriteReport`` rather than a whole ``BatchReport`` — the same divergences and the same
``CreatedNode`` tree, for one write instead of a line; ``CreatedTreeReport`` is the
`--json` shape of what it created, for a verb that answers with a whole subtree rather
than a single touched node.

``WriteDivergence/severity`` splits the sentences into two tiers, and the row carries
the marker: an unmarked one says the stored form means something other than the plain
reading of the line, and one prefixed `note  ` says the write means what it looks like
and states a fact about it. Only one thing is a note today — an override that *adds* a
property the component leaves unset, which is how a variant differs from its component.

## Tags

An `add` or `cp` may label what it creates with `"tag":"hero"`, and any later
line can address it as `@hero` before an id exists:

```jsonl
{"op":"add","parent":"Dashboard","node":{"type":"frame","name":"Hero"},"tag":"hero"}
{"op":"add","parent":"@hero","node":{"type":"text","name":"Headline","content":"Hi"}}
{"op":"set","target":"@hero","props":{"kind.width":480}}
```

A tag is where an address *starts*, not the whole of it: `@hero/Headline` walks
down from the tagged node exactly as a name path does, component instances
included. One batch can therefore create an instance and dress its descendants,
rather than creating everything, reading the ids back and running a second batch
to override them:

```jsonl
{"op":"cp","source":"Card","tag":"card1"}
{"op":"override","target":"@card1/Title","props":{"content":"Reykjavik"}}
```

Only creating operations declare tags. A tag pointing at nothing is an address
that matches no node, which is a failure — never a silent no-op.

## Revisions

Every line may carry `rev`, the revision the caller last read. It guards the
line's `target` where there is one, otherwise its `parent` — or the whole
document, via ``EditableDocument/documentRevision``, when there is no parent
either. A stale `rev` fails that line, names both revisions, and changes
nothing; see ``EditableDocument/apply(_:expecting:)``.

This is how two agents work the same file without a lock: they collide only when
they touch the same node, and then they get an error rather than a silent
last-writer-wins.

## Guards

A line may also carry `guard` — a ``BatchGuard``, taking the same revision token.
Where `rev` asks "is this node exactly as I last saw it, right now?", a guard asks
"has anyone **else** moved what I read?", and the difference is when it is checked.

```jsonl
{"op":"set","target":"Files/Row/Name","props":{"kind.content":"README"},"guard":"3c1f0a9b7e2d4568"}
{"op":"set","target":"Files/Row/Size","props":{"kind.content":"4 kB"},"guard":{"node":"Files","rev":"9a02b74e1c6d3f85"}}
{"op":"add","parent":"Files","node":{"type":"frame","name":"Row"},"guard":{"node":"document","rev":"5e83d1f0a97b6c24"}}
```

A bare revision pins the line's own subject — the same node its `rev` would guard.
An object pins a node you name, which is how a caller says "I read this whole frame
and composed against everything in it", or `document` for the whole file. A line may
carry several, written as an array.

**Every guard in the batch is checked once, at transaction entry**, by
``BatchApplier/checkGuards(_:in:log:file:)`` — before line 0 runs. Under the
single-writer file lock every foreign write strictly precedes that moment and every
line of this batch follows it, so a batch never trips its own guards: line 30 may
guard a frame that line 3 rewrote. That is what `rev` cannot express, because each
line's `rev` is checked as that line is applied.

A moved premise refuses the **whole batch** before anything applies, with exit 3,
naming the node, both revisions and — from the activity log — who moved it. Guards
are entry gates rather than line statuses, so they never appear in the report: a
guarded batch either runs or does not exist. A guard naming a `@tag` is refused,
because nothing a line creates exists at the door. A `--retry` checks only the
guards of the lines it actually re-runs; a line that already applied moved its own
subtree when it did.

## Atomic

`atomic: true` opts into all-or-nothing. The batch runs against a deep copy of
the document; only if every line applies are the **translated edits** replayed
onto the real document. Replaying the edits rather than re-running the batch is
what keeps the ids in the report equal to the ids the document ends up with —
re-running would draw fresh ids the caller was never told about.

On the first failure nothing is kept: the culprit is reported `failed`, every
other line `cascaded`, and the document is untouched.

## Retry

A retry is a patch, not a resend. Pass the same operations with the broken lines
repaired, plus the previous report:

```swift
let second = BatchApplier.retry(repaired, report: first, to: document)
```

Only the lines that failed or cascaded run again. Lines that already applied are
left alone and keep their result — including the tags they declared, so a
repaired line can still say `@hero`. The returned report covers every line, so
it can be retried again in turn.

## Logging a batch

Pass the transaction's ``ActivityRecorder`` and every edit that reaches the real
document goes through it, so a batch logs exactly what the same edits log applied
one at a time — same operations, same order, one batch id:

```swift
try await PenFileTransaction.run(at: url, identity: "ana") { document, recorder in
    BatchApplier.apply(operations, to: document, recorder: recorder)
}
```

A line is the unit of logging as well as of rollback. A line that fails half way
through is unwound with the inverses of the edits it already applied, and the
events those edits recorded are dropped with them — so a failed line leaves no
trace, exactly as a line that failed on its first edit would. The unwind itself
never records. An atomic batch stages on the copy with no recorder at all and
records the replay onto the real document; if the replay fails, the events go
with it.

Without a recorder the batch applies exactly as before and logs nothing — which
is what a caller editing a scratch document wants. The `identity` parameter is
unrelated: that is the CRDT ``PeerID`` stamped on the report.

## Topics

### Writing a batch

- ``BatchOperation``
- ``PenSubtreeDecoder``
- ``SubtreeIDPlan``

### Applying one

- ``BatchApplier``

### Reading the result

- ``BatchReport``
- ``BatchLineResult``
- ``BatchLineStatus``
- ``WriteDivergence``
- ``CreatedNode``
- ``WriteReport``
- ``CreatedTreeReport``

### Failures

- ``BatchError``
- ``BatchErrorMessage``
- ``RemedyDialect``
