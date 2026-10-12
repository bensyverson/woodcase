# Editing Documents

Build mutable, editable representations of .pen documents for use in editor applications.

## Overview

The editing layer provides ``EditableDocument``, a mutable class that decomposes a
``PenDocument``'s tree into a flat dictionary of nodes with a separate structure map.
This makes structural operations (insert, delete, move) efficient and straightforward,
while preserving full round-trip fidelity with the original document.

### Flat Store Architecture

Rather than editing the nested `PenDocument` tree directly, `EditableDocument` stores
nodes in a flat `[String: PenNode]` dictionary with their children stripped to `nil`.
The tree structure is maintained by three maps:

- **nodes**: Every node by ID, with children removed
- **children**: Parent ID to ordered child IDs — present, possibly empty, for every
  container that declares a children array. A container whose last child is moved or
  deleted keeps an empty list, so it materializes as `"children": []` rather than losing
  the key, and a CRDT peer applying the same removal agrees
- **parents**: Child ID to parent ID
- **rootOrder**: Ordered IDs of top-level nodes

This separation makes structural edits (reparenting, reordering, subtree deletion) simple
dictionary operations rather than recursive tree transformations.

### Creating and Materializing

```swift
// Decompose a PenDocument into the flat store
let editable = EditableDocument(from: document)

// Apply operations...
try editable.apply(.insertNode(EditOperation.InsertNode(
    node: newNode, parentID: "frame1"
)))

// Reconstruct back to PenDocument for the rendering pipeline
let updated = editable.materialize()
```

### Operations

All edits go through typed ``EditOperation`` values applied via ``EditableDocument/apply(_:)``.
Operations are value types conforming to `Friendly`, so they can be serialized, compared,
and stored for undo/redo.

**Structural operations** modify the node tree:
- ``EditOperation/insertNode(_:)`` — add a node (with optional subtree)
- ``EditOperation/deleteNode(_:)`` — remove a node and all descendants
- ``EditOperation/moveNode(_:)`` — reparent or reorder a node
- ``EditOperation/replaceSubtree(_:)`` — swap everything a node is and holds for a new
  subtree, keeping its id, its parent and its index among its siblings

**Property operations** update node data:
- ``EditOperation/updateCommon(_:)`` — replace shared properties (position, opacity, etc.)
- ``EditOperation/updateKind(_:)`` — replace type-specific data (fills, dimensions, etc.).
  A retype to a leaf drops the node's child list and is refused while it still holds
  children; ``EditOperation/UpdateKind/emptyChildren`` says whether a container with no
  children writes `"children": []`. The inverse restores both.
- ``EditOperation/setProperties(_:)`` — set individual properties by path, leaving the rest alone

### Patching Properties by Path

``EditOperation/updateKind(_:)`` replaces a node's whole payload, so a caller that
wants to change one fill must reconstruct every other field. ``EditOperation/setProperties(_:)``
names only the properties it changes:

```swift
try editable.apply(.setProperties(EditOperation.SetProperties(
    nodeID: "rect1",
    properties: [
        "kind.fills": .string("blue"),
        "kind.width": .int(240),
        "common.name": .string("Card background"),
    ]
)))
```

**The path vocabulary** is the one ``PropertyDiff`` emits and ``LWWPropertyMap`` keys
on, so an edit, a CRDT write and a dirty-tracking diff all name a property the same way:

- `"common.<field>"` — the thirteen shared properties: `name`, `x`, `y`, `rotation`,
  `opacity`, `enabled`, `flipX`, `flipY`, `reusable`, `theme`, `context`,
  `layoutPosition`, `metadata`.
- `"kind.<field>"` — the fields of *this node's kind*: `kind.fontSize` exists on a text
  node, not on a rectangle.
- `"extras.<key>"` — one of the node's ``PenNode/extras``, the keys a file wrote that
  its type does not model. A null removes the key. A key the type claims (`extras.width`
  on a frame) is refused, and so is any extra on a `ref`, whose unclaimed keys are root
  overrides. This family is for a diff and for undo: an agent's `set` cannot write one —
  ``NodePropertyCodec/checkAuthored(_:on:)`` refuses the path — and
  ``PropertyDiff/diffExtras(old:new:)`` names the keys that differ between two nodes.

A `common.metadata` write stores the Woodcase keys it changes under
`metadata.woodcase` only, and holds them to their shapes: a misspelled post-it state, or
a malformed tint, is refused with
``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)``. See
<doc:PenMetadataNamespace> and <doc:PenPostItConvention>.

``NodePropertyCodec/paths(for:)`` lists what a given node accepts, and
``NodePropertyCodec/value(at:of:)`` reads one back. `"kind.type"` is deliberately not a
path — changing a node's type is ``EditOperation/updateKind(_:)``'s job, or
``EditOperation/replaceSubtree(_:)``'s when its contents change with it.

### Replacing a subtree

``EditOperation/replaceSubtree(_:)`` is the "rebuild this node" edit, and it exists as
one operation rather than a delete plus an insert because a delete takes the node's
*place* with it: the id, the position among its siblings, and every reference pointing
at it. The subtree carries the id of the node it replaces, so the operation needs no
second identifier that could disagree with it, and its own inverse is another
``EditOperation/replaceSubtree(_:)`` carrying the subtree the document held — which is
what makes an undo restore the previous bytes rather than an equivalent tree.

```swift
try editable.apply(.replaceSubtree(EditOperation.ReplaceSubtree(node: rebuilt)))
```

Two consequence guards apply, both refusing rather than surprising the caller: a
replacement that would strand a component's instances raises
``EditingError/componentHasInstances(componentID:instanceIDs:)``, exactly as a delete
does, and changing the root *type* of a reusable definition that instances point at
raises ``EditingError/componentTypeChange(componentID:from:to:instanceIDs:)``. In
collaborative mode the operation is decomposed into the primitives the CRDT already
converges on before it is replicated, because there is no whole-subtree CRDT
primitive.

**Values are in the .pen file's own JSON shape**, carried as ``AnyCodable``: a number is
`42`, a variable reference is `"$spacing.large"`, a sizing is a number or
`"fit_content"`/`"fill_container"`, a fill is whatever the file's `fill` key holds.
Reading a property and writing the result back is a no-op. Writing ``AnyCodable/null``
clears the property.

**One value converts, in one direction.** A *number* written to a property whose shape
is a string or a `$variable` — `kind.content`, `kind.fontFamily`, `kind.icon` and their
kin — is stored as the string it spells, because there is no other value such a
property could take from a number and refusing taught nothing. Nothing else converts,
and a node of an unrecognized type is never converted at all. See
``NodePropertyCodec/coercing(_:at:on:)``. A conversion is not silent: the write reports
it as a ``WriteDivergence``, which is how a caller learns its number is now text
without reading the node back.

