# The Woodcase Metadata Namespace

Everything Woodcase keeps in a node's `metadata` lives under one key, `woodcase`; the
spellings from before it are still read, and both merges resolve it key by key.

## Overview

Pen keeps every `metadata` key on every node it draws, nested values included (on notes,
prompts, contexts and text, probed with the headless engine 0.3.11, format 2.21 —
`project/2026-10-11-what-pen-keeps-on-a-note.md`). It does **not** keep the `metadata`
of a `ref` node, nor `metadata` inside a `descendants` override (pen CLI 0.3.11,
2026-10-20, leaf 9Sw8C0): see *Natural paths* below. Woodcase stores what it owns there
under one object, so the keys say whose they are and cannot collide with anyone else's
metadata:

```json
{ "type": "note", "name": "Device check", "content": "Does the scanner …",
  "metadata": { "woodcase": { "type": "postit", "author": "claude",
                              "tint": "#A5D6A7", "fontSize": 15 } } }
```

```json
{ "type": "frame", "name": "Button", "reusable": true,
  "metadata": { "type": "component",
                "woodcase": { "role": "button", "props": { "label": "Label" } } } }
```

`metadata.type` stays the schema's own key, beside the namespace. The decision is Ben's
(Penumbra `project/2026-10-11-notes-comments-and-spans.md`, decisions 1–3).

