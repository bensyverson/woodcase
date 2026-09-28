# PenEngine Phase 1 — Implementation Progress

**Date:** 2026-03-22
**Status:** Complete — all 10 steps done
**Parent:** [Pen-Based Title System](2026-03-21-pen-title-system.md)
**Test corpus:** [Pen Renderer Test Corpus](2026-03-22-pen-test-corpus.md)

## Overview

This document tracks the implementation of Phase 1 of the PenEngine: parser, variable resolver, ref expander, and layout engine. It is designed to allow a fresh context to pick up where we left off.

## Completed Steps

### Step 1: Foundation Types (Done)

Created 6 model files in `FirstPassPro/PenEngine/Models/`:

| File | What it provides |
|------|-----------------|
| `AnyCodable.swift` | Type-erased Codable wrapper for preserving unknown JSON. Supports null/bool/int/double/string/array/dictionary. ExpressibleBy literals. |
| `PenEnums.swift` | Small enums: PenLayoutDirection, PenJustifyContent, PenAlignItems, PenTextGrowth, PenTextAlign, PenTextAlignVertical, PenStrokeAlign, PenStrokeJoin, PenStrokeCap, PenFillRule, PenImageFillMode, PenLayoutPosition, PenGradientType, PenBlendMode (with `.unknown(String)` forward compat). |
| `PenValue.swift` | `PenValue<T: Friendly>` — generic `.literal(T)` / `.variable(String)` enum. Handles NumberOrVariable, ColorOrVariable, BooleanOrVariable, StringOrVariable from the .pen TypeScript schema. Custom Codable: `$`-prefixed strings decode as `.variable`. |
| `PenSizing.swift` | `PenSizing` — `.fixed(Double)` / `.fitContent(fallback:)` / `.fillContainer(fallback:)` / `.variable(String)`. Parses strings like `"fit_content(200)"` via Swift Regex. |
| `PenRect.swift` | `PenRect` — Friendly rect (x, y, width, height: Double) with CGRect bridge. Used as layout engine output. |
| `PenPadding.swift` | `PenPadding` — `.uniform` / `.symmetric(h:v:)` / `.individual(top:right:bottom:left:)`. Each edge is a `PenValue<Double>`. Includes `Edges` resolved type with `.resolve()`. |

33 tests in `PenModelTests.swift`.

### Step 2: Property Types (Done)

Created 5 model files in `FirstPassPro/PenEngine/Models/`:

| File | What it provides |
|------|-----------------|
| `PenFill.swift` | Discriminated union: `.shorthand(String)` / `.color(PenColorFill)` / `.gradient(PenGradientFill)` / `.image(PenImageFill)` / `.meshGradient(PenMeshGradientFill)`. Custom Codable dispatches on `type` field; bare strings are shorthand. `PenFills` wrapper handles single-or-array. |
| `PenStroke.swift` | `PenStroke` struct with align, thickness (uniform or per-side), join, cap, dashPattern, fill. `PenStrokeThickness` is its own enum. |
| `PenEffect.swift` | Discriminated union: `.blur` / `.backgroundBlur` / `.shadow`. Custom Codable dispatches on `type` field. `PenEffects` wrapper handles single-or-array. |
| `PenTextStyle.swift` | `PenTextStyle` struct (font family/size/weight/style, spacing, alignment, decorations). `PenTextContent` enum (`.plain(PenValue<String>)` / `.rich([PenTextSpan])`). `PenTextSpan` for rich text with per-span overrides. |
| `PenVariable.swift` | `PenVariable` struct (type + value). `PenVariableType` enum. `PenVariableValue` enum (`.simple(AnyCodable)` / `.themed([PenThemedValue])`). `PenThemedValue` for theme-conditional values. |

17 additional tests in `PenModelTests.swift` (50 total).

### Step 3: Node + Document Types (Done)

Created 4 model files in `FirstPassPro/PenEngine/Models/`:

| File | What it provides |
|------|-----------------|
| `PenCornerRadius.swift` | `.uniform(PenValue<Double>)` / `.perCorner(topLeft:topRight:bottomRight:bottomLeft:)`. Custom Codable: single value or 4-element array. `Corners` resolved type with `.resolve()` and `.isUniform`. Parallels PenPadding. |
| `PenDescendantOverride.swift` | Thin wrapper around `[String: AnyCodable]` for ref descendant overrides. Computed `isObjectReplacement` (true when `properties["type"]` is present). Resolved during ref expansion (Step 6). |
| `PenNode.swift` | The core scene graph node. `PenNodeCommon` (13 shared Entity properties) + `PenNode.Kind` discriminated enum with 13 type-specific data structs nested inside PenNode + `.unknown(typeName:properties:)` for forward compat. Flat Codable: decodes `type` first, passes same decoder to PenNodeCommon and the data struct. See detailed notes below. |
| `PenDocument.swift` | Root document: `version`, `themes`, `imports`, `variables`, `children`. Auto-synthesized Codable. |

19 additional tests in `PenModelTests.swift` (69 total).

**Deviations from the original plan:**