**Nothing is set silently and nothing fails silently.** The operation is atomic: every
key and value is validated before anything is written, so a map with one bad entry
leaves the document untouched. A key that is not a property of this node's kind throws
``EditingError/unknownProperty(nodeID:key:nodeType:)`` — including a key the file carries
that the model does not, which is kept in ``PenNode/extras`` and written back but never
edited — and a value that cannot decode
throws ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``, whose
`expected` spells out the accepted shape and `actual` says what was wrong with the value
given — for `kind.fills`, `expected` is *a color string, a $variable, a fill object, or
an array of either (a fill object's type is one of color, gradient, image, mesh_gradient,
shader), for example `[{"type":"color","color":"#FFD166"}]`* and `actual`, for an array
with one bad element, is *an array (`[0].type`: "solid" is not an accepted spelling)*.

Both halves are assembled rather than written out. A ``PenPropertyShape`` is a list of
``PenValueForm``s, not a list of sentences: each form knows both how a refusal words it
(*a `$variable`*) and what it machine-is (a reference to a variable of type `number`).
Every enumerated vocabulary is read off the type that decodes it —
``PenPropertyShape/oneOf(_:)`` over the `String` enums — and every structured form points
at the ``PenNestedShape`` declared beside its decoder: ``PenFill/schema``,
``PenEffect/schema``, ``PenStrokeWidth/schema``. Every ``PenPropertyShape/example`` is
written through the codec by `StructuredPropertyShapeTests`, and `PenSchemaTests` holds
each nested variant's keys against the payload's own stored properties, so a message
cannot describe a decoder the library does not have. It did once: the accepted-forms text
offered `{"type":"solid"}`, which no .pen decoder has ever taken, and called a two-element
padding `[horizontal, vertical]` when the decoder reads it as `[vertical, horizontal]`.

### The vocabulary as a whole

``PenSchema`` assembles the same shapes into tables — one per node type, plus the shared
`common.*` one — which is what `woodcase schema` prints and what
<doc:WoodcaseCLI> documents. It reads `PropertyDiff.allKindKeys` for the paths and
``NodePropertyCodec/shape(of:)`` for the shapes, so the table and the refusal are the
same list by construction; a test walks every ``PenNode/NodeType`` and asserts it.

The inverse of a patch is a patch: ``EditableDocument/prepareInverse(of:)`` returns a
`setProperties` carrying the prior value of exactly the same keys, so undo restores a
cleared property as well as a changed one. In collaborative mode the patch replicates as
one last-writer-wins ``CRDTOperation/SetProperty`` per path, so two peers editing
different properties of the same node both keep their edit — except `extras.<key>` paths,
which replicate as one write of the node's whole extras register
(``CRDTDocument/extrasProperty``).

**Component operations** work with reusable component instances:
- ``EditOperation/overrideDescendant(_:)`` — create or update descendant overrides on a ref node
- ``EditOperation/overrideRoot(_:)`` — create or update the root overrides a ref shows the component through
- ``EditOperation/detachRef(_:)`` — replace a ref with its expanded independent nodes

A detach's ids are derived, not drawn: ``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``
hashes the ref's id and each expanded node's id (FNV-1a, written as five base-62
characters) and re-salts deterministically on a collision with an id the document holds
— or, in a collaborative session, one the replica has deleted. So the same document and
ref detach to the same ids every time, and ``EditableDocument/prepareInverse(of:)``
returns the complete inverse —
delete the expanded root, re-insert the ref's whole subtree where it was — *before* the
detach runs. A detaching delete's inverse is likewise whole: the deleted subtree back,
then each detach undone, last first.

In a collaborative session the hash is also namespaced by the replica's ``PeerID``. A CRDT
names a node by its id, so two peers detaching one instance concurrently must create
distinct nodes — with shared ids, one peer's delete of its copy was undone by the other's
late `createNode`, and the replicas diverged.

Both override operations carry an `unset` list, applied after the merge. Removing a key
is not the same as overriding it with null: a null is *stored* and clears the
definition's value when the instance expands, while a removed key lets the definition
show through again. An entry left with no keys at all goes away, so a removal reads back
as the absence it is — and the inverse of an override unsets whatever the write added,
so undo puts the map back exactly as it stood.

**Document-level operations** manage metadata:
- Variables: ``EditOperation/addVariable(_:)``, ``EditOperation/updateVariable(_:)``, ``EditOperation/removeVariable(_:)``
- Imports: ``EditOperation/addImport(_:)``, ``EditOperation/updateImport(_:)``, ``EditOperation/removeImport(_:)``
- Themes: ``EditOperation/addThemeAxis(_:)``, ``EditOperation/updateThemeAxis(_:)``, ``EditOperation/removeThemeAxis(_:)``
- The root's own properties: ``EditOperation/setDocumentProperties(_:)`` sets or clears
  `fonts`, `version`, `fileToken` and root `extras.<key>` by key, in the vocabulary of
  ``DocumentPropertyCodec``. The keys `variables`, `imports` and `themes` carry only
  whether each table is declared: `{}` declares it (a file may write an empty table)
  and leaves its entries alone; null leaves out a table with no entries and is refused
  for one that has some, since its inverse could not restore them. Removing a table's
  last entry still leaves the table out, so a merge that must end on `"variables": {}`
  removes the entries and then declares the table. Its inverse names exactly the keys
  it wrote, with their prior values. It is **local-only** in a collaborative session: the CRDT keeps no
  register for these, so ``EditableDocument/applyLocal(_:)`` applies it to the flat
  store and returns no operations to send.

### Component Registry and Expansion

The ``EditableDocument`` maintains a live ``EditableDocument/componentRegistry`` — a
`[String: PenNode]` index of all nodes with `reusable == true`. This registry updates
automatically as nodes are inserted, updated, or deleted.

**Expansion** resolves `ref` nodes into their full component trees:

```swift
// Expand a single ref with provenance tracking
let result = try editable.expandRef(nodeID: "ref1")
print(result.provenance.componentID)  // "Button"

// Expand all refs in a subtree
let (expanded, context) = try editable.expandSubtree(rootID: "container")

// Expand the entire document
let (doc, context) = editable.expandedDocument()
```

All three route through ``PenRefExpander`` — the one expander — over a registry
built from *every* reusable in the document, so a ref nested inside a component
expands with it, a component that is itself a ref follows its chain, and the
editing layer's answer is the same one `woodcase tree` and the code generators
get. The registry is materialized on demand: ``EditableDocument/componentRegistry``
holds flat-store nodes whose children were stripped on the way in, and handing
those to the expander would expand a component to an empty shell.