**Metadata always has a type.** Pen's schema requires one
(`metadata?: { type: string; [key: string]: any }`), so Woodcase never writes metadata
without (Ben's ruling, 2026-10-11): metadata a write creates, or leaves without a type,
takes ``PenMetadata/woodcaseType`` (`"woodcase"`); an old post-it's `type: "postit"` is
rewritten to it when the type moves into the namespace; and metadata holding nothing but
`type: "woodcase"` is removed, since that type only exists to make other keys valid. A
type anyone else wrote is never touched. The rule applies wherever Woodcase *authors*
metadata — a `set` (deep key or whole object), `add`, `replace`, `woodcase migrate`, the
three-way merge's merged value — and to ``PenMetadata/subscript(woodcase:)``. A raw
``EditOperation`` (an undo, an editor's `updateCommon`) and a CRDT entry write land
exactly as written: a peer must reach what the writing peer's own store holds. Since every
authored write carries its type as its own entry, the CRDT can only end typeless when one
peer clears a node's metadata while another adds to it; the next authored write to that
node types it again.

### The keys

``PenMetadata/WoodcaseKey`` lists every key, in six groups
(``PenMetadata/WoodcaseKey/Group``):

| Group | Keys | Read by |
|---|---|---|
| code generation | `props`, `role`, `states`, `action`, `scroll` | ``ComponentAnalyzer``, ``PageAnalyzer``, ``EditableDocument/parameters(ofComponent:)``, the `codegen-*` and `clipped` lints |
| notes | `type`, `state`, `author`, `leaf`, `stage`, `tint`, `copiedFrom`, `anchor`, `replyTo`, `requestedBy`, `createdAt` | ``PenPostIt/Metadata``; see <doc:PenPostItConvention> |
| a note's text style | `fontFamily`, `fontSize`, `fontWeight`, `fontStyle`, `letterSpacing`, `lineHeight`, `textAlign`, `textAlignVertical` | the note's look; Pen strips a note's own text style on load, so it lives here |
| a text's protected decoration | `textDecoration` | ``PenTextDecoration`` and ``PenNode/protectingTextDecoration()``: ``PenParser`` keeps a text's native `underline` and `strikethrough` and this key in step on every read and write, so Pen — which strips the native keys — cannot lose them; see <doc:PenRichText>, *Underline and strikethrough survive Pen* |
| a text's rich text | `spans` | ``PenMetadata/textSpans`` and ``PenNode/appliedRuns``: the layout, the renderer and the `spans-stale` lint; see <doc:PenRichText> |
| a stroke's dash | `strokeDash`, `strokeDashOffset` | ``PenNode/strokeDash`` (``PenStrokeDash``): every renderer and emitter, the planner and the `stroke-dash-ignored` lint; an inspector reads them as fields through ``PenSchema/woodcaseFields(for:)``; see <doc:PenRendering>, *Dashed strokes* |
| editor state | `locked`, `defaultTextStyle` | an editor: a locked node (``PenNode/isLocked``: the key is the boolean `true`) is not selected or hit on the canvas, only in its layer list (Penumbra spec §14, the integrator's ruling of 2026-10-15); an inspector reads it as a field through ``PenSchema/woodcaseFields(for:)``. The format has no lock, and Pen keeps the key and ignores it. `defaultTextStyle: true` marks a text as the document's default text style, since the format has no document-level metadata (Penumbra spec §6.3, Ben's ruling of 2026-10-18): ``EditableDocument/defaultTextStyleNodeID()`` finds the first marked text in document order and ``EditPlanner/planMarkDefaultTextStyle(nodeID:in:)`` moves the mark; only a text's mark counts, and only a text takes it as a field. A write of either is held to `true` or `false` on any node, as every key's form is held whatever the node |
| a stroke's miter limit | `strokeMiterLimit` | ``PenNode/strokeMiterLimit``: every renderer and emitter, painted extent and the stroke-band hit test; Pen's 4 where absent; see <doc:PenInteroperability>, *Miter Limits and Shadow Spreads Live in Metadata* |
| a shadow's spread | `shadowSpread` | ``PenShadowSpread`` and ``PenNode/shadowSpread(forEffect:)``: the CG renderer and SVG export, and the `shadow-spread-stale` lint; one entry per spread shadow, addressed by its place among the effects and stale once that shadow changes |
| a node's blend mode | `blendMode` | ``PenNode/blendMode``: every renderer and emitter (the CG renderer, SVG export, React and SwiftUI), as one isolated group. A write never emits a top-level `blendMode`. Pen keeps the key (pen CLI, 2026-10-20) |

Every key of the last five groups but `shadowSpread` and `textDecoration` is read and
written at a natural path — `kind.strokeDash`, `common.locked`, `kind.spans` — not at
its storage path; see *Natural paths* below.

### Natural paths

**A key that stands in for a property Pen's format lacks is read and written at a natural
path, and Woodcase decides where it is stored** (Ben's ruling, 2026-10-20;
`project/2026-10-20-natural-paths-for-woodcase-properties.md`). One table,
``PenMetadata/WoodcaseKey/naturalPath`` with ``PenMetadata/WoodcaseKey/naturalPathTypes``,
names each:

| Natural path | Stored at | Node types |
|---|---|---|
| `kind.blendMode` | `metadata.woodcase.blendMode` | the drawn shapes, text, icons, frames and groups (``PenNode/blendedTypes``) |
| `kind.strokeDash`, `kind.strokeDashOffset` | `metadata.woodcase.strokeDash`, `.strokeDashOffset` | frame, rectangle, ellipse, polygon, path, line |
| `kind.strokeMiterLimit` | `metadata.woodcase.strokeMiterLimit` | as above, but not line |
| `common.locked` | `metadata.woodcase.locked` | every type (``NodePropertyCodec/naturalCommonPaths``) |
| `kind.defaultTextStyle`, `kind.spans` | `metadata.woodcase.defaultTextStyle`, `.spans` | text |

The codec converts at the door (``NodePropertyCodec/storingNaturalPaths(_:on:)``): a
write of `kind.strokeDash` is planned, applied, replicated and undone as the ordinary
metadata write it stands for, and a read of it reads the stored key. `woodcase set`,
batches, `tree --props`, `find`, `woodcase schema` (the rows name the stored key under
`.pen key`), ``PenSchema/field(_:for:)`` and the `doc` API all speak the natural path;
`get` prints the values a node sets under a `woodcase-owned` block, and in `--json` as
``NodeReport/properties``, beside the node JSON that keeps them in metadata. The typed
accessors — ``PenNode/strokeDash``, ``PenNode/strokeMiterLimit``, ``PenNode/isLocked``,
``PenNode/blendMode`` — are unchanged, and every renderer reads through them.

**The storage path is refused as a way in.** An authored write — a `set`, a batch, the
`doc` API, an inspector's planned intent, an override — that names
`common.metadata.woodcase.strokeDash`, or a deep key below it, is refused with
``EditingError/storedAtNaturalPath(nodeID:path:naturalPath:)``
("common.metadata.woodcase.strokeDash is stored for you; write kind.strokeDash"), so two
spellings of one write cannot drift. The whole `common.metadata` object is still written
as given, and reading `common.metadata` (or a deep key into it) still shows what is
stored. A raw ``EditOperation`` — an undo, a CRDT entry, a session edit — is not an
authored write and lands as written. Keys with no natural path yet — the code-generation
keys, the note keys and a shadow's spread — are written at their storage paths as before.

**An instance override of a Woodcase-owned key is stored in the override's own
`metadata.woodcase`** (rule 6; Ben's ruling, 2026-10-20). `override Inst/Box
kind.strokeDash=[4,2]` — or `strokeDash=[4,2]` — writes
`descendants.Box.metadata.woodcase.strokeDash`, laid over what the entry already keeps
there (``NodePropertyCodec/foldingNaturalOverrideKeys(_:unset:onto:)``, the one fold the
planner, ``EditOperation/normalized(in:)``, the document's apply, the CRDT and decoding all
use). On expansion the override's metadata is laid over the component node's **per
entry**, `woodcase` key by key (``PenMetadata/overlaying(_:onto:)``): the component's notes
and other Woodcase keys still reach the instance, later edits to them still flow through,
and a `null` clears one key on that instance alone. The instance root takes the `ref`
node's own `metadata.woodcase` laid over the component root's
(``PenMetadata/instanceRoot(of:under:)``), so an override of the root, and an instance's
lock (`set Inst common.locked=true`), are written on the ref node. A raw key a file from
before the rule wrote (`descendants.Box.blendMode`, or a ref's root override `blendMode`) is
read into that metadata on load. A file or an `add` that writes a natural field top-level on
a node is read into the node's own metadata the same way.

**Pen drops these overrides**, and Ben accepts it: a `metadata` object in a `descendants`
override, and the metadata of a `ref` node, are both gone after Pen's load and save (pen CLI
0.3.11, 2026-10-20, leaf 9Sw8C0), as was the raw key before. Transfers run from Pen to
Penumbra, not round trips, and Pen ignores Woodcase's metadata anyway. The
`pen-drops-override` notice (<doc:WoodcaseLint>) names what a save through Pen would lose.

### One accessor

All Woodcase code reads and writes its keys through
``PenMetadata/subscript(woodcase:)``, never through ``PenMetadata/extensions``:

```swift
var metadata = node.common.metadata ?? PenMetadata(type: nil)
metadata[woodcase: .tint]                       // either spelling, the namespace winning
metadata[woodcase: .author] = .string("claude") // stored under woodcase; old spelling removed
metadata[woodcase: .leaf] = nil                  // both spellings removed
```

`spans` is the one key whose value is structured: its shape,
``PenMetadata/WoodcaseKey/Shape/textSpans``, holds an authored write to
``PenTextSpans/init(metadataValue:)``, and a refusal names what is wrong
(``EditingError/textSpansRejected(nodeID:reason:)``). Code reads it as typed spans through
``PenMetadata/textSpans``, which goes through the same subscript.

**Adding a key** is one case of ``PenMetadata/WoodcaseKey``, and, for a key that stands
in for a property the format lacks, its row in the natural-path table
(``PenMetadata/WoodcaseKey/naturalPath``, ``PenMetadata/WoodcaseKey/naturalPathTypes``)
and its field row (``PenSchema/woodcaseFields(for:)``) — `NaturalPathTableTests` fails on
a field row with no natural path. Then its
``PenMetadata/WoodcaseKey/group``, its ``PenMetadata/WoodcaseKey/shape`` (what an
authored value is held to), a ``PenMetadata/WoodcaseKey/summary``, and an
``PenMetadata/WoodcaseKey/oldSpelling`` only if files from before the namespace carry it
— a new key has none. Reading, writing, the authoring check, `woodcase schema postit`
(for a note key), the `metadata-old-style` lint and `woodcase migrate` all follow from
the case.

### Old spellings

Files written before the namespace are still read — a deliberate exception to the build
stage's "no backward compatibility", because Ben has internal files that use them:

- **The code-gen keys** with an underscore, at the top of `metadata`: `_props`, `_role`,
  `_states`, `_action`, `_scroll`. Read wherever they appear.
- **The post-it keys**, bare, beside `metadata.type: "postit"` (the old marker, read as
  `woodcase.type: postit`, and rewritten to `type: "woodcase"` when it moves in): `state`, `author`, `leaf`, `stage`, `tint`, `copiedFrom`.
  Read only on metadata that is a post-it's — `type: "postit"`, or a `woodcase.type` —
  because anywhere else a bare `author` is someone else's key.

Where both spellings are written, `woodcase.*` wins. A post-it's legacy `kind`
(`question`, `answer`, `reference`) is no longer part of the convention: it is left as
written and nothing reads it. A plain note's `state` is no longer drawn either — only
comments and prompts have one (Ben's ruling, 2026-10-11) — but `state` is still a live key,
so a bare one still moves into the namespace like any other; the `note-state` lint
(<doc:WoodcaseLint>) names one on a plain note, and nothing drops it.

**A write converts what it touches.** An authored metadata write — a `set`, deep key or
whole object, a session edit's deep key, and every node of an `add` or `replace` subtree — stores the Woodcase keys
it changes under the namespace only
(``NodePropertyCodec/storingWoodcaseKeysInNamespace(_:replacing:)``): a key written in
the namespace removes its old spelling, and a key written under its old spelling
(`common.metadata._role=button`, a legacy post-it's `common.metadata.state=resolved`)
lands in the namespace. A deep key into a namespaced key whose value still lives under
its old spelling (`common.metadata.woodcase.props.caption=…` beside an old `_props`)
moves that value in first, so the entry merges with it. Keys the write leaves alone keep
their spelling, so a write never rewrites more than it names.

**A deep-key read sees what a write would touch.** `tree --props` and `find` read a deep
key through the same accessor (``NodePropertyCodec/deepValue(in:at:of:)``):
`common.metadata.woodcase.leaf` answers from either spelling, and an old spelling such as
`common.metadata.leaf` reads the namespaced value exactly where a write to it would land
in the namespace — on a `type: postit` object, or one that names its `woodcase.type` —
and the bare key as written anywhere else.

**`woodcase migrate`** converts a whole file at once — current format version or not —
as one ordinary, logged and undoable edit
(``EditableDocument/oldStyleWoodcaseKeyMigration()``,
``PenFileTransaction/moveOldStyleWoodcaseKeys(at:identity:log:timeout:effect:isolation:)``).
`woodcase lint --severity notice` names a node's old spellings first, as
`metadata-old-style` (<doc:WoodcaseLint>). Override patches inside a `ref`'s
`descendants` are not rewritten.

### Merging per key

Both merges resolve metadata per **entry** rather than as one value: each top-level key
of the object, except `woodcase`, which splits one level deeper — each key under it is
its own entry (``NodePropertyCodec/metadataEntries(of:)``). So two people changing one
note's tint and its author both keep their edit.

- **The CRDT** replicates a metadata change as one LWW write per changed entry, at the
  entry's path (`common.metadata.type`, `common.metadata.woodcase.tint`), never the whole
  object, so a whole-object write never races an entry write. A removed entry writes
  `null`; an object or namespace a write empties is removed.
- **The three-way merge** takes an entry only theirs changed, keeps ours where both
  changed it differently, and reports that as a ``MergeConflict/Subject/property(nodeID:path:)``
  at the entry's path (<doc:MergingDocuments>).

Below an entry a value is whole: two edits to different parameters inside
`woodcase.props` are one entry both sides changed. A key holding `.` or `%` is
percent-escaped in an entry path (`%2E`, `%25`).

### Writing one entry from an app

A ``DocumentSession`` edit takes the same paths as `woodcase set`: an
``EditOperation/setProperties(_:)`` of `kind.spans` (or `null`, to remove it) — or of a
deep key such as `common.metadata.woodcase.tint` — is folded onto the node's metadata by ``NodePropertyCodec/folding(_:onto:)``
when it is normalized (``EditOperation/normalized(in:)``), the one fold the batch planner
also runs, so it follows every rule above. A metadata write is then entry by entry
throughout:

- **Keys.** It stamps one ``ChangeKey/property(node:path:)`` per entry it changes, at the
  entry's path — the key a collaborator's replicated entry write stamps — so the two meet.
- **Undo.** Its inverse is one guarded step per entry (``EditableDocument/granularInverse(of:)``).
  Undo restores each entry exactly, old spelling and missing `type` included, and keeps
  an entry another author has written since (``CommittedChange/kept``), restoring the
  rest around it (``GuardedInverse/resolved(in:)``).
- **Replay.** Each step also carries the whole object as it stands after the steps
  before it, so an activity row's inverse or a batch's undo, replayed on the document
  the write left, restores it exactly.

## Topics

### The namespace

- ``PenMetadata``
- ``PenMetadata/woodcaseNamespace``
- ``PenMetadata/woodcaseType``
- ``PenMetadata/WoodcaseKey``
- ``PenMetadata/subscript(woodcase:)``
- ``PenMetadata/textSpans``
- ``PenMetadata/oldStyleWoodcaseKeys``
- ``PenMetadata/migratingOldStyleWoodcaseKeys()``

### Writing and migrating

- ``NodePropertyCodec/storingWoodcaseKeysInNamespace(_:replacing:)``
- ``NodePropertyCodec/storingWoodcaseKeysInNamespace(in:current:)``
- ``EditableDocument/oldStyleWoodcaseKeyMigration()``
- ``PenFileTransaction/moveOldStyleWoodcaseKeys(at:identity:log:timeout:effect:isolation:)``

### Natural paths

- ``PenMetadata/WoodcaseKey/naturalPath``
- ``PenMetadata/WoodcaseKey/naturalPathTypes``
- ``PenMetadata/WoodcaseKey/propertyPath``
- ``PenMetadata/WoodcaseKey/init(naturalPath:)``
- ``PenMetadata/WoodcaseKey/init(storagePath:)``
- ``NodePropertyCodec/naturalCommonPaths``
- ``NodePropertyCodec/naturalKey(of:on:)``
- ``NodePropertyCodec/naturalValues(of:)``
- ``NodePropertyCodec/checkNoStoragePaths(_:nodeID:)``
- ``NodePropertyCodec/foldingNaturalOverrideKeys(_:unset:onto:)``
- ``PenMetadata/overlaying(_:onto:)``
- ``PenMetadata/instanceRoot(of:under:)``
- ``NodePropertyCodec/writesNaturalPath(_:on:)``
- ``NodePropertyCodec/storingNaturalPaths(_:on:)``
- ``PenNode/blendMode``
- ``PenNode/blendedTypes``

### Merging

- ``NodePropertyCodec/MetadataEntry``
- ``NodePropertyCodec/metadataEntries(of:)``
- ``NodePropertyCodec/metadataEntryWrites(from:to:)``
- ``NodePropertyCodec/metadataEntryPath(_:)``
- ``NodePropertyCodec/settingMetadataEntry(_:at:on:)``