1. **Added `PenCornerRadius.swift`** — not originally listed in Step 3 but needed by FrameData, RectangleData, and PolygonData. The .pen format allows `cornerRadius` as a single value or a 4-value array, which requires the same single-or-array Codable pattern as PenPadding.

2. **`unknown` case uses inline associated values, not a wrapper struct.** The original plan called for `case unknown(UnknownData)` with a struct wrapping `typeName` and `rawProperties`. This was simplified to `case unknown(typeName: String, properties: [String: AnyCodable])` to avoid an unnecessary wrapper type — `[String: AnyCodable]` is already Codable.

3. **`PenNode.Kind` has explicit Codable stubs that throw.** The compiler can't auto-synthesize Codable for an enum with heterogeneous associated values including `[String: AnyCodable]`. The Kind's `init(from:)` and `encode(to:)` throw with a message directing callers to use PenNode's Codable instead. All Codable dispatch happens in PenNode's `init(from:)` / `encode(to:)`.

4. **CodingKeys map `fill` → `fills` and `effect` → `effects`.** The .pen JSON uses singular (`fill`, `effect`) but we store as plural (`fills`, `effects`) to match our `PenFills`/`PenEffects` wrapper types. Every data struct with fills/effects has a CodingKeys enum handling this mapping.

**Key implementation details for the next agent:**

- **Flat Codable pattern:** The .pen JSON is flat (all properties at the same level). PenNode's `init(from:)` creates a keyed container for `id`/`type`, then passes the **same `decoder`** to `PenNodeCommon(from:)` and to the appropriate `*Data(from:)`. Each struct defines its own CodingKeys and ignores unknown keys — no collision. This is the same pattern used by PenFill and PenEffect.

- **DynamicKey for unknown nodes:** Unknown node types can't use typed CodingKeys. PenNode defines a private `DynamicKey: CodingKey` struct and a `reservedKeys` set (id, type, + all PenNodeCommon property names). Decoding iterates `allKeys`, filters out reserved keys, and collects the rest into `[String: AnyCodable]`. Encoding writes `type` via CodingKeys, delegates common properties, then emits remaining properties via DynamicKey. This means common properties (name, opacity, etc.) are decoded into `PenNodeCommon` for uniform access, while type-specific unknown properties live in the dict.

- **PenNodeCommon has 13 properties** (one more than the original plan estimated): name, x, y, rotation, opacity, enabled, flipX, flipY, reusable, theme, context, layoutPosition, metadata. All optional. The `metadata` field is `[String: AnyCodable]?` to preserve arbitrary metadata objects.

- **`NodeType` enum** is separate from `Kind` — it's a simple `String`-backed enum used only for Codable dispatch. If `NodeType(rawValue:)` returns nil, the node is decoded as `.unknown`.

### Step 4: Parser + Fixtures (Done)

Created 3 artifacts:

| File | What it provides |
|------|-----------------|
| `PenParser.swift` | Stateless `nonisolated enum` wrapping JSONDecoder/JSONEncoder. Methods: `parse(_: Data)`, `parse(_: String)`, `parse(contentsOf: URL)`, `encode(_:)`, `encodeToString(_:)`. `PenParserError` enum with `.decodingFailed`, `.invalidString`, `.fileReadFailed`. |
| `FirstPassProTests/Fixtures/` | 15 manually-authored .pen JSON fixtures covering: empty document, all node types, nested children, fill types (solid/gradient/image), multiple fills, stroke variants (uniform/per-side/dashed), effect variants (shadow/blur/multiple), text content (plain/rich/variable/textGrowth), variables (4 types), themed variables, reusable+ref with descendant overrides, imports, unknown properties (forward compat), context nodes in hierarchy, realistic lower-third design. |
| `PenParserTests.swift` | 37 tests: 15 fixture-loading structural tests, 15 parameterized round-trip tests (parse → encode → parse → assert equality), 6 error cases (invalid JSON, empty data, missing version, missing children, non-existent file, string parsing), 1 encode-to-string test. |

**Deviations from the original plan:**

1. **No deviations to the parser itself.** PenParser is exactly the thin JSONDecoder wrapper described in the plan. No special decoder configuration was needed — all Codable dispatch is handled by the model types from Steps 1-3.

2. **Fixtures are parser-only, not Pencil MCP-generated.** The test corpus doc (`project/2026-03-22-pen-test-corpus.md`) describes two categories of fixtures: parser fixtures (hand-authored, testing Codable correctness) and layout/renderer fixtures (generated via Pencil MCP as ground truth). Step 4 only covers the first category. Pencil MCP fixtures come in Step 7 and will add `.layout.json` / `.png` files alongside `.pen` files in the same `Fixtures/` directory.

**Key decisions:**

1. **JSON field names must match model property names (or CodingKeys mappings).** When writing fixtures, the JSON keys must correspond to the Swift property names *after* CodingKeys mapping. For example: `PenGradientFill` uses `gradientType` (not `gradient`), `colors` (array of `PenGradientStop`) not `stops`; `PenImageFill` uses `url` (not `src`); fill/effect arrays use the singular JSON key (`fill`, `effect`) which CodingKeys maps to plural properties (`fills`, `effects`). Getting these wrong produces silent nil values, not errors, since all properties are optional.