A read that walks instances without expanding them — ``TreeView``'s expanded rows,
the descendant-key walk, the address resolver — has to stop where the expander stops.
The expander carries the components already on its chain and leaves a `ref` as written
when its component, or any member of that component's loop, is on the chain — so the
nesting among components that contain each other is not expanded at all, and a
definition drawn where it is written counts as its component entered (see
<doc:ComponentLoops>). ``EditableDocument/componentPlacement(of:onChain:)`` is that step,
alias links included, and ``EditableDocument/effectiveRefData(of:enclosedBy:)`` settles a nested
`ref` from the payload the walk already holds for its enclosing instance. The tree
walk carries both down, so a row costs the same however deep its instance chain.

Only ``EditableDocument/expandRef(nodeID:)`` is cached, in an ``ExpansionCache``;
the subtree and document reads expand in one pass instead.

A cached expansion is a snapshot of a component's whole subtree, so any edit
*inside* that subtree falsifies it — a text node three levels down, a child
inserted, a node moved out — not just an edit to the ref or to the component's
root. One rule enforces that, in one place:
``EditableDocument/invalidatingCaches(touching:_:)`` wraps every mutating
path (``EditableDocument/apply(_:)`` for local edits,
``EditableDocument/applyMutation(_:)`` for remote CRDT ones, the reconciliation
that closes a remote batch, and the two value-returning mutators
``EditableDocument/deleteNode(_:)`` and ``EditableDocument/detachRef(_:)``). Each
names the nodes it touches — every node whose content it writes, and the parent a
move or an insert lands under — and the rule reads them before and after the
mutation: a delete only looks like component work beforehand, an insert only
afterwards.

What the rule forgets is the edit's *revision closure*
(``EditableDocument/revisionDependents(of:)``): each touched node, each ancestor
above it, each node that renders one of those (an instance of a component on the
spine), each of *its* ancestors, and so on. The walk reads the reverse of
``PenNode/renderedComponentIDs`` from a `ComponentReferrers` index, which the same
rule keeps exact, so it costs what the edit reaches — its spine, for an edit clear of
every component — rather than a pass over the document. The cached expansions it
drops are the instances in that closure, since an expansion reads exactly what its
instance renders; the component loops memoized beside them are dropped only by an
edit that can change the component graph (a component made or unmade, an instance
inside one rewritten, or a subtree carrying either moved in or out). Every other
expansion stays cached.

The same closure scopes the second cache. ``EditableDocument/revision(of:)``
memoizes into a `RevisionCache`: a node's revision hashes the node, its descendants
and the nodes it renders, so an edit can only move the revisions in its closure. The
wrapper forgets exactly those — before the mutation and after it, so a move's old
parent chain and its new one are both dropped — and leaves every other entry warm.
Each node's own canonical encoding is memoized beside its revision and forgotten only
when the node itself is written, so refolding a forgotten instance or ancestor costs a
few string combines rather than a JSON encoding. That is what makes
`woodcase tree --json`, which asks for one revision per row, a single pass over the
document rather than one subtree walk per row — and an edit inside a component cost
its instances rather than the document. ``EditableDocument/documentRevision`` is not
cached at all: it is one hash over the root nodes' revisions, which are.

> **Corrected 2026-10-05 (Woodcase leaves `OWicrc`, `tHIrpG`):** until then any edit
> touching a `ref`, a component or a node inside one emptied both caches, and a remote
> batch's reconciliation emptied the revision cache. Every session commit reads
> ``EditableDocument/documentRevision``, so each such edit re-encoded every node: 13 ms
> for a nudge inside a component on a 2,580-node document, 24 ms for a collaborator's
> recolor on Penumbra's 2,464-node perf board. Both now cost what they reach — see
> `project/2026-10-05-edit-cost-proportional.md` for the figures.

### Component Introspection

Use ``EditableDocument/inspectComponent(_:)`` to discover a component's slots and
overridable property surface:

```swift
if let surface = editable.inspectComponent("comp1") {
    for slot in surface.slots {
        print("Slot: \(slot.frameName ?? slot.frameID)")
    }
    for node in surface.overridableNodes {
        print("\(node.nodeName ?? node.nodeID): \(node.properties)")
    }
}
```

### Incremental Layout

For interactive editing, ``EditableDocument`` provides an incremental layout pipeline
that avoids full re-layout after every edit. The system classifies each change and
lays out again only the containers it reaches. The layout lives in one
``PenLayoutState`` the document's ``LayoutCache`` holds, and
``EditableDocument/computeLayout(textMeasurer:)`` returns a ``PenLayoutChange`` naming
exactly the rects that differ; ``EditableDocument/layoutRects`` holds them all.

```swift
// First call does a full layout pass: every rect is new
let change = editable.computeLayout()
let rects = editable.layoutRects

// After an edit, check what's dirty
try editable.apply(.updateKind(EditOperation.UpdateKind(
    nodeID: "rect1",
    kind: .rectangle(PenNode.RectangleData(
        width: .fixed(200), height: .fixed(50),
        fills: .single(.shorthand("blue"))
    ))
)))

// dirtyLayoutNodeIDs: nodes needing re-layout (+ ancestors)
// dirtyRenderNodeIDs: nodes needing visual update only (e.g. color change)
// dirtyNodeIDs: union of both sets
print(editable.dirtyLayoutNodeIDs)  // ["rect1", "frame1"]

// Lay out again node by node: the change names rect1, frame1 and what they moved
let update = editable.computeLayout()

// After rendering dirty nodes, clear tracking
editable.clearDirtyNodes()
```

**Three-tier change categorization** (``ChangeCategory``):
- **Render-only** — color, opacity, fills, stroke, effects, blendMode, etc. Skip re-layout.
- **Layout** — x, y, width, height, gap, padding, font props, rotation, enabled, theme,
  reusable, etc. Names the node and its spine. A `theme` change names the node's
  whole subtree, since every descendant resolves its variables through it. When the
  node is a component, sits inside one, or is drawn by a `ref` — so expansion carries
  the change into other boards — it also names every placed instance that draws it, by
  its `ref`, through components nesting it: each instance is laid out whole with its
  ancestors, and the rest of its board answers from memory.
- **Structural** — insert, delete, move. Names only the spines it touches: the parent a
  node leaves and the parent it enters, with their ancestors — plus, when the edit is
  inside a component, the placed instances that draw it, as above. Every sibling answers
  from memory and moves at most. ``EditableDocument/structurallyEditedNodeIDs`` lists the
  nodes inserted, deleted or moved and the parents they land under, for a host whose own
  pipeline must still take a full path for a change of the tree's shape.
