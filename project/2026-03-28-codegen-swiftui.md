# Research: .pen to SwiftUI Code Generation

## 1. Can We Achieve 100% 1:1 Mapping?

**Short answer: No, but approximately 92-95% coverage with high fidelity.** The remaining gaps are mostly edge cases (shadow spread, inner shadows, per-side strokes, two blend modes) that can be approximated. Nothing in the .pen format is architecturally impossible in SwiftUI.

### Layout: Flexbox to SwiftUI

This is the most important and most nuanced mapping.

**Direct mappings (exact):**
- `layout: horizontal` -> `HStack`
- `layout: vertical` -> `VStack`
- `layout: none` -> `ZStack` with `.position(x:, y:)` on children
- `gap` -> `HStack(spacing:)` / `VStack(spacing:)`
- `padding` (all three forms) -> `.padding(EdgeInsets(...))` or shorthand forms
- `alignItems: start/center/end` -> `HStack(alignment: .top/.center/.bottom)` / `VStack(alignment: .leading/.center/.trailing)`
- `justifyContent: start/center/end` -> Spacer-based or `.frame(maxWidth: .infinity, alignment:)` wrapping
- `width/height: fixed(N)` -> `.frame(width: N)` / `.frame(height: N)`
- `fit_content` -> No frame modifier (intrinsic sizing)
- `fill_container` -> `.frame(maxWidth: .infinity)` or `.frame(maxHeight: .infinity)`
- `clip: true` -> `.clipped()` or `.clipShape(...)`
- `layoutPosition: absolute` -> `.overlay { child.position(x:, y:) }`

**Key concerns:**

**`space_between` and `space_around`:** HStack/VStack don't natively support these. Solution: the **Layout protocol** (iOS 16+). Define `SpaceBetweenLayout` and `SpaceAroundLayout` as custom Layout types implementing the exact same algorithm as `PenLayoutEngine`. This is idiomatic and precise.

**`fill_container` in a `layout: none` parent:** Falls back to its fallback value, since there's no flex axis. Emit `.frame(width: fallback)` instead of `.frame(maxWidth: .infinity)`. Matches `PenLayoutEngine`'s behavior.

**`fill_container` with multiple fill children:** SwiftUI's `.frame(maxWidth: .infinity)` gives equal priority when multiple siblings compete -- same as .pen dividing remaining space equally.

**`fit_content` with fallback:** Maps to `.frame(minWidth: fallback)` or `.frame(minHeight: fallback)`.

### Fills

| .pen fill | SwiftUI | Fidelity |
|---|---|---|
| Solid color | `.background(Color(...))` | Exact |
| Linear gradient | `LinearGradient(...)` | Exact |
| Radial gradient | `EllipticalGradient(...)` | Exact (handles non-circular) |
| Angular gradient | `AngularGradient(...)` | Exact |
| Image (stretch/fill/fit) | `Image(...).resizable().scaledToFill()/scaledToFit()` | Exact |
| Mesh gradient | `MeshGradient(...)` (iOS 18+) | Close, not exact — see the correction below |
| Multiple fills | Stacked `.background()` modifiers | Exact |
| Fill opacity/enabled | `.opacity()` / conditional inclusion | Exact |
| Fill blend mode | `.blendMode(...)` on the background view | Exact |

SwiftUI is the only target where mesh gradients have a native equivalent.

> **Correction (2026-09-26):** SwiftUI's `MeshGradient` is close to Pen's mesh, not exact. Fed Pen's positions and
> handles (`smoothsColors: true`), it measured MAE 0.4–3.2 against Pen's exports, and 7.1 on a folded mesh: it is
> Apple's color interpolation, not Pen's. See [the mesh report](2026-09-26-mesh-gradients.md) §1, "The empirical check".

> **Correction (2026-09-26):** "Exact" for linear, radial and angular gradients holds only with
> `Gradient.colorSpace(.device)`: SwiftUI's default interpolation measured MAE 10.69 against Pen's `render-gradients`
> export, `.device` 0.135 (CoreGraphics: 0.133). Text needs Inter's automatic optical sizing pinned off (MAE 3.61 → 3.17).
> Shadow and blur radii are half of Pen's `blur`. See [the SwiftUI feasibility report](2026-09-26-swiftui-codegen-feasibility.md) §1.3 and §4.1.

### Shapes

