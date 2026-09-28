# Editing from the Command Line

The read–write–verify loop an agent runs against a .pen file, and the vocabulary it
needs to run it.

## Overview

`woodcase` is built so an agent can change a design without opening one. The whole
workflow is three commands:

```bash
woodcase tree design.pen                 # read: what is there, and what it is called
woodcase set design.pen Card/Title …     # write: change one node, guarded by a revision
woodcase tree design.pen Card            # verify: read back the settled result
```

Nothing in that loop needs pixels. `tree` reports the geometry the layout engine
actually produced, so the cheap structural read answers most of the questions a
screenshot would — and <doc:WoodcaseLint> answers the rest. `shot` is there for the
last mile.

No file yet? `woodcase new design.pen` writes the minimum a .pen file needs — the
format version and an empty `children` array — before the loop above begins. Every
verb's own "no such file" refusal names it, so an agent never has to remember it
unprompted.

Every transcript below is real output from `Tests/WoodcaseTests/Fixtures/banking.pen`
and `batch.pen`, copied into a scratch directory with `WOODCASE_HOME` pointed at one
too — so the transcripts have a log of their own rather than the project's. Generated
ids and revisions differ on every insert, so yours will differ.

## The loop

**Read.** `tree` prints one row per node: type, name indented by depth, the settled
rect, a clip flag, and the id. The header carries the *document* revision.

```text
$ woodcase tree banking.pen --depth 1
rev 7cf8d84e7b6b9b23  25 rows
prompt  #j4hLC                     3053,-288 0×0                j4hLC
*frame  banking-home               3053,-10 402×874             nSNTs
frame     status-bar +2            0,0 402×33                   DLRXo
frame     header +2                0,33 402×72                  6m90O
frame     card-section +1          0,105 402×240                m0GAt
frame     quick-actions +4         0,345 402×73                 X0xcX
…
*frame  component/QuickAction      3600,-10 42×65               msdSu
ref     banking-home / Dark +7     4520,-10 402×874             YGJ0d
```

A `*` marks a reusable component definition, `+N` counts children the listing left
out, and `⚠ clipped` / `⚠ partial` marks a node that falls outside its parent.

**Coordinates are parent-relative.** A row's `x,y` is its offset inside its *own*
parent, which is the layout engine's convention: only a top-level node's rect is in
canvas coordinates, so a leaf that sits in its parent's corner reads `0,0` however deep
it is. `--absolute` prints the same column in document space instead, from the walk
`shot --outline` draws with, so two nodes under different parents can be compared
without adding up their ancestors — and the header says `absolute` so a saved outline
is never ambiguous:

```text
$ woodcase tree banking.pen banking-home/header --absolute
rev 7cf8d84e7b6b9b23  5 rows  absolute
frame  header        3053,23 402×72  6m90O
frame    hdrG        3077,43 95×52   CcYdb
text       hdrL      3077,43 95×18   DhDsc
text       hdrN      3077,63 51×32   4YeMj
ref      bellBtn +2  3389,48 42×42   E97qI
```

`--json` needs no flag: every row carries `rect` and `absRect` both.

Narrow to a subtree and ask for the properties you care about as columns — or write
`--props` bare for the four most files carry (`kind.layout`, `kind.fill`,
`kind.content`, `kind.fontSize`):

```text
$ woodcase tree banking.pen banking-home/header --props kind.content
rev 7cf8d84e7b6b9b23  5 rows
type   name          rect          clip  id     kind.content
frame  header        0,33 402×72         6m90O  -
frame    hdrG        24,20 95×52         CcYdb  -
text       hdrL      0,0 95×18           DhDsc  Good morning
text       hdrN      0,20 51×32          4YeMj  Alex
ref      bellBtn +2  336,25 42×42        E97qI  -
```

`--json` prints the same rows as a decodable report, and there every row carries a
`rev` of its own — the node's revision, the token a write to that row quotes back. The
text outline has room for the document revision only, in its header:

```text
$ woodcase tree banking.pen --json
{
  "revision" : "7cf8d84e7b6b9b23",
  "rows" : [
    {
      "address" : "banking-home/header",
      "id" : "6m90O",
      "rev" : "34bbdffe96f18d60",
      "depth" : 1,
      …
```

`get` prints one node as the file stores it, children stripped, with that *node's*
revision on the header line:

```text
$ woodcase get banking.pen hdrL
DhDsc  banking-home/header/hdrG/hdrL  rev fc0db203760457c2
{
  "content": "Good morning",
  "fill": "$ink-soft",
  "fontFamily": "Inter",
  "fontSize": 14,
  "fontWeight": "normal",
  "id": "DhDsc",
  "name": "hdrL",
  "type": "text"
}
```

**Write.** Quote that revision back with `--rev` and the write is guarded: if anything
changed the node in between, it fails instead of overwriting blind. A write answers
with the name → id tree of what it touched and both revisions.

```text
$ woodcase set banking.pen hdrL kind.content="Good evening" --rev fc0db203760457c2
banking-home/header/hdrG/hdrL  DhDsc
rev  8fbaa75444b5a51e
document  71108d83bc08a28b
```

Three lines and no more is the write saying *what you asked for is what it stored*.
A write reports three-way — requested → applied-as → the line's status — and when all
three agree it prints exactly the report above. Anything extra between the path and
the revisions is a **divergence**: one whole sentence saying what the stored form now
means, and the remedy where there is one.

```text
$ woodcase set banking.pen hdrL kind.content='$ink-soft'
banking-home/header/hdrG/hdrL  DhDsc
kind.content resolved $ink-soft as a reference to the color variable ink-soft — write \$ink-soft for the literal
rev  0f328acb9f9e5b9e
document  ae2a80ee7eda2696
```

The write still happened; the line is not a failure. It is the tool telling you that
what it stored means something other than the plain reading of what you typed, because
the expensive mistakes here are the ones that are *accepted*. Read the sentence and
decide: if it is what you meant, carry on; if it is not, the remedy is in the sentence.
A divergence is on **stdout**, part of the answer, not a warning on stderr.

Seven things a write says this about: a `$name` stored as a reference to a variable the
document defines; a number stored as the text it spells; an override of a property the
component's definition does not set; an override of one its node type has no room for,
which nothing will ever read; an override carrying a `type` key, which replaces the
whole node instead of patching it; a root-level `add` or `cp` given coordinates so it
does not land on an artboard already there; and a `rm --detach` that detached live
instances first. In a batch, a divergence rides indented under its own `line N` row, and
`--json` carries them per line as `divergences`, alongside the post-state `node` the
line left behind — for a caller that would rather diff than re-read.

Those seven come in two tiers, and `--json` carries which one as `severity`. A
**divergence** is an unmarked sentence: what was stored means something other than the
plain reading of the line. A **note** is prefixed `note  ` and says the opposite — the
write means exactly what it looks like, and one fact about it is worth stating. Adding
a property the component leaves unset is the only note today, because
`override Card1/Label enabled=false` is *how* a variant differs from its component
rather than a mistake to warn about.

**Verify.** Read the same subtree back. The header's revision is the one the write
just reported, which is how you know you are looking at your own edit.

```text
$ woodcase tree banking.pen banking-home/header --props kind.content
rev 71108d83bc08a28b  5 rows
type   name          rect          clip  id     kind.content
frame  header        0,33 402×72         6m90O  -
frame    hdrG        24,20 92×52         CcYdb  -
text       hdrL      0,0 92×18           DhDsc  Good evening
text       hdrN      0,20 51×32          4YeMj  Alex
ref      bellBtn +2  336,25 42×42        E97qI  -
```

Note the settled width moved from 95 to 92: the read reports layout, not just data.

## Addressing a node

Every verb takes the same address, and the last column of a `tree` row *is* one. There
are four forms and one escape:

| Form | Example | Notes |
|---|---|---|
| id | `DhDsc` | Unique, never ambiguous, tried first for a bare segment |
| name path | `banking-home/header/hdrG/hdrL` | Consecutive parent→child steps |
| instance path | `banking-home/quick-actions/qa1/label` | Steps *into* a component instance |
| instance id-path | `zHahn/M5gJu` | The instance's id, then the node's — what `tree --expand` prints |
| forced id | `#msdSu` | `#` makes a segment an id, never a name |
| batch tag | `@hero`, `@hero/Title` | Inside one `apply` batch: what an earlier line created, and any path down from it |

A name path may start at **any** node, not only a root — `header/hdrG/hdrL` and
`hdrL` both resolve here. That is what makes short addresses usable, and it is also
why a name that repeats needs saying which one:

```text
$ woodcase set banking.pen label kind.content=x
label matches 3 nodes: #Dt9Jv/label (HpvPY), #d4kAy/top/label (t6Cmu), #msdSu/label (M5gJu) — address it by id to say which, as `#HpvPY`
[exit 2]
```

The candidates it lists are addresses that *do* resolve, so the fix is a copy-paste —
usually one more segment on the front of the address you tried.

**Name a node for what it is, and keep the name unique among its siblings.** Siblings
are the only scope that matters, and the only one `lint` checks: two same-named
*cousins* cost one extra segment and nothing else, because an address may start at any
node. Additive names like `Masthead Top Row Title` buy nothing the path does not
already carry, and you retype them on every write; `Title` under `Masthead/Top Row` is
the taught style. Same-named siblings are the case no name path can separate, which is
why `duplicate-name` reports those and only those.

An address that matches nothing is the same exit code with a different sentence:

```text
$ woodcase set banking.pen banking-home/header/greeting kind.content=x
banking-home/header/greeting matches no node in this document — run `woodcase tree banking.pen` to list the addresses it has
[exit 2]
```

**Unnamed nodes, and names that cannot be read back.** A node with no name is
addressable only by id, and `tree` prints its address as `#j4hLC` rather than
inventing one. The same marker appears whenever a name would not survive the round
trip — it is empty, contains a `/`, or begins with `#` or `@`. That is why
`component/QuickAction` above shows as `#msdSu`: its *name* contains a slash, so the
name path would be read as two segments. A printed address always resolves back to
the node it describes; that is the whole contract.