- **Document-level** — variable, import and theme changes, plus replace, detach and
  remote edits. Full re-layout (``EditableDocument/isLayoutFullyInvalidated``).

**Source ids in, expanded ids out.** The dirty sets name nodes as the document stores
them, but layout runs on the expanded document, where an instance's nodes answer to
`<ref>/<id>` in another board. ``EditableDocument/layoutInvalidation`` gathers the dirty
tracking into one ``PenLayoutInvalidation`` value; ``PenLayoutIndex`` indexes an expanded
document — parent, index, depth and root per expanded id, and each ref's instance roots —
and ``PenLayoutIndex/expandedIDs(for:)`` translates: a node keeps its id, a `ref` names its
instance whole, a root names its expanded root whole. A host that runs its own pipeline
hands the invalidation to
``PenLayoutEngine/layoutIncremental(_:previousRects:invalidation:textMeasurer:options:measurementCache:)``,
the one call that translates, forgets the measurements of the translated ids and lays out
the roots holding them. A host that lays out every frame holds a ``PenLayoutState``
instead (below) — what ``EditableDocument/computeLayout(textMeasurer:)`` does, and the
host keeps no measurement cache of its own. `IncrementalLayoutEquivalenceTests` holds all
three to a full layout, bit for bit, over every fixture and a spread of writes, structural
ones included. ``PenLayoutInvalidation/formUnion(_:)`` merges the invalidations of runs a
newer one superseded.

```swift
// A host pipeline: take the dirty tracking with the document, lay out elsewhere.
let invalidation = editable.layoutInvalidation
editable.clearDirtyNodes()
let resolved = PenVariableResolver.resolve(editable.expandedDocument().0)
rects = PenLayoutEngine.layoutIncremental(
    resolved, previousRects: rects, invalidation: invalidation,
    measurementCache: &measurementCache
)
```

**Node-granular layout and previews.** A host that lays out every frame of a gesture
holds a ``PenLayoutState``: the expanded document, its index, every rect, and what the
walk remembers of each node's size. ``PenLayoutState/update(to:invalidation:)`` commits an
edit and lays out only the containers on the edited node's spine — each walking its
children, which answer from memory and only move — plus the descendants whose offered
space changed. ``PenLayoutState/hypothetical(_:)`` previews a ``PenLayoutEdit`` — a node
removed, moved to another index among its siblings, or given another size — on a copy,
leaving the state and the document untouched. Both return a ``PenLayoutChange`` naming
exactly the rects that differ, with what moved, what resized, and the topmost changed
subtrees a renderer produces again; both equal a full layout bit for bit, so a preview
hands off to its commit without a flash. The state measures text through its own
bounded ``TextSizeCache`` (``PenLayoutState/textSizes``), so a text it has typeset is not
typeset again, and after a font registration its next update lays out everything.

