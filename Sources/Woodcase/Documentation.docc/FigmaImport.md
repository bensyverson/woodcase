# Importing Figma Layers

Turn a decoded Figma clipboard message into Pen nodes, and say what did not survive.

## Overview

``FigmaImporter`` takes a decoded clipboard (<doc:FigmaClipboard>) and returns a
``FigmaImport``: a ``PenClip`` holding the selection as Pen nodes, and a list of
``FigmaImportLoss``es — every Figma feature the Pen nodes do not carry as Figma had it.

```swift
let clipboard = try FigmaClipboardDecoder().decode(html: html)
let result = try FigmaImporter().clip(from: clipboard)
result.clip.contentIDs      // the selected layers, as Pen roots
result.losses.map(\.description)
// "\"V1b donut\": booleanOperation flattened (SUBTRACT)"
let plan = try result.clip.plan(into: document, at: target)
```

The output is a clip rather than a bare document so a paste takes the same road as a Pen
copy: ``PenClip/plan(into:at:)`` re-ids what collides, reuses a component the document
already holds and places the roots. The clip's roots are the selected layers at their
canvas positions, then any component an instance needs that was not itself selected.

**Nothing is dropped silently.** Every field of every mapped node is either read, known to
be safe to leave (bookkeeping, publishing state, data Figma derives from fields it reads),
or reported as ``FigmaImportLoss/Feature/unreadField`` with its name — so a field a new
Figma release adds shows up as a loss, not as nothing. One loss covers one feature of one
node; a feature spanning several fields (four bound corner radii) is reported once, its
fields in ``FigmaImportLoss/detail``.

**A refusal is whole.** A selection holding a node type the importer does not map is
refused with ``FigmaImportError/unsupportedNodes(_:)``, which names every such layer and
its type; the importer never returns part of a selection.

### Placement

A Figma node's `transform` is an affine map into its parent, turning about the node's
top-left corner. Pen places a node by the same anchor, flips it, then turns it
counter-clockwise (``PenLayoutEngine/freeRect(of:x:y:box:)``), so an orthonormal matrix
decomposes exactly: `x` and `y` are the translation, a negative determinant is a flip, and
the turn is the column's angle negated. A mirror with no turn is a vertical *or* a
horizontal flip plus a half turn; the importer takes whichever leaves the smaller turn, so a
vertical flip stays `flipY`. Children are placed in their parent's coordinates, groups and
booleans included, as in Pen. Every frame is written with `layout: none`, so a child keeps
the position Figma gave it — auto layout's computed positions included.

Figma's groups arrive as frames with `resizeToFit`; there is no `GROUP` node in any
capture. Siblings sort by `parentIndex.position`, byte by byte, which puts the bottom layer
first — Pen's order. The roots are the children of every page that is not `internalOnly`;
the internal page holds the masters, styles and variables a selection depends on.

`FigmaImportGeometryTests` lays out the imported V1, T1 and G1 fixtures with
``PenLayoutEngine`` and holds every node's corners to Figma's own transforms, composed up
to the canvas, within 0.01 pt; it holds each V1 vector's path, drawn where Pen draws it, to
Figma's SVG export within 0.01 pt, and each boolean's outline to the export's bounds.

### Ids

A node's id is `figma-<session>-<local>`, from its GUID (``FigmaImporter/penID(sessionID:localID:)``),
so an instance's ref and overrides can name its component and the component's children
before either is mapped.

### The mapping table

What each Figma node type becomes:

| Figma | Pen | Loss |
|---|---|---|
| `FRAME` | `frame`, `layout: none`, `clip` unless `frameMaskDisabled` | — |
| `FRAME` with `resizeToFit` (a group) | `group` | a group's own paint, if any: `unsupportedPaint` |
| `SECTION` | `frame` | `section`, approximated |
| `SYMBOL` (component) | `frame`, `reusable: true` | component properties: `componentProperties`, dropped |
| `INSTANCE` of a carried component | `ref`, overrides as root and descendant overrides | see Instances |
| `INSTANCE` of a component not in the clipboard | `frame` of its size and paint, no children | `missingComponent`, placeholder; or refused (``FigmaImportOptions/MissingComponents/refuse``) |
| `ROUNDED_RECTANGLE`, `RECTANGLE` | `rectangle`, per-corner radii included | — |
| `LINE` | `line`, length from `size`, turn from `transform` | arrow and marker caps: `strokeCap`, approximated |
| `REGULAR_POLYGON` | `polygon`, `polygonCount` from `count`, its box fitted so the corners land on Figma's | a gradient or image over a grown box: `polygonBox`, approximated |
| `STAR` | `path`: its geometry blob if the clipboard carries one, else computed from `count` and `starInnerScale` | `cornerRadius` > 0: `shapeCornerRadius`, approximated |
| `ELLIPSE` | `ellipse`, with arc and ring | — |
| `VECTOR` | `path`, its network's regions as `geometry`, `viewBox` the network's space | see Vectors |
| `BOOLEAN_OPERATION` | `path` of the computed result | `booleanOperation`, flattened |
| `TEXT` | `text` | see Text |
| `DOCUMENT`, `CANVAS` | the clip itself | — |
| anything else (`STICKY`, `CONNECTOR`, `SHAPE_WITH_TEXT`, `STAMP`, `WASHI_TAPE`, `HIGHLIGHT`, `TABLE`, `SLIDE`, …) | **refused** | `FigmaImportError.unsupportedNodes` |

The FigJam and Slides types are leaf `flhl7G`. No committed capture holds a `RECTANGLE`,
`LINE`, `REGULAR_POLYGON` or `STAR`; `FigmaImportShapeTypeTests` builds each as a synthetic
message, and E2b's line (local only) maps from the capture.

**Polygons and stars fill their box.** Pen puts a polygon's corners on the ellipse
inscribed in its box, first corner at the top, clockwise; a triangle's base then sits a
quarter of the height above the bottom edge. Figma stretches the polygon's own bounds over
the box — the apex at the top edge, the base on the bottom one — so the importer grows the
Pen box and moves its anchor until the polygon's bounds are Figma's box. A polygon with a
multiple of four sides fills its box in both and keeps it. The computed star is stretched
the same way. That Figma fills the box is how its polygon tool draws; no capture pins it
yet.

What each property becomes, and every lossy mapping (the ``FigmaImportLoss/Feature`` case
is the loss reported):

