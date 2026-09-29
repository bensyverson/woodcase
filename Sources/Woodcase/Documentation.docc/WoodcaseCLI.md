# Woodcase CLI

Read, edit and render .pen files from the command line.

## Overview

The `woodcase` command-line tool is the whole library without writing Swift: it reads a
document's settled tree, edits it a node at a time or a batch at a time, records every
edit in an activity log that `undo` can replay, renders PNG and PDF, generates React,
serves a live viewer, and rewrites older files in the current format.

It is built for agents first — see <doc:WoodcaseEditor> for the read-write-verify loop
and the addressing vocabulary — but everything it does is equally usable from a shell.

## Installation

With Homebrew (builds from source; needs Xcode 26 or later):

```bash
brew install bensyverson/tap/woodcase
```

Or from a checkout, into `~/.local` (`--prefix` to change it); running it again upgrades in place:

```bash
scripts/install
```

Both lay the install out as `libexec/woodcase/woodcase` beside `Woodcase_Woodcase.bundle`, with
`bin/woodcase` a symlink to it. The bundle holds the icon fonts and the SwiftUI and viewer templates, and
the binary finds it through ``WoodcaseResources``. `swift package experimental-install` copies the binary
alone: such a copy edits and lints, but `generate swiftui`, `generate react --viewer` and icon rendering
fail with *Woodcase's resources are missing* (exit 5).

Or build and run from the checkout without installing:

```bash
swift build -c release      # binary at .build/release/woodcase
swift run woodcase render myfile.pen
```

## The verbs

Every verb takes a `.pen` file as its first argument. **Read** verbs take a shared lock
and change nothing; **write** verbs run inside a file transaction and append to the
activity log; **render** verbs write images or code; the **viewer** verbs serve. `new`
is the one write verb that opens no transaction — there is no existing file to lock —
and so is the one edit the activity log never records.

Exit codes are the house table below — 0 and the codes each verb can additionally
return are listed here, so a script knows what it must branch on.

| Verb | Class | What it does | Exit codes |
|---|---|---|---|
| `tree` | read | The settled node tree, one row per node with its rect | 0 2 3 4 |
| `find` | read | The rows of that tree a JavaScript predicate keeps | 0 1 2 3 4 |
| `get` | read | One node as canonical .pen JSON, with its revision | 0 2 3 4 |
| `lint` | read | What is wrong with the file, from its settled layout | 0 1 2 3 4 |
| `vars` | read | The variables and theme axes the document defines | 0 2 3 4 |
| `imports` | read | The component libraries the document imports | 0 2 3 4 |
| `themes` | read | The theme axes and their options | 0 4 |
| `activity` | read | The log of edits, newest last; `--follow` tails it | 0 2 5 |
| `icons` | read | The icon names an icon library defines, or matching a query | 0 1 2 |
| `schema` | read | Every property a node type takes, and each value's shape | 0 2 |
| `help` | read | The primer: `woodcase help design` teaches the loop | 0 2 |
| `new` | write | Write the minimum .pen file a design can grow from | 0 3 4 5 |
| `add` | write | Insert a .pen subtree under a parent, or at the root | 0 2 3 4 5 |
| `set` | write | Patch properties of one node by path | 0 2 3 4 5 |
| `replace` | write | Swap a node's subtree for a new one, keeping its place | 0 2 3 4 5 |
| `cp` | write | Duplicate a subtree with fresh ids | 0 2 3 4 5 |
| `mv` | write | Reparent or reorder a node | 0 2 3 4 5 |
| `rm` | write | Delete a node, refusing to strand instances | 0 2 3 4 5 |
| `override` | write | Write an override into a component instance | 0 2 3 4 5 |
| `apply` | write | A JSONL batch of the above, in one transaction | 0 1 2 3 4 5 |
| `js` | write | A JavaScript program over the document, in one transaction | 0 1 2 3 4 5 |
| `undo` | write | Replay the inverse of the last recorded edits | 0 1 2 3 4 5 |
| `vars set/rm` | write | Add, change or remove a variable or theme axis | 0 2 3 4 5 |
| `imports set/rm` | write | Add, repoint or drop a library import | 0 2 3 4 5 |
| `migrate` | write | Rewrite older files in the current format, in place | 0 2 4 |
| `shot` | render | One node to a PNG, scaled, with the scale printed | 0 2 3 4 |
| `render` | render | The whole document to PNG or PDF | 0 1 2 4 |
| `generate react` | render | React + Tailwind source from the document | 0 2 4 |
| `generate swiftui` | render | A SwiftPM package of SwiftUI views from the document | 0 2 4 |
| `serve` | viewer | A local, read-only live web view — <doc:WoodcaseViewer> | 0 2 3 4 5 |
| `preview` | viewer | The viewer's own components, in every state worth looking at | 0 2 3 5 |

## Contracts every verb keeps

These hold for every `woodcase` verb, so an agent learns them once.

### Exit codes

One table, shared with the other command-line tools in this family. Anything a verb
can fail with maps onto it — nothing invents a number of its own.

| Code | Meaning |
|------|---------|
| 0 | Success, or the asserted condition holds |
| 1 | Clean negative: the check ran and the answer is no (a `lint` with findings) |
| 2 | Usage error: an unknown flag, a missing argument, an address that resolves to nothing, a property no node of that type has |
| 3 | Conflict or timeout: a stale `--rev`, or a .pen file another process still holds the lock on |
| 4 | Target failure: the .pen file is missing, unreadable, or not a .pen document |
| 5 | Environment error: the activity log could not be written, its directory is unusable |

Two consequences worth knowing. A **missing file is 4, never 2** — the invocation's
shape was fine, the world was not; existence is checked when the verb runs, not when
its arguments parse. And an edit whose *log entry* could not be written is **5, not 4**:
the .pen file is committed before the log is appended, so the message says the edit is
on disk and names the log file. `woodcase` also returns 2, not ArgumentParser's default
of 64, for a malformed command line.

### A file that will not parse