**Inside an instance.** A node inside a component instance has no storage of its own —
it belongs to the component. Addressing still works, and `tree --expand` shows the ids
those nodes take:

```text
$ woodcase tree banking.pen banking-home/quick-actions --expand --depth 2 --props kind.content
rev 71108d83bc08a28b  13 rows
type   name                 rect            clip  id           kind.content
frame  quick-actions        0,345 402×73          X0xcX        -
ref      qa1                46.75,4 42×65         zHahn        -
ref        #zHahn/M7RGT +2  0,0 42×42             zHahn/M7RGT  -
text       label            6,50 30×15            zHahn/M5gJu  Send
ref      qa2                134.25,4 46×65        5qeyz        -
…
```

Those ids are addresses like any other: `woodcase get banking.pen zHahn/M5gJu` works,
and so does `override`. An id-path names the instance and then the node, and it may
**skip the containers in between** — if the component wraps `label` in a group, the
address is still `zHahn/M5gJu`, because that is the key the instance's
`descendants` map holds in the file. A *name* never skips a step, so `qa1/label` only works when `label`
is a direct child of the component; when it is not, the name path names every step
(`qa1/content/label`), which is what error messages and `get` print back — a name path
that skips one misses, and the miss hands back the full instance path rather than the
definition's own copy of that name.

The instance's **own** address — `qa1`, with nothing after it — is the ref node, and it
is also how the component root's properties are overridden. There is no
`qa1/<component id>` form; see **Overrides**, below.

Writing to a node inside an instance is `override`, not `set` — see **Overrides**,
below. The underlying resolver is documented in <doc:EditingDocuments> under
*Addressing Nodes*.

## Property paths

`set` speaks one vocabulary: **prefixed property paths**, the same ones the CRDT layer
keys its registers with. Every path begins `common.` or `kind.`.

- `common.*` is everything every node has: `common.name`, `common.x`, `common.y`,
  `common.opacity`, `common.rotation`, `common.reusable`.
- `kind.*` is what this node *type* has: `kind.content` on a text, `kind.width` on a
  frame, `kind.fills` on anything paintable.

A bare `content` is not a path and neither is a misspelling, so `set` refuses and
prints the whole accepted list rather than guessing:

```text
$ woodcase set banking.pen hdrL kind.contnet=Hi
kind.contnet is not a property of a text — banking-home/header/hdrG/hdrL (DhDsc) accepts
`common.context`, `common.enabled`, `common.flipX`, `common.flipY`, `common.layoutPosition`,
`common.metadata`, `common.name`, `common.opacity`, `common.reusable`, `common.rotation`,
`common.theme`, `common.x`, `common.y`, `kind.blendMode`, `kind.content`, `kind.effects`,
`kind.fills`, `kind.fontFamily`, `kind.fontSize`, `kind.fontStyle`, `kind.fontWeight`,
`kind.height`, `kind.href`, `kind.letterSpacing`, `kind.lineHeight`, `kind.strikethrough`,
`kind.stroke`, `kind.strokeAlignment`, `kind.strokeLinecap`, `kind.strokeLinejoin`,
`kind.strokeWidth`, `kind.textAlign`, `kind.textAlignVertical`, `kind.textGrowth`,
`kind.underline`, `kind.width`
[exit 2]
```

> Important: two paths do not match the JSON key beside them in the file. A .pen file
> writes `"fill"` and `"effect"`; the paths are **`kind.fills`** and
> **`kind.effects`**, because the path vocabulary names the model's fields, not the
> wire's. `kind.fill` is refused — read the accepted list, which is always right.

Several paths in one command are applied together or not at all. A refusal leaves the
file untouched, so a typo in the third assignment does not half-apply the first two:

```text
$ woodcase set banking.pen hdrL common.name=Greeting kind.fontSize=16 kind.fills='$ink'
banking-home/header/hdrG/Greeting  DhDsc
rev  c473caf8b4d0bff4
document  b69f6dc48a5ddc6c
```

Setting a path to `null` clears it. Reading the vocabulary programmatically is
``NodePropertyCodec``.

Getting it wrong once is the slow way to learn a shape. `woodcase schema <type>` is the
fast one: it prints every path that type accepts, the key the file writes it under, and
every form the value may take with the enumerated values spelled out — the same
vocabulary the refusal above lists, read from the same decoders, and it needs no file.

```text
$ woodcase schema text
text — a run of text, with its font, growth behaviour and alignment

  path                    .pen key           value
  kind.content            content            string | $string
  kind.fills              fill               color | $color | fill | [color | $color | fill, …]
  kind.fontSize           fontSize           number | $number
  kind.textGrowth         textGrowth         "auto" | "fixed-width" | "fixed-width-height"
  …
```

Nested shapes — a fill, an effect, a per-side `strokeWidth` — get a key table of their
own under `NESTED SHAPES`, so `{"type":"solid"}` never has to be guessed at. Run
`woodcase schema` with no type for the fifteen node types and the `common.*` table,
and `--json` on either for the machine form. See <doc:WoodcaseCLI> for the verb.

## How a value is typed

A command line carries only strings; a .pen file carries numbers, booleans, colours,
references and whole objects. The rules are few and total, and every mutating verb
prints them in its `--help`:

| Written | Becomes |
|---|---|
| `240`, `-12`, `0.5`, `1e3` | a number |
| `true`, `false` | a boolean |
| `null` | null — which *clears* the property |
| `[…]`, `{…}` | JSON, parsed as written — `kind.padding=[12,16]`, `kind.fills=[{"type":"color","color":"#FFD166"}]`. A structured value that is refused comes back with the shapes it does take and a literal to paste, so the fastest way to learn one is to get it wrong once |
| `"…"` | the string inside the quotes, whatever it looks like |
| anything else | a string |

The last row is the one that matters: a colour (`#ff8800`), a variable reference
(`$brand`) and the sizing keywords (`fill_container`, `fit_content`) are all *strings*
in a .pen file, so they need no syntax of their own. The quoted form is the escape
hatch for the rare string that looks like something else — `common.name='"42"'` is the
name `42`.

One rule bends, in one direction only. A **number written to a property that takes
text or a `$variable`** — `kind.content`, `kind.fontFamily`, `kind.fontWeight`,
`kind.icon` and their kin — is stored as the string it spells, so
`kind.content=3` writes the caption `3` rather than refusing. There is no other value
a caption could take from a number, and quoting it was a round trip that taught
nothing. Nothing else converts: a string where a number belongs, a boolean where text
belongs, an object where a caption belongs are all still refused, with the shape that
would have been taken. See ``NodePropertyCodec``.

Only the **first** `=` splits, so a value may contain as many more as it likes. A key
given twice is refused rather than silently keeping one. `-F props.json` supplies the
same pairs as a JSON object, and a `key=value` on the command line wins over the same
key in the file.

Two shell notes. Quote a `$variable` value (`'$ink'`) or the shell eats it. And a
variable name that itself begins with a dash needs `vars`'s end-of-options marker, or
the parser reads it as an option: `woodcase vars rm design.pen -- --legacy-brand`.

A string property can itself need to hold a `$` — showing the token name
`$v-muted` rather than the colour it resolves to. `\$` is the escape:
`kind.content='\$v-muted'` (single-quote it, so the shell keeps the backslash)
stores the literal `$v-muted`, and a `\$` **anywhere else in the string** loses its
backslash the same way, so `kind.content='Total: \$30'` draws `Total: $30`. Only a
*leading* `$` is ambiguous on the wire, so only a leading one is written back
escaped; a `$` further in is stored bare, so a reader that knows nothing of this
convention — the format defines none of its own — still takes it as text. See
``PenDollarEscape``. The one string this cannot carry is a literal backslash standing
immediately before a `$`: the pair reads as the escape and the backslash is dropped.
A write that stores an *unescaped* `$name` naming a variable the document really
defines reports it as a divergence and writes it anyway, since that string almost
certainly resolved when a literal was meant.

**Text content forgives the other case — whichever verb wrote it.** A `content` that
begins with `$` and names no variable the document defines anywhere is restored as the
literal it almost certainly was, so `$120,000` draws as `$120,000` and `lint` says
nothing (``PenVariableResolver``). That is the *property's* rule, not the verb's: it
holds for `set … kind.content=` on a text node and for `override … content=` into an
instance's `descendants` map alike, and the two lint and draw identically. Every
*other* property is strict, on both routes: a bare `$name` naming nothing stays a
dangling reference, draws nothing, and `lint` reports it as `unresolved-variable`. So
does a name the document *does* define but nothing resolves — a circular chain, say —
so the forgiveness can never hide a real dangling reference. Write the escape anyway
in content: the stored value is what `get`, the code generators and a later theme all
read, and a theme that one day defines that name would swallow your text.

**`kind.lineHeight` is a multiple of `kind.fontSize`, not a length in points.** It is
the one number in the schema that is not points: `1.4` is 140% leading, and `23` on a
15pt face is a 345pt line box, laid out and rendered without complaint. The schema's
legend says so at the foot of every table, and a refusal names it too.

## Adding a subtree