| Figma | Pen | Loss |
|---|---|---|
| `name` | `name` | — |
| `transform` | `x`, `y`, `rotation`, `flipX`, `flipY` | a scale or skew: `transformSkew`, dropped |
| `size` | `width`, `height` (fixed) | — |
| `opacity` | `opacity` | — |
| `visible: false` | `enabled: false` | — |
| `locked: true` | `metadata.woodcase.locked` (``PenNode/isLocked``) | — |
| `mask: true` | the mask shape `enabled: false` | `mask`, dropped: the masked layers draw unmasked |
| `horizontalConstraint`, `verticalConstraint` other than `MIN` | — | `constraints`, dropped |
| `stackMode` (auto layout) | positions as Figma computed them | `autoLayout`, flattened |
| `layoutGrids` | — | `layoutGrid`, dropped |
| `blendMode` (node) | `metadata.woodcase.blendMode`; `NORMAL` and `PASS_THROUGH` none | an unknown mode: `blendMode`, approximated |
| `cornerRadius`, `rectangle…CornerRadius` | `cornerRadius`, per corner only when independent and different | `cornerSmoothing` > 0: `cornerSmoothing`, approximated |
| `arcData` | `startAngle`, `sweepAngle` (radians clockwise → degrees counter-clockwise), `innerRadius` | — |
| `fillPaints` | `fill`, bottom paint first | see Paints |
| `strokePaints`, `strokeWeight`, `strokeAlign` | `stroke`, `strokeWidth`, `strokeAlignment` (`INSIDE` inner, `OUTSIDE` outer) | — |
| `borderStrokeWeightsIndependent` with `border…Weight` | per-side `strokeWidth` | — |
| `strokeCap` `NONE`, `ROUND`, `SQUARE` | `strokeLinecap` butt, round, square | arrows and markers: `strokeCap`, approximated as butt |
| `strokeJoin` | `strokeLinejoin` | — |
| `dashPattern` | `metadata.woodcase.strokeDash` | with per-side widths, which Pen cannot dash: `strokeDash`, dropped |
| `effects` | `effect` | see Effects |
| `styleIdForFill`, `…StrokeFill`, `…Text`, `…Effect`, `…Grid` | the style's values, which the node carries | `styleReference`, resolved |
| a bound variable (`colorVar` alias, `parameterConsumptionMap` alias) | the value Figma drew | `variableBinding`, resolved |
| `variableModeBySetMap` | the mode's values, which the descendants carry | `variableMode`, resolved |
| `isStateGroup` (a variant set) | `frame` of components | `variants`, dropped |
| a field the importer has never met | — | `unreadField`, dropped, the field named |
| `textTracking`, `fontVariations`, `fontVariantCommonLigatures`, `fontVariantContextualLigatures`, `textDecorationSkipInk` away from their defaults (0, none, on, on, on) | — | `unreadField`, dropped, the field named |

#### Paints

| Figma | Pen | Loss |
|---|---|---|
| `SOLID` | `color`, paint opacity multiplied into the hex alpha | — |
| `GRADIENT_LINEAR`, `…RADIAL`, `…ANGULAR` | `gradient`; stops with their alpha; paint opacity as `opacity`; the transform as `center`, `size`, `rotation` | a skewed transform: `gradientSkew`, approximated |
| `GRADIENT_DIAMOND` | radial `gradient` | `diamondGradient`, approximated |
| `IMAGE` whose hash the caller resolved (``FigmaImportOptions/imageURLs``) | `image`: `FILL` cover, `FIT` contain, `STRETCH` stretch with the inverse of Figma's crop transform | `TILE`: `imageTile`, approximated as cover; a rotated image: `unsupportedPaint` |
| `IMAGE` otherwise | ``FigmaImagePlaceholder``: a `color` fill of ``FigmaImagePlaceholder/gray``, the paint's visibility and blend mode kept and its opacity in the alpha | `imageNotEmbedded`, placeholder, the hash as detail |
| `VIDEO`, `EMOJI`, `NOISE`, `PATTERN`, … | — | `unsupportedPaint`, dropped |
| a paint's `visible: false` | `enabled: false` | — |
| a paint's `blendMode` | `blendMode` | — |

A gradient's frame: Figma's `transform` maps the node's normalized box into gradient
space, where a linear gradient runs from `(0, 0.5)` to `(1, 0.5)` and an angular one starts
along +x (its SVG export writes `conic-gradient(from 90deg, …)`). Pen's unit space is a
quarter turn from Figma's, so Pen's frame is the inverse of Figma's transform after that
turn, decomposed into a center, a turn and a size (`FigmaImportPaintTests`). Pen's frame
has no skew; the gradient's own axis is kept exact and the cross axis is projected.

#### Effects

| Figma | Pen | Loss |
|---|---|---|
| `DROP_SHADOW`, `INNER_SHADOW` | `shadow` outer, inner: `offset`, `blur` = `radius`, color with its alpha | — |
| a shadow's `spread` | `metadata.woodcase.shadowSpread` | — |
| a drop shadow with `showShadowBehindNode` under a translucent fill | `shadow`; Pen knocks it out under the silhouette | `shadowBehindNode`, approximated |
| `FOREGROUND_BLUR`, `BACKGROUND_BLUR` | `blur`, `background_blur`, `radius` (both sigma radius ÷ 2) | — |
| a progressive blur (`blurOpType: PROGRESSIVE`) | — | `progressiveBlur`, dropped |
| `NOISE`, `GRAIN` (texture), `GLASS`, … | — | `unsupportedEffect`, dropped |