Exit 4, and one sentence on stderr — the same one from every verb, whether it reads the
file directly or under a transaction. It names the file, says what the decoder actually
objected to (the key path and the type it wanted, not Foundation's "the data couldn't be
read"), and ends in a command:

```
$ woodcase tree broken.pen
Cannot read /w/broken.pen: not a .pen document — children[0].id should be a string — check the file's JSON with `python3 -m json.tool /w/broken.pen`.
```

A document whose `version` is not a `major.minor` string says so instead. A file from
a newer Pen of the same major — 2.20 while this build models 2.19 — reads and writes
normally: every read verb prints one `notice: [migration]` line on stderr, and every
write keeps the file's declared version. A file of another major is **read-only**:
when it still reads as a 2.x document, the read verbs work and print a warning, and
every write verb (and `migrate`) refuses with exit 4:

```
$ woodcase set future.pen Card/Title kind.content=Hi
Cannot write /w/future.pen: it declares .pen format 3.0, a different major version from the 2.19 this build models, so it is read-only — the read verbs (`woodcase tree`, `get`, `lint`, `render`, `shot`) still work; to edit it, update Woodcase to a build that writes 3.x, or edit it in Pen.
```

When it does not read as a 2.x document, every verb says which key path failed and
exits 4.

### `--as <name>` and `$WOODCASE_AS`

Every write is attributed to a name. There is no registration step: naming an identity
is creating it.

```bash
woodcase set design.pen Card/Title common.name=Heading --as ana
WOODCASE_AS=ana woodcase set design.pen Card/Title common.name=Heading
```

`--as` wins over `$WOODCASE_AS`, and blank in either place counts as unset. With
neither, the edit is applied and logged as an *unattributed* write: the event is there
with an empty identity, so it still shows in `activity`, in the viewer and in `undo`, and
simply names nobody. The name is never taken from the OS account, which on a shared
machine would attribute everyone's edits to whoever is logged in.

The log is the project's, not the machine's: `.woodcase/activity.jsonl` at the nearest
`.git` above the .pen file, or beside the file when there is no repository. The write
that creates it adds `.woodcase/` to that repository's `.gitignore`. `$WOODCASE_HOME`
overrides the whole thing with a single log — see <doc:WoodcaseActivityLog>.

A write that finds the file changed since the log's newest entry leads its answer with
one note on stdout — `note  <file> was rewritten outside woodcase since rev …` — records
that fact in the log as an `external` row, and carries on. It fires once per hole, and
under `--json` it goes to stderr so the answer stays one document.

### `--json`

The default output is the tersest faithful form — an indented outline, one row per
item. `--json` is always one flag away and gives the stable machine shape, including
the document revision a later mutation can pass back as `--rev`. Both go to stdout and
produce the same bytes in a pipe as in a terminal; messages, warnings and refusals go
to stderr, so a parse never has to filter them out.

A mutating verb answers with the name → id map of what it created, as a tree that
mirrors the structure, so the next command needs no lookup:

```text
Card  ALu8G
  Title  x9Kqp
```

### `--dry-run`

Every write verb takes `--dry-run`, which rehearses the write instead of making it:
`add`, `apply`, `cp`, `mv`, `override`, `replace`, `rm`, `set`, `undo`, `vars set`,
`vars rm`, `vars axis add`, `imports set`, `imports rm` and `new`. The verb takes the file's exclusive lock, checks
its `--rev` and `--guard`, applies the edit, settles the layout and builds the answer it
would have printed; then the transaction rolls the whole thing back. The file's bytes,
its revisions and the activity log are exactly what they were, and no `.gitignore` line
is added.

`new` is the one that works differently, because there is no file yet to lock: it runs
both of its refusals — the path already exists (exit 3), the parent directory does not
(exit 4) — and then answers without creating anything.

```text
$ woodcase set design.pen Cards/First kind.width=900 --dry-run
dry run  nothing written
Canvas/Cards/First  Cd101
warning clipped  Canvas/Cards/First (Cd101)  0,0 900×60 sits partly outside Cards (380×200). …
warning clipped  Canvas/Cards/Second (Cd201)  900,0 100×60 sits entirely outside Cards (380×200). …
```

Three things differ from the real write's answer.

- **A marker leads standard output**, so a rehearsal in a log can never be read as a
  write. `--json` carries `"dryRun": true` instead — a marker line would not parse.
- **No revision is printed.** The file is still at the revision it had, and the one this
  edit would have made names nothing on disk; printing it would be the plausible wrong
  answer `rm` already declines to give for the node it deleted. Rehearse, then run the
  verb for real, and read the revision from that.
- **The findings the write would introduce** follow the report, in `lint`'s own line
  format, so `--dry-run | grep '^error'` reads the same as `lint | grep '^error'`. Only
  the *new* ones: a node that already tripped a check still trips it, so a file that
  already lints dirty does not bury the answer. `--json` carries them under `lint`.

The exit code is the write's, not the lint's: a rehearsal whose result would lint dirty
still exits 0, and one a `--guard` refuses still exits 3 having printed no report at all.
A batch settles every line before it lints, so a line that breaks the layout and a later
line that repairs it net out to nothing.

The verbs that answer with something other than a node keep their own shape and gain the
same three differences — `vars set` and `vars axis add` print their variable or axis
rows, `imports set` its import row, `vars rm` and `imports rm` their `Removed …`
sentence, `undo` its reversed rows, `new` the path — each
without the revision line it would have ended on. `vars rm --force --dry-run` is the one
worth knowing by name: it is how you see, before removing anything, exactly which nodes
would be left holding an unresolved `$name`.

## Commands

The reading and editing verbs are summarized here; <doc:WoodcaseEditor> is the guide
that puts them together into a working loop, with a real transcript for each.

### `tree`

Print the settled node tree, one row per node — the read that replaces most
screenshots. The header line carries the document revision; each row is the node's
type, its name indented by depth, the settled rect as `x,y w×h`, a clip flag, and its
id. A `*` marks a reusable component definition, `+N` counts children the listing left
out, and the last column of a row is an address every other verb accepts.

```bash
woodcase tree design.pen
woodcase tree design.pen Dashboard --depth 2 --props kind.content,kind.fills
woodcase tree design.pen --expand --json
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--depth` | — | How many levels below the root to descend; `0` lists the roots alone |
| `--props` | — | Property paths to show as columns, comma separated |
| `--theme` | — | Pin theme axes before resolving variables: `"mode=dark"` |
| `--expand` | `false` | Walk into component instances, addressing their nodes by id path |
| `--json` | `false` | The machine-readable form, including the revision |

### `find`

Print the rows of that same settled tree that a JavaScript predicate answers truthy
for — `tree` with a question attached. The predicate is an arrow function taking one
row, the same row `tree --json` prints, so there is no query grammar to learn. It sees
no `doc` and cannot write; `woodcase js` is where a program with `doc` lives.

```bash
woodcase find design.pen 'r => r.type === "text" && r.rect.height < 2'
woodcase find design.pen Dashboard 'r => r.clip !== "none"'
woodcase find design.pen 'r => r.props["kind.fontSize"] < 12' --props kind.fontSize
woodcase find design.pen 'r => r.childCount > 8' --json | jq -r '.rows[].address'
```

A row carries `type`, `name`, `address`, `id`, `rev`, `depth`, `rect`, `absRect`,
`clip`, `overflowAxes`, `isReusable`, `isInstance`, `isSlot` and `childCount` — and the
columns `--props` asked for, read as `r.props["kind.fontSize"]`. **A member a row does
not have is refused, not read as `undefined`**: `r.fontSize` written for
`r.props["kind.fontSize"]` would compare `undefined < 12`, which is `false`, and print
nothing — a wrong answer to a question nobody asked. The refusal names the row it
happened on and lists the members a row carries.

The output is `tree`'s, filtered: the same header carrying the same revision, the same
columns, the same `--json` report, so `find` pipes wherever `tree` does. Column widths
are measured over the rows that matched, and `+N` counts the children *this* listing
left out — so a row whose children did not match reads `+N` where `tree` showed them.

**Exit codes:** `0` with matches; `1` for none, printing nothing at all in either form,
so `woodcase find … && …` branches on the answer; `2` when the predicate does not parse
or throws, or when the address resolves to nothing.

The predicate is one operand, and the subtree to search is the one before it. With `-F`
the predicate is already given, so a lone operand is the subtree.

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-F <file>` | — | The predicate, when it outgrew a line; `-` reads standard input |
| `--props` | — | Property paths to show as columns and expose as `r.props[…]` |
| `--expand` | `false` | Walk into component instances, addressing their nodes by id path |
| `--absolute` | `false` | Print rects in document space rather than relative to each parent |
| `--json` | `false` | The machine-readable form, including the revision |

### `get`

Print one node as canonical `.pen` JSON, with its revision on the header line. The node
is printed as the file *stores* it, children stripped — `tree` is the structural read.
`--expand` prints it as it renders instead: instances expanded, overrides applied.

`--instances` asks the opposite question of a reusable component — which `ref` nodes
draw it — and prints one row per instance instead of a node. See <doc:WoodcaseEditor>.

```bash
woodcase get design.pen Dashboard/Header/Title
woodcase get design.pen Nav01 --expand --json
woodcase get design.pen Button --instances
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--expand` | `false` | Print the node as it renders, children and all |
| `--instances` | `false` | List every `ref` that draws this component, one row each |
| `--json` | `false` | `{"node":…,"revision":…}`, or `{"definition":…,"instances":[…]}` |

### `lint`

Report what is wrong with the file, from its settled layout: broken refs, unresolved
variables, text with no fill, containers that cannot size themselves, clipped nodes.
Exits 1 when it finds anything, so it composes as an assertion. See <doc:WoodcaseLint>.

```bash
woodcase lint design.pen && woodcase render design.pen
woodcase lint design.pen Dashboard/Header --theme "mode=dark" --json
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--theme` | — | Pin theme axes before settling the layout |
| `--json` | `false` | One JSON object per finding |

### `activity`

Show the log of committed edits, newest last, one line each — time, identity, verb,
path. `--follow` keeps printing as new events arrive. See <doc:WoodcaseActivityLog>.

```bash
woodcase activity --file design.pen -n 20
woodcase activity --follow
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--file` | — | Only this .pen file's events; the file need not still exist |
| `--as` | — | Only this writer's events — a *filter* here, not attribution |
| `-n`, `--count` | `50` | How many of the most recent events to show |
| `--follow` | `false` | Keep printing new events until interrupted, or until the launching process exits |
| `--json` | `false` | Each event in the log's own wire form, one per line |

With `--file` the log read is that file's project log; with no `--file`, the log of the
project the working directory is in. An empty or not-yet-created log prints nothing and
exits 0. A log directory that exists but is not a readable directory exits 5.

`--follow` is the one verb with no ending of its own, so it has a second reason to
stop: it exits when the process that launched it goes away. A follower whose reader is
gone is printing into nothing, and a script or test that spawns one and is then killed
would otherwise leave it running forever, polling a log and holding a lock-shaped
grudge against whichever process next opens the same file. A follower that was
*already* orphaned when it started — `nohup woodcase activity --follow &`, a launch
agent — has no parent's death to notice and keeps running.

### `icons`

The icon names a library defines — bundled `lucide`, `feather`, `phosphor`, `Material
Symbols Outlined`, `Material Symbols Rounded`, `Material Symbols Sharp`, or any family
registered at runtime via `PenIconFontRegistry.register(family:fontName:mapping:)`. No
`.pen` file is read: this is offline, over the codepoint tables alone.

With no query every name is printed, sorted, one per line — for `grep`. With a query,
names are ranked best first through the same pipeline `unknown-icon` proposes fixes
from: an exact match, then a substring match, then a fuzzy match on shared name tokens
or a close edit distance. See <doc:PenIconFonts>.

```bash
woodcase icons lucide
woodcase icons lucide check
woodcase icons lucide check-circle-2 --json
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--json` | `false` | A JSON array of names, in the same ranked order |

An unknown library is refused at exit 2, naming the libraries this build knows. A
query that matches nothing prints nothing and exits 1, the clean negative.

### `schema`

Every property a node type takes, and the shape of each value. It opens no file — the
vocabulary belongs to the format, not to any document — so it answers before there is
anything to read.

```bash
woodcase schema              # the node types, and the common.* properties
woodcase schema text         # one type's own properties
woodcase schema text --json  # the same tables, machine-readable
```

Each row is the codec path `set` accepts, the key the `.pen` file writes the value
under, and every accepted form as one union — enumerated values spelled out
(`"auto" | "fixed-width" | "fixed-width-height"`), and `$number`, `$color`, `$string`
or `$boolean` where a variable reference is taken:

```text
  path                    .pen key           value
  kind.content            content            string | $string
  kind.fills              fill               color | $color | fill | [color | $color | fill, …]
  kind.strokeWidth        strokeWidth        number | $number | per-side width
  kind.textGrowth         textGrowth         "auto" | "fixed-width" | "fixed-width-height"
```

A structured value is never printed as "an object": a `fill`, an `effect`, a per-side
`strokeWidth` and everything they contain get a key table of their own under `NESTED
SHAPES`, one block per variant of the `"type"` key, with required keys marked `*`.

A type's table lists that type's `kind.*` properties only. The thirteen `common.*` rows
are the same on all fifteen types, and repeating them would bury the eight to
twenty-three that differ, so the table points at `woodcase schema` for them instead.

Nothing here is written by hand. The paths are the ones the codec accepts — the same
list a refused `set` prints back — the spellings come off the enumerations that decode
them, and the nested key tables are declared beside their decoders and checked against
the payloads' own stored properties by the suite. A property added to a decoder appears
here or the suite fails.

An unknown type is a usage error (exit 2) naming the fifteen real ones.

### `help`

The primer. `woodcase help design` teaches the loop — addressing, property paths, the
revision handshake — in the terminal, so an agent needs no other document to start.
`woodcase help schema [<type>]` is the `schema` verb reached the way an agent that has
read only the primer reaches it; the bytes are identical. `woodcase help recipes` is
copy-pasteable command sequences for what an agent actually does — starting a file,
building a screen, making a component and repeating it, themed variables, the
lint-shot loop, rebuilding a subtree — each ending in the read that verifies it.
`woodcase help codegen` is what `generate react` and `generate swiftui` read, and how to build and run the SwiftUI package. `woodcase help js` is the
contract a `woodcase js` program runs under — the three transaction rules, the no-session
rule, four worked scripts and the TypeScript declaration of `doc`; it shadows the verb's
own screen, which stays at `woodcase js --help`. Every snippet in `recipes`, `codegen`
and `js` is extracted by a test and run against a fixture, so none of them can rot.

```bash
woodcase help design
woodcase help schema text
woodcase help recipes
woodcase help js
woodcase help <verb>
```

### `new`

Write the minimum a `.pen` file needs — the current format version and an empty
`children` array, with no themes, imports or variables — so `add` and `cp` have
something to grow. There is no existing file to guard, so `new` takes no `--rev`; the
file is created under its lock, and its first activity-log row is a `new` event naming
the writer — `undo` stops there.

```bash
woodcase new design.pen
woodcase tree design.pen
```

Refused rather than overwritten when the path already exists (exit 3) — `woodcase
tree` is the read that shows what is there. The parent directory has to exist already;
`new` does not create one (exit 4, naming it).

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--as` | `$WOODCASE_AS` | Who the file's first activity-log row, `new`, is attributed to; with neither, it is unattributed |
| `--dry-run` | `false` | Run both refusals and print the path, creating nothing. No revision, because no file was made |
| `--json` | `false` | `{"path":…,"documentRevision":…}` |

### `add`

Insert a `.pen` subtree under a parent, or at the document root (`document`). The
subtree is read with `-F` (or `-F -` for standard input). Ids are optional: leave
`"id"` out and one is generated — the name → id tree printed back is where those come
from — and an id you do write is kept, as long as it has no `/` in it and nothing else
in the file or the subtree uses it. Every node needs a `"name"`.

```bash
woodcase add design.pen Card -F badge.json --at 0 --as ana
echo '{"type":"text","name":"Caption","content":"Hi"}' | woodcase add design.pen Card -F -
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-F` | — | A .pen subtree as JSON; `-` reads standard input (required) |
| `--at` | append | Position among the parent's children, counting from 0 |
| `--rev` | — | The revision you last observed for the *parent* |
| `--as` | `$WOODCASE_AS` | Who to attribute the edit to |
| `--json` | `false` | The machine-readable created-tree report |

A root-level add declaring neither `x` nor `y` is placed in empty space to the right of
the existing roots. A node added to a laid-out parent should carry no coordinates.

### `set`

Set properties on one node, by prefixed property path — `common.name`, `kind.width`,
`kind.fills`. Only the keys given are touched; `null` clears one. A key the node does
not have is refused with the list of the ones it does.

```bash
woodcase set design.pen Card/Title kind.content=Hello kind.fontSize=18 \
  --rev 4f2a1b0c9d8e7f60 --as ana
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-F` | — | A JSON object of properties; a `key=value` argument wins over the same key in it |
| `--rev` | — | The revision you last observed for this node |
| `--as` | `$WOODCASE_AS` | Who to attribute the edit to |
| `--json` | `false` | The machine-readable write report |

Values are typed by how they are written: `240` and `0.5` are numbers, `true`/`false`
booleans, `null` clears the property, `[8,16]` and `[{"type":"color","color":"#FFD166"}]`
are JSON, and
`"42"` is the string `42`. Anything else is a string — which is what a `#ff8800`
color, a `$variable` reference and the `fill_container` / `fit_content` keywords
already are. Only the first `=` splits.

### `replace`

Swap a node's whole subtree for an authored one. The node keeps its **id**, its
**parent** and its **index among its siblings**; everything under it — its own
properties included — becomes what the subtree says. This is the "rebuild it" idiom as
one rev-guarded call: an `rm` followed by an `add` would change the id, and every path,
`--rev` and component reference pointing at the node would go stale.

The subtree is read with `-F` exactly as `add` reads one, and ids follow the same rule:
one you write is kept, one you leave out is generated. There is one addition — an id
the *replaced* subtree holds today may be reused, because it goes away with it. The
root's own `id` is the target's whatever you write; leave it out, or write the target's,
and a different one is refused rather than quietly ignored. Every node needs a `"name"`.

```bash
woodcase get design.pen Card --json > card.json          # keep the old one
woodcase replace design.pen Card -F rebuilt.json --rev 4f2a1b0c9d8e7f60 --as ana
woodcase tree design.pen Card                            # verify
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-F` | — | A .pen subtree as JSON; `-` reads standard input (required) |
| `--rev` | — | The revision you last observed for *this node* |
| `--as` | `$WOODCASE_AS` | Who to attribute the edit to |
| `--json` | `false` | The machine-readable created-tree report |

Rebuilding a reusable component is what the verb is for, and every instance follows the
new contents. Changing what *kind* of node the definition is while instances point at it
is refused (exit 2), naming the instances: they would silently draw something else, and
a type change does not converge between peers.

One `replace` is one activity event, and `woodcase undo` reverses it in one step,
restoring the previous subtree exactly.

### `cp`

Copy a node into a parent, with fresh ids. Copying a reusable component makes an
*instance* of it, as Pen does; copying anything else deep-copies it. Properties apply
to the copy and never to the source, and a key written as a name path
(`Header/Title/kind.content`) lands on that node inside the copy.

```bash
woodcase cp design.pen Home document common.name=Checkout \
  Header/Title/kind.content=Checkout --as ana
```

**Options:** `-F`, `--at`, `--rev`, `--as`, `--json` — as `add` and `set` — plus:

| Option | Default | Description |
|--------|---------|-------------|
| `--times` | — | Copy N times in order, instead of once. Requires `common.name` to contain `{n}` (1-based) |

`--times N` makes N copies in one write. Because identical names would make the
copies indistinguishable by path, it requires `common.name` to contain the
placeholder `{n}`, refusing and naming it otherwise; `{n}` is then replaced with
`1`, `2`, … `N` in every property that carries it, not only `common.name`.
`--rev`, when given, guards only the first copy. Each copy logs the same events a
single `cp … common.name=X` already does — an insert and a property set — but they
share one batch id, so one `woodcase undo` takes the whole write back.

```bash
woodcase cp design.pen Cards/Row Cards common.name='Card {n}' --times 3
```

### `mv`

Move a node to another parent, or to another position under the same one. The node
keeps everything it had; only where it sits changes. A move into a node's own subtree,
or into a component instance, is refused with the reason.

```bash
woodcase mv design.pen Card/Badge Card/Header --at 0 --as ana
```

**Options:** `--at`, `--rev`, `--as`, `--json`.

### `rm`

Delete a node and its descendants. Deleting a reusable component while instances of it
exist is refused, listing them by path; `--detach` opts into the consequence, turning
each instance into a real copy of what it showed before the component goes.

```bash
woodcase rm design.pen Library/Button --detach --as ana
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--detach` | `false` | Detach every instance of this component before deleting it |
| `--rev` | — | The revision you last observed for this node |
| `--as` | `$WOODCASE_AS` | Who to attribute the edit to |
| `--json` | `false` | The machine-readable write report |

### `override`

Write properties onto a node *inside* a component instance. Address it by stepping
through the instance (`Orders/Value`, or `Orders/Badge/Count` for a nested one). The
value becomes an entry in the instance's `descendants` map, exactly as the format writes it.

Property names are **stored** as raw .pen names — `content`, not `kind.content` —
because that is the vocabulary that map's keys use; a property path is translated on
the way in, so either vocabulary is accepted. A value the node cannot take is refused
rather than stored, since an override that will not merge is dropped when the instance
expands. The answer names the *instance*, since that is where the override is stored
and what `--rev` guards.

```bash
woodcase override design.pen Orders/Value content=42 --as ana
```

**Options:** `-F`, `--rev`, `--as`, `--json`.

### `apply`

Apply a batch of edits — JSONL, one operation per line, in order — in one transaction.
A failed line changes nothing and does not stop the batch; a line depending on a failed
one is cascaded. `woodcase apply --help` prints the whole grammar; <doc:WoodcaseBatches>
explains it.

```bash
woodcase apply design.pen -F ops.jsonl --as ana
woodcase apply design.pen -F ops.jsonl --json > report.json
woodcase apply design.pen --retry report.json --as ana
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-F` | — | The batch; `-` reads standard input |
| `--atomic` | `false` | Discard every edit in the batch if any line fails |
| `--retry` | — | A previous `--json` report; only its failed and cascaded lines are re-run |
| `--as` | `$WOODCASE_AS` | Who to attribute the edits to |
| `--json` | `false` | The full ``BatchReport`` |

Exit 0 when every line applied, 3 when a line failed on a stale revision, 1 for any
other failure in the mix, and 2 for malformed JSONL — which never opens the document.

### `js`

Run a JavaScript program against the document, in one transaction. `apply` is the
multi-edit transaction that needs no program and `find` the query that needs no script;
`js` is where control flow lives — read, decide and write in one pass, which no batch can
express. The program gets `doc`, whose members mirror the editing verbs one for one, and
`console`. Reads see settled layout, so a script may measure what it just made and throw
rather than commit. `woodcase help js` is the whole contract, with the TypeScript
declaration of `doc` and four worked scripts; <doc:WoodcaseScripting> is the same
contract at length, with the library API a Swift caller uses.

```bash
woodcase js design.pen -F rows.js --as ana
woodcase js design.pen -F helpers.js -F rows.js --dry-run
woodcase js design.pen -F rows.js --guard 9c1b04e6f2a71d38 --json
echo 'doc.lint().length' | woodcase js design.pen -F -
```

```text
$ woodcase js banking.pen -F rows.js --as ana
cp           banking-home/transactions-section/row-Groceries  3cW3o
cp           banking-home/transactions-section/row-Transit  Yname
cp           banking-home/transactions-section/row-Coffee  QdQkT
rm           banking-home/transactions-section/t1  aqCub
result  10
document  8989ea918f5d755c
```

**Nothing is written until the script ends without an uncaught error.** A throw, a
refusal the script did not catch, or the `--timeout` leaves the file byte for byte what
it was and the activity log with nothing in it — there is no partial commit to reason
about. Each call is atomic on its own, so a *caught* refusal has changed nothing and the
script carries on from a consistent document. The whole run is one transaction in the
log, and `undo` reverses it as one step.

**Nothing persists between runs and nothing is auto-loaded**: durable code is a file, and
`-F helpers.js -F run.js` evaluates the helpers first in the same context. Each source
keeps its own name, so an error in the second file reports that file's line rather than a
line in a concatenation. Scripts run to completion in one pass — there is no event loop,
and `setTimeout`, `fetch`, `require`, `import` and top-level `await` each refuse with a
sentence saying so.

**Output.** stdout is the transcript as it happens: one row per write — the member of
`doc` that made it, the path, the id, and `(+N)` for the descendants a creating verb made,
with divergences indented under it — and the `console.log` lines where the script printed
them, then `result` (the last expression, as compact JSON; omitted when there is none) and
`document`. The member column is padded to the widest member name, so the paths line up
whatever wrote them, and a document-level write (`vars.set brand`) is the member and the
name. stderr carries `console.warn`, `console.error`, root-overlap warnings and the
refusal. `--json` prints nothing live and one object at the end — `events` (a write carries
`member` and `write`; a root overlap carries the `lint` line as `text`), `result`, `documentRevision`, `commit`, `error`,
`warnings`, and `dryRun` plus `lint` for a rehearsal — built from the same value.

**Exit codes:** `0` when the run committed; `1` for an uncaught error, with the source,
line, column and quoted line on stderr and the file untouched; `2` for a source that will
not parse, or an invocation that is malformed; `3` for a stale `--guard`, a lock held
elsewhere, or the `--timeout`; `4` when the `.pen` file or a `-F` script could not be
read; `5` when the activity log cannot be written.

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-F <file>` | — | A JavaScript source; repeatable, evaluated in order in one context. `-` reads standard input |
| `--timeout` | `30` | Seconds the script may run before the run is ended with exit 3 |
| `--guard` | — | A premise checked before the first line runs; bare, it pins the whole document |
| `--dry-run` | `false` | Run everything, write nothing, and print the findings the result would introduce |
| `--as` | `$WOODCASE_AS` | Who to attribute the edits to |
| `--json` | `false` | The whole run as one object: events, result, revision, commit, error |

### `undo`

Reverse the most recent recorded edits by replaying their inverses, working back from
the newest entry in the activity log for this file. An edit is reversed only while the
file is still in the exact state that edit produced; a later edit by somebody else
stops the undo and names them (exit 3). An undo is itself recorded, and an undo entry
is stepped over rather than replayed — `undo` is not `redo`.

One step is one **transaction**: every event of one command shares a batch id, so a
batch, a `cp --times 3` or an `apply` goes back with a single `undo`, and `-n` counts
commands rather than log rows. `--event` reverses one row instead.

```bash
woodcase undo design.pen --as ana
woodcase undo design.pen -n 3 --all --as ana --json
woodcase undo design.pen --event --as ana
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `-n`, `--count` | `1` | How many transactions to reverse, newest first |
| `--event` | `false` | Reverse one logged event per step, not one whole transaction |
| `--all` | `false` | Reverse edits by any identity, not only your own |
| `--as` | `$WOODCASE_AS` | **Required** — an unlogged undo would break the log's tail |
| `--dry-run` | `false` | Print the rows the reversal would produce and roll it back; the log keeps the events it would have undone |
| `--json` | `false` | The machine-readable undo report |

With nothing left to reverse, `undo` exits 1 and says why. An edit made *outside*
woodcase is recorded in the log as an `external` row and has no inverse, so `undo`
stops at it and says when it happened (exit 3) — see <doc:WoodcaseActivityLog>.

### `vars`

List, set and remove the document's variables and theme axes. A bare `vars <file>`
lists — variables with a reference count each, then the axes.

```bash
woodcase vars design.pen
woodcase vars set design.pen --theme scheme=night -- accent=#22c55e
woodcase vars set design.pen -- bg=#111111 fg=#eeeeee
woodcase vars rm design.pen --force -- ink
woodcase vars axis add design.pen scheme=day,night
```

A variable name that itself starts with a dash needs the end-of-options marker `--`
before it, or the parser reads it as a flag. Forget it and the refusal names the rule
and prints the line to run, rather than reporting a missing argument.

**Options** (`set`): `--theme <axis=option,…>` pins the value to theme options,
registering any the document lacks; `--type <boolean|color|number|string>` declares the
type instead of inferring it. Both apply to **every** pair when several are given, and
several pairs go through one transaction — one `var` event each, so one `undo` takes
the call back whole. A name the document already defines is announced before the
outline with its old value and its reference count, and carried in `--json` as
`previous`; a whole token layer written from data belongs in `apply` (see
<doc:WoodcaseBatches>). **Options** (`rm`): `--force` removes a variable
something still references. All four take `--as` and `--json`; the three that write
also take `--dry-run`.

`vars rm` refuses while any node or variable still references the name, listing them.
`vars rm --force --dry-run` is the rehearsal worth reaching for: it prints the
`unresolved-variable` finding for every node that would be left holding a `$name`,
without removing anything.
Setting a themed value on a variable that had a single one keeps the old value as the
default variant, so nothing that referenced it changes meaning.

### `imports`

List, add, repoint and drop the component libraries the document imports. A bare
`imports <file>` lists — one row per alias, with the number of nodes that reach into its
namespace and the path it resolves to.

```bash
woodcase imports design.pen
woodcase imports set design.pen V ./library.pen
woodcase imports rm design.pen V --force
```

An import aliased `V` puts every identifier the library defines under a `V:` prefix —
`V:Bt0aA`, `$V:--primary`, the axis `V:Mode` — see <doc:PenImportNamespaces>. So
`imports set` on an alias the document already has repoints all of them at once, and
`imports rm` is refused while any node still reaches into the namespace, listing what
would be affected. **Options** (`rm`): `--force` drops it anyway. All three take `--as`
and `--json`; the two that write also take `--dry-run`.

Removal is the one import operation the batch grammar deliberately omits, for the reason
it omits variable removal: an optional payload would turn a dropped field into a silent
delete. `{"op":"import","alias":ALIAS,"path":PATH}` adds or repoints, and nothing more.

### `shot`

Render one node to a PNG, scaled so its longest side is at most `--max`, and print
what is needed to map a pixel back to a layout point:

```text
point = (pixel − gutter) / scale + origin
```

`scale`, `gutter` and the rect whose `x,y` is `origin` are all on the printed line, and
`gutter` is `0,0` unless `--grid` was asked for — so the one formula covers every shot.
A bare `shot` with no node is refused and lists everything renderable at the top level
— the reusable component *definitions* (marked as such) and the `ref` nodes that place
them — to pick from: a giant collage is a plausible wrong answer, and those are worse
than an error. `shot` renders both halves of a component. A top-level `ref` — every
artboard in `woodcase-app.pen` — is named by its authored id or name, and the printed
`node=` is the id expansion gives it, `<ref id>/<component root id>`. A reusable
definition — every top-level frame in `banking.pen` — renders as itself, because `shot`
keeps definitions in the expanded tree the way `tree --expand` does.

```bash
woodcase shot design.pen Dashboard --out dash.png --max 800
woodcase shot design.pen Dashboard/Header --out header.png --max 800 --grid \
  --outline Dashboard/Header/Logo
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--out` | — | Output PNG path (required) |
| `--max` | `1600` | Longest side, in points; the node is never enlarged past its own size. Ignored when `--scale` is given |
| `--scale` | — | Pixels per layout point; unlike `--max`, this enlarges. Takes precedence over `--max` |
| `--theme` | — | Pin theme axes: `"mode=dark,platform=web"` |
| `--grid` | `false` | Add a ruler numbered in layout points; grows the image past `--max` |
| `--outline` | — | Box this node's layout rect and tag it with its name (repeatable) |
| `--json` | `false` | Node, scale, rect, pixel size and gutters as JSON |

`shot` is the pixel-level read, and both its annotations exist so the pixels map back to
something you can edit. `--outline <node>` boxes a node's layout rect and tags it with
the node's name; it takes the same addresses everything else does, repeats, and draws
its ring just *outside* the rect so the node's own edge pixels survive. Only a node inside
the rendered node's own subtree can be boxed; anything else is refused, not drawn
nowhere. The box is placed in the rendered node's coordinate frame — the layout engine
stores each rect relative to its parent, and `shot` composes the offsets down the subtree. `--grid` adds a ruler
numbered every 100 **layout points**, not pixels: a node whose rect starts at x=40 shows
no tick before 100, whatever `--max` shrank the render to. The ruler lives in a gutter
added *outside* the render, so `--grid` makes the PNG larger than `--max` — the printed
`pixels=` is the file's real size and `gutter=` is what was added.

### `serve`

Serve a local, read-only live web view of the .pen files you are working on, plus the
JSON, PNG and Server-Sent Events API it is built on. Editing a watched file pushes an
event and a fresh render to every open page. Everything about it — routes, fragments,
endpoints, the event shape — is in <doc:WoodcaseViewer>.

```bash
woodcase serve                         # every .pen this project's log has seen;
                                       # searches 7333 upward, reports the port it got
woodcase serve design.pen --open       # one file, opened in the browser
woodcase serve --port 0 --json         # an ephemeral port, reported as JSON
woodcase serve --port 7333             # pins exactly 7333; fails if it's taken
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--port` | unset | Pin exactly this port and fail if it's taken; `0` takes whatever the system offers. Omit to search upward from 7333 until one is free (up to 100 past it) |
| `--open` | `false` | Open the URL in the default browser once the server is up |
| `--json` | `false` | Print `{url, port, files}` instead of the bare URL |

The URL is the only thing on stdout, flushed, so `woodcase serve | head -1` finds it;
everything else goes to stderr while the process runs. Given no files, it serves every
.pen file the *working directory's* project log has seen — so `woodcase serve` in a
checkout is that checkout's dashboard. Given files, it follows each file's own project
log, which is one log for one project and two for files from two. `Ctrl-C` stops it and
leaves nothing behind.

Without `--port`, a second `serve` on the same machine does not fail — it reports 7334
instead of 7333, the way `job serve` behaves. A bind refused because the environment
forbids listening on a port at all (a sandbox) is reported as that, distinctly from an
ordinary busy port, and never as a plain "port in use" — retrying a different port would
not have helped either way.

### `preview`

Serve the viewer's own component previews: an index of components, a canvas per
component with every state stacked, and a page per state whose URL is stable enough to
paste into a review. It is `serve` with nothing to serve — no files, no activity log,
no watcher — and it reads and writes nothing on disk. `serve` answers the same
`/preview` routes, so a person already looking at a document does not need a second
process; this verb is for looking at the components when there is no document.

```bash
woodcase preview                       # the index; searches 7333 upward
woodcase preview outline-panel         # straight to one component's canvas
woodcase preview avatar/small --open   # straight to one state, in the browser
woodcase preview --list                # every state's path; starts nothing
woodcase preview --list --json         # the same as objects, for an agent
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--port` | unset | Pin exactly this port and fail if it's taken; `0` takes whatever the system offers. Omit to search upward from 7333. `--list` binds nothing and prints paths, so it ignores this |
| `--open` | `false` | Open the URL in the default browser once the server is up |
| `--list` | `false` | Print every component and state with its path, and exit. Starts no server |
| `--json` | `false` | With `--list`, the catalog as objects; otherwise `{url, port, components, states}` instead of the bare URL |

The positional argument is `component` or `component/state`, and it is checked against
the catalog **before** any port is bound: a typo prints the list of components (or of
that component's states) and exits 2, rather than leaving a server running on a 404.
`--list` refuses to be combined with a component or with `--open` — it starts nothing,
so there is nothing to filter and nothing to open.

`--list` prints one row per state, two-space columns — the state is what gets shot and
reported, so it is what a row can be grepped by:

```text
avatar/small  strip  /preview/avatar/small
outline-panel/crowded  left-pane  /preview/outline-panel/crowded
```

Those are **paths, not URLs**. `--list` binds no port, so it has no base to name and no
business guessing one: a listing written against 7333 while the server took 7334 is a
page of dead links that look alive. The base belongs to whichever server is running —
it prints its own URL on stdout, and `--json` reports it as `url` — and the two are
joined at the point of use:

```bash
woodcase preview --port 7333 &        # prints http://127.0.0.1:7333/preview
woodcase preview --list               # prints /preview/avatar/small
sleepy shot http://127.0.0.1:7333/preview/avatar/small
```

Everything about the pages themselves — the routes, the frames and the review loop — is
in <doc:WoodcaseViewer>.

### `render`

Render a `.pen` file to PNG or PDF.

```bash
woodcase render myfile.pen
woodcase render myfile.pen --format pdf
woodcase render myfile.pen --theme "mode=dark" --scale 3
woodcase render myfile.pen --vars '{"--primary":"#FF0000"}'
```

The libraries a file's `imports` name are read from beside it, as Pen reads them; there
is no flag for them. A missing one is a warning, and fails `--strict`. See
<doc:PenImportNamespaces>.

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--format` | `png` | Output format: `png` or `pdf` |
| `--scale` | `2` | Scale factor (PNG only) |
| `--theme` | — | Pin theme axes: `"mode=dark,platform=web"` |
| `--vars` | — | JSON dictionary of variable overrides |
| `--vars-file` | — | Path to a JSON file of variable overrides |
| `--output-dir` | — | Output directory (defaults to input file's directory) |
| `--strict` | `false` | Fail on warnings (missing fonts, broken refs) |

### `generate react`

Generate React + Tailwind code from a `.pen` file.

```bash
woodcase generate react myfile.pen --output ./src
```

Every component the file's imported libraries define is generated beside the file's
own.

This produces a complete file set: `components/*.tsx`, `pages/*.tsx`, `ThemeProvider.tsx`, `lib/cn.ts`, and `theme.css`.

#### Packaged output

Add `--package` to wrap the output in an npm package structure, ready to build and publish:

```bash
woodcase generate react myfile.pen --output ./my-ui --package --name @myorg/ui
```

This relocates source files under `src/`, generates a barrel `index.ts`, and scaffolds `package.json` and `tsup.config.ts`. The scaffolded `package.json` automatically includes dependencies for any icon libraries used (Lucide, Feather, Phosphor, Material Symbols) and Fontsource packages for fonts referenced in the design. Image assets referenced by components are copied from the input `.pen` file's directory to the output. Scaffold files are only created if they don't already exist, so you can customize them without losing changes on re-generation. Use `--force` to clear the output directory and regenerate everything from scratch.

```
my-ui/
├── src/
│   ├── components/*.tsx
│   ├── pages/*.tsx
│   ├── lib/cn.ts
│   └── ThemeProvider.tsx
├── theme.css
├── states.css          # Only when components have interactive states
├── manifest.json
├── index.ts
├── tsup.config.ts
└── package.json
```

#### Preview viewer

Add `--preview` (requires `--package`) to generate a `viewer/` app alongside the package. The viewer lets you browse components, inspect theme variables, and toggle theme axes in the browser:

```bash
woodcase generate react myfile.pen --output ./my-ui --package --name @myorg/ui --preview
cd my-ui && npm install && npm run preview
```

The viewer is a standard Vite + React app that reads `manifest.json` for component and theme metadata. Scaffold files (`viewer/App.tsx`, `viewer/package.json`, etc.) are only written once, so you can customize the viewer after initial generation. Only `viewer/components.ts` and `manifest.json` are regenerated on each run to stay in sync with the design.

```
my-ui/
├── src/                    # Generated components
├── viewer/
│   ├── index.html
│   ├── main.tsx
│   ├── App.tsx             # Viewer shell (sidebar + content)
│   ├── components.ts       # Auto-generated component registry
│   ├── vite.config.ts
│   └── package.json
├── manifest.json           # Component & theme metadata
├── theme.css
├── states.css              # Only when components have interactive states
├── index.ts
├── tsup.config.ts
└── package.json
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--output` | `.` | Output directory for generated files |
| `--package` | `false` | Wrap output in an npm package structure |
| `--name` | `@woodcase/ui` | Package name (requires `--package`) |
| `--preview` | `false` | Generate a viewer app (requires `--package`) |
| `--force` | `false` | Clear the output directory before generating |

### `generate swiftui`

Generate a SwiftPM package of SwiftUI views from a `.pen` file — the first slice of the SwiftUI target (<doc:PenCodeGen>).

```bash
woodcase generate swiftui myfile.pen --output ./AcmeUI --name AcmeUI
```

It writes `Package.swift` (only when absent), one `public struct <Page>: View` per top-level frame under `Sources/<name>/Pages/`, and the helpers under `Sources/<name>/Support/` (`PenSupport.swift` and its `PenSupport+<Concern>.swift` siblings). `--name` is the module and must be a Swift identifier (default `PenUI`). `--floor ios26` (the default) or `--floor ios18` sets the platforms the manifest declares; the views are the same at both. `--force` clears the output directory first.

This slice writes frames, rectangles, ellipses and text with solid colors, laid out as idiomatic stacks. Every other node becomes a marked placeholder, and components are not written yet; each gap is printed on stderr as `warning: <id>: …` (or `notice:`), and the exit code stays 0.

### `themes`

List theme axes and options defined in a `.pen` file.

```bash
woodcase themes myfile.pen
```

Output:

```
mode: light, dark
platform: ios, web
```

### `migrate`

Rewrite `.pen` files in the current format version, in place.

Each file is parsed through the version gate — which runs ``PenLegacyMigrator`` over any
document older than 2.19, turning a pre-2.19 inner shadow into an outer one and dropping
`spread`, as Pen does — and written back with sorted keys and two-space indentation,
under the file's lock. A rewrite adds one `migrate` row to the activity log; the
document's revision does not change, so `undo` passes over it.
Directories are searched recursively; a file already at the current version — or at
a newer 2.x minor, which a newer Pen wrote — is left alone unless `--force` is given,
and `--force` keeps a newer minor's own version. A file of another major is read-only:
it counts as a failure, and is left untouched. Every migration diagnostic goes to stderr, prefixed
with the file's path, so discarded legacy data (a stroke `dashPattern`, per-run text
styling) is visible rather than silent.

```bash
woodcase migrate myfile.pen
woodcase migrate Tests --dry-run
woodcase migrate Tests --exclude Tests/WoodcaseTests/Fixtures/v2.9
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--dry-run` | `false` | Report what would change without writing |
| `--force` | `false` | Rewrite files that already declare the current version |
| `--exclude` | — | A file or directory to leave alone (repeatable) |
| `--as` | `$WOODCASE_AS` | Who each `migrate` row is attributed to; with neither, it is unattributed |

**Exit codes:**

| Code | When |
|------|------|
| 0 | Every file was rewritten, skipped or — under `--dry-run` — reported. A run that finds no .pen file at all is 0 too, with `No .pen files found.` on stdout |
| 2 | The invocation was malformed: an unknown flag, or an argument naming a file that is not a .pen file |
| 4 | An argument named nothing at all, **or** at least one file could not be read, migrated or written |

`--dry-run` never changes the code: reporting a file it *would* rewrite is still 0.
The two 4s differ in when they land. A path that does not exist is refused before any
file is touched, because it is almost always a typo and half a run is worse than none:

```
$ woodcase migrate /nowhere/gone.pen
Cannot open /nowhere/gone.pen: no such file. Check the path — `ls /nowhere` lists what is there.
$ echo $?
4
```

A file that *exists* but cannot be handled does not stop the run — the point of walking
a tree is to migrate everything that can be migrated. Each failure is named on stderr,
the summary line counts them, and the process exits 4 at the end:

```
$ woodcase migrate ./designs
./designs/broken.pen: error: Failed to decode .pen document: …
migrated 3 file(s), skipped 1 already current, 1 failed.
$ echo $?
4
```

`scripts/migrate-pen` wraps this for the repository's own fixtures: it builds the CLI,
defaults to `Tests`, and excludes the two directories that must not be rewritten (see
**Fixture layout**, below).

The reusable half is ``PenFileMigrator``, which takes one file's bytes and returns the
rewritten bytes plus the version the source declared and the version they now
declare. Migration is idempotent.

## Fixture layout

The test fixtures under `Tests/WoodcaseTests/Fixtures/` are in three layers, and only
the first is ever rewritten by `migrate`:

| Directory | Holds |
|-----------|-------|
| `Fixtures/` | the working fixtures, all at the current version |
| `Fixtures/v2.9/` | the legacy originals, kept verbatim as migrator input |
| `Fixtures/v2.17/` | the format's own editor's saves — the golden oracle for migration parity |

`GoldenParity` compares a `v2.9` original with its `v2.17` golden; keeping the legacy
half out of the migration run is what keeps that a real acceptance test.

## Output Naming

**PNG files:**
- Single frame: `{filename}@{scale}x.png` (scale suffix omitted at 1x)
- Multiple frames: `{filename}-{framename}@{scale}x.png`

"Multiple" counts the document's top-level frames, reusable definitions included, not
the frames one theme combination matches — so an artboard carries the same name in
every theme subdirectory.

**PDF files:**
- One PDF per theme combination, with each frame as a page: `{filename}.pdf`

**Theme subdirectories:** When multiple theme combinations are rendered, each gets a subdirectory named by the option values sorted alphabetically and joined with `-`. An artboard with no `theme` renders into every subdirectory; one that sets `theme` renders only into the combinations that agree with it:

```
output-dir/
├── dark-ios/
│   ├── myfile-Screen1@2x.png
│   └── myfile-Screen2@2x.png
├── dark-web/
│   └── ...
├── light-ios/
│   └── ...
└── light-web/
    └── ...
```

## Diagnostics

The `--strict` flag causes the CLI to exit with a non-zero status when the pipeline produces warnings (such as missing fonts or unresolved references). Without `--strict`, warnings are printed to stderr but rendering proceeds.

## Topics

### Scripting

- <doc:WoodcaseScripting>

### Pipeline

- ``PenParser``
- ``PenImportResolver``
- ``PenRefExpander``
- ``PenVariableResolver``
- ``PenLayoutEngine``
- ``PenRenderer``

### Diagnostics

- ``PenDiagnostic``
- ``PenDiagnosticCollector``