`add` takes .pen JSON with `-F` (or `-F -` for standard input). You never have to
invent an id: leave `"id"` out and one is drawn for you, and the name → id tree
printed back is where the real ones come from. An id you *do* write is kept, so a
script that already knows what to call a node can say so. Every node needs a
`"name"`: an unnamed node could not be addressed by path afterwards, so it is refused
rather than silently made unreachable. A key its type does not take — `"fil"` for
`"fill"`, or a fill object's `"colour"` — is refused too, naming the key, rather than
dropped.

A file written by a newer Pen may carry keys, fill types or effect types this build does
not model. Every verb keeps them exactly as written — `get` prints them, `set`, `cp`,
`mv`, `override` and `undo` carry them along — but none edits them: `set` on such a key
is refused with a message saying the key is kept as the file wrote it.

```json
{
  "type": "frame", "name": "Notice", "layout": "vertical",
  "padding": 12, "gap": 4, "fill": "$paper-raised",
  "children": [
    {"type": "text", "name": "NoticeTitle", "content": "Scheduled maintenance",
     "fontSize": 14, "fill": "$ink"}
  ]
}
```

```text
$ woodcase add banking.pen banking-home/header -F notice.json --at 0
Notice  2w9T3
  NoticeTitle  3GgTo
rev  0517029fde265e14
document  7da5c16401e62e08
```

An id you supply has to be one the file format allows and one nothing else is using:
a non-empty string with no `/` in it (`/` separates the segments of an address), not
already in the document, and not repeated inside the subtree you are adding. A
supplied id that fails any of those refuses the whole line and changes nothing — here
the same JSON with an explicit `"id"` that happens to name a node already in the file
(`hdrG`'s own id, `CcYdb`):

```text
$ woodcase add banking.pen banking-home/header -F notice-retry.json
the id CcYdb is already taken — by a node in this document, or by another node in the same subtree — pick an unused `"id"`, or leave it out and let `woodcase add` generate one
[exit 2]
```

Placement is flex-first: a node added to a laid-out parent takes **no** coordinates —
leave `x` and `y` off and let the parent place it. `--at` picks the position among the
parent's children, counting from 0; omitting it appends. Only a root-level node (parent
`document`) is coordinate-placed: an add that declares neither `x` nor `y` is put in
empty space to the right of the existing roots, because two artboards at the same
coordinates sit on top of each other — and a root-level `cp` always is, because the
source's coordinates say where the *source* sits. Pass `common.x`/`common.y` in the
copy's props to put it somewhere specific.

### A subtree may contain instances

A subtree is not limited to leaves. A node of type `"ref"` names the definition it
draws in `"ref"` and carries its own overrides in `"descendants"`, keyed by the
definition's child ids — including a `"children"` array that fills the definition's
slot frame, refs nested inside that included. So a board assembled from a component
library is **one** `add`, rather than one `cp` per instance and an `override` per
value:

```json
{"type": "ref", "name": "Row 1", "ref": "Card0",
 "descendants": {"CTtl0": {"content": "Acme"},
                 "CSlt0": {"children": [
                   {"id": "Nte01", "type": "text", "name": "Note",
                    "content": "filled from the instance"}]}}}
```

`"reusable": true` works in a subtree too, so a definition and the instances that draw
it can be written in one batch. `woodcase schema ref` prints the shape; **Overrides**
and **Filling a slot**, below, are what the keys mean.

### Artboards do not overlap

"Empty space to the right" is exactly **100 points past the rightmost edge any root
settles at**, aligned with the topmost root — one named constant,
``RootOverlap/margin``, shared by the placement and by the advice a collision gets.
Because the placement clears every existing edge, an auto-placed root cannot land on
one, whatever order the roots happen to be declared in.

"Any root" includes **reusable component definitions**. A definition is drawn on the
canvas like any other root, so a kit of components fans out to the right exactly as a
row of artboards does, and two definitions on top of each other warn and lint the same
way. So does a component *instance* placed at the root, at its component's size.
Placement and the overlap check measure exactly the root rects `lint` reads — only the
roots, and only the subtrees of roots sized to their content, so the check stays cheap —
and the two cannot disagree about what is on the canvas.

A root you place *yourself* is placed exactly where you say, even on top of another
root. The write is not refused — you may be about to write again — but it says so, one
line per pair on standard error, and `--json` carries the same lines in the report's
`warnings` array:

```text
$ woodcase set design.pen Chk01 common.x=100
Checkout  Chk01
rev  4f2a1b0c9d8e7f60
document  a1b2c3d4e5f60718
warning artboard-overlap  Checkout (Chk01)  100,0 200×100 overlaps Home (Home1) 0,0 200×100. Artboards do not overlap: run `woodcase set design.pen Chk01 common.x=300` to put it clear by 100pt.
```

Only overlaps the write *created* are warned about — one already in the file is
`lint`'s business, and repeating it on every unrelated edit would train you to ignore
the line. `woodcase lint` reports every overlapping pair, under the same
`artboard-overlap` check, until they are resolved.

`cp` is the other way to make nodes: it duplicates a subtree with fresh ids — always
fresh, since a copy that kept the source's ids would collide with it — and copying a
*reusable* node makes an instance of it, exactly as Pen does. An instance *inside* the
copied subtree follows the copy of its component; one pointing at a component outside
the subtree still points at the original. Properties on
the command line apply to the copy and never to the source, and a key written as a
name path lands inside the copy:

```bash
woodcase cp design.pen Home document common.name=Checkout \
  Header/Title/kind.content=Checkout --as ana
```

When the copy is an *instance*, a name-path property has nowhere of its own to land:
a node inside an instance is stored in the instance's `descendants` map, keyed by the
raw .pen name. `cp` writes it there in the same write, translating `kind.content` to
`content` on the way — so the command above reads the same whether `Home` is reusable
or not, and the second vocabulary is only needed for a later `override`. A raw name
(`Header/Title/content=Checkout`) is taken as written either way.

**Repeating a node.** `--times N` makes N copies in one write, in order, at `--at` if
given. Identical names would make the copies indistinguishable by path, so `--times`
requires `common.name` to contain the placeholder `{n}` — and refuses, naming it,
when it does not:

```text
$ woodcase cp batch.pen Canvas/Cards/First Canvas/Cards common.name='Card {n}' --times 3
Card 1  kmucG
Card 2  oOwV3
Card 3  UTB9Q
document  50e8fe3366ef6a5f
```

`{n}` is replaced with `1`, `2`, … `N` in every property that carries it, not only
`common.name` — a name path such as `Header/kind.content='Item {n}'` numbers a
descendant the same way. A `--rev` guards only the first copy; the rest apply
against the document each previous copy just produced, so re-checking the same
token against them would fail against this command's own writes.

Each copy logs the same events a single `cp … common.name=X` already does — an
insert and, because `--times` always sets a name, a property set:

```text
$ woodcase activity --file batch.pen
01:32:26 | ana | add      | Canvas/Cards/First +1
01:32:26 | ana | set      | Canvas/Cards/Card 1
01:32:26 | ana | add      | Canvas/Cards/First +1
01:32:26 | ana | set      | Canvas/Cards/Card 2
01:32:26 | ana | add      | Canvas/Cards/First +1
01:32:26 | ana | set      | Canvas/Cards/Card 3
```

One `cp --times` is one command, so one `undo` takes the whole of it back however
many rows it logged; `undo --event` steps one row at a time when a row is what you
mean.

**A list of nodes.** `--times` repeats a copy but cannot vary what is *in* it, which is
what a list of cards, rows or chips needs. `--each rows.jsonl` makes one copy per row,
and a row is one JSON object whose keys are exactly the keys `cp` takes on the command
line — including the name paths that land inside the copy:

```text
$ cat rows.jsonl
{"common.name":"Chip 1","Label/kind.content":"Draft"}
{"common.name":"Chip 2","Label/kind.content":"Shipped"}
{"common.name":"Chip 3","Label/kind.content":"Archived"}
$ woodcase cp design.pen Chip Board --each rows.jsonl
Chip 1  kmucG
Chip 2  oOwV3
Chip 3  UTB9Q
document  50e8fe3366ef6a5f
```

A key given on the command line is the default for every row, and a row's own key wins
over it — which is how a value shared by every copy is written once. `{n}` still counts,
from 1. `--at` places the copies in row order from the index given. `--each` and
`--times` are alternatives; pass one.

The whole run is all or nothing, in the message as well as in the file: every row's name
paths are resolved against the **source** before the first copy is written, so a typo on
row 39 is refused naming the row and the key, with nothing created:

```text
$ woodcase cp design.pen Chip Board --each rows.jsonl
row 3 writes Nowhere/kind.content, but Chip has no Nowhere inside it, so the copy would have nowhere to put it — run `woodcase tree design.pen Chip` to list the paths inside it, and key the property with one of them
```

There is no templating beyond `{n}` and no binding syntax: a row is data, and anything
more elaborate belongs in whatever wrote the rows. In a batch the same thing is an
`each` array on a `cp` line, with the rows written inline.

## Rebuilding a subtree

When a node needs to change more than a few properties, `replace` swaps its whole
subtree for an authored one — and keeps the node's **id**, its **parent** and its
**index among its siblings**. That is the difference from `rm` followed by `add`: the
id survives, so every path, `--rev` and component reference pointing at the node still
points at it.

The subtree is read with `-F` exactly as `add` reads one, and the same id rule
applies, with one addition: an id the *replaced* subtree holds today may be reused,
because it goes away with it. The root's own id is the target's whether you write it
or not.

```text
$ woodcase replace banking.pen hdrG -F hdrg.json --as ana
hdrG  CcYdb
  Greeting  mg6AA
  hdrN  nC2gn
rev  7b0756f5c60c4191
document  ecd6ea9d16fb0f94
```

