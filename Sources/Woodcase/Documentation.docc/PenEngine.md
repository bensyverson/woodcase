# The PenEngine Pipeline

An overview of how Woodcase processes .pen documents from raw JSON to rendered pixels.

## Overview

The PenEngine pipeline transforms a `.pen` JSON file into rendered images through six stages. Each stage is a pure function — no shared state, no side effects — implemented as a static method on a `nonisolated enum`.

```
.pen JSON ──→ PenParser ──→ PenImportResolver ──→ PenRefExpander ──→ PenVariableResolver ──→ PenLayoutEngine ──→ PenRenderer ──→ CGImage
                 │                  │                    │                    │                   │                │
            PenDocument        PenDocument          PenDocument          PenDocument        Layout rects     Rendered image
          (raw imports)     (imports resolved)    (refs expanded)    (variables resolved)   keyed by node ID
```

## Stage 1: Parsing

``PenParser`` decodes `.pen` JSON into a strongly-typed ``PenDocument``.

```swift
let document = try PenParser.parse(contentsOf: penFileURL)
// or from Data / String:
let document = try PenParser.parse(jsonData)
let document = try PenParser.parse(jsonString)
// with a collector for version warnings and discarded legacy data:
let document = try PenParser.parse(jsonData, diagnostics: diagnostics)
```

**Key behaviors:**
- The document round-trips cleanly: `parse → encode → parse` produces an identical value.
- Unknown node types decode as `.unknown(typeName:properties:)`, preserving their properties as `[String: AnyCodable]` for forward compatibility.
- Unknown keys on known node types, on the document root, on fills, stroke paints and effects, and on the objects nested inside them are kept verbatim as ``PenExtras`` and written back; unknown fill and effect `type`s decode as `.unknown(typeName:payload:)`. See <doc:PenEngine#Forward-Compatibility>.
- Encoding uses sorted keys for deterministic output.

The document model supports 16 node types via ``PenNode/Kind``:

| Node type | Data struct | Description |
|-----------|------------|-------------|
| `frame` | ``PenNode/FrameData`` | Flex container with layout, sizing, padding, gap |
| `text` | ``PenNode/TextData`` | A string or `$variable`, with node-level style properties |
| `rectangle` | ``PenNode/RectangleData`` | Rectangle with corner radius, fills, strokes |
| `ellipse` | ``PenNode/EllipseData`` | Ellipse with fills, strokes, effects |
| `path` | ``PenNode/PathData`` | SVG path data |
| `group` | ``PenNode/GroupData`` | Transparent container: children only, no layout of its own |
| `line` | ``PenNode/LineData`` | Line between two points |
| `polygon` | ``PenNode/PolygonData`` | Regular polygon with N sides |
| `ref` | ``PenNode/RefData`` | Reference to a reusable component |
| `note` | ``PenNode/NoteData`` | Annotation note |
| `prompt` | ``PenNode/PromptData`` | AI prompt node |
| `context` | ``PenNode/ContextData`` | Context boundary for theming |
| `icon` | ``PenNode/IconData`` | Icon font glyph |
| `script` | ``PenNode/ScriptData`` | Sized placeholder for a user-authored script; never executed — see <doc:PenRendering> |
| `browser` | ``PenNode/BrowserData`` | An embedded web page (Pen 2.19): laid out like a rectangle, drawn as a placeholder, never loaded — see <doc:PenRendering> |
| `connection` | ``PenNode/ConnectionData`` | A connector from an anchor on one node to an anchor on another; top level only, drawn as a stroked segment — see <doc:PenRendering> |

### The document's fonts

A document may declare the font files it ships in a root `fonts` array, one
``PenFontDeclaration`` each: a family ``PenFontDeclaration/name``, a
``PenFontDeclaration/url``, and optionally the ``PenFontDeclaration/style``
(`normal` or `italic`) and ``PenFontDeclaration/weight`` — one number, or `[min, max]`
for a variable font — the file covers. ``PenDocument/fonts`` and
``EditableDocument/fonts`` carry them through every edit, and the document revision
covers them. ``PenFontDeclaration/resolvedURL(relativeTo:)`` turns a url into a file
URL, resolving a relative path against the .pen file's directory as an image fill's
path is resolved, and ``PenFontDeclaration/weightRange`` gives the weights a file
covers, 400 when it names none.

The keys are exactly those Pen's own validator accepts; it refuses any other key on a
declaration. Pen itself drops a declaration with no name or no url when it opens a
file, and writes a `[min, max]` weight back as its first number only — Woodcase keeps
the range as written. The declared files are registered ahead of Google Fonts on every
read and render — see <doc:PenGoogleFonts>, *Declared fonts*.

### The connection node

A `connection` (``PenNode/ConnectionData``) joins an anchor on one node to an anchor on
another: ``PenNode/ConnectionData/source`` and ``PenNode/ConnectionData/target`` each
name a node by id — or by an `instance/child` path into a component instance — and an
``PenNode/ConnectionData/Anchor``: `center`, or the middle of the `top`, `left`,
`bottom` or `right` edge. It takes the five stroke keys and the properties every node
has, and nothing else: no fill, no size, no effects. Pen's validator accepts a
connection only at the top level of a document. A connection has no box of its own —
it is drawn from where its endpoints are (``PenNode/ConnectionData/segment(in:)``) — so
the layout engine gives it no size and moves nothing for it.

### The version gate

The `.pen` format has had one breaking change, 2.10 → 2.17, and one change of meaning,
2.17 → 2.19. Woodcase models 2.19 and keeps **one**
in-memory model — the current one — so `PenParser` decodes the raw JSON tree first,
parses the `version` field as a numeric ``PenFormatVersion`` (`"2.9"` sorts *below*
`"2.17"` numerically but above it lexically, so the string comparison is not an
option), and dispatches:

| Declared version | Handling | Written back as |
|------------------|----------|-----------------|
| 2.8 – 2.10 | ``PenLegacyMigrator`` rewrites the JSON tree, then the current decoder runs | the model's version |
| below 2.8 | migrated as legacy, with a warning | the model's version |
| 2.11 – 2.18 | ``PenLegacyMigrator/modernRules`` rewrite the tree (the 2.19 shadow change below), then the current decoder; a warning unless it is 2.17, the only one of these Pen has been seen to write | the model's version |
| 2.19 | current decoder | 2.19 |
| newer 2.x | current decoder, with one **notice** | **the declared version, unchanged** |
| another major | the structural probe below; read-only, with a warning | never — writes are refused |
| unparsable | throws ``PenParserError/unsupportedVersion(url:version:)`` | — |
| absent | migrated as legacy, with a warning | the model's version |

Each row follows from one fact, ``PenFormatVersion/Relation``: where the declared
version stands against the one Woodcase models (``PenDocument/formatRelation``).

**An older file is upgraded; a newer one is never downgraded.** A document older than
the model reports ``PenDocument/currentFormatVersion`` once parsed, and the first
write stamps it — its tree *is* a current tree by then. A document from a newer Pen of
the same major keeps its declared ``PenDocument/version`` through every edit, and
``PenParser/encode(_:)`` writes it back unchanged. Stamping the older model's version
over it would be a lie with consequences: a newer Pen migrates what it believes is an
older file, and Pen 1.2.14 turns every pre-2.19 inner shadow into an outer one on load.
The newer minor still decodes with the current model, so what that model does not
represent is not preserved yet. The notice is ``PenDiagnostic/Severity/notice``, which
ranks below a warning: `woodcase lint` shows it only with `--severity notice` and never
exits 1 for it, and `render --strict` does not fail on it — a newer Pen is not a
problem with the design.

**Another major is read-only.** It is not refused on its number alone — a 3.0 that kept
2.x's shape reads perfectly well. The structural probe reads it when the root has a
`children` array, every node at every depth is an object with a string `id` and `type`,
at least one node is of a type this build models, and the whole document decodes with
the current decoder. Then every read works, with a warning at
``PenDiagnostic/Stage/migration``, and every write is refused:
``PenFileTransaction`` throws ``PenFormatWriteRefusal`` before running a write body
(a dry run included), and ``PenFileMigrator`` throws it rather than rewrite the bytes.
A document that fails the probe throws ``PenParserError/differentMajor(url:version:reason:)``,
whose reason names the first key path that did not read. An editor that saves an
``EditableDocument`` itself asks ``PenDocument/requireWritableFormat(at:)`` first.

Nothing downstream — layout, rendering, code generation, editing — ever sees a
legacy shape.

### Shadows before 2.19

Format 2.19 changed two things about shadows, and ``PenShadowMigrationRule`` brings
every older document across, in `children` and in `ref` `descendants` override bags
alike, the way Pen 1.2.14 does when it opens one:

- **An inner shadow becomes an outer shadow.** `shadowType: "inner"` has been in the
  format since 2.10, but every Pen before 1.2.14 drew it outside the shape; 1.2.14 is
  the first to draw it inside, and converts an older file's inner shadows to outer on
  open so that the file keeps looking the way it always did in Pen. So does Woodcase:
  an inner shadow in a 2.17 file is read, drawn and written as an outer one.
- **`spread` is deleted.** 2.19 has no such key, Pen refuses a new shadow that carries
  one, and no Pen ever drew it. ``PenEffect/PenShadowEffect`` no longer models it.

Pen does both silently; Woodcase reports each as a warning at
``PenDiagnostic/Stage/migration`` naming the node. A 2.19 file's inner shadow is an
inner shadow, and its `spread` — which only a hand edit could put there — is kept as an
extra like any other key the model does not claim.

The optional `diagnostics` parameter collects those notices and warnings, plus one entry for
every property a migration discards, at ``PenDiagnostic/Stage/migration``.

A document also carries an optional top-level ``PenDocument/fileToken`` — a
per-save UUID the format's own editor stamps on every file it writes. It is outside the published
schema and carries no meaning for Woodcase: a parsed document round-trips
whatever token was on disk, and Woodcase never generates one of its own.

### Extending the migrator

Each format change is one ``PenMigrationRule``: a small `Sendable`
type with two optional hooks, one for the document root and one for a single
node's property dictionary. ``PenLegacyMigrator`` owns the traversal and calls the
node hook for every node in the document — top-level, nested under `children`, and
the property patches inside a `ref` node's `descendants` map — so a rule never
walks the tree itself.

```swift
struct IconRenameRule: PenMigrationRule {
    func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
        guard node["type"] == .string("icon_font") else { return }
        node["type"] = .string("icon")
        node["library"] = node.removeValue(forKey: "iconFontFamily")
        node["icon"] = node.removeValue(forKey: "iconFontName")
    }
}
```

``PenIconMigrationRule`` ships exactly this rule: `icon_font` → `icon`, with
`iconFontFamily`/`iconFontName` → `library`/`icon`. `weight` and `fill` carry over
unchanged. Register a new rule by appending it to ``PenLegacyMigrator/rules`` —
that array is the whole registration point, and rules run in its order. A rule
that drops something the current model cannot express must report it through the
diagnostic collector, naming the node it came from.

### Strokes

A stroke is five sibling keys on the node, not a nested object. Every payload that
can carry one conforms to ``PenStrokable``:

| Key | Type | Absent means |
|-----|------|--------------|
| `stroke` | ``PenFills`` — the same shapes `fill` accepts, `"#RRGGBB"` shorthand included | no stroke at all |
| `strokeWidth` | ``PenStrokeWidth`` — a number, a `"$variable"`, or `{"top":…,"right":…,"bottom":…,"left":…}` | a width of 1 |
| `strokeAlignment` | ``PenStrokeAlign`` — `inner`, `center`, `outer` | `center` |
| `strokeLinejoin` | ``PenStrokeJoin`` — `miter`, `bevel`, `round` | `miter` |
| `strokeLinecap` | ``PenStrokeCap`` — `butt`, `round`, `square` | `butt` |

