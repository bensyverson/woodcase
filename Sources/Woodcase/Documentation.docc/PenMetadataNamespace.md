# The Woodcase Metadata Namespace

Everything Woodcase keeps in a node's `metadata` lives under one key, `woodcase`; the
spellings from before it are still read, and both merges resolve it key by key.

## Overview

Pen keeps every `metadata` key on every node, nested values included (on notes,
prompts, contexts and text, probed with the headless engine 0.3.11, format 2.21 —
`project/2026-10-11-what-pen-keeps-on-a-note.md`). Woodcase stores what it owns there
under one object, so the keys say whose they are and cannot collide with anyone else's
metadata:

```json
{ "type": "note", "name": "Device check", "content": "Does the scanner …",
  "metadata": { "woodcase": { "type": "postit", "state": "open", "author": "claude",
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

``PenMetadata/WoodcaseKey`` lists every key, in three groups
(``PenMetadata/WoodcaseKey/Group``):

| Group | Keys | Read by |
|---|---|---|
| code generation | `props`, `role`, `states`, `action`, `scroll` | ``ComponentAnalyzer``, ``PageAnalyzer``, ``EditableDocument/parameters(ofComponent:)``, the `codegen-*` and `clipped` lints |
| notes | `type`, `state`, `author`, `leaf`, `stage`, `tint`, `copiedFrom`, `anchor`, `replyTo` | ``PenPostIt/Metadata``; see <doc:PenPostItConvention> |
| a note's text style | `fontFamily`, `fontSize`, `fontWeight`, `fontStyle`, `letterSpacing`, `lineHeight`, `textAlign`, `textAlignVertical` | the note's look; Pen strips a note's own text style on load, so it lives here |

### One accessor

All Woodcase code reads and writes its keys through
``PenMetadata/subscript(woodcase:)``, never through ``PenMetadata/extensions``:

```swift
var metadata = node.common.metadata ?? PenMetadata(type: nil)
metadata[woodcase: .tint]                       // either spelling, the namespace winning
metadata[woodcase: .state] = .string("resolved") // stored under woodcase; old spelling removed
metadata[woodcase: .leaf] = nil                  // both spellings removed
```

**Adding a key** is one case of ``PenMetadata/WoodcaseKey``: its
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
written and nothing reads it.

**A write converts what it touches.** An authored metadata write — a `set`, deep key or
whole object, and every node of an `add` or `replace` subtree — stores the Woodcase keys
it changes under the namespace only
(``NodePropertyCodec/storingWoodcaseKeysInNamespace(_:replacing:)``): a key written in
the namespace removes its old spelling, and a key written under its old spelling
(`common.metadata._role=button`, a legacy post-it's `common.metadata.state=resolved`)
lands in the namespace. A deep key into a namespaced key whose value still lives under
its old spelling (`common.metadata.woodcase.props.caption=…` beside an old `_props`)
moves that value in first, so the entry merges with it. Keys the write leaves alone keep
their spelling, so a write never rewrites more than it names.

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
note's tint and its state both keep their edit.

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

## Topics

### The namespace

- ``PenMetadata``
- ``PenMetadata/woodcaseNamespace``
- ``PenMetadata/woodcaseType``
- ``PenMetadata/WoodcaseKey``
- ``PenMetadata/subscript(woodcase:)``
- ``PenMetadata/oldStyleWoodcaseKeys``
- ``PenMetadata/migratingOldStyleWoodcaseKeys()``

### Writing and migrating

- ``NodePropertyCodec/storingWoodcaseKeysInNamespace(_:replacing:)``
- ``NodePropertyCodec/storingWoodcaseKeysInNamespace(in:current:)``
- ``EditableDocument/oldStyleWoodcaseKeyMigration()``
- ``PenFileTransaction/moveOldStyleWoodcaseKeys(at:identity:log:timeout:effect:isolation:)``

### Merging

- ``NodePropertyCodec/MetadataEntry``
- ``NodePropertyCodec/metadataEntries(of:)``
- ``NodePropertyCodec/metadataEntryWrites(from:to:)``
- ``NodePropertyCodec/metadataEntryPath(_:)``
- ``NodePropertyCodec/settingMetadataEntry(_:at:on:)``