`hdrG` kept `CcYdb`; its children are new nodes with new ids. One `replace` is one
entry in the activity log, so `undo` puts the old subtree back in one step:

```text
$ woodcase undo banking.pen --as ana
replace  ana  2026-09-26T15:44:21.739Z  banking-home/header/hdrG
revision b69f6dc48a5ddc6c
```

Two things it refuses. A root `id` that is not the target's, because the target's is
kept either way and a different one can only mean you expected something else:

```text
$ woodcase replace batch.pen Canvas/Cards -F bad.json --as ana
the replacement for Canvas/Cards writes the id Nope1, but a replace keeps the target's own id, Crd01 — write `"id": "Crd01"` on the root, or leave the id out
[exit 2]
```

And a change to the *type* of a reusable definition that instances point at — every
instance draws the definition, so the swap would silently change all of them:

```text
$ woodcase replace batch.pen Component -F comp.json --as ana
Component (Cmp01) is a reusable frame that 1 instance draws: Board/Chip (Chi01), so its root cannot become a text — keep `"type": "frame"` on the replacement's root and rebuild what is under it
[exit 2]
```

Rebuilding the definition's *contents* is exactly what the verb is for, and every
instance follows the new contents on its next render — **but not with its overrides.**
An instance's `descendants` map is keyed by the definition's child **ids**, and a
replacement mints a fresh id for every node it does not write one for. So every
override whose id the replacement does not carry forward is dropped: it stays in the
file, keyed to a node that no longer exists, and nothing draws it. No warning, no lint
finding. `woodcase get <definition> --instances` lists who would lose them.

That makes `replace` two different verbs depending on the target. On a root with no
instances it is the idempotent rebuild primitive, and the right answer. On a **live
definition** it is the dangerous one, and the house idiom is to edit in place instead:

| Change | Command |
|---|---|
| add a child | `add` or `cp` into the definition — existing ids untouched |
| change a child | `set` on that child |
| rename a child | `set common.name` — safe, because overrides are keyed by id, not name |
| remove a child | `rm` |

Writing the old ids into the replacement keeps the overrides that name them, which is
the escape hatch when a rebuild really is the shape of the change.

## Revision tokens

Every read hands back a revision; every write accepts one as `--rev`. It is optimistic
concurrency scoped as narrowly as the edit: the token guards the node the verb acts on
(the *parent* for `add` and `cp`, the whole document at the root), so two agents
editing two cards never collide.

```text
$ woodcase set banking.pen Greeting kind.content=Hi --rev 0000000000000000
banking-home/header/hdrG/Greeting (DhDsc) has changed: rev was 0000000000000000, the node is now c473caf8b4d0bff4 — re-read it with `woodcase get banking.pen DhDsc` and retry with the revision it prints
[exit 3]
```

**Exit 3 is the read-then-write signal.** The correct response is to re-read the node,
decide whether your change still makes sense, and re-issue it with the new token —
never to retry without `--rev`. Omitting `--rev` means "apply regardless", which is
right for a first write and wrong for the second half of a loop.

**Where a token comes from.** `get`'s header line, a write's `rev` line, and the `rev`
field on every row of `tree --json`. The text outline prints only the document
revision, so a per-node token comes from `--json` or from `get`.

**A rev pins a whole subtree, in one comparison.** A revision is a Merkle content hash:
16 hex characters over the node's own properties and, in order, each child's revision.
So it changes when any descendant changes and does not change when a sibling does —
and a *frame's* rev covers everything the file stores under it. "I read this whole
frame and composed against it" is therefore one token, not one per descendant: quote
the frame's rev on the write and a foreign change anywhere inside it fails loudly.

**Including what it draws.** A `ref` *stores* the component's id and its own overrides,
not the component — so a hash of stored content alone would say a frame full of
instances was unchanged after the definition edit that redrew every one of them. A ref's
rev folds in the rev of the component it renders (and of any component it repoints a
nested ref at), so editing a definition moves the definition's rev **and** the rev of
every instance, of every ancestor above one, and of the document. One token on a frame
pins what that frame renders; there is nothing separate to pin.

> Until 2026-08-31 this was the documented exception: a definition edit moved no
> instance's rev, and callers were told to pin the definition separately. It is not the
> behaviour any more, and a caller who pinned both is simply pinning one thing twice.

Three consequences worth relying on. It is **state-based**, so a node touched and put
back reads as unchanged, which is the honest answer to "has this moved since I looked?"
— a timestamp would say yes. It is **derived from the file alone**: no log, no daemon,
no history, so any process reading the same bytes prints the same token, and two agents
comparing revs are comparing the same thing. And it is **replica-independent**, so it
survives the collaborative layer unchanged.

For a row inside an expanded component instance, the `rev` is the *instance's* — an
override to that target is stored on the ref, so that is the node a write actually
moves, and it is the same token `get` hands back for the same address.

The details are in <doc:EditingDocuments> under *Revision Tokens*.

## Guards: pinning the premise, not the node

`--rev` asks *"is this node exactly as I last saw it, right now?"*. That is the right
question for a single read-then-write, and the wrong one for anything longer: a batch's
own earlier lines move the subtree its later lines quote, so a 36-line batch can only
guard its first line and an agent that wants the rest to run has to disarm the token
entirely.

`--guard` asks the other question — *"has anyone **else** moved what I reasoned about
since I read it?"* — and it takes the same token:

```text
$ woodcase tree banking.pen --json | jq -r '.rows[] | select(.address=="banking-home/header/hdrG") | .rev'
5774ee7ba5cc6fed
$ woodcase set banking.pen Greeting kind.content=Hi --guard hdrG=5774ee7ba5cc6fed --as ana
banking-home/header/hdrG/Greeting  DhDsc
rev  9c09bfd7c969c73a
document  ae82f344ac86b43f
```

Three things make it a different tool from `--rev`.

**It is evaluated once, at transaction entry** — the moment the file lock is taken and
before a single line runs. Under that lock every foreign write strictly precedes entry
and every line of your own batch follows it, so line 30 may guard a frame that line 3
legitimately rewrote and the guard still answers the question you asked.

**It can be scoped to what you read, not to what you write.** Bare, it pins the node the
verb acts on (the parent for `add` and `cp`, the document at the root, and for `apply`
the whole file — which is what a batch acts on). Written `<node>=<rev>` it pins any node
you name — the frame you read and composed against, three levels above the text you are
changing. `document=<rev>` pins the whole file. `--guard` may be repeated, and it is on
every write verb including `apply`, where argv's pins are asserted first and then each
line's own:

```json
{"op":"set","target":"Files/Row/Name","props":{"kind.content":"README"},"guard":{"node":"Files","rev":"3c1f0a9b7e2d4568"}}
```

```bash
woodcase apply design.pen -F ops.jsonl --guard Dashboard=3c1f0a9b7e2d4568 --as ana
```

**A failed guard refuses the whole transaction**, before anything applies — guards are
entry gates, not per-line statuses, so a batch whose line 30's premise moved does not
apply lines 1 to 29 against a file that is no longer what it was composed for:

```text
$ woodcase apply banking.pen -F ops.jsonl --guard banking-home/header=88999e338266072b --as ana
banking-home/header (6m90O) has changed since you read it (bo moved it): --guard pinned 88999e338266072b, and it is now 60feeb0295758bb8 — re-read it with `woodcase get banking.pen banking-home/header` and re-derive the write from what it says now
[exit 3]
```

The writer's name comes from the activity log; a write made with no `--as` reads as *an
unattributed write moved it*, and when the log cannot say the clause is simply absent.
Nothing is written, and the correct answer is always the same: re-read, decide whether
the change still makes sense, and re-issue it against what the file says now.

Guards are **absent by default**, and a write without one behaves exactly as it always
did: apply and report. That is deliberate — the default has to stay the thing that keeps
four agents working in one file at zero spurious failures.

**A guard fits a short structural batch; it is not a session-long gate.** The premise
it pins is one you read a moment before, and it costs nothing to pin the whole document
for a batch that runs in a second — one agent guarded `document=` on line 0 of a
seven-board reflow and reports it cost nothing. Held across a long run it is the
opposite: nothing renews a guard, so every unrelated edit another writer makes turns
into your failure. Read, guard, write, release the premise by finishing.

### Rehearsing a write

Every write verb takes `--dry-run` — `add`, `apply`, `cp`, `mv`, `override`, `replace`,
`rm`, `set`, `undo`, `vars set`, `vars rm`, `vars axis add`, `imports set`, `imports rm`
and `new`. It is the write,
run and thrown away: the same lock, the same `--rev` and `--guard`, the same edit, the
same settling, and then the transaction rolls it back. The file, its revisions and the
activity log are what they were.

```text
$ woodcase set design.pen Cards/First kind.width=900 --dry-run
dry run  nothing written
Canvas/Cards/First  Cd101
warning clipped  Canvas/Cards/First (Cd101)  0,0 900×60 sits partly outside Cards (380×200). …
```

Three things differ from the real answer. A marker leads standard output, so a rehearsal
in a log can never be read as a write (`--json` carries `"dryRun": true` instead — a
marker line would not parse). **No revision is printed**, because none was made: the file
is still at the one it had, and the one this edit would have produced names nothing on
disk. And the findings the write would *introduce* follow the report, in `lint`'s own
line format — only the new ones, so a file that already lints dirty does not bury the
answer.