2. **`PenParserError` wraps underlying errors.** Rather than letting raw `DecodingError` bubble up, PenParser catches and wraps them in `PenParserError.decodingFailed(underlying:)`. This preserves the original error for debugging while giving callers a predictable error type. Same pattern for file I/O errors.

3. **`encode()` uses `.sortedKeys`.** This makes round-trip output deterministic for testing. Without it, dictionary key ordering would vary between runs, making encoded JSON comparison unreliable.

**What the next agent needs to know for Step 5 (Variable Resolver):**

- **PenValue<T> is the core abstraction.** Variables appear as `PenValue.variable("name")` throughout the tree. The resolver's job is to walk the tree and replace each `.variable(name)` with `.literal(resolvedValue)` by looking up `name` in `PenDocument.variables`.

- **Variables live in `PenDocument.variables: [String: PenVariable]?`.** Each `PenVariable` has a `.type` (boolean/color/number/string) and a `.value` which is either `.simple(AnyCodable)` or `.themed([PenThemedValue])`. Themed values have a `theme: [String: String]?` dictionary for conditional matching.

- **Variable references use `$` prefix in JSON but store just the name.** `PenValue.variable("foo")` encodes as `"$foo"` in JSON. The `$` is stripped during decode and re-added during encode. The resolver should look up by bare name.

- **PenValue appears in many places.** It's used for: node common properties (x, y, rotation, opacity, enabled, flipX, flipY), sizing in some contexts, gap, padding edges, text properties (fontSize, fontFamily, etc.), fill colors, stroke thickness, effect properties, corner radius values. The resolver needs to walk the entire tree recursively.

- **Variable-to-variable chains.** A variable's value can itself be a `$reference` to another variable. The resolver should follow chains but cap at ~10 to prevent infinite loops.

- **Theme resolution.** When `PenVariable.value` is `.themed([PenThemedValue])`, the resolver needs the active theme (a `[String: String]` mapping axis names to selected options, e.g. `["mode": "dark"]`). For each themed value, check if its `theme` dictionary is a subset of the active theme. Last match wins. Values with `theme: nil` are defaults (used when no themed value matches).

