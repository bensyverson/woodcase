# 2026-09-26 — A SwiftUI emitter: feasibility, lift, and the loop that verifies it

**Verdict: feasible, and the right second target. It is about as big as the React emitter was, about 14 leaves. The riskiest part is layout: flexbox semantics against SwiftUI's stack negotiation, around text.** The measured fidelity is better than expected.
Hand-written SwiftUI, in the shape an emitter would produce and rendered with `ImageRenderer`, matches Pen's own PNGs. Layout
fixtures come out at MAE **0.000**. The gradient board is at **0.135**, beside the CoreGraphics renderer's 0.133. The effects
board is at **0.59**, where the CG renderer gets 1.12. The text board is at **3.17**, where CG gets 2.57. Two findings from those
renders change the March mapping: SwiftUI's default gradient interpolation is wrong for Pen (MAE 10.7), and so is its automatic
optical sizing of variable fonts. Both have one-line fixes, and both are in the tables below. A second target *does* force a refactor. Today's codegen has no
intermediate representation. The React emitter walks `PenNode` straight to strings, and several target-neutral decisions live inside
`ReactEmitter` extensions or leak CSS into the shared analysis types (§1.2). The render-and-compare loop is cheap, at about 1 s per view in
the Swift interpreter and about 6 s for a batch of 20 views. The library stays Foundation-only, because SwiftUI only ever appears in the
emitted *text* and in a macOS-only test that shells out to the toolchain (§4.4). The first slice is frames, rectangles and text, with a
support file, goldens, and a render test over the 25 `layout-*` fixtures that have Pen PNGs and `render-text` (§6).

Leaf `dH7FN6`, under `n42KDh`. The machine was **loaded** throughout: four or more sibling agents were building Swift, and the load
average was 10–28. Every timing is the minimum of 2–3 runs. Read the timings as ratios, not as absolute speeds.

## 1. The lift

### 1.1 What exists (measured with `wc -l`, main at 64f73d2)

| Part | Files | Lines |
|---|---|---|
| `Sources/Woodcase/CodeGen/*.swift` (the shared analysis: analyzers, definitions, diffing, prop mapping, theme, packaging) | 19 | 2,242 |
| `Sources/Woodcase/CodeGen/React/*.swift` (the emitter, its state CSS, harness builder, manifest, icon mapping) | 36 | 5,415 |
| Codegen tests (`Tests/WoodcaseTests/{React*,*Emit*,Theme*,StateEmit*,Manifest*,Component*,Page*,PropMapper*,NodeDiff*,RoleState*,Package*,Viewer*}`) | 40 | 10,999 |
| Goldens (`Fixtures/golden/`, including `mesh/`, `pages/`, `paints/`) | 20 | — |

`git log -- Sources/Woodcase/CodeGen` shows 42 commits: 27 on 2026-03-28 to 03-31, and 15 in the paint and mesh waves of August and September.

### 1.2 What is target-neutral, what is React, and where it fails to generalize

**Reusable as is.** These carry over unchanged: `ComponentAnalyzer` (components, `_props` → `PropDefinition`, roles, actions,
bindings), `ComponentAnalyzer+DescendantPath`, `PageAnalyzer`, `ThemeAnalyzer`/`ThemeManifest`, `NodeDiffer`, `StateDelta`/`DeltaProperty`
(already documented as platform-neutral), `PenNodePatcher` inlining for unmapped overrides, the three `codegen-*` lint rules,
`PenVariableResolver`, and the pure mesh core (`PenMeshGrid`, `PenMeshRasterizer`, `PortablePNGEncoder`). That is roughly 1,700 of the 2,242 shared lines.

**Where today's codegen fails to generalize.** A second target forces all five of these:

1. **There is no IR.** March's summary proposed a "shared intermediate representation" worth "~70% of the translation logic". It was
   never built. `ReactEmitter+Nodes.swift` switches on `node.kind`, and each `emit*` function appends JSX lines to `EmitContext.lines`. The
   *decisions* that are really about Pen are compiled into React extensions:
   - `PaintRoute`, which picks solid, painted or none;
   - `RadialGeometry` and `GradientOutset`, which hold Pen's gradient geometry in the node box;
   - `MeshThemes`, which finds the theme combinations a mesh depends on;
   - `StrokeRing`, which holds the stroke outset per alignment;
   - `FillBox`.

   SwiftUI needs every one of those decisions and none of the CSS they are phrased in.
   Recommendation: **do not build a full IR up front.** Extract a neutral `CodeGen/Paint/` layer only where the second emitter needs the same decision
   (rule of two). Its first contents are the paint route, gradient geometry in Pen's unit box (CSS wants an angle; SwiftUI wants two
   `UnitPoint`s, and both come from one map), mesh theme resolution, and stroke outsets. The React goldens are the safety net for this refactor, because it must not move
   one byte of React output.
2. **CSS leaks into the shared model.** `StateTrigger.pseudoClass(":hover")` and `.dataAttribute(...)` put CSS selectors in
   `StateDefinition`, and `RoleStateMapping.trigger` returns them. SwiftUI's triggers are `ButtonStyleConfiguration.isPressed`,
   `.onHover`, `@Environment(\.isEnabled)` and `@FocusState`. The trigger should name the *state*: `.hover`, `.pressed`, `.disabled`, `.focused`, or an attribute
   with a name and value. Each emitter then maps that to its own selector or API.