The exit code is the write's, not the lint's: a rehearsal that would lint dirty still
exits 0, and one a guard refuses still exits 3 having printed no report at all. So
`--dry-run` is the read that answers "what would this break?", which no other read can:
`lint` describes the file as it stands, not as your edit would leave it.

The verbs that answer with something other than a node keep their own shape and drop
their own revision line. `new` is the one exception to the mechanism: there is no file
yet to lock, so its rehearsal runs both refusals — the path exists (exit 3), the parent
directory does not (exit 4) — and then prints the path without creating anything.

## Batches

Many edits in one transaction, one operation per JSON line, applied in order:

```json
{"op":"set","target":"hdrN","props":{"kind.content":"Sam"}}
{"op":"add","parent":"banking-home/header","tag":"pill","node":{"type":"frame","name":"Pill","fill":"$accent","padding":4}}
{"op":"set","target":"@pill","props":{"kind.cornerRadius":8}}
{"op":"set","target":"nope","props":{"kind.content":"x"}}
```

```text
$ woodcase apply banking.pen -F ops.jsonl
line 0  applied  banking-home/header/hdrG/hdrN
line 1  applied  banking-home/header/Pill  Ozb3f
line 2  applied  banking-home/header/Pill
line 3  failed   nope matches no node in this document — check the path, or point it at the `@tag` of an earlier line that creates it
3 applied, 1 failed, 0 cascaded — revision 6a3defd427ca347d
[exit 1]
```

Three things to take from that. A **tag** (`"tag":"pill"`, then `"@pill"`) lets a later
line name what an earlier one created, without a round trip to learn the id. A failed
line **changes nothing and does not stop the batch** — exit 1 says some line failed,
not that the file is untouched. And `--json` gives a report you can hand straight back
as `--retry report.json`, which re-runs only the failed and cascaded lines. `--atomic`
is the other policy: discard everything on the first failure.

A line that stored something other than what it said carries its divergence indented
underneath, so the sentence and the line it belongs to are never separated:

```text
line 0  applied  banking-home/header/hdrG/hdrN
        kind.content stored the number 3 as the text "3" — the property takes text, not a number
```

The full grammar — every op, both property vocabularies, tags, placement, statuses —
is <doc:WoodcaseBatches>, and `woodcase apply --help` prints it verbatim.

## When the answer is a loop

Two of the verbs take JavaScript, and they are the two answers to questions a fixed list
of edits cannot ask. `find` is the read: a predicate over the rows `tree` prints, which
exits 1 when nothing matches, so a shell can branch on the answer. `js` is the write: a
whole program inside one transaction, with a `doc` object whose members are these verbs
one for one — and `undo` reverses the whole run as one step.

Reach for them when control flow is the point: when what to write depends on what a read
just said, when a loop carries a running total, or when a measurement decides whether to
commit at all. Reads inside a script see settled layout, so a script can write, measure
what it just made, and throw rather than commit — which is the one thing no batch can
express, because a batch is decided before it runs. The everyday tell is noticing that
the next step is the read–write–verify loop *again*: write, read the settled rect,
adjust, write again. That repetition is a `js` program — the measurement happens inside
the transaction, and nothing is committed until it passes — not a second, third and
fourth transaction of single writes.

```bash
woodcase find design.pen 'r => r.rect.height > 64'
echo 'doc.lint().length' | woodcase js design.pen -F -
```

A verb is still often enough, and `cp --each` and `apply` cover a surprising amount.
<doc:WoodcaseScripting> is the whole contract — the transaction rules, the TypeScript
declaration of `doc`, the refusals and the watchdog — and `woodcase help js` prints it in
the terminal.

## The activity log, and undo

Every write appends to the project's log: `.woodcase/activity.jsonl` at the
nearest `.git` above the .pen file, or beside the file when there is no repository. The
write that first creates `.woodcase/` adds it to that repository's `.gitignore`, so the
history stays local. `$WOODCASE_HOME`, if set, overrides all of that with one log.

Identity comes from `--as` or `$WOODCASE_AS`; with neither, the edit still applies and
is still logged, as an unattributed write with an empty identity. Nothing you do to a
.pen file through `woodcase` is invisible to the log.

`woodcase activity --file <path>` reads that file's project log; with no `--file` it
reads the log of the project you are standing in.

The .pen file to narrow to is the first argument, where every other verb takes it;
`--file` spells the same thing, and naming two different files that way is a usage
error. Either way the file need not still exist — the feed is the log's, not the
file's.

```text
$ woodcase activity banking.pen -n 6
10:47:20 | ana | add      | banking-home/header/Notice +1
10:47:21 | ana | override | banking-home/quick-actions/qa1
10:47:21 | ana | var      | -
10:47:21 | ana | set      | banking-home/header/hdrG/hdrN
10:47:21 | ana | add      | banking-home/header/Pill +1
10:47:21 | ana | set      | banking-home/header/Pill
```

Each event carries the operations that reverse it, which is what makes `undo` exact
rather than a guess:

```text
$ woodcase undo banking.pen -n 2
set  ana  2026-09-26T15:47:21.765Z  banking-home/header/Pill
add  ana  2026-09-26T15:47:21.761Z  banking-home/header/Pill
set  ana  2026-09-26T15:47:21.727Z  banking-home/header/hdrG/hdrN
var  ana  2026-09-26T15:47:21.362Z  -
revision f4144cc3b4900df4
```

**One step is one command.** Every event of one write shares a batch id, and `undo`
reverses the whole of the newest one — so a batch of forty lines, a `cp --times 3` or
an `apply` goes back with a single `undo`, and `-n` counts commands, not log rows: the
call above reversed two *commands* — the `apply` batch (three rows: `set`, `add`,
`set`) and the `var` write before it — which is four rows in the printout. The rows are
still what it prints, one per event, newest first. `undo --event` is the finer step for
when the row is what you mean; the two compose, so a plain `undo` after an `--event`
one finishes the command it left half reversed.

An edit is reversed only while the file is still in the exact state that edit
produced. Somebody else's later edit stops the undo and names them — here `bo` edits
`hdrN`, `ana` edits it again afterward, and `bo`'s own attempt to undo his edit is
refused because the node has moved since:

```text
$ woodcase undo banking.pen --as bo
Cannot undo banking.pen: ana made a later set to banking-home/header/hdrG/hdrN at
2026-09-26T15:48:27.433Z, leaving it at revision 95ab8eb3e3a02da2. Undo never guesses.
See it with `woodcase activity --file banking.pen`, or pass --all to undo across
identities.
[exit 3]
```

An undo is itself a logged edit, so a second `undo` reaches the edit before the one the
first reversed. Undo is not redo: an undo entry in the log is stepped over, never
replayed. With nothing left to reverse it exits 1 and says so. Unlike every other
write, `undo` **requires** an identity — an unlogged undo would leave the log's tail no
longer describing the file. The wire format and rotation are <doc:WoodcaseActivityLog>.

### When somebody edits the file behind the log's back

Every write checks, as it opens the file, that the log accounts for the bytes it just
parsed: the newest event records the revision it produced, and a document revision is a
content hash. When they disagree, something rewrote the file without asking for the lock
— another editor saving, a script with a JSON parser — and the write says so and carries
on:

```text
$ woodcase set banking.pen hdrN kind.content=New --as ana
note  banking.pen was rewritten outside woodcase since rev 1ce327f4 (ana, 10:48); the log has no record of that change
banking-home/header/hdrG/hdrN  4YeMj
rev  bfbf43f5f0f4afe0
document  4e965df92d501bb2
```

It is a note, not a refusal — the outside edit may be perfectly good. The write records
what it found as an `external` row in the log, so the note fires once and `woodcase
activity` shows where the history has a hole. Under `--json` the note goes to standard
error instead, so the answer stays one parseable document.

`undo` will not step past that row: there is no inverse to replay for an edit woodcase
did not make. The write above is itself perfectly reversible — one `undo` puts `hdrN`
back to what the external edit left — so it takes a *second* `undo` to reach the row
with no inverse:

```text
$ woodcase undo banking.pen --as ana
set  ana  2026-09-26T15:48:43.202Z  banking-home/header/hdrG/hdrN
revision 27f7aae3f421b70f

$ woodcase undo banking.pen --as ana
Cannot undo banking.pen: cannot undo past an edit made outside woodcase at 10:48, which
left it at revision 27f7aae3f421b70f. Nothing woodcase did produced that change, so there
is no inverse to replay. See the history with `woodcase activity --file banking.pen`.
[exit 3]
```

The lesson the note is teaching is the one the primer opens with: edit .pen files
through `woodcase`, so the lock, the log and undo all keep working.

## Overrides

A node inside a component instance stores nothing of its own. Writing to it creates an
entry in the instance's `descendants` map, exactly as the format writes it — that is
`override`, and `set` will tell you so if you aim it there.

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/label content=Top-up
banking-home/quick-actions/qa1  zHahn
rev  f479a8178a6cd161
document  3a7cd56b1641f783
```

**Overrides are keyed by the definition's child ids, never by their names.** The map
in the file reads `"descendants": {"uDTGV": {"content": "…"}}`, so renaming a
definition's child — or renaming the whole definition and every node under it — costs
an instance nothing. What *does* break an override is losing the id, which is what
`replace` does to a live definition; see **Rebuilding a subtree**, above. Names are how
you address a node; ids are the currency inside an instance.

The answer names the **instance**, because that is where the override lives and what
`--rev` guards. Property names here are **raw .pen names** — `content`, not
`kind.content` — because that is the vocabulary Pen keys the map with. It is the one
place the two vocabularies differ, and it is the *stored* form, not a demand: write
`kind.content` and `override` translates it to `content`, the way `cp` does for a copy
it just made. So the vocabulary you read is always a vocabulary you can write.

Values are read the same way `set` reads them, and that includes the one coercion: a
number written to a property that takes text is stored as the text it spells, and says
so.

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/label content=42
banking-home/quick-actions/qa1  zHahn
content stored the number 42 as the text "42" — the property takes text, not a number
rev  ce885479b77e3750
document  7bda5905da07c6c3
```