``PenStrokeMigrationRule`` flattens the 2.10 nested object into these:
`fill` → `stroke`, `thickness` → `strokeWidth`, `join` → `strokeLinejoin`,
`cap` → `strokeLinecap` (with the retired `none` becoming `butt`), and
`align` → `strokeAlignment` with `inside`/`outside` renamed to `inner`/`outer`.
Two behaviours copy version 1.2.7 of the format's own editor, whose own re-saves
are the oracle for the migration: a value equal to the default is written as
nothing at all, and a stroke
object with no `fill` is dropped entirely — it had no paint, so it drew nothing.
`dashPattern` and `miterAngle` left the format with no replacement and are
discarded with a diagnostic.

### Rich text

Up to 2.10 a text node's `content` could be an array of styled runs. 2.17 removed
them: `content` is a string or a `$variable`, and the model has no type for a run.
``PenRichTextMigrationRule`` concatenates the runs' text into one string, in order
and with no separator, and warns that the per-run styling was discarded.

Version 1.2.7 of the format's own editor drops the property outright on save,
losing the words along with the styling. Keeping the text is a deliberate
departure — the words are the part a
reader would miss.

### Groups

Up to 2.10 a `group` (``PenNode/GroupData``) could carry its own `layout`, `gap`,
`padding`, `justifyContent`, `alignItems`, `width` and `height` — a flex container
like `frame`. 2.17 makes a group a pure container: children, effects and blend
mode only. ``PenGroupMigrationRule`` removes the retired keys from every legacy
`group` node; a value that already matched the property's old default (`layout:
"none"`, a zero gap or padding, `justifyContent`/`alignItems: "start"`, a
`fit_content` width or height) is dropped silently, since nothing observable
changes, while a real layout choice, nonzero gap or padding, or explicit size is
reported through the diagnostic collector. Downstream, every group behaves as if
`layout: "none"` — see the layout engine's *Groups are always absolute
containers* note below.

## Stage 2: Import Resolution

``PenImportResolver`` resolves cross-file imports by merging library components, variables, and themes into the host document with alias-prefixed identifiers.

```swift
let resolved = PenImportResolver.resolve(document, libraries: ["kit.lib.pen": libDoc])
// or with a resolver closure:
let resolved = try PenImportResolver.resolve(document) { path in
    try PenParser.parse(contentsOf: urlForPath(path))
}
```

**Key behaviors:**
- **Alias prefixing:** Each import alias becomes a namespace prefix. Components become `V:componentId`, variables become `V:varName`, and theme axes become `V:axisName`.
- **Reusable extraction:** Only nodes with `reusable: true` are extracted from the library. ``PenImportResolver/resolve(_:libraries:)`` merges them into the host document's children (what `generate` wants); ``PenImportResolver/definitions(for:libraries:)`` keeps them apart as ``PenImportedDefinitions``, for the expander's registry — what every canvas read uses through ``EditableDocument/expanded(for:)``, since Pen never draws an imported definition on the importing canvas.
- **Variable and theme merging:** Library variables and theme axes are merged with alias prefixes. Host values take precedence on conflict.
- **Reference rewriting:** All `ref` targets, descendant override keys and values, `$`-prefixed variable references, and theme conditions within library nodes are prefixed with the alias. This includes identifiers nested inside descendant override values such as children arrays and nested descendants. See <doc:PenImportNamespaces> for details.
- **One level, as in Pen:** a library's own `imports` are not followed, so there is no cycle to detect. (Before 2026-09-26 this resolved them recursively; Pen does not, so neither does Woodcase.)
- **Where libraries come from:** the document's own `imports`, relative to its file, loaded once by ``PenFileTransaction`` into ``EditableDocument/readContext`` — there is no `--library` flag. See <doc:PenImportNamespaces>.

## Stage 3: Ref Expansion

``PenRefExpander`` expands component instances (`.ref` nodes) into concrete node subtrees, and, depending on ``PenRefExpander/Purpose``, strips reusable component definitions from the output.

```swift
let expanded = PenRefExpander.expand(document)             // .export: definitions stripped
let canvas = PenRefExpander.expand(document, for: .canvas) // definitions kept, as artboards
```

**Key behaviors:**
- **Cloning:** Each ref is replaced by a deep clone of the target component (the node with `reusable: true` whose `id` matches the ref's `ref` field).
- **Descendant overrides:** Property patches from ``PenNode/RefData/descendants`` are applied to matching nodes within the clone via JSON round-trip (encode → merge → decode).
- **Object replacement:** If a descendant override contains a `type` property, the entire node is replaced with a new node built from the override.
- **ID prefixing:** Expanded node IDs are prefixed with the ref node's ID using `/` as separator (e.g., `refId/childId`) to avoid collisions when the same component is instanced multiple times.
- **Positional transfer:** The ref node's positional properties (x, y, rotation, opacity, etc.) are transferred to the cloned component's root node.
- **Nested refs:** Refs within components are expanded as the walk reaches them, with circular ref protection via a visited set. An override naming a node another component wrote is handed down to the nested instance its path starts at, and applies before that instance's own nested refs expand — so a path naming a nested *instance* (`Mid/Dot`) patches its `ref` node, as Pen does.
- **Own slot content:** A key naming content the instance wrote into a slot itself is dropped, as Pen drops it: the patcher never enters children an override wrote.
- **Stack depth:** Every walk — expanding, patching, prefixing, stripping, placing override keys — is `PenTreeRewrite`'s or an explicit work list, never recursion, and ``PenNode/Kind`` is `indirect`, so the expansion's stack use does not grow with the tree: a debug build expands sixteen nested instances, 108 levels deep, in about 100 KB of a Swift task's 512 KiB (`PenRefExpanderStackTests`). The same holds for the rest of the settled-tree read — decoding, flattening, materializing, variable resolution, font collection, layout, revisions and the tree listing (`TreePipelineStackTests`). Freeing a tree still recurses, about 770 bytes a level in debug, and Foundation's JSON scanner about 600; JSON nesting caps a parsed frame tree at 255 levels. The measurements are in `project/2026-09-26-debug-stack-depth.md`.

## Stage 4: Variable Resolution

``PenVariableResolver`` walks the document tree and replaces every ``PenValue/variable(_:)`` with its resolved ``PenValue/literal(_:)`` value. Text content forgives a `$name` the document defines nowhere — `"$186"` is a price, not a dangling reference — and the resolver applies that rule to a `ref`'s own `descendants` and `rootOverrides` too, so a `content` override reads the same whether it meets the resolver before ref expansion or after it. Resolution still runs *after* expansion in every pipeline, because that is the order the rest of the stages need; it is no longer the only order that reads a dollar literal correctly.

```swift
// Resolve with inherited per-node theming (default: first option per axis)
let resolved = PenVariableResolver.resolve(expanded)