3. **JSX formatting in a shared type.** `PropMapper.MappedProp.jsValue` formats values as `"var(--x)"` or `{false}`. The mapper should return a typed value
   (a string, a colour literal or variable, a bool, an image URL), and each emitter should format it.
4. **CoreGraphics in the geometry the emitter needs.** `PenSVGPathParser` and `PenShapeBuilder` `import CoreGraphics` and return
   `CGPath`. React never needed them, because it hands SVG the `d` string. SwiftUI must emit `Path` code, and the emitter must build on Linux, so the parser needs splitting into
   a CG-free command model (the parse) and a CG builder (the render). The polygon and arc/donut geometry needs the same split. This is also a gain for the library's Linux story.
5. **Web-only packaging.** `ThemeEmitter`, `ThemedCustomProperty` (`css`), `FontsourceMapping`, `IconLibraryMapping` (npm), `PackageScaffolder` (npm),
   `ViewerScaffolder` (Vite) and `ReactHarnessBuilder` stay React's. `ManifestEmitter` sits under `React/` but is neutral, so move it.
   `EmitResult` is fine for both.

No protocol is needed over the two emitters (*just enough abstraction*). `SwiftUIEmitter.emit(document:components:pages:theme:options:diagnostics:)`
mirrors `ReactEmitter`'s signature, and `woodcase generate swiftui` sits beside `woodcase generate react`.

### 1.3 Feature map: .pen → SwiftUI

Grades are **exact** (measured, or exact by construction), **approx** (a known, bounded difference), or **impossible** (no faithful
construct). "Support" means a small helper in one generated `PenSupport.swift`, which the emitter writes once per output. OS versions are
the API's introduction, read from the SDK's symbol graph (§3), and are iOS / macOS. Measured rows cite §4.

**Layout**