| .pen shape | SwiftUI | Fidelity |
|---|---|---|
| Rectangle (uniform radius) | `RoundedRectangle(cornerRadius:)` | Exact |
| Rectangle (per-corner) | `UnevenRoundedRectangle(...)` (iOS 17+) | Exact |
| Full ellipse | `Ellipse()` | Exact |
| Arc/donut ellipse | Custom `Shape` with `addArc` | Exact |
| Polygon | Custom `Shape` (trivial trig) | Exact |
| Rounded polygon | Custom `Shape` with `addArc(tangent1End:...)` | Exact |
| Line | Custom `Shape` with two points | Exact |
| SVG path | `SwiftUI.Path` from parsed commands | Exact |

SwiftUI's `Shape` protocol is fully capable. Everything `PenShapeBuilder` draws with CGPath can be drawn with SwiftUI `Path`.

### Text

**Exact mappings:** `fontFamily` (`.font(.custom(...))`), `fontSize`, `fontWeight`, `fontStyle: italic` (`.italic()`), `letterSpacing` (`.tracking(...)`), `textAlign` (`.multilineTextAlignment(...)`), `underline`, `strikethrough`, `textGrowth` modes, `textAlignVertical` (via `.frame(alignment:)`).

**Rich text:** `AttributedString` with `Text(attributedString)` for full per-span control.

**Minor issues:**
- `textAlign: justify` -- no SwiftUI equivalent. Fall back to `.leading`.
- `lineHeight` (multiplier) -- SwiftUI's `.lineSpacing()` is inter-line spacing, not total line height. Compute as `(multiplier - 1.0) * fontSize`.

### Effects

| .pen effect | SwiftUI | Fidelity |
|---|---|---|
| Outer shadow (no spread) | `.shadow(color:radius:x:y:)` | Exact |
| Outer shadow WITH spread | No direct equivalent | **Moderate gap** -- approximate with enlarged background shape |
| Inner shadow | No built-in modifier | **Moderate gap** -- achievable via overlay with inverted mask + shadow |
| Blur | `.blur(radius:)` | Exact |
| Background blur | `.background(.ultraThinMaterial)` | Close -- exact radius needs `UIViewRepresentable` |

### Blend Modes

14 of 16 map exactly to `.blendMode(...)`. Two exceptions: `linearBurn` (approximate as `.multiply`) and `linearDodge` (approximate as `.screen`). Same approximations already used in Woodcase's renderer.

### Transforms -- PERFECT

- `rotation` -> `.rotationEffect(Angle(degrees:))`
- `flipX` -> `.scaleEffect(x: -1, y: 1)`
- `flipY` -> `.scaleEffect(x: 1, y: -1)`
- `opacity` -> `.opacity(Double)`

### Strokes

Uniform strokes with center/inside alignment, join, cap, and dash patterns all map via `StrokeStyle`. **Gaps:** outside stroke alignment (workaround: expand shape by half stroke width) and per-side thickness (workaround: overlay rectangles per side).

### Components and Theming

**Components:** Each `reusable: true` node becomes a `View` struct. `propMapping` metadata maps semantic names to typed init parameters. `_role` metadata determines semantic SwiftUI views: `button` -> `Button(action:)`, `textInput` -> `TextField(text:)`, `toggle` -> `Toggle(isOn:)`.

**Theming:** For simple light/dark, map directly to `@Environment(\.colorScheme)`. For multi-axis themes, generate custom `EnvironmentKey` types per axis. Variables with themed values become computed properties that switch on the active theme. `context` nodes emit `.environment(\.penThemeMode, .dark)`.

### Icon Fonts

Bundle TTF files, register via `Info.plist` `UIAppFonts`, and render as `Text("\u{XXXX}").font(.custom(fontName, size:))`. The icon name-to-Unicode mapping from `PenIconFontRegistry` is emitted as a lookup table.

---

## 2. Specific Gaps

### Moderate Gaps

1. **Shadow spread** -- SwiftUI `.shadow()` has no spread parameter. Workaround: enlarged background shape.
2. **Inner shadow** -- No built-in modifier. Workaround: custom ViewModifier using overlay with inverted mask + shadow.
3. **Per-side stroke thickness** -- No native support. Workaround: overlay rectangles per side.
4. **Background blur (precise radius)** -- Material system doesn't expose radius. Workaround: `UIViewRepresentable`.
5. **Outside stroke alignment** -- No `.strokeOutside()`. Workaround: expanded shape with center stroke.

### Minor Gaps