**Cards drawn raw.** An editor draws the note, prompt or context being edited raw — its
markdown as written — and the card grows to fit that text too: its height is the most of
its set height, its styled text's and its raw text's. Every layout entry point takes a
``PenLayoutOptions`` naming the cards drawn raw (``PenPostIt/DrawingOptions/layoutOptions``
gives a renderer's); ``PenLayoutState/update(to:invalidation:options:)`` lays out again
each card that starts or stops being raw, and a host with its own measurement cache
merges ``PenLayoutOptions/invalidation(from:)`` into its invalidation.
`RawCardLayoutEquivalenceTests` holds both to a full layout with the same raw cards.

```swift
var state = PenLayoutState(document: resolved)            // once, in full
let preview = state.hypothetical([.move("row7", toIndex: 2)])
draw(preview.applied(to: state.rects))                      // the document is untouched

try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "row7", newParentID: "list", index: 2)))
let invalidation = editable.layoutInvalidation
editable.clearDirtyNodes()
let change = state.update(to: PenVariableResolver.resolve(editable.expandedDocument().0),
                          invalidation: invalidation)  // equals the preview
```

**Content hashing** for tile caches: ``EditableDocument/contentHash(for:)`` combines
node properties, layout rect, and children's hashes. The editor stores this alongside
rendered tiles — if unchanged, the tile is still valid.

### Revision Tokens

``EditableDocument/revision(of:)`` returns a stable, 16-character hex content hash for
a node's subtree — 64-bit FNV-1a over the node's canonical JSON followed by each
child's own revision, in ``EditableDocument/children`` order. A container written
`"children": []` is hashed with that empty list, so it differs from one written without
the key. Editing a node changes its own revision and every ancestor's, but never an
unrelated sibling's.
``EditableDocument/documentRevision`` does the same for the whole document, folding in
the root nodes' revisions plus ``EditableDocument/version``, ``EditableDocument/themes``,
``EditableDocument/imports`` and ``EditableDocument/variables``.

Because a node's revision folds in its children's, it is a pin on the subtree the flat
store holds under that node: comparing one frame's revision answers "has anything
stored under here changed?" in a single comparison.

It folds in one thing more. A `ref` stores its component id and its overrides rather
than the component, so a hash of stored content alone would leave every instance — and
every ancestor above one — unmoved by the definition edit that redraws them all. A ref's
revision therefore mixes in ``EditableDocument/revision(of:)`` for the component it
names, for any component one of its own `descendants` overrides *repoints* a nested
ref at, and for any component an instance written in its overrides — slot content, or a
replacement node — instantiates (``EditableDocument/componentsRendered(by:)``). The token is a **rendered**-premise
pin: one comparison on a frame answers "has anything this frame draws changed?", which is
the question a caller who read that frame actually has.
``EditableDocument/revisionCoverage(of:)`` is the set that answers it.

The component graph may cycle — a component holding an instance of itself, or of one
that holds one of it — in a file that arrived that way; an edit can no longer make one
(<doc:ComponentLoops>). The members of each such group share a *group revision*: each is
hashed with references to the group's members written as markers naming them, and the
group revision folds those hashes in id order. A ref to a member folds in the group
revision with the member's id, so an edit inside any member moves every member and every
instance of one. The definition reads only the document, so a cyclic revision is
memoized like any other and is the same whichever node was asked for first.

> **Corrected 2026-10-05:** until then a component already on the fold's chain was
> skipped and nothing above the cut was memoized. That made the value depend on the
> walk, and the cost exponential: one revision on fuzz seed 12581 (2,244 nodes, 228
> nested components) took 7.4 s and its merge 481 s. Every revision of that document now
> takes 42 ms in all (debug build, load about 5, measured on the merge fuzzer's seed-12581
> document with component cycles allowed; `RevisionCycleTests` pins a document of the same
> size and shape, built directly, since edits can no longer make cycles).

Unlike ``EditableDocument/contentHash(for:)`` — which mixes in layout rects and uses
Swift's per-process-seeded `Hasher` — a revision is content-only and deterministic
across processes, so two peers computing it for the same node agree. It is
Foundation-only and derived from the file alone: no log, no history, no daemon.
Values are memoized in a `RevisionCache` and forgotten over an edit's revision
closure — its spine, and for an edit inside a component every instance that draws it
and their spines — so the cached answer and a from-scratch recompute are the same
answer. See the invalidation rule under *Component Registry and Expansion* above.

```swift
let expected = editable.revision(of: "rect1")

// ...time passes; another peer may have edited the document...

try editable.apply(
    .updateKind(EditOperation.UpdateKind(nodeID: "rect1", kind: newKind)),
    expecting: ["rect1": expected!]
)
```

``EditableDocument/apply(_:expecting:)`` and ``EditableDocument/applyLocal(_:expecting:)``
check every `expecting` entry against the current revision before applying anything: a
mismatch throws ``EditingError/revisionConflict(nodeID:expected:actual:)`` naming the node
and both revisions, and a node absent from the document throws ``EditingError/nodeNotFound(id:)``
— either way the document is left unchanged.

``BatchGuard`` is the other half of the same token, and the difference is *when*.
`expecting` is checked as the edit is applied, so a batch's own earlier lines can
falsify a later line's expectation. A guard is checked once, by
``BatchApplier/checkGuards(_:in:log:file:)``, at the door of the transaction — before any
line of it has run. Under the single-writer file lock every foreign write strictly
precedes that moment, so a guard asserts *"nothing anyone else did has moved what I read"*
and a batch never trips its own. A failed guard throws, refusing the whole transaction;
it is never a per-line status.

### Comparing Two Documents

``DocumentChanges/init(from:to:)`` lists what differs between two documents — the
two-way half of a three-way merge. Nodes are matched by id; each differing node is a
``NodeChange`` holding its ``NodeChange/State`` on both sides and the
``NodeChangeKey``s that differ: one per property path (as ``PropertyDiff`` names them),
one per node extra, one ``NodeChangeKey/type`` standing for every `kind.*` key when the
type changed, and the placement keys ``NodeChangeKey/parent``,
``NodeChangeKey/children`` and ``NodeChangeKey/declaredChildren``. Document members
are ``DocumentChangeKey``s, per variable, import alias, theme axis and root extra.

The walk is pruned by revision tokens: a node both documents hold with one
``EditableDocument/revision(of:)`` pins an identical subtree, so the walk records that
node's placement and goes no deeper. Two copies of a large document cost one visit per
root; one edit costs a visit per node on its spine and per sibling beside it. A
declared `"children": []` hashes apart from absent children, so declared-ness needs no
scan of its own: the walk reaches it like any other edit.

### Merging Documents

``DocumentMerge/merge(base:ours:theirs:)`` folds an external version of a document —
an agent's rewrite of the file on disk — into the local one, as ordinary
``EditOperation``s: what only theirs changed is taken, what only ours changed is kept,
and where both changed one key differently the local value wins and a
``MergeConflict`` reports it. The rules, the operation order and how the merge is
tested are in <doc:MergingDocuments>.

### Addressing Nodes

An agent or a CLI names a node with an *address* rather than an id it had to look up
first. ``EditableDocument/resolve(_:tags:)-(String,_)`` turns one into a
``ResolvedNodeAddress``; ``EditableDocument/namePath(of:)-(String)`` goes the other way
and is what every error message and tree row prints.

```swift
try editable.resolve("ALu8G")                  // .node(id: "ALu8G")
try editable.resolve("Dashboard/Header/Title") // .node(id: "Ttl01")
try editable.resolve("Header/Title")           // the same node — any node may start a path
try editable.resolve("@hero", tags: tags)      // a tag a batch created earlier

editable.namePath(of: "Ttl01")                 // "Dashboard/Header/Title"
```

A segment matches a node by **id** or by **name** (`common.name`); `#ALu8G` matches by
id only. Segments are consecutive parent→child steps, but the first may be any node in
the document, so a short path from mid-tree is legal. A bare single segment is tried as
an id first, then as a name — ids are unique, so an exact id match is never ambiguous.
An unnamed node is addressable only by its id.

**Into an instance.** When a segment lands on a `ref` node and segments remain, the ref
stands in for the component's root and the rest of the path resolves among the
component's children (nested refs recurse the same way). The result is
``ResolvedNodeAddress/instanceDescendant(refID:descendantKey:)``, whose key is exactly
what the format writes in `descendants` — a direct child's id, or the containing instance's id
and a slash for a child of a nested instance.

```swift
try editable.resolve("Nav/Label")       // .instanceDescendant(refID: "Nav01", descendantKey: "Lbl01")
try editable.resolve("Nav/Badge/Count") // .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01/Cnt01")
```

**Into a slot.** A child the instance *injected* into a component's slot frame is
addressed the same way, though it exists in no store — only inside the `children` the
instance wrote onto that frame. ``EditableDocument/injectedChildren(of:insideInstances:)``
is the one place that answers what an instance put in a slot, and the tree walk, the
resolver, the override guard and the name path all read it, so they cannot disagree. The
key is the injected node's own id. It is an address, not an override *key*: Pen drops
any key of the same instance that names its own slot content, bare or by path, and so
does ``PenRefExpander`` — ``PenNodePatcher/applyOverrides(to:overrides:enteringRoot:)``
never enters children an override itself wrote. So a raw
``EditOperation/OverrideDescendant`` storing such a key is refused with
``EditingError/overrideOnOwnSlotContent(refID:descendantKey:slotPath:)``, and a write
*addressed* to the node is rewritten instead: `EditableDocument.slotFillRewrite(of:)`
turns it into one override of the slot's own key carrying the whole `children` list
with that node changed — a node inside an injected `ref` is written into that ref's own
`descendants`, inside the fill. ``BatchApplier`` plans every `override` through it, so
the `override` verb, `apply` and the script host's `doc.override` agree, and the line
reports a ``WriteDivergence/Kind/slotFillRewrite`` note naming the slot. What is
recorded, replicated and undone is that override of the slot, never a key Pen drops.

```swift
try editable.resolve("Inst0/Note0")       // .instanceDescendant(refID: "Inst0", descendantKey: "Note0")
try editable.resolve("Inst0/Tag00/BTxt0") // .instanceDescendant(refID: "Inst0", descendantKey: "Tag00/BTxt0")
editable.namePath(ofDescendant: "Note0", in: "Inst0") // "Page/Filled/Body/Note"
```

**Through an alias.** A reusable component may itself be a `ref` to another component —
an "Icon Button" that is a `ref` to "Button" with a few overrides. ``PenRefExpander``
follows that chain and clones its **far end**, so an instance of the alias holds the
last component's nodes under the instance's own id, with no step for the alias. The
resolver, the override guard and the name path follow the same chain, through
``EditableDocument/componentRoot(ofInstanceChain:)``, so `Inst2/Lbl04` is an address and
`Inst2/IconC/Lbl04` is not — the key the expander would apply is the short one.

**Ids skip containers, names do not.** A `descendants` key is a chain of ids and says
nothing about the containers between a node and its component's root, so an id segment
inside an instance matches any node in the component, however deep: `Card1/Btn02` names
the nested `ref` even when the component wraps it in a group. That is the id-path
``TreeView`` prints, and ``ResolvedNodeAddress/address`` yields, so a printed address is
always one `resolve` accepts. A **name** segment stays a parent→child step — a repeated
name deeper in a component can never make a name path ambiguous — which is why
``namePath(ofDescendant:in:)`` expands each key step into every step it stands for
(`"Ttl03"` in `Card1` prints `Page/Card/Row/Title`).

**Pen accepts other spellings of some keys.** The key above is the one an address
yields, but a file may hold others, and Pen applies them (measured with the `pen` CLI;
`project/2026-09-26-slot-override-keys.md`). A key's **first** step may name any node the
component *wrote*, however deep — including content it writes into a nested instance's
slot, and into slots inside that — so `Chip` alone names a chip the component placed in
`Place`'s slot, as does `Place/Chip`. Each **later** step names a node below the
previous one written by a component the key has already entered, or a node of the
previous instance's own component, which enters it: `Card/Frame/Chip` steps through a
frame, `Place/Chip` skips an instance the chip sits in, but `Mid/Chip` cannot reach a
chip that `Mid`'s component wrote into *its* nested slot — that takes `Mid/Place/Chip`.
A node another component wrote is never a first step. When two keys name one node, Pen
applies the one written last in the file, whole; Woodcase's model does not keep key
order, so the key that sorts last wins — the order Woodcase writes keys in, so the two
agree on any file Woodcase saved. ``PenRefExpander`` and the override guard read the
same resolver, so an override the guard accepts is one the expansion draws; a bare key
on slot content is written into that content before the nested instance expands
(``PenNodePatcher/applySlotContentOverrides(to:overrides:)``), and a path naming a node
another component wrote — `Mid/Dot`, even when `Dot` is itself an instance — is handed
to the instance it starts at, which applies it as one of its own before its nested refs
expand. A key the resolver cannot place is dropped, as Pen drops it, except a bare id,
and a path through a nested `ref` the instance repoints, which the resolver cannot see
into.

**Failures teach.** More than one match throws
``EditingError/ambiguousAddress(address:candidates:)`` listing every candidate as a
``NodeAddressCandidate`` — an id-only address plus a full name path. No match throws
``EditingError/addressNotFound(address:nearMisses:)``, whose `nearMisses` are the nodes
anywhere in the document whose name equals the address's last segment — except where
the failing step was a step *into* an instance, in which case they are that instance's
own addresses for the name (`Card1/Body/Title`, not the definition's `Card/Body/Title`),
each flagged by ``NodeAddressCandidate/isInstanceDescendant``. A caller who skipped a
frame wanted the copy this instance draws, and the address that names it also
demonstrates the rule that a name path skips nothing.

**Name paths always resolve back.** A segment falls back to the id marker `#<id>` — which
the resolver accepts as that exact node — whenever the name cannot be read back: it is
missing or empty, contains a `/`, or begins with `#` or `@`. So
`"Dashboard/Header/#Unn01"` names an unnamed node, and round-tripping a name path
through `resolve` always returns the node it described.

### Settled Tree View

``TreeView`` is the read that replaces most screenshots: one ``TreeRow`` per node, in
pre-order, with the geometry the layout engine actually produced.

```swift
let rows = try TreeView.rows(of: editable, depth: 2)
print(TreeFormatter.text(rows))
// name                   type       rect           id
// Card                   frame      0,0 200×100    Card1
//   fits                 rectangle  10,10 50×50    Fit01
//   overflows ⚠ partial  rectangle  160,20 80×40   Ovr01
//   #Out01 ⚠ clipped     rectangle  260,120 20×20  Out01
```

**Settled, not authored.** Every read runs the pipeline first — materialize, expand
refs, resolve variables for the chosen `theme`, lay out — so a rect is what renders,
not what the file typed. Rects are already parent-local, so a row's `x,y w×h` is
directly comparable with its parent's `0,0 w×h`; ``TreeRow/clip`` is that comparison,
flagging a child that crosses its parent's edge (`partial`) or misses it entirely
(`full`). The pipeline is side-effect-free: it does not touch the document's layout
cache. Unlike ``EditableDocument/computeLayout(textMeasurer:)`` it keeps reusable
component definitions, so a component has a rect of its own.

**Rows are addresses.** ``TreeRow/id`` is the unique handle and ``TreeRow/address`` is
what a later command passes — a name path in the document's own tree, and the id-path
`refID/descendantKey` for a node inside an instance. Both go straight back through
``EditableDocument/resolve(_:tags:)-(String,_)``, so a read hands back the addresses a
write accepts.

**Instances are one row until asked.** A `ref` is a single row of type `"ref"`;
`expandInstances: true` walks into it. Either way the row's ``TreeRow/childCount`` is
the component's, so a collapsed instance says how much it is hiding — as does any row
cut off by `depth`. ``TreeFormatter`` renders that as `+N` after the name, a `*` before
the type for a component definition, and `#id` in the name column for an unnamed node.

**Slots are flagged too.** ``TreeRow/isSlot`` is true for a frame a component definition
marks with `slot` — the placeholder an instance's descendant overrides fill. It rides
alongside ``TreeRow/isReusable`` and ``TreeRow/isInstance`` on every row; the viewer's
outline draws a distinct badge for whichever of the three applies.

**And what an instance puts in one is walked.** A `children` override replaces a slot
frame's subtree when the instance expands, and those children live in the instance's
`descendants` map rather than in the document's tree. `expandInstances: true` gives them
rows under the slot, with the id-path ids the expansion assigns
(`"Card1/Note0"`) — a `ref` among them expands in turn. The slot's
``TreeRow/childCount`` is then what that instance holds, so a filled slot and an empty
one no longer read alike.

**Property columns on request.** `properties: ["kind.content"]` adds one column per
``NodePropertyCodec`` path, read from the settled node — so an instance descendant
reports the override, not the definition's value. A path that is not a property of a
node's kind is simply absent from that row.

**Every row carries its revision.** ``TreeRow/rev`` is
``EditableDocument/revision(of:)`` for what the row addresses, so it pins the row's
whole subtree in one comparison — see *Revision Tokens* below. Inside an expanded
instance it is the instance's own revision, because an override to that target is
stored on the ref, which is the same token `woodcase get` reports for that address.
`woodcase get`'s own `--json` is ``NodeReport``: the node plus that revision, and the
parameters it publishes when it has any.

``TreeFormatter/json(_:revision:)`` is the machine form: a ``TreeReport`` of the same
rows plus the ``EditableDocument/documentRevision`` they were read at, pretty-printed
with sorted keys. Pass a row's ``TreeRow/rev`` — or that document revision — back to
``EditableDocument/apply(_:expecting:)`` and a subtree that moved underneath fails
loudly.

### Who owns a document

``EditableDocument`` is **non-isolated and not `Sendable`**. It carries no global actor,
so it is owned by whoever creates it, on whatever actor they happen to be: a SwiftUI
editor's view model owns one on the main actor, a CLI verb owns one on its main entry
point, a script host owns one wherever it was called from. Nobody annotates anything at
a call site.

What makes that safe is the missing `Sendable` conformance rather than an annotation.
The compiler refuses to let a document — or its caches, its ``ActivityRecorder``, its
``CRDTDocument`` — cross an isolation boundary, so two domains can never hold the same
one. The guarantee the old `@MainActor` pin bought is still here; it is simply no longer
spent on pinning every caller to one actor.

What crosses a boundary is a value. ``EditableDocument/materialize()`` gives a
``PenDocument``, ``EditableDocument/applyLocal(_:)`` gives ``CRDTOperation``s for a peer,
``CRDTSnapshot`` carries a whole CRDT state, and the activity log is a stream of
``ActivityEvent``. Each is `Friendly`, and each is the thing to send when the other side
lives elsewhere. Collaboration works the same way it always did: the operations travel,
the documents do not.

``EditableDocument/onRemoteChange`` follows from that. It is a plain closure — no
`@Sendable`, no global actor — called synchronously inside `applyRemote`, in the domain
that owns the document, so it may touch that owner's state directly.

### File Transactions

``EditableDocument`` is in-memory; ``PenFileTransaction`` is how it meets a file on
disk. One call is the whole of a command's contact with a .pen file: take the lock,
parse, run the edit, write back only if something changed, release.

```swift
let outcome = try await PenFileTransaction.run(at: url) { document in
    try document.apply(.updateCommon(
        EditOperation.UpdateCommon(nodeID: "jSUCH", common: renamed)
    ))
    return document.nodes.count
}
outcome.didWrite   // false if the edit was a no-op
```

``WriteEffect/dryRun`` runs all of that and keeps none of it: same lock, same parse, same
body, same settling, and then neither the rename over the file nor the append to the log.
``PenFileTransaction/Commit/previewed`` is how the outcome says the edit would have
landed. ``LintPreview`` is its companion — snapshot the findings before the edit, compare
after, and report only what the edit introduced — and together they are what the CLI's
`--dry-run` is.

``PenFileTransaction/read(at:timeout:diagnostics:fonts:isolation:_:)`` is the same shape under a shared lock and
never writes, so any number of reads run together while a writer still excludes them.

``PenFileTransaction/run(at:identity:log:timeout:effect:fonts:isolation:_:)`` adds attribution: the body is
handed an ``ActivityRecorder`` beside the document, and operations applied through it
become one line each in the activity log once the file is committed. The recorder
submits each one to a transient ``DocumentSession`` over the body's document — the CLI's
write path is the library's one edit funnel, not a second one. See
<doc:WoodcaseActivityLog> and <doc:Session>.

Five properties matter to callers:

- **The body runs where its caller runs.** Every entry point takes
  `isolation: isolated (any Actor)? = #isolation`, so the actor is filled in at the call
  site: a CLI verb's body lands on the main actor because the CLI's entry point is
  isolated to it, and a script host or a test calling from its own actor gets that
  actor. There is no hop to the main actor inside a transaction, and no `@Sendable` on
  the body — it may capture and mutate whatever its caller owns. The document the body
  is handed is created and destroyed inside the call and cannot escape it.
- **The lock is advisory, and it is on the .pen file itself** — a `flock(2)` on the
  path, not on a sidecar. Another tool that opens the same path takes part in it;
  a tool that writes the file without asking for the lock is not stopped. Everything
  in Woodcase that opens a .pen file for editing goes through a transaction.
- **Waiting is bounded.** Acquisition polls with `LOCK_NB` and suspends between
  attempts, so it never blocks a thread and never hangs. A lock still held after the
  timeout fails with ``PenFileError/lockTimeout(url:timeout:)``.
- **An unchanged document is not written.** The materialized result is compared with
  the parsed input in the canonical encoding ``PenParser/encodeForFile(_:)`` produces.
  Equal bytes mean no write at all — the file's modification date does not move, so a
  no-op never looks like an edit to a file watcher. A body that throws also writes nothing.
- **Writes are atomic.** New contents go to a uniquely named temporary file in the
  same directory, take the original's permissions, and are then renamed over it.
  A reader sees either the whole old file or the whole new one, and a failure leaves
  the original intact with no temporary file behind.

Every failure is typed and names the file. ``PenFileError`` covers the file itself:
``PenFileError/cannotOpen(url:reason:)`` (missing or unopenable),
``PenFileError/lockTimeout(url:timeout:)`` (someone else has it), and
``PenFileError/writeFailed(url:reason:)`` (edited but not saved). Contents that are not
a readable .pen document raise the parser's own ``PenParserError``, with the file
attached — it already carries the key path and the type the decoder wanted, and
re-wrapping it as ``PenFileError/unreadable(url:reason:)`` would flatten that into a
string. That is why a transaction and a bare ``PenParser/parse(contentsOf:diagnostics:)``
fail with the same sentence.

### Error Handling

Operations validate their preconditions and throw ``EditingError`` on failure. Errors
are specific and carry the relevant IDs, making it straightforward to present diagnostics.

Each guard is written once and shared. Every operation checks itself before it writes
anything, so a refused operation leaves the document exactly as it was, and
``EditableDocument/applyLocal(_:)`` runs the whole check up front — before the CRDT
layer records anything — so a refused edit in collaborative mode is not replicated
either. The two modes refuse the same operations with the same error.

### Guards

Three operations can do damage past the node they name. Each refuses and explains,
carrying everything a message needs to offer the remedy.

**Deleting a component with instances.** Deleting a reusable node strands every `ref`
that points at it — the instances stop expanding and quietly go empty. The delete
refuses with ``EditingError/componentHasInstances(componentID:instanceIDs:)``, naming
every instance that would be stranded. Instances *inside* the deleted subtree go away
with it and do not count. To go ahead, set
``EditOperation/DeleteNode/instances`` to ``EditOperation/DeleteNode/Instances/detach``:
each stranded instance is detached into independent nodes first, then the component is
deleted.

```swift
// Refused, naming the instances:
try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Btn01")))

// Detach them first, then delete:
try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Btn01", instances: .detach)))
```

A component that renders itself — directly, or through another component the delete also
removes — expands with the inner instance that closes the loop left as a `ref`, because
the expansion ignores a loop's nesting (<doc:ComponentLoops>). Once the component is gone that ref would name
nothing, so the detach leaves out every instance of a component the delete removes: no ref survives that names a deleted
component, and the delete's inverse, built from the same plans, puts everything back.

Use ``EditableDocument/deleteNode(_:)`` instead of ``EditableDocument/apply(_:)`` when
you need the ``DetachResult`` of each detach. An undo stack no longer does:
``EditableDocument/prepareInverse(of:)`` names the expanded roots before the delete runs,
and the old completion step,
``EditableDocument/completeDetachingDeleteInverse(detached:partialInverse:)``, is a
deprecated pass-through.

**An override that matches nothing.** An ``EditOperation/OverrideDescendant`` whose
`descendantID` names no node in the referenced component throws
``EditingError/overrideTargetNotFound(refID:descendantKey:candidates:)``, listing every
node the component *does* contain as a ``NodeAddressCandidate`` — an id-path that writes
(`"Nav01/Bdg01"`) and the full name path that reads (`"Dashboard/Nav/Badge"`). Nested
keys (`"Bdg01/Cnt01"`, a node inside a ref inside the component) are checked and listed
the same way. A ref whose component is not in the registry — an unresolved import — is
left alone, since there is nothing to check the key against.

**An override the node cannot take.** The other half of the same guard: an override is
merged onto the component's node as raw JSON when the instance expands, and
``PenNodePatcher/patchNode(_:with:)``'s answer to a merge that will not decode is the
*unpatched* node — the override stays in the map, reads back, and never draws. A value
of the wrong shape therefore throws
``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``, naming
the key and the shape the property takes. Two entries are exempt: an override carrying a
`type` key replaces the node whole rather than patching it, and an unresolved component
has nothing to judge against. Expansion itself stays tolerant, because Woodcase renders
files it did not write.

The candidate list holds only the keys an **address** can reach and Pen applies.
``EditableDocument/overridableDescendantKeys(ofInstance:)`` includes the component root,
because Pen's patcher matches it like any other node, but no address resolves to it —
stepping into an instance lands on the component's *children*, so that one node never
has two addresses storing an edit in two places. The root's own properties are the
instance's root overrides, written by addressing the instance itself. Content the
instance wrote into a slot itself (`EditableDocument.ownSlotContentKeys(ofInstance:)`)
is an address but never a candidate key: a write addressed to it is rewritten into the
slot fill.

**A root override the ref cannot carry.** ``EditOperation/OverrideRoot`` writes the
component root's properties as one instance shows them, and the format writes those as
the ref node's own non-reserved top-level keys. A reserved key — `opacity`, `ref`,
`descendants`, `id` — would come back meaning the instance rather than the root, so it
throws ``EditingError/rootOverrideKeyReserved(refID:key:reason:)`` carrying a
``RootOverrideRefusal`` that says which command writes it instead. Values are judged
against the component root exactly as a descendant's are, throwing
``EditingError/rootOverrideValueRejected(refID:key:expected:actual:)``.

**Moving a node into its own subtree.** ``EditOperation/moveNode(_:)`` onto itself or
under one of its own descendants throws
``EditingError/wouldCreateCycle(nodeID:targetParentID:)``.

**Closing a component loop.** An insert, move, replace, property patch, retype, root or
descendant override that would make components contain each other — an instance of a
component placed inside it, directly or through others, or a frame made reusable while it
holds an instance of a component that names it — throws
``EditingError/wouldCloseComponentLoop(path:)``, naming the loop as component ids in
render order: `["Card", "Badge", "Card"]`. Only a loop the document does not already hold
counts, so a file that arrived with one still takes its fix. See <doc:ComponentLoops>.

## Topics

### Core Types

- ``EditableDocument``
- ``EditOperation``
- ``EditingError``
- ``NodePropertyCodec``
- ``DocumentPropertyCodec``
- ``PenPropertyShape``
- ``PenValueForm``
- ``PenNestedShape``
- ``PenSchema``
- ``PenSchemaTable``

### Addressing

- ``NodeAddress``
- ``ResolvedNodeAddress``
- ``NodeAddressCandidate``

### Reading the Tree

- ``TreeView``
- ``TreeRow``
- ``TreeFormatter``
- ``TreeReport``
- ``NodeReport``

### File Transactions

- ``PenFileTransaction``
- ``PenFileError``
- ``WriteEffect``
- ``LintPreview``
- <doc:WoodcaseActivityLog>

### Comparing Documents

- <doc:MergingDocuments>
- ``DocumentMerge``
- ``MergeResult``
- ``MergeConflict``
- ``DocumentChanges``
- ``NodeChange``
- ``NodeChangeKey``
- ``DocumentChangeKey``

### Incremental Layout

- ``LayoutCache``
- ``ChangeCategory``
- ``PenLayoutInvalidation``
- ``PenLayoutIndex``
- ``PenLayoutState``
- ``PenLayoutChange``
- ``PenLayoutEdit``
- ``PenLayoutStats``
- ``PenLayoutOptions``
- ``TextSizeCache``

### Component Editing

- ``ComponentProvenance``
- ``ExpandedRef``
- ``ExpansionContext``
- ``ExpansionCache``
- ``ComponentSurface``
- ``ComponentSlotInfo``
- ``OverridableNode``
- ``RootOverrideRefusal``
- ``DetachResult``
- ``PenID``

### Collaborative Editing

For real-time collaboration, initialize an ``EditableDocument`` with a ``PeerID``
to enable the CRDT layer. Use ``EditableDocument/applyLocal(_:)`` instead of
``EditableDocument/apply(_:)`` to produce replicable operations, and
`applyRemote(_:)` to merge operations from other peers.

For late-joining peers, use ``EditableDocument/init(from:snapshot:peerID:)``
with a ``CRDTSnapshot`` from an existing peer. Offline operations can be
merged via ``EditableDocument/replayOfflineOperations(_:)``.

Coordinate save-point truncation with ``EditableDocument/checkpoint()``
and ``EditableDocument/truncateLog(acknowledgedBy:)``.

See <doc:CRDTArchitecture> for details on the convergence guarantees.

- ``CRDTDocument``
- ``CRDTOperation``
- ``CRDTSnapshot``