// Pin a root-level theme (children with their own common.theme still override)
let resolved = PenVariableResolver.resolve(
    expanded,
    theme: ["mode": "dark"],
    overrides: ["speaker": .string("Jane Doe")]
)
```

**Key behaviors:**
- **Inherited per-node theming:** Themes cascade like CSS. The default theme (first option per axis from `document.themes`) applies at the root. Any node with `common.theme` overrides those axes for itself and its descendants. Children without their own theme inherit from their parent. A single `resolve()` call handles the entire document — no need for per-root or per-combination resolution loops.
- **Theme matching:** When a variable has themed values, the resolver picks the best match for the effective theme at each node. Specific matches (non-nil `theme` dictionary) take priority over defaults (`theme: nil`). Among specific matches, last-match-wins.
- **Variable table caching:** Since the table only depends on the effective theme combination (not the node), tables are cached keyed by `[String: String]`. With typical documents having 2-4 theme combinations, this means 2-4 cached tables reused across hundreds of nodes.
- **Variable chains:** A variable's value can reference another variable (`$other`). Chains are followed up to 10 levels deep, with cycle detection.
- **External overrides:** The `overrides` parameter provides runtime values that take precedence over document-defined variables.
- **Type coercion:** `AnyCodable.int` values are coerced to `Double` when resolving `PenValue<Double>`.
- **Stripping:** For ``PenRefExpander/Purpose/export``, expansion removes every node with `reusable: true` from the document afterward — they've served their purpose as templates. For ``PenRefExpander/Purpose/canvas``, they stay, because a definition is a root the canvas draws like any other.

## Stage 5: Layout

``PenLayoutEngine`` computes the position and size of every node, returning a flat dictionary of ``PenRect`` values keyed by node ID.

```swift
let rects = PenLayoutEngine.layout(expanded)
// rects["nodeId"] == PenRect(x: 24, y: 16, width: 352, height: 268)
```

**Key behaviors:**

- **Three layout paths:**
  - *Leaf nodes* — use their explicit width/height sizing.
  - *Absolute containers* (`layout: "none"`, and every `group`) — children placed at explicit x/y. A frame's `fit_content` size is its fallback, 0 by default, never its children's extent; a group's size is its children's true union (below); `fill_container` uses its fallback value.
  - *Flex containers* (horizontal/vertical) — full flex layout with gap, padding, justify, and align.

- **Sizing modes:**

| Mode | Behavior |
|------|----------|
| `fixed(n)` | Exactly `n` points |
| `fit_content(fallback)` | Size to children; use fallback if no children. On a `layout: "none"` frame, always the fallback (0 by default) |
| `fill_container(fallback)` | Fill remaining space in parent, at least 1 pt on the main axis (Pen's floor when siblings and gaps leave less, overflowing or not: `flex-fill-squeeze.pen`); use fallback in non-flex context |

- **Flex layout properties:**
  - `justifyContent` — main-axis distribution: `start`, `center`, `end`, `spaceBetween`, `spaceAround`
  - `alignItems` — cross-axis alignment: `start`, `center`, `end`
  - `gap` — spacing between children (additive with justify spacing)
  - `padding` — uniform, symmetric (`[vertical, horizontal]` — CSS convention), or per-edge

- **Defaults:** Layout defaults to `horizontal`, justifyContent to `start`, alignItems to `start`, gap to `0`, sizing to `fitContent`. These match the format's own editor.

- **Absolute positioning:** Children with `layoutPosition: .absolute` are excluded from flex flow but still laid out within the parent's content area using their explicit x/y.

- **A turned child takes the bounds of its turned box.** A flex container allocates, aligns and fits each flow child's *bounds*: its box turned (and flipped, which changes nothing here). A `fill_container` child fills its **unturned** box first and then turns: the main-axis share becomes its unturned width (in a row; height in a column), the container's inner cross size its unturned height (width), and the room it takes is the bounds of the result. So a turned fill child can take more than its share — in a 300-wide row of padding 10 and gap 10 beside two 60×40 siblings, a 40-tall child with `width: fill_container` turned 30° fills a 140×40 box and takes 141.24×104.64, pushing its later sibling 1.24 pt past the share and the row's `fit_content` height to 124.64 — and a turned cross-axis fill can take a different amount of the main axis than it measured: 60 wide, `height: fill_container` and turned 90° in a row of height 120, it fills a 60×100 box and takes 100×60. A cross-axis fill adds nothing to its container's cross fit; in a `fit_content` cross axis it fills what its siblings set. Its rect carries the unturned box (``PenRect/unturnedSize``). `flex-turned-fill.pen` covers both axes in rows and columns, pinned by `PenLayoutTurnedFillTests` against Pen's settled layout (`scripts/pen-settle`); where Pen's first layout after load differs, Woodcase keeps the settled one (<doc:PenInteroperability>, *Kept Divergences*). One case is not settled: when a main-axis fill sibling, not the measured children, sets a `fit_content` cross size, a turned cross-axis fill's main extent is taken after the shares are, which are not divided again.

- **Groups are always absolute containers:** unlike a frame, a `group` (``PenNode/GroupData``) has no `layout`, `gap`, `padding`, `justifyContent`, `alignItems`, `width` or `height` of its own — every group behaves as if `layout: "none"`, and its children are always positioned at their own explicit x/y. Having no declared size, a group is always `fit_content`, so its rect is always its children's union — the true union, which need not contain its anchor (below).

### Absolute containers and `fit_content`

A container that places its children absolutely — a `frame` with `layout: "none"`,
and every `group` — has no flow for `fit_content` to measure, and the two resolve it
differently. A **frame** settles a `fit_content` width or height at its **fallback**,
0 when it has none, whatever its children reach; a missing width or height is
`fit_content` with no fallback, so a sizeless absolute frame settles at 0×0, and Pen
re-saves it as `fit_content(0)`. A **group** has no size to declare and takes its
children's true union, which need not contain its anchor (below):

```
frame:  width  = fallback ?? 0        height = fallback ?? 0        (fit_content only)
group:  box = union over enabled children of childRect   (origin and size; empty → 0×0 at the anchor)
```

`childRect` is the child's resolved layout rect *after its own layout* — its
measured or fixed size, expanded to the rotated bounding box when the child is
rotated and moved to where turning about its anchor puts it (below), exactly the
rect the engine writes for that child.

> **Correction, 2026-09-27 (leaf `Jg0BOv`):** this section used to say that a
> `layout: "none"` frame resolves `fit_content` to the union of its children measured
> from its own origin (right and bottom edges; negative offsets overhang). That rule
> was inferred, never measured, and Pen contradicts it: the Pen-oracle probe on leaf
> `Jg0BOv` — now `render-sizeless-frames.pen`, pinned by `PenSizelessFrameTests` —
> settles every sizeless absolute frame at 0×0, an explicit `fit_content` at 0×0 and
> `fit_content(30)` at 30, whatever its children reach. What Pen draws follows: the
> children still draw at their own `x`/`y`, overhanging the point (no clip by
> default); with `clip: true` none of them draws; the frame's fill has no area, but an
> outer stroke and an outer shadow still paint around the point; and in a flex parent
> the frame takes no room, so the next sibling lands on its children and a
> `fit_content` parent fits only its padding. The union rule drew the fill across the
> children, clipped them to it, and grew flex slots by it. `collapsed-absolute-frame`
> (<doc:WoodcaseLint>) warns on such a frame with children. Groups keep a union — the
> true one (leaf `cqBw2i`).

The details worth stating, because they are all askable questions:

- **A frame's children overhang it.** A child of an absolute frame sits at its own
  `x`/`y` from the frame's origin whatever the frame's size, and is drawn there
  unless the frame sets `clip`.
- **A rotated child contributes its rotated bounding box** to a group's union, not
  its declared box, because that expanded box *is* the child's layout rect — the
  same size a flex parent counts for it — at the place the anchor turn below gives it.
- **A node placed by its own `x`/`y` turns and flips about that anchor.** Pen
  turns (and, first, flips) a root, a child of a `layout: "none"` frame or of a
  group, and an absolutely positioned child of a flex frame about its top-left
  corner, and its settled layout reports the bounds of the result
  (``PenLayoutEngine/freeRect(of:x:y:width:height:)``). So the layout rect can start
  left of or above the anchor: `render-rotated-free.pen`'s 200×60 rectangle at
  `(80, 60)`, turned −20°, settles at `(59.479, 60)`, 208.46×124.79 — 60 × sin 20°
  left of its anchor — and a `flipX` node settles its whole width left of it
  (`render-transformed-free.pen`; both are Pen-oracle fixtures, and
  `PenTransformedFreeTests` holds every rect within 0.5 pt of Pen's). The renderer
  draws the unturned box centred in that rect and pivots at its centre, which is
  the same picture. A child in a **flex flow** is different: Pen grows its slot to
  the turned bounds and the child sits in it, so its rect is the rotated bounding
  box at the flow's cursor. Either way the bounds do not say what size the node is
  drawn at, so a turned node's rect carries the size the layout gave it before it
  turned it (``PenRect/unturnedSize``); every reader — the renderers,
  ``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)``,
  ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` — reads it there, and
  incremental and subtree layouts, which copy rects, carry it with them.
  ``PenLayoutEngine/canvasPlacement(of:in:layoutRects:)`` is the whole placement
  (its map alone is ``PenLayoutEngine/canvasTransform(of:in:layoutRects:)``; see
  *Three extents* below), composed from the root down: the affine map from a node's own
  coordinates to the canvas, with the box it carries, for a caller that needs a turned node's quad, a hit test in its space, or
  a canvas drag delta in its parent's (the inverse of the parent's map).

  > **Correction, 2026-09-27 (leaf `nAuBKh`):** this section used to say that "for
  > a sized node the layout rect is the rotated bounding box anchored at the
  > declared `x`/`y`", and that a flipped child contributes its declared box. Both
  > were wrong for a node placed by its own coordinates: the box's corner was pinned
  > at the anchor while the render turned it about the box's centre, so turned free
  > nodes drew up to 20 pt from where Pen draws them (CG MAE 2.6–7.3 on
  > `render-rotated-free` and `render-text-fills`' `txt-rotated`, now 0.02–0.14).
  > The rule was inferred from `render-transforms-and-effects`, whose turned node is a
  > flex child. See `project/2026-09-27-fidelity-gaps.md`, F4.
- **A group's rect is its children's true union, and its anchor is not its corner.**
  A group has no box of its own: its `x`/`y` is the origin its children are placed
  from, and its children's rects are measured from that anchor, not from the group
  rect's corner. The group's rect is the union of those rects
  (``PenLayoutEngine/groupBox(of:in:)``) wherever it starts — left of and above the
  anchor when a child reaches there, right of and below it when every child sits
  away from it (the anchor itself is not in the union). Placed by its own `x`/`y`,
  the group turns and flips about its anchor like any free node, and its rect is
  the bounds of the union turned (``PenLayoutEngine/freeRect(of:x:y:box:)``); in a
  flex flow its slot is the union's size, grown to the turned bounds when it turns,
  with the union centred in it. `render-free-groups.pen` is the Pen-oracle fixture:
  a group at `(50, 50)` with children at `(20, 30)` and `(80, 60)` settles at
  `(70, 80)`, 90×60, and `PenFreeGroupTests` holds every rect within 0.5 pt of Pen's.

  > **Correction, 2026-09-27 (leaf `cqBw2i`):** this section used to say that a
  > group is exempt from the rotated-bounds and anchor-turn rules, that its rect is
  > the *un-rotated* union measured from its anchor, and that the renderer pivots it
  > at its rect's origin. That was inferred, not measured, and Pen's layout
  > contradicts it: Pen settles the true union, turned. The old rule drew free groups
  > right (the anchor pivot is the same picture) but placed a group in a flex flow a
  > union's offset off (MAE 2.55, and 5.53 turned) and cut a blurred group's reach
  > left of its anchor out of the blur buffer (1.46).
- **Disabled children are excluded** from a group's union, matching the flex path:
  `enabled: false` takes no space.
- **`padding` is not reserved.** An absolute container does not offset its
  children by padding, so it does not add padding to its size either.
- **Only `fit_content` differs.** `fixed(n)` resolves as anywhere else, and
  `fill_container` is its fallback in a non-flex context; with neither a parent to
  fill nor a fallback, an absolute frame's `fill_container` still takes its
  children's extent from its origin — Pen has not been measured there.

- **Incremental layout:** ``PenLayoutEngine/layoutIncremental(_:previousRects:dirtyNodeIDs:textMeasurer:)`` accepts cached rects and dirty node IDs, re-laying out only the root subtrees that contain dirty descendants. Clean roots have their previous rects copied unchanged. Since `.pen` documents are organized as independent top-level artboards, skipping clean artboards is the highest-value optimization.

### Three extents

A node has three extents, and each has one owner and one set of readers. Pen keeps the
same three (`computeLocalBounds`, `getTransformedLocalBounds`, `getVisualLocalBounds`);
strokes, shadows and blur enter only the third, never layout — not for a flex slot, a
sibling, a `fit_content` parent or a group's union, turned or not, and not even with
`layoutIncludeStroke: true`, which Pen parses and ignores
(`project/2026-09-28-geometry-model.md`).

| Extent | What it is | API | Readers |
|---|---|---|---|
| (i) Bounds | The axis-aligned bounds of the node's turned, flipped box, in its parent's coordinates | ``PenRect``, as ``PenLayoutEngine/layout(_:textMeasurer:)`` settles it; ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` composes it | The layout engine; `tree`'s `rect` and `absRect`; `shot`'s `rect=`, `--outline` and `--crop`; overlap lint; snapping and marquee selection; codegen's positioned wrappers |
| (ii) Placement | The box `0, 0, w, h` (a group's: its children's union, from its anchor) and the map that turns, flips and moves it into the parent, or the canvas | ``PenPlacement``, from ``PenLayoutEngine/placement(of:rect:layoutRects:)`` and ``PenLayoutEngine/canvasPlacement(of:in:layoutRects:)`` | Every renderer; the space children's rects are measured in; hit-testing the turned quad; selection handles and drag |
| (iii) Painted extent | What may carry ink: the box grown by its stroke band, unclipped children, shadows and blur | ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``, ``PenLayoutEngine/canvasPaintedExtent(of:in:layoutRects:)`` | Export and render canvas size; `shot --extent painted`; the render tests that place Pen's references; viewport culling; dirty-rect invalidation; stroke-band hit-testing |

The placement's map sends the box to the quad the node is drawn as, and that quad's
bounds are (i). Woodcase spells the map as the box centred in the bounds, flipped and
turned about its centre; Pen's is translate-to-anchor · turn · flip. They draw the same
quad, because a turned rectangle's bounds are centred on its centre.

The painted extent is Pen's `getVisualLocalBounds`, reproduced. In the node's own
coordinates it starts from the geometry — a frame's box, a shape's fill outline (a
`viewBox` path can reach outside its box: `viewbox-experiment`'s triangle paints 40 pt
above its frame) — and adds the stroke band: nothing for an inner stroke, half the width
for a centred one, all of it for an outer one, per side on a frame or rectangle, a line's
caps and a sharp polygon's miters counted. An unclipped frame and a group add each
enabled child's painted extent through the child's placement; a clipping frame adds none,
and a group has no box of its own to start from. Then each enabled outer shadow adds a
copy of that extent moved by its offset and grown by 1.5 × its blur — Pen does not count
the spread — and each layer blur grows the whole by 1.5 × its radius; a background blur
and an inner shadow add nothing. Last, the extent is mapped through the node's placement
corner by corner, so a turned node's mitred band reaches past its bounds: the probe's
100×60 rectangle with a 12 pt outer stroke turned 30° paints 149.39×134.75 pt, where its
bounds are 116.60×101.96. Pen's export of a node is its painted extent: drawn from the
extent's exact corner, fractional or not, at a pixel size rounded up
(``PenRect/grownToWholePixels(at:)``). `PenPaintedExtentProbeTests` holds six of Pen's
exports to it — every size to the pixel, and the renders framed that way within MAE 0.5
of Pen's.

A text now counts its glyphs' ink, as Pen does — ``PenLayoutEngine/textInkBounds(of:box:)``
lays out the same lines ``PenTextRenderer`` draws and unions each line's Core Text image
bounds — modulo the Core Text/Skia glyph-metric gap `PenGoogleFonts.md` already documents
for Inter at these sizes (`PenTextOpticalSizeTests`); `PenPaintedExtentProbeTests`' x5–x7
hold three of Pen's exports to it, within that gap rather than to the pixel. An icon now
counts its fitted glyph's ink too — ``PenLayoutEngine/iconInkBounds(of:box:)`` measures
the exact Core Text glyph ``PenIconGlyph``/``PenIconFontRenderer`` already draw — modulo a
wider, font-*substitution* gap for at least one bundled icon (x8–x9 in
`PenPaintedExtentProbeTests`; Woodcase draws icon fonts installed on the system, where Pen
draws its own bundled vector set, and the two libraries' glyphs are not always the same
shape for the same name). One approximation remains: a sharp corner of a path's stroke
counts only the band's half width, where Pen counts the miter.

## Text Measurement

``PenTextMeasurer`` measures text bounding boxes using Core Text's `CTFramesetter`. It is used by both the layout engine (to compute text node sizes) and the renderer (to resolve fonts and measure text for vertical alignment).

```swift
let size = PenTextMeasurer.measure(
    "Hello World",
    fontFamily: "SF Pro",
    fontSize: 24,
    fontWeight: "bold",
    maxWidth: 300
)
```

**Supported properties:** font family, size, weight (CSS names and numeric values), style (italic), letter spacing, line height multiplier, and max width for wrapping. Defaults to SF Pro at 16pt.

**Line height.** Every line is set at one fixed pitch, and a text's height is its line count times that pitch (``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)``). An explicit `lineHeight` is `lineHeight × fontSize` rounded to a whole point, half up, *per line*: three lines of 14 pt at 1.25 are 54 points tall, not 52.5 rounded up (`Tests/WoodcaseTests/Fixtures/text-line-height-rounding.layout.json`, Pen's own). With no `lineHeight`, the pitch is the font's ascent + descent + leading rounded to a whole point, as Pen rounds it (``PenTextMeasurer/naturalLineHeight(of:)``) — not Core Text's own natural line height, which rounds differently: Inter at 16 pt is 19.36 pt, which Pen sets as 19 and a bare `CTFramesetter` as 20. The renderer sets lines at the same pitch, so a box's vertical alignment centres the block of lines layout measured, and it places each line itself rather than leaving it to Core Text (see Text in <doc:PenRendering>). The figures are Pen's own, from `Tests/WoodcaseTests/Fixtures/text-natural-line-height.layout.json` (`scripts/pen-oracle`). Measuring typesets a text once: the line count and the width both come from one pass of Core Text's typesetter (a frame, for a justified paragraph, whose lines a frame stretches) — the width is the widest line's typographic width less its trailing whitespace, which is exactly what `CTFramesetterSuggestFrameSizeWithConstraints` returns, bit for bit, over 54,432 cases of six faces, sizes, wrapping widths, letter spacings, alignments and strings with trailing, leading and only whitespace, hard breaks, CJK, emoji and right-to-left text (`PenTextMeasurerTypesettingTests`), and the line count is a frame's. Asking for the suggested size and a frame typeset every text twice (<doc:WoodcasePerformance>).

### Font resolution and registration

Resolving a family to a `CTFont` is expensive — `CTFontCopyVariationAxes` reads the font's `fvar` table — so ``PenTextMeasurer`` memoizes the result process-wide, keyed by family, size, weight and style. A family that Core Text does not know falls back to SF Pro, and that fallback is memoized too.

A weight is read as a CSS weight (100–900) by ``PenFontWeight``, which needs no Core Text: the SwiftUI emitter reads a `fontWeight` the same way when it writes one into generated code.

The set of fonts Core Text knows about is not fixed for the life of a process: ``PenIconFontRegistry`` registers bundled icon fonts on first use, and ``GoogleFontResolver`` registers families as it downloads them. A resolution made before a family was registered is therefore only true until it is. ``PenFontRegistry`` names that fact as a **generation**: it counts font-set changes, every cached resolution belongs to the generation it was made under, and the cache is discarded wholesale the first time it is touched after a change. Without it a single early lookup would pin SF Pro for a family for the rest of the process.

Every registration inside Woodcase goes through ``PenFontRegistry/registerFont(at:)``, which moves the generation **only when Core Text added a face**. Registering a file Core Text already has is routine — a settled read registers the document's declared fonts on every read — and answers ``PenFontRegistry/Registration/alreadyRegistered`` without moving anything. That matters beyond the font cache: a move also discards the run's text sizes and every piece a settled tree could reuse (<doc:WoodcasePerformance>), so a generation that moved on a no-op made every read of a document that declares `fonts` a whole re-layout. **Code outside Woodcase that registers fonts must tell the registry**: a font file through ``PenFontRegistry/registerFont(at:)``, anything else by calling ``PenFontRegistry/didRegisterFonts()`` after a `CTFontManagerRegister…` call that succeeded:

```swift
PenFontRegistry.registerFont(at: url)             // a file: moves the generation only if it added a face

CTFontManagerRegisterGraphicsFont(font, nil)      // anything else
PenFontRegistry.didRegisterFonts()
```

As a second line of defence Woodcase also observes `kCTFontManagerRegisteredFontsChangedNotification`, which Core Text posts whenever anyone changes the font set. That covers a registrar that forgets the call, but only in a process that runs a run loop — Core Text delivers it on the run loop, not during the registering call — so it supplements the explicit call rather than replacing it. It is not posted for a file Core Text already has (measured 2026-09-27), so it never moves the generation for a no-op either.

## Stage 6: Rendering

``PenRenderer`` renders a document into a `CGImage` (or an existing `CGContext`) using the layout rectangles from Stage 4.

```swift
let image = PenRenderer.render(expanded, layoutRects: rects, size: CGSize(width: 800, height: 600), scale: 2)
```

**Key behaviors:**

- **Tree walk:** Traverses the document tree, drawing each node at its layout position. Disabled nodes and non-visual types (note, prompt, context, ref) are skipped.
- **Shapes:** Rectangles, ellipses, polygons, lines, and SVG paths are outlined by `PenShapeGeometry` (SVG paths parsed into ``PenPath``) and drawn with fills and strokes.
- **Fills:** Solid colors, linear/radial/angular gradients. Each fill respects enabled state, blend mode, and opacity. Colors are parsed from hex strings by ``PenColorParser``.
- **Text:** Rendered via Core Text. Supports horizontal alignment (left/center/right/justify), vertical alignment (top/middle/bottom), letter spacing, line height, underline and strikethrough. Style is node-level: 2.17 has no styled runs.
- **Icon fonts:** Six bundled icon font families (Lucide, Feather, Phosphor, Material Symbols Outlined/Rounded/Sharp) are auto-registered with CoreText on first use. Icon glyphs are rendered as single Unicode characters, centered in their bounding rect. Material Symbols supports variable weight via the `wght` OpenType variation axis.
- **Transforms:** Rotation, horizontal/vertical flip, applied around the center of each node's unturned box, centred in its layout rect — which, for a node placed by its own `x`/`y`, the layout has already moved to where turning about that anchor puts it. A group's box is its children's union, measured from its anchor.
- **Compositing:** Node-level opacity uses transparency layers to composite children correctly. Per-fill and per-node blend modes are supported.
- **Coordinate system:** CoreGraphics' bottom-left origin is flipped once at context creation so all drawing uses top-left coordinates matching the .pen format.

## Design Patterns

### Stateless pipeline stages

Every pipeline stage is a `nonisolated enum` with only static methods. No instances, no shared state, no side effects. This makes the pipeline trivially thread-safe and easy to test — each stage is a pure function from input to output.

### PenValue\<T\> for variable bindings

Properties that can be either a literal value or a `$variable` reference are typed as ``PenValue`` where `T: Friendly`. The Codable implementation decodes `$`-prefixed strings as `.variable(name)` and everything else as `.literal(value)`. This pattern appears throughout the model: coordinates, opacity, font sizes, colors, padding edges, corner radii, etc.

### Flat Codable for .pen nodes

The .pen JSON format is flat — all node properties (common + type-specific) are at the same level. `PenNode.init(from:)` reads `id` and `type` from a keyed container, then passes the **same decoder** to both ``PenNodeCommon`` and the type-specific data struct (e.g., ``PenNode/FrameData``). Each struct declares its own `CodingKeys` and ignores the others' keys, so there's no collision. A final pass over the same decoder with a `DynamicCodingKey` collects whatever no struct claimed into ``PenNode/extras`` (the claimed set per type is `PenNode.claimedKeys`, read off the property vocabulary). Fills and effects do the same for their payloads. A frame's or group's payload is handed a wrapper decoder that sets its `children` array aside rather than decoding it, and `PenNode.init(from:)` decodes the whole subtree from an explicit work list of those arrays — so only one node's decode is on the stack at a time, however deep the tree.

### JSON round-trip for descendant overrides

Ref descendant overrides are applied by encoding the target node to `[String: AnyCodable]`, merging the override properties, and re-decoding. This leverages all existing Codable infrastructure rather than manually patching individual typed properties.

## Key Decisions

1. **Combined measure+arrange** for layout instead of separate passes — `fill_container` needs parent space (top-down) while `fit_content` needs child sizes (bottom-up); one algorithm per container handles both directions. It is written as a resumable state machine per container (`AbsoluteLayout`, `FlexLayout`) driven from an explicit stack of frames rather than as a recursive function, so layout's stack use does not grow with the tree; the order of every measurement and rect write is the recursive algorithm's.

2. **Pure Core Text for text measurement** — no AppKit/UIKit dependency. Uses `CFAttributedString` + `CTFramesetter` directly, keeping the library portable to iOS and watchOS.

## Forward Compatibility

The .pen format evolves independently of Woodcase. The library handles unknown data gracefully:

- **Unknown node types** decode as `.unknown(typeName:properties:)`, preserving all properties as `[String: AnyCodable]`. The layout engine reads `width` and `height` back out of them — a number or a sizing keyword — and places the node as an inert box of that size, so its siblings stay where Pen put them; the renderer draws nothing for it.
- **Unknown keys** are kept verbatim as ``PenExtras``: on the document root (``PenDocument/extras``), on a node of a known type (``PenNode/extras``), on each fill, stroke paint and effect payload, on each ``PenFontDeclaration``, and on every object nested inside those that the model decodes into a struct of its own — a gradient's stops (``PenFill/PenGradientStop``), centre and size, a shadow's ``PenEffect/PenOffset``, a mesh vertex written as an object (``PenMeshPoint/Object``), a connection's endpoints, a per-side `strokeWidth` object (``PenStrokeWidth/Sides``), and a ``PenVariable`` and each of its ``PenThemedValue``s. A stroke in .pen is five sibling keys on the node, so its unknown keys are node extras, and its paint's are fill extras. The `themes` and `imports` maps and a themed value's `theme` are maps of data, not structs: every key in them is a value and always survives.
- **Unknown fill and effect types** decode as ``PenFill/unknown(typeName:payload:)`` and ``PenEffect/unknown(typeName:payload:)``. Nothing renders or emits code for them; they are written back as read.

Extras are **write-through only**. Layout, rendering and code generation never read them; `set`, `cp`, `mv`, `override` and undo carry them along, `rm` removes them with the node, and `replace` gives the node its replacement's — which authored input never has. No verb writes one: `set` on a preserved key is refused with ``EditingError/unknownProperty(nodeID:key:nodeType:)``, and the refusal says the key is kept. In a collaborative session a node's extras are one last-writer-wins register (`CRDTDocument.extrasProperty`). Revisions hash a node's canonical encoding, which includes its extras; the document revision adds the root's.

**Two decoding modes.** Only a *file* is read leniently. A decoder's ``PenDecodingMode``, set on its `userInfo` under ``PenDecodingMode/userInfoKey``, decides: ``PenDecodingMode/file`` (the default, and what every decode of Woodcase's own output uses — the undo log, CRDT operations, the property codec's round trips, override merges) keeps unknown keys and types; ``PenDecodingMode/authoring`` refuses them. An agent's input is authoring: ``PenSubtreeDecoder`` (`add`, `replace`, batch and script subtrees) decodes in it, ``NodePropertyCodec/checkAuthored(_:on:)`` checks the fill, stroke and effect values `set` writes, and ``NodePropertyCodec/checkAuthoredOverride(_:on:refID:descendantKey:)`` holds an override — from `override`, or from a `cp` of a component whose path-keyed properties become overrides — to the same, and also refuses a whole-node replacement or a slot child of a node type the format does not have. A typo such as `"fil"` is refused instead of kept, and so is a node `type` the format does not have — `{"type":"video_clip"}` is refused with the list of real types, while the same node in a file is kept as `.unknown`.
- **Unknown enum values** (layout direction, blend mode, etc.) use an `.unknown(String)` case that preserves the raw value through round-trips.