- **External overrides.** The resolver should accept an optional `[String: AnyCodable]` of external variable values (e.g., from FPP's runtime: speaker name, timestamp). These take precedence over document-defined variables.

- **Fixtures already test variable parsing.** `parser-variables.pen` and `parser-themed-variables.pen` confirm the model layer correctly parses variable definitions and `$`-prefixed bindings. Step 5 tests should focus on *resolution* behavior: substitution, chaining, theme matching, missing variables, type mismatches.

### Step 5: Variable Resolver (Done)

Created 2 artifacts:

| File | What it provides |
|------|-----------------|
| `PenVariableResolver.swift` | Stateless `nonisolated enum` that walks the entire document tree replacing `PenValue.variable("name")` with `PenValue.literal(resolvedValue)`. Three-phase algorithm: (1) build resolved variable table from document variables with theme matching, (2) apply external overrides, (3) resolve `$`-prefixed variable chains with cycle detection. Core `resolve<T>` generic extracts typed values from `AnyCodable`. Separate resolver methods for every compound type: padding, cornerRadius, sizing, fills, stroke, effects, text content, text spans, gradient stops, fill size. |
| `PenVariableResolverTests.swift` | 47 tests covering: basic resolution (string/number/boolean/color), all compound types (padding 3 variants, cornerRadius 2 variants, sizing, fills shorthand/color/gradient/mesh, stroke uniform/per-side/miterAngle/fill, effects shadow/blur/offset, text plain/rich spans), common properties, frame gap/clip, ellipse, polygon, iconFont, gradient fill size, multiple fills/effects, variable chains, circular chain protection, themed variables (light/dark/default/lastMatchWins/multiAxis), external overrides, missing variable, type mismatch, nested children, int-as-double coercion, literal passthrough, variables dict preservation. |

**Deviations from the original plan:**

1. **Theme matching separates defaults from specifics.** `PenThemedValue` entries with `theme: nil` (defaults) are only used as fallback when no specific themed value matches. Specific matches (non-nil theme) take priority. Among specific matches, last-match-wins. This prevents a default value from shadowing a valid specific match.

2. **Circular chain detection uses two-pass approach.** First pass identifies all keys involved in cycles (walks chains and marks cycle participants). Second pass resolves non-cyclic chains to their terminal values. This eliminates non-determinism from dictionary iteration order.

3. **Variables dict preserved on output.** The resolved document keeps its `variables` dictionary intact for downstream inspection (e.g., UI binding to variable names/types).

**Key implementation details for the next agent:**

- **PenFill.shorthand `$variable` resolution:** Shorthand strings starting with `$` are variable references to color values. The resolver strips the `$`, looks up the variable, and replaces the shorthand string if the result is a `.string(colorString)`.

- **PenSizing.variable resolution:** When a sizing variable resolves to a number (`.double` or `.int`), it becomes `.fixed(Double)`. Otherwise stays as `.variable`.

- **AnyCodable extraction handles int-as-double:** `AnyCodable.int(16)` resolves for `PenValue<Double>` by converting to `Double(16)`.

- **Resolver architecture — one helper per compound type:** The tree walk uses a dispatcher (`resolveKind`) that pattern-matches on `PenNode.Kind` and delegates to kind-specific resolvers (`resolveFrameData`, `resolveTextData`, etc.). Each of these calls shared compound resolvers (`resolveFills`, `resolveStroke`, `resolveEffects`, etc.). Adding a new node type or property requires: (1) add the kind-specific resolver, (2) add a case to `resolveKind`, (3) call the appropriate compound resolvers for its properties. The entire resolver is ~400 lines due to the mechanical nature of this walk.

- **RefData and unknown kinds are NOT resolved:** The resolver skips `.ref` nodes (their `ref` field is a plain String, not a `PenValue`, and their `descendants` are raw `AnyCodable`). It also skips `.unknown` nodes (their properties are `[String: AnyCodable]`, not typed). This is intentional — ref expansion happens after variable resolution in the pipeline, and unknown nodes can't be walked without knowing their structure.

- **Pipeline integration point:** The resolver runs between parser and ref expander: `parse → resolve → expand → layout → render`. This means the ref expander receives a document where all variable references in the existing tree are already resolved. However, variables inside descendant overrides (which are raw `[String: AnyCodable]`) are NOT resolved by the variable resolver — they'd need resolution after the override is applied. Currently this isn't an issue because overrides in the fixture use literal values, but a future enhancement might need to run resolution again after expansion, or resolve within the override dicts.

### Step 6: Ref Expander (Done)

Created 2 artifacts + 1 fixture:

| File | What it provides |
|------|-----------------|
| `PenRefExpander.swift` | Stateless `nonisolated enum` that expands ref nodes and strips reusable definitions. Three-phase algorithm: (1) build component registry by scanning for `reusable: true` nodes, (2) expand ref nodes by cloning target component, applying descendant overrides, prefixing IDs, and transferring ref node's positional properties, (3) strip reusable definitions from output. Descendant overrides use JSON round-trip: encode existing node → merge patch properties → re-decode as PenNode. Object replacement (override with `type` field) builds new node from override properties + original ID. |
| `PenRefExpanderTests.swift` | 17 tests covering: simple expansion, correct output type, position inheritance, ID prefixing (root + children), descendant overrides (property patch, multi-property, enabled), multiple instances (distinct prefixes, no overlap), reusable stripping, nested ref expansion, missing ref target, circular ref protection, no-refs passthrough, name preservation, override isolation (only affects matching descendant), component dimension inheritance. |
| `Fixtures/expander-nested-ref.pen` | Nested ref fixture: badge component (reusable), button component (reusable, contains ref to badge with override), nav-button ref (to button with override). Tests two levels of ref nesting with overrides at each level. |

**Key implementation details:**

- **JSON round-trip for overrides:** Descendant overrides are raw `[String: AnyCodable]` dicts. Rather than manually patching each property, the expander encodes the existing node to JSON, merges override properties on top, and re-decodes. This leverages all existing Codable infrastructure and handles any property type.

- **ID prefixing uses `/` separator:** Expanded node IDs follow `refNodeID/originalNodeID`. For nested expansions, prefixes chain: `outer/inner/nodeID`.

- **Circular ref protection via visited set:** Each expansion pass tracks visited component IDs. If a ref points to an already-visited component, the ref node is left unchanged (not expanded).

- **Overrides applied before ID prefixing:** Descendant overrides use original (non-prefixed) node IDs, so overrides must be applied before prefixing.

- **JSON round-trip trade-off:** The `patchNode` method encodes the entire node to `[String: AnyCodable]`, merges override properties, and re-decodes. This is elegant (reuses all Codable logic, handles any property) but has a cost: PenNode's Codable uses CodingKeys mappings (e.g. `fills = "fill"`, `effects = "effect"`). When the node is encoded, the JSON uses the CodingKeys names (`fill`, `effect`), and when the override dict uses the same keys, the merge works correctly. If an override used the Swift property name instead of the JSON key (e.g. `"fills"` instead of `"fill"`), it would silently fail. This hasn't been an issue because overrides come from .pen JSON (which uses the JSON keys), but it's worth knowing if you ever construct overrides programmatically.

- **`mapChildren` helper:** A utility that maps a transform over a node kind's children array while preserving the kind. Only `frame` and `group` have children. If a future node type adds children, update `mapChildren`, `nodeChildren`, and the resolver's `resolveKind` dispatcher.

- **Transfer of common properties from ref to expanded root:** The expander copies positional properties (x, y, rotation, opacity, enabled, flipX, flipY, name) from the ref node to the cloned component root, with ref properties taking precedence when non-nil. The `reusable` flag is always set to `nil` on the expanded root to prevent it from being mistakenly stripped.

**What the next agent needs to know for Step 7 (Layout Fixtures):**

- Steps 5 and 6 complete the "transform" phase of the pipeline. The next step (7) generates layout fixtures using Pencil MCP, and Steps 8-9 implement the layout engine that consumes those fixtures.

- The resolver and expander are both tested with programmatically constructed `PenDocument` values (not fixture files), so they don't depend on any specific fixture structure. The existing parser fixtures (`parser-variables.pen`, `parser-themed-variables.pen`, `parser-reusable-ref.pen`) test parsing, not resolution or expansion.

- After expansion, the document is a flat tree of concrete nodes (no refs, no reusable definitions, all variables resolved where possible). This is what the layout engine will receive.

### Step 7: Generate Layout Fixtures from Pencil MCP (Done)

Generated 25 layout fixture triplets using Pencil MCP as the ground-truth oracle:

| Category | Fixture name | What it exercises |
|----------|-------------|-------------------|
| **Positioning** | `layout-absolute` | `layout: "none"`, children at explicit x/y |
| **Stacking** | `layout-horizontal` | Default horizontal layout, 3 fixed-width children |
| | `layout-vertical` | Vertical layout, 3 fixed-height children |
| **Gap** | `layout-gap` | Horizontal layout with `gap: 16` |
| **Padding** | `layout-padding-uniform` | `padding: 24` (all sides) |
| | `layout-padding-2val` | `padding: [16, 24]` (vertical, horizontal) |
| | `layout-padding-4val` | `padding: [8, 16, 24, 32]` (top, right, bottom, left) |
| **justifyContent** | `layout-justify-start` | Default — children packed to start |
| | `layout-justify-center` | Children centered on main axis |
| | `layout-justify-end` | Children packed to end |
| | `layout-justify-space-between` | Equal space between children |
| | `layout-justify-space-around` | Equal space around each child |
| **alignItems** | `layout-align-start` | Children aligned to start of cross axis |
| | `layout-align-center` | Children centered on cross axis |
| | `layout-align-end` | Children aligned to end of cross axis |
| **fill_container** | `layout-fill-container` | Single child fills parent width |
| | `layout-multi-fill` | Three fill_container children split equally |
| | `layout-mixed-fill` | Two fixed + one fill_container gets remainder |
| **fit_content** | `layout-fit-content` | Parent sizes to children (no fallback) |
| | `layout-fit-content-fallback` | `fit_content(200)` with no children — fallback used |
| **fill fallback** | `layout-fill-fallback` | `fill_container(150)` in non-layout parent — fallback used |
| **Nesting** | `layout-nested` | Vertical frame containing horizontal rows |
| | `layout-deep-nesting` | 4 levels: vertical → horizontal → vertical → horizontal |
| **Corner cases** | `layout-zero-children` | Empty frame with explicit dimensions |
| | `layout-single-child` | Single child with `justifyContent: center` + `alignItems: center` |

Each fixture is a triplet: `.pen` (input JSON) + `.layout.json` (Pencil's computed layout rects as ground truth) + `.png` (Pencil's rendered screenshot for visual reference).

**Workflow used:**
1. `batch_design` to create each minimal test structure
2. `snapshot_layout` to capture Pencil's computed layout rects
3. `batch_get` to export the canonical .pen JSON
4. Wrote `.pen` (wrapped in `PenDocument` with `version: "0.0.1"`) and `.layout.json` (flat `{ nodeId: { x, y, width, height } }`) to `FirstPassProTests/Fixtures/`

**Key observations from Pencil's layout behavior:**
- Frames default to `layout: "horizontal"` (not `"none"`) — omitting `layout` gives you a horizontal flex container
- `fit_content` normalizes to `fit_content(0)` when no fallback specified
- `space_around` produces fractional pixel values (e.g. `36.666...`) — our engine will need floating-point tolerance
- `fill_container` in a non-layout parent uses the fallback value (confirmed: 150px fallback used)
- `padding: [h, v]` maps to `padding: [vertical, horizontal]` — first value is vertical (top/bottom), second is horizontal (left/right)

**Screenshots (.png) captured** at 1x scale for all 25 fixtures. These serve as visual reference for renderer validation (Phase 2) and quick visual debugging during layout engine development.

**Text fixtures excluded from Pencil ground truth.** Pencil doesn't support SF Pro (Apple-only font), and its text rasterizer (likely Skia/web-based) will produce different measurements than our CTFramesetter-based measurer regardless of font. Text measurement will be tested independently in Step 8 using known CTFramesetter outputs. The layout fixtures cover only non-text layout behavior (positioning, stacking, gap, padding, justify, align, fill/fit sizing, nesting).

### Step 8: Text Measurer (Done)

Created 2 artifacts:

| File | What it provides |
|------|-----------------|
| `PenTextMeasurer.swift` | Stateless `nonisolated enum` wrapping CTFramesetter. Measures text bounding boxes given font properties (family, size, weight, style, letterSpacing, lineHeight) and optional maxWidth for wrapping. Uses pure CoreText APIs (CFAttributedString, CTParagraphStyle) for cross-platform compatibility. Default font: SF Pro at 16pt. Font resolution via CTFontDescriptor with weight traits + `CTFontCreateCopyWithSymbolicTraits` for italic. Output sizes are ceil'd to avoid sub-pixel clipping. |
| `PenTextMeasurerTests.swift` | 20 tests covering: empty string, single-line measurement, longer-is-wider, font size scaling, default font/size, custom font family, bold weight, CSS weight mapping (10 named + numeric values), unknown weight fallback, text wrapping with maxWidth, large maxWidth passthrough, nil maxWidth single-line, positive/negative letter spacing, custom line height, SF Pro resolution, italic resolution, unknown family fallback, deterministic repeated measurements (both single-line and wrapped). |

**Key implementation details:**

- **Pure CoreText API:** Uses `CFAttributedStringCreate` + `CTFramesetterCreateWithAttributedString` + `CTFramesetterSuggestFrameSizeWithConstraints`. No AppKit/UIKit dependency — works on macOS, iOS, and potentially Linux with swift-corelibs.

- **Font resolution:** Builds a `CTFontDescriptor` with family name and weight trait, then applies italic via `CTFontCreateCopyWithSymbolicTraits`. Falls back gracefully if the requested variant doesn't exist.

- **Weight mapping:** CSS weight strings ("100"-"900", "thin", "bold", etc.) map to CoreText weight values (-0.6 to 0.5). Unknown values default to 0.0 (normal).

- **Line height:** Uses `CTParagraphStyle` with `minimumLineHeight` and `maximumLineHeight` set to `fontSize * lineHeight` multiplier. Created via `CTParagraphStyleCreate` with unsafe pointer to the CGFloat value.

### Step 9: Layout Engine (Done)

Created 2 artifacts + 1 bug fix:

| File | What it provides |
|------|-----------------|
| `PenLayoutEngine.swift` | Stateless `nonisolated enum` implementing a combined measure/arrange recursion. Extracts uniform `NodeLayoutProperties` from any node kind, then dispatches to leaf, absolute-container, or flex-container layout paths. Handles: horizontal/vertical stacking, gap, padding (uniform/symmetric/individual), justifyContent (start/center/end/spaceBetween/spaceAround), alignItems (start/center/end), fill_container (equal distribution among siblings), fit_content (size to children with fallback), and arbitrary nesting depth. |
| `PenLayoutEngineTests.swift` | 27 tests: 25 parameterized fixture tests (one per Pencil MCP ground-truth triplet) with 0.5px tolerance, plus 2 edge case tests (empty document, leaf-only document). |
| `PenPadding.swift` (bug fix) | Fixed 2-value symmetric padding Codable to match CSS/Pencil convention: `[vertical, horizontal]`, not `[horizontal, vertical]`. |

**Bug fix: PenPadding symmetric Codable mapping.**

The `layout-padding-2val` fixture (`padding: [16, 24]`, children at `x=24, y=16`) revealed that `PenPadding.init(from:)` had the 2-value array mapping backwards. The .pen format follows CSS convention where `[16, 24]` means vertical=16, horizontal=24. The code was mapping `array[0]` to `h` (horizontal) instead of `v` (vertical). Fixed both decode and encode. Updated 2 existing model tests.

**Key implementation details:**

- **Combined measure+arrange recursion:** Rather than two separate passes, a single recursive `layoutNode` function passes available space down (for `fill_container`) and bubbles content size up (for `fit_content`). This handles the bidirectional dependency naturally.

- **Three layout paths:** `layoutLeafNode` (fixed sizes), `layoutAbsoluteContainer` (layout: none, children at explicit x/y, fill_container uses fallback), `layoutFlexContainer` (horizontal/vertical flex with gap/padding/justify/align).

- **fill_container distribution:** Remaining main-axis space after fixed children and gaps is divided equally among fill_container children. Fill children are then re-measured recursively with their resolved available space to handle nested fit_content containers.

- **justifyContent + gap interaction:** Free space is computed as `contentSize - totalChildrenSize - totalGaps`. The gap between children is additive with justify spacing. For spaceBetween: `effectiveSpacing = gap + freeSpace/(count-1)`. For spaceAround: `chunk = freeSpace/count`, `startOffset = chunk/2`, `effectiveSpacing = gap + chunk`.

- **Text measurement deferred:** The layout engine does not call PenTextMeasurer. Text nodes use their `width`/`height` sizing properties like any leaf node. Text measurement integration will be added when text-specific layout fixtures are created.

**Deviations from the original plan:**

1. **Combined recursion instead of two-pass.** The original plan called for a separate measure pass (bottom-up) then arrange pass (top-down). In practice, `fill_container` requires parent-available space (top-down) while `fit_content` requires child sizes (bottom-up). A single recursive `layoutNode(node, availableWidth, availableHeight) → (size, rects)` handles both directions naturally by passing available space down and returning computed size up. A true two-pass approach would have required an intermediate data structure to store partial measurements, adding complexity for no benefit.

2. **Three layout dispatch paths, not one.** The original plan described a single `arrangeNode` function. The implementation splits into `layoutLeafNode`, `layoutAbsoluteContainer`, and `layoutFlexContainer` — this is cleaner because absolute and flex layout have almost nothing in common (absolute just places children at x/y, flex does gap/padding/justify/align distribution). Leaf nodes are trivially different too (no children to recurse into).

3. **No separate `MeasuredSize` type.** The plan proposed a `MeasuredSize` struct for intermediate results. Instead, `ChildMeasurement` bundles the measurement with the node reference and flex flags, and the recursive `layoutNode` returns a simple `(size: (width: Double, height: Double), rects: [String: PenRect])` tuple. This avoided an extra type without losing clarity.

4. **fill_container children re-measured after space distribution.** When a `fill_container` child is itself a container (e.g., a frame with fit_content height), we must re-measure it after resolving its main-axis size, because its cross-axis size may depend on the resolved main size (e.g., nested children that wrap). The initial measurement uses `nil` available space; after fill distribution, a second `layoutNode` call with the resolved available space produces the correct sizes.

5. **No protocol for extracting sizing.** The plan considered a protocol to extract width/height from different node kinds. The switch-based `extractLeafWidth`/`extractLeafHeight` approach was chosen instead, consistent with the variable resolver's pattern. Adding a new node type requires adding a case to each switch — mechanical but explicit.

**What the next agent needs to know for Step 10 (Documentation):**

- **The layout engine is ~280 lines** and follows the same stateless `nonisolated enum` pattern as PenParser, PenVariableResolver, PenRefExpander, and PenTextMeasurer. The public API is a single `layout(_:) -> [String: PenRect]` method.

- **The layout engine does NOT integrate with PenTextMeasurer yet.** Text nodes are treated as leaf nodes with explicit width/height sizing. To add text intrinsic sizing, modify `layoutLeafNode` (or `extractLayoutProperties`) to detect `.text` kind and call `PenTextMeasurer.measure()` when sizing is `fitContent`. This will also need new text-specific layout fixtures with platform-appropriate ground truth (Core Text produces different measurements than Pencil's web-based renderer).

- **`layoutPosition: .absolute` children are excluded from flex flow** but still laid out. They use their explicit x/y within the parent's content area. This matches CSS `position: absolute` behavior within a flex container.

- **The `NodeLayoutProperties` extraction uses the same defaults as Pencil:** layout defaults to `.horizontal` (not `.none`), justifyContent defaults to `.start`, alignItems defaults to `.start`, gap defaults to `0`, sizing defaults to `.fitContent(fallback: nil)`. These defaults were validated against all 25 Pencil fixtures.

- **Double-counting avoidance in flex layout:** When a `fill_container` child is also a container, `layoutNode` is called twice: once during initial measurement (to get non-fill children's sizes), and once after fill space distribution (to get the final layout). The second call's rects overwrite the first's via `merge(_:uniquingKeysWith:)`. This is correct because the second call has the resolved available space.

### Step 10: Documentation (Done)

Created 3 artifacts + 1 update:

| File | What it provides |
|------|-----------------|
| `Sources/Woodcase/Documentation.docc/Woodcase.md` | DocC landing page with Topics groups organizing the full public API into categories: Pipeline Stages, Document Model, Value Types, Visual Properties, Variables, Enumerations. |
| `Sources/Woodcase/Documentation.docc/PenEngine.md` | DocC article covering the full pipeline: parsing (with node type table), variable resolution (theme matching, chains, overrides), ref expansion (cloning, overrides, ID prefixing, stripping), layout engine (three paths, sizing modes, flex properties, defaults), text measurement, and forward compatibility. |
| `project/Architecture.md` | Project-level architecture document: source tree, design patterns (stateless enums, PenValue\<T\>, flat Codable, discriminated unions), pipeline data flow diagram, testing strategy table (6 suites, 217 tests), key decisions. |
| `README.md` | Added Documentation section with links to Architecture.md and PenEngine.md, plus `swift package generate-documentation` command. |

Also added `swift-docc-plugin` dependency to `Package.swift` for DocC generation support.

## Gotchas Discovered During Implementation

1. **Codable + Friendly:** When a type declares `: Friendly` (which includes Codable), you **cannot** re-declare Codable in an extension. Provide `init(from:)` and `encode(to:)` in a plain `extension Foo {` instead of `extension Foo: Codable {`.

2. **PenValue generics:** `PenValue<T: Friendly>` must declare protocol conformances explicitly (`Sendable, Equatable, Hashable, Codable`) rather than using the `Friendly` typealias, because Swift doesn't allow a generic enum to conform to a typealias that includes protocols requiring associated type conformance from its generic parameter. The constraint `T: Friendly` ensures all conformances are satisfiable.

3. **Raw string literals with hex colors:** `#"..."#` raw strings break when the content contains hex colors like `#FF0000`. Use `##"..."##` (double-pound) raw strings instead.

4. **SourceKit false positives:** SourceKit shows many "Cannot find type 'Friendly' in scope" errors on new files before the project is fully indexed. These are false — the real compiler handles the typealias fine. Always verify with `xcodebuild build` rather than trusting SourceKit diagnostics on new files.

5. **Cannot mix container types on a single decoder/encoder.** Swift's JSONDecoder/JSONEncoder do not allow calling both `singleValueContainer()` and `container(keyedBy:)` on the same decoder. The original plan for unknown node decoding tried `singleValueContainer().decode([String: AnyCodable].self)` after already using `container(keyedBy:)` for `id`/`type` — this would crash at runtime. The fix is a `DynamicKey: CodingKey` struct that lets you iterate `allKeys` on a keyed container with runtime-determined key names. Same pattern works for encoding.

6. **Themed variable matching must separate defaults from specifics.** The .pen spec says `theme: nil` is a default used when no themed value matches. If you treat nil as "always matches" and use last-match-wins, a default placed after specific values will shadow them. The fix: collect specific matches and default matches separately; prefer specific, fall back to default.

7. **Circular variable chain detection must be deterministic.** Dictionary iteration order varies between runs. If you process chains one-at-a-time and remove cycle participants as you find them, the removal of one key can break the cycle detection for another key. The fix: two-pass approach — first pass identifies ALL cycle participants, then remove them all, then second pass resolves remaining chains.

8. **Ref expander descendant overrides must be applied before ID prefixing.** Descendant overrides use original (non-prefixed) node IDs from the component definition. If you prefix IDs first, override keys won't match. Apply overrides on the clone first, then prefix all IDs.

9. **Enum Codable auto-synthesis limits.** Swift can't auto-synthesize Codable for enums with heterogeneous associated values (e.g. `Kind` has both `FrameData` and `(String, [String: AnyCodable])`). You must provide explicit `init(from:)` and `encode(to:)`. For `PenNode.Kind`, since all Codable dispatch happens in PenNode itself, the Kind stubs just throw — they should never be called directly.

10. **PenPadding 2-value array follows CSS convention, not intuitive order.** The .pen format's `padding: [a, b]` means `[vertical, horizontal]` (matching CSS shorthand), not `[horizontal, vertical]`. The original Codable mapped `array[0]` to `h` — this was wrong and only caught when layout fixture tests compared computed positions against Pencil's ground truth.

## File Inventory

```
Sources/Woodcase/
├── Friendly.swift
├── Models/
│   ├── AnyCodable.swift           ✅ Done
│   ├── PenEnums.swift             ✅ Done
│   ├── PenValue.swift             ✅ Done
│   ├── PenSizing.swift            ✅ Done
│   ├── PenRect.swift              ✅ Done
│   ├── PenPadding.swift           ✅ Done
│   ├── PenFill.swift              ✅ Done
│   ├── PenStroke.swift            ✅ Done
│   ├── PenEffect.swift            ✅ Done
│   ├── PenTextStyle.swift         ✅ Done
│   ├── PenVariable.swift          ✅ Done
│   ├── PenCornerRadius.swift      ✅ Done (Step 3)
│   ├── PenDescendantOverride.swift ✅ Done (Step 3)
│   ├── PenNode.swift              ✅ Done (Step 3)
│   └── PenDocument.swift          ✅ Done (Step 3)
├── PenParser.swift                ✅ Done (Step 4)
├── PenVariableResolver.swift      ✅ Done (Step 5)
├── PenRefExpander.swift           ✅ Done (Step 6)
├── PenTextMeasurer.swift          ✅ Done (Step 8)
├── PenLayoutEngine.swift          ✅ Done (Step 9)
└── Documentation.docc/
    ├── Woodcase.md                ✅ Done (Step 10)
    └── PenEngine.md              ✅ Done (Step 10)

Tests/WoodcaseTests/
├── PenModelTests.swift            ✅ 69 tests passing
├── Fixtures/                      ✅ 91 fixtures (15 parser + 1 expander + 25 layout .pen + 25 layout .layout.json + 25 layout .png)
├── PenParserTests.swift           ✅ 37 tests passing (Step 4)
├── PenVariableResolverTests.swift ✅ 47 tests passing (Step 5)
├── PenRefExpanderTests.swift      ✅ 17 tests passing (Step 6)
├── PenTextMeasurerTests.swift     ✅ 20 tests passing (Step 8)
└── PenLayoutEngineTests.swift     ✅ 27 tests passing (Step 9)

project/
└── Architecture.md                ✅ Done (Step 10)
```

## Reference Documents

- **Design doc:** `project/2026-03-21-pen-title-system.md` — full architecture, data model, HDR, expressions, editing model
- **Test corpus:** `project/2026-03-22-pen-test-corpus.md` — test matrix, fixture generation plan, validation strategy
- **Pen format spec:** https://docs.pencil.dev/for-developers/the-pen-format
- **Existing patterns to follow:**
  - Tagged Codable enum: `FirstPassPro/GraphicsEngine/Models/GraphicParamDef.swift`
  - Forward-compat unknown: `FirstPassPro/GraphicsEngine/Models/GraphicParamType.swift`
  - Stateless nonisolated enum: `FirstPassPro/GraphicsEngine/CSSColorParser.swift`
  - Swift Testing: `FirstPassProTests/GraphicParamTypeTests.swift`