A descendant key that names nothing in the component is **refused**, with the keys it
does have — and so is a **value the node it patches cannot take**. An override is
merged onto the component's node as raw JSON when the instance expands, and a value of
the wrong shape makes that merge fail, leaving the unpatched node: an override `get`
confirms back forever and that never draws. Either it applies or the write is refused;
it is never quietly dropped.

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/label content='{"a":1}'
content on banking-home/quick-actions/qa1/label takes a string or a $variable, but the value given is an object; an override a node cannot take is dropped when the instance expands, so it is refused here instead — correct the value; `woodcase get banking.pen zHahn/M5gJu` shows what it draws now
```

A key that is right but a *property* the definition never sets is a **note**, not a
refusal and not a warning — adding a property is how a variant differs from its
component, and the sentence says which of the two things you did:

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/label letterSpacing=1
banking-home/quick-actions/qa1  zHahn
note  banking-home/quick-actions/qa1/label adds letterSpacing rather than replacing it — component/QuickAction does not set letterSpacing, which is how an instance varies from its component
rev  b23b4ce4c4fe4813
document  e995738237ba9be3
```

That is the ordinary way to write a variant: `enabled=false` on a descendant the
component never disables, `opacity=0.5` on one it never fades. Nothing is wrong, and
nothing needs fixing.

If instead the property is one the node's *type* has no room for, the sentence is a
divergence and says so outright — the override is stored, and nothing will ever read
it. That is the failure mode this echo exists for: `get` will confirm the key back to
you, faithfully, forever.

### Declaring a component's parameters

A component can publish the handful of things an instance is *meant* to vary, so a
caller does not have to know which node inside it holds the title. The declaration is
`common.metadata._props` — the one code generation has always read — mapping a name to
the name path of the node the value belongs to:

```text
$ woodcase set design.pen StatCard common.metadata._props.label=Body/Title
$ woodcase get design.pen StatCard
Stc01  StatCard  rev 91b0c2d3e4f50617
props
  label  Body/Title/kind.content  string
{ … }
```

`common.metadata` is a whole object, and writing it replaces everything in it — which
is how `_props` used to get dropped by a write that only meant to add `_role`.
`common.metadata.<key>` writes one entry and leaves the rest; a dot goes deeper, and a
null takes one entry away. Nothing else takes a deep key.

A deep key that *creates* the object writes a `type` beside your key:

```text
$ woodcase set design.pen Button common.metadata._role=button
$ woodcase get design.pen Button --json | jq .node.metadata
{ "type": "unknown", "_role": "button" }
```

That is the schema, not a stray: `.pen` declares `metadata` as an object whose `type` is
required, so an object created from nothing has to carry one, and `unknown` is the
default this write fills in — a read of a file that already has a typeless metadata
object leaves it exactly as it was; only a write that creates the object from nothing
chooses a type. Nothing reads it — code generation decides what a node is
from `common.reusable` and `_role` — so it is free to leave. Choose it in the same write
when you have a better answer, and the two keys land together:

```text
$ woodcase set design.pen Button common.metadata.type=component common.metadata._role=button
$ woodcase get design.pen Button --json | jq .node.metadata
{ "type": "component", "_role": "button" }
```

Once a parameter is declared, its name is a key `override` and `cp` accept, resolved to
the node and property the declaration names:

```text
$ woodcase override design.pen Page/Card label=Revenue
Page/Card  Crd01
rev  6364cb651bbad74b
document  b2a456870b128afb
```

Three rules go with it. A name the addressed node already has a property of is the
**property** — `width` on an instance is the instance's width — and the answer says so
rather than choosing quietly. A name whose declared path resolves to nothing is refused
before anything is written, naming both the parameter and the path, because a stale
declaration would otherwise store an override that reads back forever and draws
nothing. And a name the component does not publish at all is unchanged: it is stored as
the raw override it has always been.

The type in the `props` block is the one code generation will emit for that parameter —
`string` for a text node's content, `color` or `imageURL` for a shape's fill — read from
the same inference, so the list is what the generated component's props will be.

## Filling a slot

A component may leave a hole for its instances: a frame whose `slot` lists the types it
accepts, which `tree` marks and `lint` leaves alone however empty it is. An instance
fills one by overriding that frame's `children` with .pen subtrees — the same JSON
`add` takes — and the expansion draws them in place of whatever the definition put
there:

```text
$ woodcase override design.pen Card1/Body -F children.json
Canvas/Card1  Card1
rev  4f2a1b0c9d8e7f60
document  a1b2c3d4e5f60718
```

```json
{"children": [
  {"id": "Note0", "type": "text", "name": "Note",
   "content": "Filled from the instance", "fontSize": 12, "fill": "$ink"},
  {"id": "Tag00", "type": "ref", "name": "Tag", "ref": "Badge1",
   "descendants": {"BTxt0": {"content": "live"}}}
]}
```

**Every injected node needs an `"id"`.** The document mints ids for what it stores, and
these are stored in the instance, so `add`'s "leave it out and one is drawn for you"
does not apply here: a child with no id is refused, naming the missing key, rather than
written as something no override could ever address.

An injected child may be a `ref` carrying overrides of its own, so a slot takes whole
composites, not only leaves. `tree --expand` prints them under the instance under the
id path the expansion gives them (`Card1/Note0`, `Card1/Tag0/BTxt0`) — reading them
back is how you check what a slot now holds.

Those ids are addresses. `get Card1/Note0` answers the injected node as it renders, and
`override` writes to it. The node is the instance's *own* content, and Pen ignores any
`descendants` key the same instance writes for it — bare or by path — so the write is not
stored as one: it is rewritten into the slot's `children`, on the node itself, where Pen
reads it. The answer leads with the instance, as every `override` does, and a `note`
line names the slot the change landed in; `--json` carries it as a `slotFillRewrite`
divergence whose `applied` is that slot's path. A second `tree --expand` shows the change:

```text
$ woodcase override design.pen Card1/Note0 content="Filled again" --as ana
Canvas/Card1  Card1
note  Card1/Note0 is content this instance wrote into the slot Canvas/Card1/Body itself, so the change was written there, on the node in the slot's children — Pen ignores an override an instance keys to its own slot content
rev  62b06f8ec3102d5c
document  0d8e7f604f2a1b0c

$ woodcase tree design.pen Card1 --expand --props kind.content
```

A name path works too, and it steps through the slot frame like any other container:
`Canvas/Card1/Body/Note`. A node inside an injected `ref` is one step deeper —
`Card1/Tag00/BTxt0` — and lands on that `ref`'s own `descendants`, inside the fill.
Content this instance wrote into a *nested* instance's slot is rewritten the same way,
into the fill keyed by the path to that slot. `--unset key` removes the property from the
injected node itself — it has no component value underneath to show through — and a
value the node cannot take is refused naming the node, not the slot.

What a slot *holds* is still one value. `rm`, `mv` and `cp` refuse an injected child and
say so: the node is one entry in the slot's `children`, so adding, removing or
reordering means writing that array again, and `tree --expand` is how you read the
result.

**Removing an override is `--unset`, not `=null`.** The two look alike and are
opposites. `key=null` *stores* a null: the override entry is still there, `get` still
reports it, and what it does when the instance expands is take the definition's value
away. `--unset key` removes the entry, so the definition shows through again — and an
entry left with no keys goes away entirely, so a removal reads back as the absence it
is. `--unset` is repeatable, takes either vocabulary, and may be written with or
without a `key=value` — but never for the same key as one.

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/label fontSize=18
banking-home/quick-actions/qa1  zHahn
rev  b23b4ce4c4fe4813
document  e995738237ba9be3

$ woodcase override banking.pen banking-home/quick-actions/qa1/label --unset fontSize
banking-home/quick-actions/qa1  zHahn
rev  b090a7b4c731c3a6
document  c06303709f9f65bb
```

A null over a value the definition *does* set is the destructive case, and says so:

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/label content=null
banking-home/quick-actions/qa1  zHahn
banking-home/quick-actions/qa1/label sets content in component/QuickAction — the null override clears it rather than removing the override; unset content instead to show the component's value again
rev  00fd062478308537
document  abc71b7df4007428
```

A null over a property the definition never sets patches nothing, and stays quiet.

**A name path into an instance names every frame of the component's tree.** Only an
**id** may skip the containers between the component root and the node. So a path that
does not resolve is refused the same way any other missing address is:

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/count content=3
banking-home/quick-actions/qa1/count matches no node in this document — run `woodcase tree banking.pen` to list the addresses it has
```

When a name *does* exist further down the component's own tree, the miss instead hands
back the address that would have worked, naming the container the name path skipped —
`qa1/label` only resolves when `label` is a direct child of the component; a name
wrapped in an extra frame needs every step (`qa1/content/label`), and only an id may
skip one.

**Repointing a nested instance.** `ref` is a property like any other, so an override
that writes it swaps which component one of the instance's own nested instances shows
— an icon glyph that reads `V:IbYvu` in the definition can read `V:jyrsO` in this
instance alone:

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1/#M7RGT ref=V:jyrsO
banking-home/quick-actions/qa1  zHahn
rev  c1b92d8ebab9b7da
document  6bad4bb240de0f49
```