#### Vectors

A vector's `geometry` is every region's loops, drawn by ``FigmaVectorNetwork/path(ofRegion:)``,
in `vectorData.normalizedSize` space; the `viewBox` is that space, which Pen stretches onto
the node's size as Figma does. A network with no region (none in the fixtures) is stroked
segment by segment.

| Figma | Pen | Loss |
|---|---|---|
| a region's winding rule | `fillRule` (`evenodd`, or none for nonzero) | regions with different rules: `windingRules`, approximated with the first |
| stroked segments outside every region | — | `openStrokeSegments`, dropped |
| a `styleOverrideTable` entry a vertex, segment or region uses, differing from the node | — | `vectorStyleOverride`, dropped |

A boolean operation carries no geometry in the clipboard, so the importer computes it:
each operand's outline (`PenShapeGeometry`), placed by its transform and normalized to its
fill rule, combined bottom operand first with Core Graphics' set operations — union, the
bottom one less the rest, intersection or exclusion. The operands do not survive as nodes.
An operand with no outline (text, a frame) is left out: `booleanOperand`, dropped.

#### Text

Text is read from `textData` and the node's style. The glyph outlines in `derivedTextData`
are Figma's rendering and play no part — a color emoji's glyph blob is empty, and its
character still comes through.

| Figma | Pen | Loss |
|---|---|---|
| `textData.characters` | `content` | — |
| `fontName.family` | `fontFamily` | — |
| `fontName.style` | `fontWeight` and `fontStyle`, from `derivedTextData.fontMetaData`, else from the style name (`Semi Bold Italic` is 600, italic) | — |
| `fontSize` | `fontSize` | — |
| `lineHeight` 100 `PERCENT` (Figma's "auto") | none: the font's natural line height | — |
| `lineHeight` `RAW` (the UI's percentage: "120%" is stored as `RAW` 1.2) | that multiple of the size | — |
| `lineHeight` `PIXELS` | the pitch ÷ the size | — |
| `lineHeight` `PERCENT` other than 100 | a percentage of the font's natural line height (inferred: no capture holds one) | — |
| `letterSpacing` `PIXELS`, `PERCENT` | `letterSpacing` in points | — |
| `textAutoResize` `WIDTH_AND_HEIGHT`, `HEIGHT`, `NONE` | `textGrowth` auto, fixed-width, fixed-width-height | — |
| `textAlignHorizontal`, `textAlignVertical` | `textAlign`, `textAlignVertical` | — |
| `textDecoration` | `underline`, `strikethrough` | — |
| `characterStyleIDs` with `styleOverrideTable` | `metadata.woodcase.spans`, each run holding only what differs from the node | an override field other than font, size, fill and decoration: `unreadField` |
| `textTruncation` | — | `textTruncation`, dropped |
| list lines (`lineType` other than `PLAIN`) | the text, without markers | `textList`, dropped |
| `textCase` | — | `textCase`, dropped |
| `paragraphSpacing`, `paragraphIndent` | — | `paragraph`, dropped |
| `hyperlink` | — | `hyperlink`, dropped |

Which unit is which is pinned by T1. The fixture plugin set T1c's line height to
`{ value: 120, unit: 'PERCENT' }` — the UI's 120 %, 1.2 × the size — and the message stores
`{ value: 1.2, units: RAW }`. "Auto" is stored as 100 `PERCENT`, and T1a shows that is the
font's natural height, not the size: at 32 pt its `derivedTextData.baselines` are 39 pt
apart (Inter's natural 1.2102 × 32 = 38.7, rounded), not 32. T1b's 32 `PIXELS` lines are
32 pt apart.

Run offsets are taken as UTF-16 code units, as Pen's are; the fixtures' mixed text is
ASCII, so this is inferred, not observed.

#### Instances

An instance becomes a `ref` to its component's id. Figma's `symbolData.symbolOverrides`
name their targets by a GUID path through the component; one naming the component itself is
a root override, any other a descendant override keyed by the path's ids joined with `/`.

| Figma override | Pen | Loss |
|---|---|---|
| `fillPaints`, `strokePaints` | `fill`, `stroke` | — |
| `visible`, `opacity` | `enabled`, `opacity` (on the root, the ref's own) | — |
| `textData` | `content` | — |
| a text or boolean component property (`componentPropAssignments`) | `content` or `enabled` on each node consuming it | another property type: `instanceOverride` |
| `overriddenSymbolID` (a swap) | — | `instanceSwap`, dropped |
| a resized instance | root `width`, `height` | — |
| any other override field | — | `instanceOverride`, dropped, the field named |

## Images

The clipboard carries an image's hash — the lowercase hex SHA-1 of its bytes — never the
bytes. Figmeta's `imageHashes` (``FigmaClipboardMetadata/imageHashes``) maps each hash to a
signed URL, and fetching stays outside the importer, which is synchronous and never touches
the network:

1. A ``FigmaImageFetcher``, made once and kept (per paste or for the app's life), downloads
   each URL — one image at a time with ``FigmaImageFetcher/fetch(hash:url:)``, so each can
   draw as it lands, or a whole clipboard with ``FigmaImageFetcher/fetch(_:)``. Every call
   shares one bound on downloads in flight (four by default) and each download has a
   timeout (30 seconds by default). It goes through a ``RemoteDataFetching``
   (``StandardDataFetcher/make(environment:)`` by default, whose `URLSession`s are shared
   process-wide by route, so connections pool; tests inject one). It refuses a URL that is
   not `https` — a clipboard is untrusted, and a `file:` URL would read the disk — and
   checks the bytes' SHA-1 against the hash and their format by signature
   (``ImageFileFormat``). Per hash it returns the bytes and format, or a
   ``FigmaImageFetchError``. It writes nothing.
2. The caller stores the bytes where its document can reach them and passes each hash's
   location as ``FigmaImportOptions/imageURLs``. Because the hash names the bytes, a caller
   can name the location (`./images/<hash>`) before the download finishes, paste at once,
   and fill the images in as they land.
3. A hash with no URL becomes ``FigmaImagePlaceholder``'s gray fill in the paint's place,
   reported as `imageNotEmbedded`, treated as a placeholder, with the hash. A caller whose
   fetch failed after it named a URL swaps the image fill for
   ``FigmaImagePlaceholder/fill(replacing:)``, so both routes draw alike.

## Open questions

These defaults are Ben's to confirm; each is one place in the code.

- **Instances of absent components.** Copying an instance without its master gives no
  children at all. The default is a placeholder frame; ``FigmaImportOptions/MissingComponents/refuse``
  refuses instead. Ben ruled (2026-10-20) that such an instance be flattened from
  `derivedSymbolData` into plain layers instead, but that is not built: in every capture so
  far `derivedSymbolData` holds, per component layer, only a guid path, its outline
  (`fillGeometry`) or glyphs (`derivedTextData`) in the layer's *own* coordinates, and
  sometimes a size — no position, type, paints, strokes or effects — and an instance of a
  childless component carries none at all. No capture yet has an instance whose master is
  truly absent (Figma ships hidden nodes on an internal canvas, and may ship masters there
  too).
- **Variables and styles** are resolved to the values Figma drew and reported. Mapping
  collections and modes onto Pen variables and themes is not built.
- **Auto layout** is flattened to absolute positions and reported. Mapping `stackMode` onto
  Pen's flex layout is not built.
- **The output** is a ``PenClip`` for ``PenClip/plan(into:at:)``, not a whole document.

