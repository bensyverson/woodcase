# Code Generation Feasibility: Comparative Summary

**Date:** 2026-03-28\
**Question:** Can .pen files be deterministically translated to code, without an LLM?\
**Answer:** Yes, with high fidelity across all three targets. No target achieves 100%, but the gaps are small and consistent.\

See individual reports: [HTML/CSS](2026-03-28-codegen-html-css.md) | [React+Tailwind](2026-03-28-codegen-react-tailwind.md) | [SwiftUI](2026-03-28-codegen-swiftui.md)

---

## Feature Coverage Comparison

| .pen Feature | HTML/CSS+WC | React+Tailwind | SwiftUI |
|---|---|---|---|
| **Layout (flexbox)** | Perfect | Perfect | ~95% (custom Layout needed for space_between/around) |
| **Absolute positioning** | Perfect | Perfect | Perfect (ZStack + .position) |
| **Sizing (fixed/fit/fill)** | Perfect | Perfect | Perfect |
| **Solid color fills** | Perfect | Perfect | Perfect |
| **Linear gradient** | Perfect | Perfect | Perfect |
| **Radial gradient** | Perfect (rotation workaround) | Perfect (inline style) | Perfect (EllipticalGradient) |
| **Angular gradient** | Perfect (conic-gradient) | Perfect (inline style) | Perfect (AngularGradient) |
| **Image fills** | Perfect | Perfect | Perfect |
| **Mesh gradient** | **Rasterize fallback** | **Rasterize fallback** | **Perfect** (iOS 18+ MeshGradient) — *close, not exact; see the correction below the table* |
| **Multiple fills** | CSS multi-background | Stacked elements | Stacked .background() |
| **Rectangle** | CSS div | CSS div | RoundedRectangle |
| **Per-corner radius** | CSS per-corner | Tailwind per-corner | UnevenRoundedRectangle (iOS 17+) |
| **Ellipse (full)** | CSS border-radius: 50% | CSS rounded-full | Ellipse() |
| **Ellipse (arc/donut)** | Inline SVG | Inline SVG | Custom Shape |
| **Polygon** | Inline SVG | Inline SVG | Custom Shape |
| **Line** | Inline SVG | Inline SVG | Custom Shape |
| **SVG Path** | Inline SVG | Inline SVG | SwiftUI Path |
| **Plain text** | Perfect | Perfect | Perfect |
| **Rich text (per-span)** | Nested spans | Nested spans | AttributedString |
| **Text justify** | Perfect | Perfect | **No equivalent** (fall back to leading) |
| **Vertical text align** | Flex container | Flex container | .frame(alignment:) |
| **Outer shadow** | box-shadow | box-shadow | .shadow() |
| **Outer shadow + spread** | box-shadow (perfect) | box-shadow (perfect) | **No spread param** (workaround) |
| **Inner shadow** | box-shadow inset | box-shadow inset | **Custom ViewModifier** |
| **Blur** | filter: blur() | blur-[] | .blur() |
| **Background blur** | backdrop-filter | backdrop-blur-[] | Material (imprecise radius) |
| **Shadow on SVG shapes** | drop-shadow (no spread) | drop-shadow (no spread) | .shadow() on Shape |
| **Blend modes (standard)** | mix-blend-mode (all 16) | mix-blend-* (all 16) | .blendMode() (14/16) |
| **linearBurn/linearDodge** | No CSS equiv | No CSS equiv | Approximated |
| **Rotation/Flip** | CSS transform | Tailwind transform | .rotationEffect/.scaleEffect |
| **Clipping** | overflow: hidden | overflow-hidden | .clipped() |
| **Uniform stroke** | border / SVG stroke | border / SVG stroke | .stroke() / StrokeStyle |
| **Per-side stroke** | CSS border-* | CSS border-* | **Overlay workaround** |
| **Stroke inside/outside** | box-sizing tricks | box-shadow approx | **Expand shape workaround** |
| **Gradient stroke** | border-image (breaks radius) | border-image (breaks radius) | Gradient + .stroke() |
| **Dash pattern** | SVG stroke-dasharray | SVG stroke-dasharray | StrokeStyle dashPattern |
| **Components** | Web Components | React components | View structs |
| **Component props** | Observed attributes | Typed props | Init parameters |
| **Theming** | CSS custom props + data-* | CSS vars + data-* + Tailwind | @Environment + EnvironmentKey |
| **Multi-axis themes** | Compound attribute selectors | Compound selectors | Multiple environment keys |
| **Icon fonts** | CDN / inline SVG | React icon libraries | Custom font + Unicode |
| **Interactivity layering** | Subclass pattern (.gen.js + .js) | Callback props + composition | Closure parameters |