The instance settles at the new component immediately: its rect, its children and
every address inside it are the new component's from the next read on, and writing
the original id back restores the original reading exactly. Only the instance a node
sits *directly* inside can repoint it, which is the limit the expansion itself has: a
`descendants` key with a `/` in it is applied after the nested instance has expanded,
when the `ref` it would rewrite is already gone.

**The instance's own root** is the other half. An instance may also override the
component *root's* properties — its width, its fills, its corner radius — and that is
`override` addressed at the **instance itself**, with no path after it:

```text
$ woodcase override banking.pen banking-home/quick-actions/qa1 width=80
banking-home/quick-actions/qa1  zHahn
note  banking-home/quick-actions/qa1 adds width rather than replacing it — component/QuickAction does not set width, which is how an instance varies from its component
rev  aced155966a27569
document  c2b1cbdf8de5285a
```

One address, two verbs, and the split is the format's own. `set` on that same address
writes the **ref node**: where the instance sits, whether it draws, what it is called —
`common.x`, `common.opacity`, `kind.ref`. `override` writes what the ref *shows*. Aim
either one at the other's half and it says which command does work:

```text
$ woodcase set banking.pen banking-home/quick-actions/qa1 kind.width=80
kind.width is not a property of a ref; it is a property of the component banking-home/quick-actions/qa1 (zHahn) shows, which an override writes — run `woodcase override banking.pen banking-home/quick-actions/qa1 width=…` instead; the instance itself accepts `common.context`, `common.enabled`, `common.flipX`, `common.flipY`, `common.layoutPosition`, `common.metadata`, `common.name`, `common.opacity`, `common.reusable`, `common.rotation`, `common.theme`, `common.x`, `common.y`, `kind.descendants`, `kind.ref`, `kind.rootOverrides`

$ woodcase override banking.pen banking-home/quick-actions/qa1 opacity=0.5
opacity on banking-home/quick-actions/qa1 (zHahn) is the instance's own property, not a property of the component it shows — run `woodcase set banking.pen banking-home/quick-actions/qa1 common.opacity=…` instead; it belongs to the instance, not to the component it shows
```

That refusal is the format speaking. Root overrides are written as the ref node's own
top-level keys — there is no `rootOverrides` key in a .pen file, whatever
`kind.rootOverrides` suggests — so a key the ref reserves for itself would come back
meaning the instance rather than the root it was aimed at. In a subtree they are still
written inline:

```json
{"type":"ref","ref":"msdSu","name":"Top-up","width":80}
```

and `set kind.rootOverrides={…}` still replaces the whole map at once, where
`override` merges one key and `override --unset` removes one. A subtree carrying a
literal `"rootOverrides"` key is refused: the decoder would sweep it in with the rest
and leave an override *named* `rootOverrides`, patching a property no node has — an
edit that applies, reads back, and does nothing.

**Who instances this component?** `get <definition> --instances` is the read side of
the guard `rm` and `replace` enforce. One row per `ref` that draws it — address, id and
its own revision, in document order — under the same header line a plain `get` prints,
so the pin for the write that follows is already in hand:

```text
$ woodcase get banking.pen '#msdSu' --instances
msdSu  #msdSu  rev 2682c83b7d405b3a  4 instances
banking-home/quick-actions/qa1  zHahn  rev aced155966a27569
banking-home/quick-actions/qa2  5qeyz  rev eeaddf7ce1ea702f
banking-home/quick-actions/qa3  C9ojc  rev d292abe2de0a74e2
banking-home/quick-actions/qa4  e0uPH  rev 54a4884b2b5fc9ef
```

The definition's own name contains a `/` (`component/QuickAction`), so it too shows as
`#msdSu` — the same marker **Addressing a node**, above, describes for a name that
cannot survive the round trip.

It prints no node, so it does not combine with `--expand`, and `--json` answers
`{"definition":{…},"instances":[{"id":…,"address":…,"rev":…}]}`. A node that is not
reusable is refused rather than answered with an empty list: nothing can instance it,
and an empty list would read as "nothing does".

There is no `banking-home/quick-actions/qa1/<component id>` address for the root, and
nothing offers one: an override whose descendant key names nothing lists only the keys
an address can reach.

## Refusals with consequences

Some edits change more than the node they name. Those are refused, listed, and given a
flag that opts into the consequence explicitly.

```text
$ woodcase rm banking.pen '#msdSu'
deleting #msdSu would leave 4 instances as plain nodes: banking-home/quick-actions/qa1 (zHahn),
banking-home/quick-actions/qa2 (5qeyz), banking-home/quick-actions/qa3 (C9ojc),
banking-home/quick-actions/qa4 (e0uPH) — pass `--detach` to detach them first
[exit 2]
```

`rm --detach` turns each instance into a real copy of what it was showing, and only
then deletes the component. `vars rm` has the same shape: it refuses while anything
still references the variable, lists what does, and takes `--force`. So does
`imports rm`, over the alias's namespace rather than a `$name`.

Two refusals have no flag at all, because there is no sensible way to opt in:

```text
$ woodcase mv banking.pen banking-home/header banking-home/header/hdrG
banking-home/header (6m90O) cannot move into banking-home/header/hdrG (CcYdb), which is inside it — run `woodcase tree banking.pen` to pick a parent outside the node being moved
[exit 2]

$ woodcase mv banking.pen hdrN banking-home/quick-actions/qa1
banking-home/quick-actions/qa1 (zHahn) is a ref, and only a frame or a group can hold children — run `woodcase tree banking.pen` to find a frame to add to
[exit 2]
```

Aiming `set` at a node inside an instance is refused the same way, and hands you the
command that *would* work:

```text
$ woodcase set banking.pen banking-home/quick-actions/qa1/label kind.content=x
banking-home/quick-actions/qa1/label is inside the component instance banking-home/quick-actions/qa1, which stores no properties of its own — run `woodcase override banking.pen banking-home/quick-actions/qa1/label name=value` instead, with raw .pen property names (content, not kind.content)
[exit 2]
```

All of these are exit 2, not 1: the check ran and the *invocation* is incomplete — a
flag is missing, or the target is the wrong one — rather than a question having been
answered "no".

## Variables and themes

`vars` lists what the document defines, with a reference count per variable, and the
axes underneath:

```text
$ woodcase vars banking.pen
variables
  accent          color   1 ref, 1 var
    *                       #3d5a80
    tint=sand               #b7791f
    scheme=night            #8fb0dc
    …
  ink             color   15 refs
    …
axes
  contrast  normal, high
  scheme    day, night
  tint      slate, sand, moss, clay
```

`vars set` adds or changes one, registering a theme axis or option on the fly if the
pin names one the document lacks. A variable name that starts with a dash needs a bare
`--` before it, or the parser reads it as an option: everything after the `--` is an
operand. Forget it and the refusal says so, and prints the line to run. A kit-style
name like `accent` never starts with one, so the marker below is optional here — write
it out of habit anyway, since the moment it becomes load-bearing is exactly the moment
you are least likely to remember it.

```text
$ woodcase vars set banking.pen --theme scheme=night -- accent=#22c55e
accent already existed with 1 ref, 1 var, as color * #3d5a80, tint=sand #b7791f, tint=moss #3f7d4e, tint=clay #b5543c, scheme=night #8fb0dc, scheme=night,tint=sand #e0b062, scheme=night,tint=moss #7cc48f, scheme=night,tint=clay #e38b72 — this
write changes what all 2 of them resolve to.
  accent  color  1 ref, 1 var
    *                       #3d5a80
    tint=sand               #b7791f
    scheme=night            #22c55e
    …
revision 581f0f28f3481a6b
```

`set` adds *or* changes, and the outline is the same either way — so a name the document
already defines is announced before it, with its old value, every option of a themed one,
and how many things were resolving through it. A fresh name gets no such line; `--json`
carries the same as a `previous` field rather than a sentence.

Several pairs go in one call, in one transaction, with `--theme` and `--type` applying to
every one of them — `woodcase vars set banking.pen -- --bg=#111111 --fg=#eeeeee`. Each
variable is still its own `var` event in the activity log, so one `undo` takes the call
back whole. A whole token layer written from data belongs in `apply` instead: one `var`
line per token carries every theme option at once, and registers the axes it pins. See
<doc:WoodcaseBatches>.

Pinning a themed value on a variable that had a single one keeps the old value as the
*default* variant, so nothing that referenced it changes meaning. Removing a variable
anything still uses is refused with the nodes named:

```text
$ woodcase vars rm banking.pen -- ink
Cannot remove ink: 15 nodes reference it — banking-home/status-bar/sbT, banking-home/status-bar/sbI/sbS,
banking-home/status-bar/sbI/sbW, banking-home/status-bar/sbI/sbB, banking-home/header/hdrG/Greeting,
banking-home/header/hdrG/hdrN, …
and 5 more. Pass --force to remove it anyway, leaving those references unresolved.
[exit 2]
```

`imports` is the same pair of verbs over the document's other table of names: `imports
design.pen` lists each alias with the number of nodes that reach into its namespace,
`imports set design.pen V ./library.pen` adds or repoints one, and `imports rm` refuses
in the same sentence while a `ref` or a `$V:` binding still needs it.

The type follows `--type` if given, else the variable's existing type, else the
literal's shape: `#RGB`/`#RRGGBB`/`#RRGGBBAA` is a colour, `true`/`false` a boolean, a
number a number, everything else a string. `--type` exists because without it a string
variable whose value *looks* like a colour is unreachable.

## Lint before you render