| .pen | SwiftUI | Grade | Min OS |
|---|---|---|---|
| `layout: horizontal/vertical`, `gap` | `HStack/VStack(alignment:spacing:)` | exact — `layout-nested` MAE 0.000 | 13 / 10.15 |
| `alignItems` | stack `alignment:` (`.top/.center/.bottom`, `.leading/…`) | exact | 13 / 10.15 |
| `justifyContent: start/center/end` | `.frame(maxWidth: .infinity, alignment:)` on the stack | exact by construction | 13 / 10.15 |
| `justifyContent: space_between` | `Spacer(minLength: 0)` between children | exact — MAE 0.000 | 13 / 10.15 |
| `justifyContent: space_around` | support `PenFlex: Layout` (Pen's distribution; prototype in `scripts/swiftui-fixture-probe.swift`) | exact by construction | **16 / 13** |
| `padding` (1, 2, 4 values; variables) | `.padding(EdgeInsets(...))` | exact | 13 / 10.15 |
| `width/height` fixed | `.frame(width:height:)` | exact | 13 / 10.15 |
| `fill_container` | `.frame(maxWidth: .infinity)`; in a `layout: none` parent, the fallback | exact for single fills; **approx** where several fill children compete with wrapping text (SwiftUI offers space by flexibility, not flex-grow) | 13 / 10.15 |
| `fit_content`, with fallback | intrinsic size; fallback → `minWidth:` | approx — the same text-negotiation caveat | 13 / 10.15 |
| `layout: none` + child `x/y` | `ZStack(alignment: .topLeading)` + `.offset(x:y:)`, frame sized | exact for fixed frames (`clip-frame` 0.21); a *fit-content* `none` frame needs support `PenAbsolute: Layout` to size to the children's union | 16 / 13 |
| `layoutPosition: absolute` | `.overlay(alignment: .topLeading) { child.offset(...) }` | exact | 15 / 12 |
| "wrap" | — | not a Pen feature (no wrap key in the 2.17 schema) | — |

**Text and fonts**

| .pen | SwiftUI | Grade | Min OS |
|---|---|---|---|
| `fontFamily/fontSize/fontWeight` | `.font(.custom(family, size:).weight(...))` | approx — `render-text` MAE 3.61 as written; **3.17** with optical sizing pinned off (see below); CG renders the same reference at 2.57 | 13 / 10.15 |
| variable fonts (Inter `opsz`) | `Font(CTFont)` from a descriptor with `kCTFontOpticalSizeAttribute: "none"` (support) | **March missed this.** CoreText applies optical size automatically and Pen does not: pinning it off cut MAE 3.61 → 3.17 | 13 / 10.15 |
| `fontStyle: italic` | `.italic()` | exact | 13 / 10.15 |
| `letterSpacing` | `.tracking(_:)` | exact by construction | 13 / 10.15 |
| `lineHeight` (a multiple of font size) | `.lineHeight(.exact(points: size × m))` | exact line pitch (28 pt measured) | **26 / 26** |
| `lineHeight` below 26 | `.lineSpacing(size × m − natural)` via a support modifier that branches on `#available` | approx — no half-leading above the first line | 13 / 10.15 |
| `textAlign: left/center/right` | `.multilineTextAlignment` + frame alignment | exact | 13 / 10.15 |
| `textAlign: justify` | none: `TextAlignment` and iOS 26's `AttributedString.TextAlignment` are both left/center/right only | **impossible** in `Text` (falls back to leading, with a diagnostic) | — |
| `textAlignVertical` | `.frame(minHeight: h, maxHeight: h, alignment: .leading/.topLeading/…)` | exact | 13 / 10.15 |
| `textGrowth` auto / fixed-width / fixed-width-height | intrinsic / `.frame(width:)` + `.fixedSize(horizontal: false, vertical: true)` / both | exact by construction | 13 / 10.15 |
| `underline`, `strikethrough` | `.underline()`, `.strikethrough()` | exact (Pen strips them from painted text anyway) | 13 / 10.15 |
| paints on text (gradient, image, mesh, stack) | `.foregroundStyle(ShapeStyle)`; a stack via a `.mask { Text }` over layered backgrounds | approx until measured: the paint domain must be the node box, and `foregroundStyle` spans the text's own bounds | 15 / 12 |
| Google/custom fonts | the font files ship as package resources, registered with `CTFontManagerRegisterFontsForURL` in a support `PenFonts.register()` | exact | 13 / 10.15 |

**Fills**

| .pen | SwiftUI | Grade | Min OS |
|---|---|---|---|
| solid colour | `Color(.sRGB, red:green:blue:opacity:)` | exact | 13 / 10.15 |
| linear / radial / angular gradient | `.linearGradient/.ellipticalGradient/.angularGradient(Gradient(stops:).colorSpace(.device), …)` | **exact — MAE 0.135 (CG: 0.133)**, but *only* with `.colorSpace(.device)`. The default interpolation measures **10.69**. March rated these "exact" without it | 16 / 13 |
| gradient geometry | rotation *θ* (CCW) → `startPoint` = centre + ½(sin θ, cos θ), `endPoint` opposite; radial `endRadiusFraction: 0.5`; angular `startAngle: −90°` | exact on this board; off-centre, resized and rotated-ellipse cases untested | 15 / 12 |
| image fill (fill/fit/stretch) | `Image(...).resizable().scaledToFill()/scaledToFit()` in `.background`, clipped | exact by construction | 13 / 10.15 |
| mesh gradient | native `MeshGradient(width:height:bezierPoints:colors:smoothsColors: true, colorSpace: .device)`, **or** the baked 64 px raster React already makes | native: MAE 0.4–3.2, and 7.1 folded (mesh report §1). Baked: 0.33–0.68 | native **18 / 15** |
| multiple fills, blend modes, `opacity`, `enabled` | stacked `.background { }` layers, `.blendMode`, `.opacity`, omission | exact by construction | 15 / 12 |

**Strokes**

| .pen | SwiftUI | Grade | Min OS |
|---|---|---|---|
| inner | `InsettableShape.strokeBorder(_:lineWidth:)` | exact by construction | 13 / 10.15 |
| centre | `.stroke(_:lineWidth:)` | exact | 13 / 10.15 |
| outer, on rect/rounded rect/ellipse | `shape.inset(by: −w).strokeBorder(...)` | exact by construction (**March said "workaround"**) | 13 / 10.15 |
| outer or inner on a path/polygon | stroke at 2w, then `.mask`/`.clipShape` by the shape (the trick React's SVG uses) | exact by construction | 15 / 12 |
| per-side widths | a support `PenSideStroke: Shape` building the ring path (the geometry `PenStrokeRenderer` draws) | exact by construction; untested | 13 / 10.15 |
| caps, joins, dash | `StrokeStyle(lineWidth:lineCap:lineJoin:dash:)` | exact | 13 / 10.15 |
| paints on strokes | the stroke is any `ShapeStyle`: gradients, `ImagePaint`, `MeshGradient` | exact, and simpler than React's overlay/mask machinery | 13 / 10.15 |

**Effects, clip, blend, transforms** (`render-transforms-and-effects`, 2×, crop MAE each item ±12 pt; CG in brackets)

| .pen | SwiftUI | Grade | Min OS |
|---|---|---|---|
| outer shadow, no spread | `.shadow(color:radius: blur/2, x:y:)` on the filled shape | **exact-grade — 0.43 [CG 0.51].** `radius: blur` gives 3.44. The mapping is ½ | 13 / 10.15 |
| shadow spread | support modifier: `shape.inset(by: −spread)` filled, blurred and offset behind the node | approx until measured | 13 / 10.15 |
| inner shadow | `.fill(color.shadow(.inner(color:radius:x:y:)))` (a `ShadowStyle`) | built-in, **contrary to March** ("no built-in modifier"). Not measurable here: the committed 1.2.7 reference draws the inner shadow *outside* the node (compatibility report, finding 2); both SwiftUI and CG score 5.7 against it | **16 / 13** |
| layer blur | `.blur(radius: r/2)` | **exact-grade — 0.24 [CG 0.24]**; `radius: r` gives 4.97 | 13 / 10.15 |
| background blur | `.background(.ultraThinMaterial …)` | **approx at best.** SwiftUI has no radius-controlled backdrop blur, and `layerEffect` cannot sample what lies behind a view. Emit a Material and a diagnostic | 15 / 12 |
| clip | `.clipShape(RoundedRectangle/UnevenRoundedRectangle)` or `.clipped()` | exact — 0.21 [0.25] | 13 / 10.15 |
| per-corner radius | `UnevenRoundedRectangle` | exact (**16 / 13, not 17 as March said**) | 16 / 13 |
| node blend modes | `.blendMode(...)` inside a `.compositingGroup()` parent | exact — `multiply` 0.27 [0.32]. `linearBurn` = **`.plusDarker`** and `linearDodge` = **`.plusLighter`**, which are the same formulas, not approximations as March said | 13 / 10.15 |
| rotation | `.rotationEffect(.degrees(−θ))` inside `.frame(` rotated bbox `)`. `rotationEffect` does not change layout, and Pen does | exact — 0.10 [0.15] | 13 / 10.15 |
| flipX/flipY, opacity | `.scaleEffect(x: −1)`, `.opacity` | exact — 0.42 and 0.39 [0.41 and 0.11] | 13 / 10.15 |
| the whole board | — | **0.59** [CG 1.12] | — |

**Components, themes, icons, other nodes**

| .pen | SwiftUI | Grade | Min OS |
|---|---|---|---|
| reusable component | a `struct Name: View` with `let` props from `PropDefinition` (string → `String`, colour → `Color`, boolean → `Bool`, image → `URL`/`Image`) | exact | 13 / 10.15 |
| `ref` + overrides that map to props | `Name(title: "…")` | exact | 13 / 10.15 |
| unmapped overrides | inline the patched tree, as React does (shared `PenNodePatcher`) | exact | — |
| slots (`slot: [...]`) | a generic `Content: View` parameter with a `@ViewBuilder` init | exact | 13 / 10.15 |
| pages | a `struct` per top-level frame | exact | — |
| themes / variables | a generated `PenTheme` value in the environment (`@Entry var penTheme`). Each variable is a computed `Color`/`CGFloat` that switches on the axis values. A `context` node gives `.environment(\.penTheme, theme.with(mode: .dark))`. The `mode` axis can optionally follow `colorScheme` | exact by construction. March's "EnvironmentKey per axis" works too; `@Entry` is less code | 13 / 10.15 (`@Entry` is a macro that expands to an `EnvironmentKey`; it needs Xcode 16+, not a newer OS) |
| themed mesh | native `MeshGradient` reads theme colours directly (free); the baked path needs one image per theme combination, as React does | — | 18 / 15 |
| roles/states (`button`, `toggle`, `textInput`, `select`, `tabBar`) | `Button` + a generated `ButtonStyle` (pressed, disabled via `isEnabled`, hover via `.onHover`), `Toggle`, `TextField`, `Picker`; structural states as `if/else` branches | approx: hover exists only with a pointer (macOS/iPadOS) | 13 / 10.15 |
| icon (lucide, feather, phosphor, material) | `Text(codepoint).font(.custom(...))` with the icon font Woodcase already bundles (`IconFonts/Fonts`) copied into the package | exact (the same glyphs the CG renderer draws) | 13 / 10.15 |
| `browser` | WebKit's SwiftUI `WebView(url:)` (availability via sosumi.ai; WebKit is not in the symbol cache) | approx | 26 / 26 |
| `script` | a placeholder plus a diagnostic, as React does | — | — |
| path / polygon / arc / line | `Path` code from the CG-free parser (§1.2 item 4) | exact by construction | 13 / 10.15 |

**Corrections to the March note.** It was optimistic on gradients: they are "exact" only with `.colorSpace(.device)`, and cost 10.7 MAE
without it. It was optimistic on fonts: optical sizing was missed. It was optimistic on `justify`: impossible, not "fall back" with no
cost. And it was optimistic on background blur: no exact radius, not even through `UIViewRepresentable` in a cross-platform emitter.
It was **pessimistic** on four rows. Inner shadows are built in (iOS 16). Outer strokes on insettable shapes are exact. `linearBurn`
and `linearDodge` are exact through `plusDarker`/`plusLighter`. And the shadow and blur radius mapping is simply ½.
`UnevenRoundedRectangle` is iOS 16, not 17. `lineHeight` has had an exact API since iOS 26, which did not exist in March.

## 2. API churn

**The OS floor.** Generated code should target **iOS 18 / macOS 15** by default. That is Woodcase's own `Package.swift` floor, and it
includes `MeshGradient` and every API in §1.3 except `lineHeight(_:)` and `WebView`. The floor should be a typed emitter
option (`SwiftUIEmitter.Options.deploymentFloor`, an enum of supported floors), not a string.

**How availability is handled.** Availability branches live **only in `PenSupport.swift`**, never in a component's code. A component calls `.penLineHeight(28)`. The support modifier does
`if #available(iOS 26, macOS 26, *) { content.lineHeight(.exact(points:)) } else { … lineSpacing … }`. So a component file is
the same at every floor, and an OS bump means one edit in one file. The emitter keeps a small typed table of the APIs above the minimum
floor it might emit, which the support file consults. `MeshGradient` needs no branch at an 18/15 floor. Below it, the emitter would switch to the baked raster.

**Noticing when a new SDK moves something.** Three layers, cheapest first:
1. **Compile the goldens at the floor.** The render test (§4) compiles with `-target arm64-apple-macos15.0`. Measured: an unguarded
   `lineHeight` fails with `error: 'lineHeight' is only available in macOS 26.0 or newer`. That catches availability mistakes on every run.
2. **Audit the vocabulary against the symbol graph.** The compiler does **not** warn on Apple's soft deprecations. Measured: `foregroundColor(_:)`
   and `cornerRadius(_:antialiased:)` are both "deprecated in 100000" and compile silently at every target. `scripts/swiftui-api audit`
   reads a list of the dotted SwiftUI paths the emitter writes. It fails on a path that is missing, deprecated (hard *or* soft) or above the floor.
   A sample run flagged exactly those three cases. Keep that list beside the emitter, as a test resource.
3. **The render test itself.** A new SDK can change *rendering* (text layout, interpolation defaults) without changing any API. Only the MAE
   loop sees that.

**Maintenance cost.** SwiftUI ships as a library-evolution framework. Apple adds and soft-deprecates APIs but does not remove them, so
existing emitted code keeps compiling. The yearly cost is one leaf per Xcode major:
- run `swiftui-api fetch` and `audit`;
- run the render suite on the new Xcode and re-baseline any MAE that moved;
- decide whether a new API (like 2025's `lineHeight`) should replace a support-file approximation.

Call it half a day to a day. Where there is a gap in between, it is only "a better API exists", never "the code broke".

## 3. Documentation an agent can read

Each source was tried on 2026-09-26, with Xcode 27.0 (27A266a) and SDK 27.0 on macOS 27.0:

| Source | Tried | Readable? | Complete? |
|---|---|---|---|
| **The SDK's symbol graph** (`xcrun swift-symbolgraph-extract -module-name SwiftUI … -skip-synthesized-members`) | yes | **yes**: JSON with doc comments, declarations, per-platform availability, deprecations and renames | 10,952 declarations under 9,829 paths, **8,072 with doc comments**. It is exact for the installed SDK and offline, and takes 4 s to extract. It has no articles or tutorials. Without `-skip-synthesized-members` it is 493 MB (each `View` modifier is copied onto every conforming type); with it, 23 MB |
| `SwiftUI.swiftinterface` / `SwiftUICore.swiftinterface` | yes | yes | declarations and availability only: **zero** `///` lines in 61,752 |
| `.swiftdoc` | yes | binary; readable only through the symbol-graph tool above | — |
| **sosumi.ai** (a third-party Markdown mirror: `https://sosumi.ai/documentation/swiftui/<path>`) | yes (`curl`, host `sosumi.ai`) | **yes**: clean Markdown with availability, declaration, discussion, examples and see-also | the full Apple site, including articles. It is always the *latest* docs, not your SDK. It is a third party (availability and longevity are not ours) and needs network |
| Apple's DocC JSON (`https://developer.apple.com/tutorials/data/documentation/swiftui/meshgradient.json`) | yes (`curl`, sandboxed) | yes, but it is render JSON (nested inline-content nodes, 40 KB for one page), which needs flattening | first-party and complete; network |
| Xcode's `AdditionalDocumentation/*.md` (in `IDEIntelligenceChat.framework`) | yes | yes | 20 curated "what's new" notes, dated March 2026. Thin and hedged ("additional platform-specific options may be available") |
| Xcode's MCP (`xcrun mcpbridge`: `DocumentationSearch`, `RenderPreview`) | status only | `mcp-server status`: "Permission: disabled". Headless mode needs `sudo` and a running Xcode with a project open | not tried; it needs Ben to enable it |

**Recommendation: the symbol graph, through `scripts/swiftui-api`** (new). `fetch` extracts SwiftUI, SwiftUICore and CoreText once per
SDK into `local/swiftui-docs/<sdk>/index.json` (gitignored), in about 4 s with the sandbox off. `show <query>` prints a symbol's declaration, availability (flagging soft deprecations and renames) and
Apple's doc comment. `audit <list> --floor ios=18,macos=15` is §2's churn check. It answers questions *about the SDK the code will compile against*, which
no website does. Use **sosumi.ai as the second source**, for conceptual articles; it was the most readable remote source. Apple's DocC JSON is the fallback if sosumi goes away.

```
$ scripts/swiftui-api show 'Gradient.colorSpace(_:)'
## Gradient.colorSpace(_:)  [SwiftUICore Instance Method]
func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient
Available: iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0
Returns a version of the gradient that will use a specified
color space for interpolating between its colors.
…
```

## 4. The render-and-compare loop

### 4.1 Fidelity: is `ImageRenderer` good enough to compare against Pen?

**Yes.** `ImageRenderer` returns `kCGColorSpaceSRGB` images at exactly `scale ×` the view's points: 500×513 at 1×, and 1808×368 at 2× where the reference is 1808×368. The
colour arithmetic is Pen's once gradients use `.device`. Layout is pixel-exact. Text differs by font metrics, not by rendering quality.

Method. The SwiftUI below is hand-written the way the emitter would write it, rendered with `ImageRenderer` at the reference's
scale, and compared with `PenSnapshotTestHelpers.meanAbsoluteError`'s arithmetic: sRGB, premultiplied RGBA8, the mean over every channel of the overlapping area.
The CG column is the same comparison run on `.build/debug/woodcase render <fixture> --scale <1|2>`, from main's build of 2026-09-26 13:22. Reproduce it with
`xcrun swift scripts/swiftui-fixture-probe.swift` (sandbox off; it needs Inter in `~/.woodcase/fonts/inter`).

| Fixture (Pen PNG in `Tests/WoodcaseTests/Fixtures`) | SwiftUI variant | SwiftUI MAE | CG MAE |
|---|---|---|---|
| `render-text` (1×) | `Font.custom`, automatic optical size | 3.610 | 2.574 |
| | optical size pinned off (support font helper) | **3.166** | |
| | pinned off, with the two rows blank in the reference hidden* | 2.321 | |
| `render-gradients` (2×) | default `LinearGradient`/`EllipticalGradient`/`AngularGradient` | 10.690 | 0.133 |
| | `Gradient(stops:).colorSpace(.device)` | **0.135** | |
| `layout-justify-space-between` (1×) | `HStack` + `Spacer(minLength: 0)` | **0.000** | 0.000 |
| | `PenFlex: Layout` (support) | **0.000** | |
| `layout-nested` (1×) | `VStack`/`HStack`, `fill_container` → `maxWidth: .infinity` | **0.000** | 0.000 |
| `render-transforms-and-effects` (2×) | `rotationEffect` in a bbox frame, `scaleEffect`, `ShadowStyle`, `.blur`, `.blendMode`; radius = blur/2 | **0.59** | 1.12 |

\* The `render-text` reference was exported after Pen dropped rich text, so the rows "Bold and Italic" and "Underline Strikethrough" are blank in
it (`project/2026-08-29-pen-2.17-migration.md`). Both renderers draw the words, so the comparable figures are 3.17 against 2.57. What remains is
vertical metrics: SwiftUI's board is 513 px tall against Pen's 510, and lines drift by 2–3 px.

> **Corrected 2026-09-26 (leaf `c9pSVy`):** "vertical metrics" was two causes, not one. The `lineHeight: 2` row sat
> ~6 px high because `lineHeight(.exact(points:))` puts the first baseline one em below the line top where Pen
> centres the glyphs (half-leading); `penFont` now matches Pen. The 3 px of board height is SwiftUI's 1× Text
> height for 16 pt Inter lines (20 against Pen's 19). The reference has been re-exported with the two rows drawn;
> against it SwiftUI measures 2.13. See [SwiftUI line height](2026-09-26-swiftui-line-height.md).

### 4.2 Speed: the options, measured

The prototype and the timing script live in the scratchpad (`…/scratchpad/dH7FN6/proto/`: `gen.py` lays out 20 views, five copies each of the four
fixture views; `bench.py` times them). They are throwaway. Each figure is the minimum of 3 runs (2 for the interpreter), on a **loaded** machine. `-Onone`
applies to the generated code throughout.

| Loop | Per view | Batch of 20 |
|---|---|---|
| **Cold** first compile (fresh `-module-cache-path`, one view + harness) | 4.9 s once | — |
| Per-view executable, harness compiled with it (`swiftc`) | 1.7–2.1 s compile + 0.15–0.8 s run | ~40 s (serial) |
| Per-view executable against a prebuilt harness dylib | 1.05–1.11 s compile + 0.5 s run | ~30 s |
| **One module, a `switch` over names** (`swiftc`, harness as source) | — | 4.5 s compile + 3.8 s run (`-Onone` MAE loops dominate the run) |
| One module against a prebuilt `-O` harness | 1.1 s (one view) | **5.5 s compile + 0.5 s run** |
| Resident host + a freshly built dylib per view (`dlopen`) | 0.7–1.0 s dylib compile + **0.07–0.12 s** load, render, MAE, PNG | 20 × ~1 s compile + 2.6 s host run |
| **Interpreter**, `xcrun swift view.swift` (harness inlined) | **0.65–1.0 s** end to end | 4.4 s (9.6 s first run) |
| `swiftc -typecheck` of the 20-view module | — | 8.7 s: *slower* than compiling, because it is a single frontend with no batch parallelism |
| Xcode previews / `RenderPreview` over MCP | not measured: needs a running Xcode, an open project, and sudo-granted permission | — |

What the numbers say: **compilation dominates everything.** A resident host saves only the ~0.1 s render, and pays for it with
`dlopen` and duplicated type metadata across images. The prototype had to share a `ViewBox` class between host and dylib, which is only sound through a
shared harness module. **Not recommended.** Batching amortizes the compiler's fixed cost (~1 s) across views: about 0.3 s per view in a batch of 20.

### 4.3 Recommendation

- **(a) The test suite: one batch per test run.** The test writes every emitted view for the fixture set, plus a small harness `main.swift`
  (a test resource that renders each named view with `ImageRenderer` and writes PNGs), into a temporary directory. It then runs **one** `xcrun swiftc -Onone
  -target arm64-apple-macos15.0 …` and executes the result. It compares in-process, with `PenSnapshotTestHelpers`, board by board, as
  parametrized Swift Testing cases. Keep MAE out of the child: its `-Onone` loops were most of the 3.8 s. Expect about 6 s for 20 boards on this machine,
  in the same range as the WebView suites. A compile error becomes a failing test with the compiler's diagnostic, not a broken build.
- **(b) An agent iterating on one view: the interpreter.** `xcrun swift` on one file with the harness inlined takes about 1 s, and leaves no build products.
  `scripts/swiftui-fixture-probe.swift` is that loop: 8 renders in 2.4 s. When the emitter exists, the loop wants a verb, for example `woodcase generate swiftui
  <file> --preview <node>` → PNG. That verb shells out, so it belongs in an Apple-only target, beside `WoodcaseViewer`, not in `Woodcase`.

### 4.4 How it fits the repo

- **The emitter** goes in `Sources/Woodcase/CodeGen/SwiftUI/`. It is Foundation-only string generation that never imports SwiftUI, so it builds and its
  golden tests run on Linux. SwiftUI is in the *output*, not the library. That is the whole answer to "the library must stay cross-platform".
- **The support file** (`PenSupport.swift`: `PenFlex`, `PenAbsolute`, the font helper, shadow spread, per-side strokes, the `#available` branches) is
  emitted source, stored as a template resource the way `CodeGen/ViewerTemplates/` is. So a generated package depends on nothing of ours.
- **The render test** goes in `Tests/WoodcaseTests/`, wrapped in `#if os(macOS)` like `ReactPaintWebViewTests`, with a tag such as
  `.swiftUIRegression` and an `.enabled(if:)` trait that `xcrun --find swiftc` succeeds. It shells out to the toolchain, so no target in the
  package ever links SwiftUI. Compiling emitted goldens *into* a test target was considered and rejected: one bad emission would break the build of the whole test bundle.
  It would also need `#if canImport(SwiftUI)` wrappers the real output must not carry.
- **The harness sandbox.** `swift test` already runs with the sandbox disabled, so the child `swiftc` has its module cache. The first run on a fresh machine pays ~5 s.

## 5. Verdict, lift, risk

**Feasible.** Nothing in the format is blocked: `justify` text is impossible, background blur is approximate, and everything else is exact or exact
by construction. The measured fidelity already matches or beats the CG renderer on four of the five boards.

**The lift: about 14 leaves** (§6). That is roughly the React emitter's size: an estimated 4,500–6,000 source lines against React's 5,415 plus its share
of the 2,242 shared lines, and a comparable 8–11k lines of tests. It is less web plumbing (no Tailwind, no SVG overlays, no npm or Vite
scaffolding) and more Swift-typing plumbing (typed props, environment theme, `ButtonStyle` states). About two of the 14 leaves are the generalizing refactors of §1.2.

**The riskiest part: layout semantics around text.** Flexbox and SwiftUI agree on fixed boxes, and measured zero error there. They
disagree on how `fill_container` and `fit_content` siblings negotiate with wrapping text: SwiftUI hands space out by flexibility order, not by flex-grow
and flex-shrink. The fallback is known and exact by construction: a support `Layout` that ports `PenLayoutEngine`'s algorithm. The cost is less
idiomatic output, where the emitter cannot prove that a stack is equivalent. The first slice exists to find where that line falls, against the 25 `layout-*`
fixtures with Pen PNGs (most with a `.layout.json` too). The second risk is the §1.2 refactor, which must leave every React golden byte-identical.

**The first thin slice** is leaf 3 below. It emits frames (stacks, `ZStack` for `none`, padding, gap, sizing, justify, align, clip),
rectangles and ellipses with solid fills and corner radii, and text (font, weight, size, colour, align, growth, line height). It writes the support file and runs the render test over
the `layout-*` fixtures and `render-text`. It proves the pipeline end to end before any paint work.

## 6. Implementation plan

The path is clear. Four decisions are **Ben's to make** first (leaf 0). The plan below assumes my recommendation for each.

> **Rulings (Ben, 2026-09-26, leaf `bpfpVZ`). Two differ from the recommendations below; the plan that follows them is
> [2026-09-26-swiftui-emitter-plan.md](2026-09-26-swiftui-emitter-plan.md).**
> 1. **Floor: iOS 26 / macOS 26 by default** (not 18 / 15). The code is green-field and should be modern. A lower floor
>    (iOS 18 / macOS 15) is welcome through `#available` branches in `PenSupport.swift`, but never at the cost of the quality
>    or modernity of the generated component code.
> 2. **Mesh: always native `MeshGradient`**, including folded meshes (MAE 7.1 there); lint's `mesh-gradient-distorted`
>    is the warning. No baked path in the SwiftUI emitter.
>
>    > **Updated 2026-09-27 (leaf `rlSTe9`).** The 0.4–3.2 / 7.1 figures are for Pen's grid handed to `MeshGradient`
>    > as is, and the translucent `malpha` board, "n/a" in the mesh report, measures 5.0 that way: SwiftUI blends
>    > colours premultiplied, Pen unpremultiplied. The emitter instead writes the support file's `PenMeshGradient`
>    > style, which resolves to a `MeshGradient` of 8 × 8 cells per Pen cell, each corner's position, tangents and
>    > colour evaluated from Pen's own patch. Still native and resolution-independent; every `render-mesh-gradients`
>    > board measures 0.18–0.83, the fold included (`swift test --filter SwiftUIRenderTests`, Xcode 27.0, macOS 27.0).
> 3. **Output: a SwiftPM package**, as recommended.
> 4. **Layout: always idiomatic stacks** (not "stacks where provable, `PenFlex` otherwise"). "The goal is not necessarily
>    pixel perfection when it comes to code generation; what matters more is intent." No port of `PenLayoutEngine`; the
>    render loop guards intent and regressions, and a board where stack negotiation differs from flexbox records its MAE
>    rather than failing a CG + 1.0 gate.

| # | Leaf | Files | Criteria | Size |
|---|---|---|---|---|
| 0 | **Rulings** (Ben): the default floor (recommend iOS 18 / macOS 15); mesh (recommend native `MeshGradient`, themeable and resolution-independent at MAE ≤ 3.2, under the 8.0 threshold; bake only meshes `lint` reports as `mesh-gradient-distorted`); the output shape (recommend a SwiftPM package with `Sources/<Name>/{Components,Pages,Theme,Support}` and fonts and icons as resources); layout policy (recommend stacks where provably equivalent, `PenFlex` otherwise) | this doc | rulings recorded here as a marked block | — |
| 1 | **Neutral seams**: `StateTrigger` names states, not selectors; `PropMapper` returns typed values; `ManifestEmitter` moves out of `React/`; a `CodeGen/Paint/` home for `PaintRoute`, Pen unit-box gradient geometry, mesh theme resolution and stroke outsets | `CodeGen/*.swift`, `CodeGen/Paint/*`, `React/*` | every React golden and WebView MAE unchanged; DocC updated | M |
| 2 | **CG-free geometry**: split `PenSVGPathParser` into a command model and a CG builder; the same for polygon and arc geometry | `Rendering/PenSVGPathParser*.swift`, a new `Models/…` | the renderer's snapshots unchanged; the parser builds without CoreGraphics | M |
| 3 | **Thin slice**: `SwiftUIEmitter` skeleton, `PenSupport.swift` template, the render-test harness (a batch `swiftc` child, PNGs back, in-process MAE), `woodcase generate swiftui` | `CodeGen/SwiftUI/*`, `CodeGen/SwiftUITemplates/*`, `Tests/WoodcaseTests/SwiftUI*Tests.swift`, `GenerateCommand.swift` | goldens over `layout-*.pen` and `render-text.pen`; render MAE ≤ CG's + 1.0 per board; golden tests pass on Linux (no SwiftUI import); compiled at `-target …macos15.0` | L |
| 4 | **Paints**: gradients (`.device`, geometry), images, stacks, fill blend modes, opacity; paints on text | `CodeGen/SwiftUI/SwiftUIEmitter+Paint*.swift` | `render-gradients`, `render-gradient-geometry`, `render-text-fills` within CG + 1.0 | M |
| 5 | **Strokes**: all alignments, per-side (support shape), dash, caps, joins, paints on strokes | `…+Stroke*.swift`, the support file | `render-per-side-strokes`, `render-stroke-fills` boards within CG + 1.0 | L |
| 6 | **Effects and transforms**: shadow (radius = blur/2), spread, inner (`ShadowStyle`), blur, background blur (Material + diagnostic), clip, rotation bbox, flips, node blend | `…+Effects.swift`, the support file | `render-transforms-and-effects` ≤ 1.0 with the inner-shadow item excluded until the reference is re-exported; `blur1–3` | M |
| 7 | **Shapes and icons**: polygon, arc/donut, path, line, viewBox from leaf 2's commands; icon fonts as resources | `…+Shapes.swift`, `…+Icon.swift` | `render-arc-donut`, `render-strokes-and-paths`, `render-fill-domains`, an icon fixture | M |
| 8 | **Components and pages**: view structs, typed props, refs, mapped overrides, inlining, slots | `…+Component.swift`, `…+Ref.swift` | goldens over `woodcase-app.pen` and `pages.pen`; the WebView-equivalent MAE on the `woodcase-app-*` screens | L |
| 9 | **Themes**: a `PenTheme` environment value, themed variables, `context` nodes, the `colorScheme` bridge | `…+Theme.swift` | the `banking-home-{light,dark}` and `woodcase-app-*-dark` references | M |
| 10 | **Roles and states**: `Button` + `ButtonStyle`, `Toggle`, `TextField`, `Picker`, tab bar, structural states | `…+States.swift` | goldens over the state fixtures; pressed and disabled renders compared with the `:state` siblings | L |
| 11 | **Mesh**: native `MeshGradient` per the ruling, the baked fallback | `…+Mesh.swift` | the `render-mesh-gradients-*` boards at ≤ 3.5 (mfold baked ≤ 0.7) | S |
| 12 | **Packaging and docs**: SwiftPM scaffold, font and icon resources and registration, `PenCodeGen.md` SwiftUI section, `woodcase help codegen` | `CodeGen/SwiftUI/SwiftPackageScaffolder.swift`, DocC | a generated package `swift build`s on macOS; DocC 100% | M |
| 13 | **Churn guard**: the SwiftUI vocabulary list as a test resource; the yearly checklist in DocC; `scripts/swiftui-api audit` green at the floor | a test resource, DocC | `audit` exits 0; the checklist documented | S |

The order is 0 → 1, 2 (in parallel) → 3 → 4–7 (in parallel, all touching the support file, so carve its sections per leaf) → 8 → 9, 10, 11 → 12, 13.