> **Correction (2026-09-26):** SwiftUI's `MeshGradient` is close to Pen's mesh, not exact. Fed Pen's positions and
> handles (`smoothsColors: true`), it measured MAE 0.4–3.2 against Pen's exports, and 7.1 on a folded mesh: it is
> Apple's colour interpolation, not Pen's. See [the mesh report](2026-09-26-mesh-gradients.md) §1, "The empirical check".

---

## Gaps At a Glance

### Universal gaps (all three targets)
- **linearBurn/linearDodge blend modes** -- rare Photoshop-legacy modes, no standard equivalent anywhere
- **Shadow blend modes** -- per-shadow blend mode is not natively supported; workarounds exist

### Web-only gaps (HTML/CSS and React)
- **Mesh gradient** -- no CSS equivalent; must rasterize to image
- **Shadow spread on SVG shapes** -- CSS `drop-shadow()` lacks spread parameter

### SwiftUI-only gaps
- **Shadow spread** -- `.shadow()` has no spread parameter
- **Inner shadow** -- requires custom ViewModifier
- **Background blur radius** -- Material system doesn't expose precise radius
- **Text justify** -- no SwiftUI equivalent
- **space_between/space_around** -- requires custom Layout protocol types (solvable but non-trivial)

### No severe gaps in any target
Every .pen feature has at least a workable representation. The worst cases are moderate (degraded but functional with known workarounds).

---

## Architecture Comparison

### Component Model

| Aspect | HTML/CSS | React | SwiftUI |
|---|---|---|---|
| Component unit | Web Component class | Function component (.tsx) | View struct |
| Style encapsulation | Shadow DOM | Tailwind scoping / CSS modules | SwiftUI view boundaries |
| Props | Observed attributes | Typed TS props | Init parameters |
| Interactivity | Subclass extends .gen.js base | Callback props (onClick, etc.) | Closure parameters |
| Regeneration safety | .gen.js regenerated; .js user-owned | Component file regenerated; wrapper file user-owned | Same pattern possible |

### Theming Model

All three targets use a similar approach:
- Theme axes become selectors/keys (data-attributes for web, EnvironmentKey for SwiftUI)
- Variables become runtime-switchable tokens (CSS custom properties for web, computed properties for SwiftUI)
- Context nodes create scoping boundaries

### Pipeline Integration

All three share the same pre-generation pipeline stages:
```
PenParser -> PenImportResolver -> (partial) PenVariableResolver
```

Key difference from the rendering pipeline:
- **Do NOT fully resolve variables** -- preserve theme-dependent variables as runtime references
- **Do NOT expand refs** -- each ref becomes a component instantiation, not a flattened clone
- **Do NOT run layout** -- the target platform's layout engine handles positioning

---

## Recommended Fixture Gaps to Fill

To validate code generation across all three targets, we need .pen files that the current test corpus lacks:

### Must-have (blocks validation)
1. **Component with `propMapping` metadata** -- tests prop generation
2. **Component with `_role` metadata** -- tests semantic element emission
3. **Multi-axis themed design** -- tests theme switching beyond light/dark
4. **Nested component instances** -- ref inside ref, with overrides at both levels
5. **UI widget showcase** -- button, text input, toggle, link, dropdown, card with image

### Nice-to-have (improves confidence)
6. **Full-page layout** -- header/sidebar/content/footer composition
7. **Data table** -- repetitive component instances with varied content
8. **Form layout** -- labels, inputs, validation states
9. **Mesh gradient** -- for rasterization fallback testing (web) vs native (SwiftUI)
10. **Complex strokes** -- per-side, gradient, dashed, inside/outside on rounded shapes

### Already covered by existing fixtures
- Basic layout (all justify/align combinations, sizing modes, nesting)
- Shape types and fill types
- Text (plain and rich)
- Gradients (linear, radial, angular)
- Effects (shadow, blur)
- Transforms (rotation, flip)
- Simple component/ref expansion
- Variables and basic theming

---

## Recommendation

All three targets are viable for deterministic code generation. The engineering effort breaks down as:

1. **React + Tailwind** -- Easiest to implement. Layout maps 1:1, React's component model naturally handles props and composition, Tailwind handles most styling, and the ecosystem has mature icon libraries. The Tailwind-vs-inline-style decision is the main design question. **Start here for a prototype.**

2. **HTML/CSS + Web Components** -- Similar difficulty to React for the CSS side. Web Components add complexity (Shadow DOM, attribute observation, custom element registration) but avoid any framework dependency. The subclass pattern for interactivity is less ergonomic than React props but fully workable.

3. **SwiftUI** -- Highest fidelity potential (mesh gradients, native shapes, blend modes) but the flexbox-to-SwiftUI layout translation is the most complex piece of engineering. Custom Layout types for space_between/around, and custom ViewModifiers for inner shadow/spread, add to the effort. Worth pursuing for the native app use case.

All three share ~70% of the translation logic (node classification, fill mapping, effect mapping, component extraction, theme generation). This should be built as a shared "intermediate representation" that each target-specific emitter consumes.