`lint` is the review that needs no pixels: broken refs, unresolved variables, text with
no fill, text in a box too short to show it, containers that cannot size themselves,
anything clipped by its parent, two *siblings* sharing a name — a same-named cousin is
fine, since an address may start one segment higher — any two artboards sitting on top
of each other, and a `ref`'s own
stored override carrying a value, a key or a property its instance will drop silently on
expansion — the read side of the refusals **Overrides**, above, describes at the write.
It exits 1 when it finds something, so it composes as an assertion.

```text
$ woodcase lint banking.pen Dt9Jv --severity error
error unknown-icon  #Dt9Jv/icon (qbtkE)  uses icon `home` from library `lucide`, which has no icon of that name. No similar name was found in `lucide`.
[exit 1]
```

A document is linted with the libraries its `imports` name, read from beside it —
`banking.pen`'s `V:` instances resolve against the `kit.lib.pen` next to it — and an
import with nothing to read is one `import-not-found` finding at the top of the report,
not a failed lint. See <doc:PenImportNamespaces>.

```bash
woodcase lint design.pen && woodcase render design.pen
```

Filter what's reported with `--exclude <check-id>` (repeatable) and `--severity
<level>` — the gate still exits 1 for anything left *after* filtering, 0 otherwise. A
phone screen whose scrolling list is meant to overflow the fold trips `clipped` on
purpose — or say so instead of excluding it: `common.metadata._scroll` on the clipping
frame declares which axis is a designed scroll, and lint stays quiet there while still
catching a genuine bug on the other axis.

```bash
woodcase set design.pen banking-home/list common.metadata._scroll=vertical
```

For a pre-render gate that wants everything past clipping out of the way regardless:

```bash
woodcase lint design.pen --exclude clipped && woodcase render design.pen
```

Its clip findings read `tree`'s own rows, so the two cannot disagree. The full check
table and the deliberate omissions (fonts, imports, per-instance faults) are
<doc:WoodcaseLint>.

## Fonts, and a width you should not trust

Every verb that settles a document registers its fonts first, from this machine and
from the font cache — so `tree`, `lint` and `shot` measure text in the same faces. A
family that is on neither gets one line on standard error, naming it and the face the
measurement actually used:

```text
woodcase: font "Manrope" is not installed and not in the font cache at /Users/ana/.woodcase/fonts; text in it is measured in SF Pro. Run `woodcase render` or `woodcase shot` once to download it there.
```

Standard output is unaffected and the exit code stays 0 — the file is fine, the machine
is missing a face — but **every text width in that listing is the fallback's**, so a
layout decision taken on it will not survive the render. `shot` and `render` may
download a Google font; the read verbs never go to the network, so running one of them
once is what fills the cache for the reads that follow.

The cache is `$WOODCASE_HOME/fonts`, which is `~/.woodcase/fonts` unless you set that
variable — the same variable that moves the activity log. Images downloaded for remote
fills sit beside it in `$WOODCASE_HOME/images`.

There is a second reason a font can be missing, and it has its own sentence, because
running `shot` would not help:

```text
woodcase: font "Manrope" is not installed, and the font cache at /Users/ana/.woodcase/fonts exists but cannot be read, so the fonts in it are not used; text in it is measured in SF Pro.
```

That is a permissions problem — most often an agent sandbox whose allowlist does not
name the directory. Fix the access, or point `$WOODCASE_HOME` somewhere the process can
read, and the cached faces come back.

## When you do need pixels

`shot` renders one node, scaled so its longest side fits `--max`, and prints the scale
so a pixel maps back to a layout point — `point = (pixel − gutter) / scale + origin`,
where `origin` is the printed rect's `x`/`y` and `gutter` is `0,0` unless `--grid` was
asked for.

```text
$ woodcase shot batch.pen Canvas --out canvas.png --max 800
Cnv01  scale=1.0  rect=0.0,0.0,400.0,300.0  pixels=400x300  gutter=0,0  out=/…/canvas.png
```

A bare `shot` with no node is refused rather than rendering a giant collage, and the
refusal lists what to pick — even when there is exactly one frame, because a caller
who meant a different file should see that mistake:

```text
$ woodcase shot batch.pen --out x.png
No node given — rendering the whole document risks a giant, misleading image. Pick one of these, by name or id:
  Canvas  Cnv01
  Board  Brd01
  Component  Cmp01  (component definition)
[exit 2]
```

`--grid` overlays a coordinate grid — which grows the image past `--max` by the
gutters it adds, by design — and `--outline <node>` draws a labelled box around a
node's rect, for pointing at one thing in a busy screen.

`--scale <multiplier>` renders at exactly that many pixels per layout point, and —
unlike `--max` — enlarges: a 16pt icon is unreadable at `--max`'s default 1×, but
`--scale 8` makes it a 128×128 PNG. `--scale` takes precedence over `--max` entirely,
so give one or the other, not both:

```text
$ woodcase shot icons.pen bellIcon --out bell.png --scale 8
Bel01  scale=8.0  rect=0.0,0.0,16.0,16.0  pixels=128x128  out=/…/bell.png
```

Pass your vision model's own longest-edge limit as `--max`, then read `pixels=`: it
says whether the node fitted in one look. When it did not, the answer is more pictures,
not a smaller scale. `--crop x,y,w,h` renders one sub-rectangle, written in the node's
own layout points — the space `rect=` prints — and becomes the `rect=` of that run, so
the mapping formula needs no second form. `--max` and `--scale` size the *crop*, which
is what makes a tile of a tall board legible, and `--outline` is judged against the
crop rather than the whole node.

```text
$ woodcase shot board.pen Feed --out tile-2.png --crop 0,1500,1200,1500
Fee01  scale=1.0  rect=0.0,1500.0,1200.0,1500.0  pixels=1200x1500  gutter=0,0  out=/…/tile-2.png
```

`--extent painted` frames what the node *paints* instead of its layout rect: its
stroke band, its shadows and blur, and any child an unclipped frame lets hang outside it
— the way Pen frames an export. The printed `rect=` is then that extent, in the same
space as the layout rect, so the mapping formula holds unchanged and `--crop` and
`--outline` are judged against it. The default, `--extent layout`, is the rect `tree`
reports:

```text
$ woodcase shot card.pen Card --out card.png --extent painted
Crd01  scale=1.0  rect=26.0,16.0,148.0,108.0  pixels=148x108  gutter=0,0  out=/…/card.png
```

That is a 100×60 card at (40, 30) with a 12-point outer stroke and a shadow offset
(10, 10), blur 8: the stroke reaches 12 points out, and the shadow's copy of the stroked
card reaches 22 points further right and down.

Without `--crop`, `--extent painted` also grows `rect=` to a whole number of pixels at
the render scale — the same rounding Pen's own PNG export does: the extent's corner
stays exactly where it is, fractional or not, and only the width and height grow, just
enough that `pixels=` lands on a whole pixel rather than truncating the last row or
column away. A turned node whose painted extent is 149.39×134.75 points prints a
149.5×135.0 `rect=` at `--scale 2`, so `pixels=299x270` — not `298x269` — matches Pen's
export exactly.

A crop that runs off the node is refused, naming the node's rect and the crop that
would fit; `woodcase shot … --json` prints that rect without rendering anything you
have to look at twice.

`--json` also answers the question a screenshot otherwise leaves open — *which pixels
is that?* It lists every rect the run drew, the node first and then each `--outline` in
flag order, each with the id it is keyed by and the address you typed, all in the
rendered node's own space. With the run's `scale` and gutters that is enough to place
any of them: `pixel = (point − origin) × scale + gutter`.

```text
$ woodcase shot design.pen Header --out h.png --outline Header/Logo --json
{
  "node" : "Hdr01",
  "rect" : { "x" : 0, "y" : 0, "width" : 1600, "height" : 400 },
  "rects" : [
    { "role" : "node", "id" : "Hdr01", "address" : "Header", "name" : "Header",
      "rect" : { "x" : 0, "y" : 0, "width" : 1600, "height" : 400 } },
    { "role" : "outline", "id" : "Lgo01", "address" : "Header/Logo", "name" : "Logo",
      "rect" : { "x" : 40, "y" : 24, "width" : 160, "height" : 48 } }
  ],
  "scale" : 1, "pixelWidth" : 1600, "pixelHeight" : 400,
  "gutterLeft" : 0, "gutterTop" : 0, "output" : "/…/h.png"
}
```

## Exit codes

The house table, in full in <doc:WoodcaseCLI>. What an editing loop actually branches
on:

| Code | Means | Do |
|---|---|---|
| 0 | It worked | Read the name → id tree it printed |
| 1 | A clean negative | `lint` found something; an `apply` line failed; nothing to undo |
| 2 | The invocation is wrong | An address, a property, a missing flag — the message names the fix |
| 3 | The world moved | Re-read, then re-issue with the new `--rev` |
| 4 | The file is missing or unreadable | Check the path |
| 5 | The environment is wrong | The edit may be **on disk** already and only the log failed — the message says which |

## Recipes

Copy-pasteable command sequences for what an agent actually does with everything
above — starting a file, building a screen root down, making a component and placing
it, repeating a node, themed variables, the lint-shot loop, rebuilding a subtree in
place. Each one ends in the read that verifies it, and the project's own tests keep
every command in it running: `woodcase help recipes`.

## Topics

### The verbs

- <doc:WoodcaseCLI>
- <doc:WoodcaseBatches>
- <doc:WoodcaseScripting>
- <doc:WoodcaseLint>
- <doc:WoodcaseActivityLog>
- <doc:WoodcaseViewer>

### The model underneath

- <doc:EditingDocuments>
- ``EditableDocument``
- ``NodeAddress``
- ``NodePropertyCodec``
- ``BatchOperation``
- ``ActivityEvent``