1. **`textAlign: justify`** -- No SwiftUI equivalent. Fall back to `.leading`.
2. **`linearBurn`/`linearDodge` blend modes** -- Approximated same as current renderer.
3. **Line height multiplier** -- Computed as `(multiplier - 1) * fontSize` for `.lineSpacing()`.

**No severe gaps.**

---

## 3. Proposed Architecture

### Node-to-View Mapping

- `frame` (horizontal/vertical) -> `HStack`/`VStack` with background/overlay for fills, strokes, effects
- `frame` (layout: none) -> `ZStack` with positioned children
- `frame` (space_between/around) -> Custom `Layout` structs
- `text` -> `Text(...)` or `Text(AttributedString)` with modifiers
- `rectangle` -> `RoundedRectangle`/`UnevenRoundedRectangle`
- `ellipse` -> `Ellipse()` or custom arc `Shape`
- `polygon` -> Custom `RegularPolygon` shape
- `line`/`path` -> Custom `Shape` implementations
- `ref` -> Instantiation of generated component View
- `iconFont` -> `Text("\u{...}").font(.custom(...))`
- `note`/`prompt` -> Skip
- `context` -> `.environment(\.penTheme, ...)` boundary

### File Structure

```
Generated/
  Theme/           -- EnvironmentKeys, variable resolution
  Shapes/          -- RegularPolygon, ArcShape, InnerShadow modifier, custom Layouts
  IconFonts/       -- Icon name to Unicode scalar lookup
  Components/      -- One View struct per reusable component
  Screens/         -- One View per top-level frame
  Extensions/      -- Color+Hex, View+PenEffects
```

### Layout Translation Decision Tree

1. `layout: none` -> `ZStack`, children positioned with `.position(x:, y:)`
2. `justifyContent` in `{start, center, end}` -> `HStack/VStack(spacing: gap)`, justify via Spacers or `.frame(alignment:)`
3. `justifyContent` in `{space_between, space_around}` -> Custom `Layout` struct
4. Per-child sizing: `fixed(N)` -> `.frame(width: N)`; `fill_container` -> `.frame(maxWidth: .infinity)`; `fit_content` -> intrinsic; fallbacks as `minWidth`/`minHeight`

### Interactivity

SwiftUI is the most idiomatic target for interactivity layering:

- Components emit closure parameters: `PenButton(label: "Submit", onTap: { ... })`
- `_role: "button"` -> `Button(action: onTap) { ... }`
- `_role: "textInput"` -> `TextField(text: $text) { ... }`
- `_role: "toggle"` -> `Toggle(isOn: $isOn) { ... }`
- Users pass `@State`/`@Binding` values and closures at the call site

---

## 4. Test Fixture Needs

**Layout:** All 5 justify modes x 2 orientations, all 3 align modes, fill_container (single, multiple, mixed), fit_content with/without fallback, nested containers, absolute positioning.

**Shape/Fill:** All shape types, all gradient types, image fills (3 modes), mesh gradient, multiple fills with blend modes.

**Text:** Plain/rich, all typography properties, all textGrowth modes, textAlignVertical.

**Component/Ref:** Simple component, overrides, nested components, propMapping, _role metadata.

**Theme:** Light/dark, multi-axis, themed variables, variable chains, context nodes.

**Effects:** Shadow with/without spread, inner shadow, blur, background blur, combined effects.

**Strokes:** Uniform, per-side, all alignments, dash patterns, gradient stroke.

---

## 5. Summary

| Category | Coverage | Key Challenge |
|---|---|---|
| Layout | ~95% | Custom Layout for space_between/space_around |
| Shapes | ~100% | All via Shape protocol |
| Fills | ~98% | Mesh gradient needs iOS 18+ |
| Text | ~95% | Justify missing; line height needs math |
| Effects | ~85% | Inner shadow/spread need custom ViewModifiers |
| Blend modes | ~90% | Two modes approximated |
| Transforms | ~100% | Perfect mapping |
| Strokes | ~90% | Per-side/outside need workarounds |
| Components | ~100% | View structs with typed parameters |
| Theming | ~100% | Environment-based |
| Icon fonts | ~100% | Custom font + Unicode scalars |

**Overall: Highly feasible.** The .pen format's declarative, flexbox-based architecture is a natural fit for SwiftUI. The Layout protocol solves the hardest layout problems, and the Shape protocol provides full geometry parity. The biggest engineering efforts will be the layout translation logic and the effects ViewModifiers.
