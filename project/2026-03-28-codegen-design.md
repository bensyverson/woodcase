# Deterministic Code Generation from .pen Files

**Date:** 2026-03-28\
**Status:** Phase 3 complete; Phase 4 in progress (harness + builder done, visual fidelity bugs surfacing)\
**Feasibility reports:** [HTML/CSS](2026-03-28-codegen-html-css.md) | [React+Tailwind](2026-03-28-codegen-react-tailwind.md) | [SwiftUI](2026-03-28-codegen-swiftui.md) | [Summary](2026-03-28-codegen-feasibility-summary.md)\
**Related:** [Gemini DX & propMapping Origin](2026-03-26-Gemini-DX.md)

---

## 1. Vision & Scope

### What this is

A deterministic (no LLM) translation from .pen design files to production UI code. The .pen file is the source of truth for **what components look like** — their structure, styling, layout, theming, and prop interfaces. Generated code is ephemeral: regenerated on every .pen change, never manually edited.

### What this is not

This is not an app scaffold generator. It does not generate routing, state management, data fetching, or business logic. Those concerns belong to user-authored code that *consumes* the generated components.

### The boundary

| Owned by .pen | Owned by user code |
|---|---|
| Component structure & layout | State management |
| Styling & theming | Data fetching & business logic |
| Prop interfaces via `_props` (what can be customized) | Prop values (what the customizations are) |
| Semantic roles (this is a button) | Behavior (what the button does) |
| Visual variants (themed, sized) | Application routing & navigation |

### Primary use case

Design teams maintain .pen files defining a design system and key screens. Woodcase generates typed, themed, prop-driven components. Developers import and compose those components with their own logic. The feedback loop: if a developer needs a new prop exposed, the designer adds it to the .pen metadata, and the next regeneration surfaces it.

### Target frameworks

1. **React + Tailwind CSS** (v4) — recommended starting point
2. **Vanilla HTML/CSS + Web Components** (ES modules, no bundler)
3. **SwiftUI** (iOS 17+ / macOS 14+)

---

## 2. Metadata Conventions

The .pen format's `metadata` field on every node is an arbitrary `{ type: string; [key: string]: any }` dictionary. We define the following conventions, using underscore-prefixed keys to avoid conflicts with user-defined props.

### 2.1 `_role` — Semantic Element Type

Declares what interactive element this node represents. The code generator emits the appropriate native element for the target framework.

```json
{ "metadata": { "_role": "button" } }
```

**Defined roles:**

| `_role` | HTML | React | SwiftUI |
|---|---|---|---|
| `"button"` | `<button>` | `<button>` | `Button(action:)` |
| `"link"` | `<a>` | `<a>` | `Link(destination:)` |
| `"textInput"` | `<input type="text">` | `<input>` | `TextField(text:)` |
| `"textArea"` | `<textarea>` | `<textarea>` | `TextEditor(text:)` |
| `"toggle"` | `<input type="checkbox">` | `<input type="checkbox">` | `Toggle(isOn:)` |
| `"select"` | `<select>` | `<select>` | `Picker(selection:)` |
| `"image"` | `<img>` | `<img>` | `Image(...)` |
| `"heading"` | `<h1>`–`<h6>` | `<h1>`–`<h6>` | `Text(...).font(.title)` |
| `"nav"` | `<nav>` | `<nav>` | (structural hint) |
| `"section"` | `<section>` | `<section>` | (structural hint) |
| `"list"` | `<ul>` | `<ul>` | `List` |
| `"listItem"` | `<li>` | `<li>` | (child of List) |

Nodes without `_role` emit the default element for their node type (`<div>`, `View`, etc.). This list is extensible — new roles can be added without changing the generator's core logic, as long as a mapping is provided per target.

### 2.2 `_action` — Named Callback

Declares the semantic name of an action this node triggers. Only meaningful on nodes that also have an interactive `_role`. The code generator emits a callback prop named `on{Action}` (camelCase).

```json
{ "metadata": { "_role": "button", "_action": "submit" } }
```

Generates: `onSubmit?: () => void` (React), `onSubmit: (() -> Void)?` (SwiftUI), `"submit"` event (Web Component).

If `_action` is absent but `_role` is interactive, the generator falls back to the generic callback for that role (`onClick` for buttons, `onChange` for inputs, etc.).

### 2.3 `_bind` — Two-Way Binding Name

Declares the semantic name of a value this node binds to. Only meaningful on input-type roles (`textInput`, `textArea`, `toggle`, `select`). The code generator emits both a value prop and a change callback.

```json
{ "metadata": { "_role": "textInput", "_bind": "email" } }
```

Generates:
- React: `email?: string` + `onEmailChange?: (value: string) => void`
- SwiftUI: `email: Binding<String>`
- Web Component: `email` attribute + `email-change` event

### 2.4 `_props` — Content Prop Interface

Declared on `reusable: true` component nodes. Maps semantic prop names to descendant paths, using the same `/`-delimited path syntax as the existing `descendants` override system.

```json
{
  "id": "CardComp",
  "type": "frame",
  "reusable": true,
  "metadata": {
    "_props": {
      "title": "header/title-text",
      "subtitle": "header/subtitle-text",
      "heroImage": "image-container/hero"
    }
  }
}
```

Each entry becomes a typed prop on the generated component. The prop type is inferred from the target node's type:
- Text node content → `string` / `String`
- Fill property → `string` (color) / `Color`
- Enabled property → `boolean` / `Bool`
- Image fill URL → `string` / `URL`

Props have default values derived from the component's own content, so instances that don't override a prop render identically to the master component.

**Relationship to MCP addressability:** `_props` defines a component's *public interface* — what consumers can customize via overrides or generated props. It does not address the separate MCP concern of navigating a component's internal tree during editing. That problem is handled by the node `name` field: designers name their layers meaningfully, the MCP supports name-path resolution (e.g., `"Header/Title"` to disambiguate duplicate names), and uniqueness within a component is enforced by convention. These are complementary: `_props` maps the contract, `name` maps the internals.

### 2.5 Metadata example: complete component

```json
{
  "id": "LoginForm",
  "type": "frame",
  "reusable": true,
  "metadata": {
    "_props": {
      "title": "heading-text",
      "submitLabel": "actions/submit-btn/label"
    }
  },
  "children": [
    {
      "id": "heading-text",
      "type": "text",
      "content": "Sign In"
    },
    {
      "id": "email-field",
      "type": "frame",
      "metadata": { "_role": "textInput", "_bind": "email" }
    },
    {
      "id": "password-field",
      "type": "frame",
      "metadata": { "_role": "textInput", "_bind": "password" }
    },
    {
      "id": "actions",
      "type": "frame",
      "children": [
        {
          "id": "submit-btn",
          "type": "frame",
          "metadata": { "_role": "button", "_action": "submit" },
          "children": [
            { "id": "label", "type": "text", "content": "Sign In" }
          ]
        }
      ]
    }
  ]
}
```

Generated React component signature:

```tsx
interface LoginFormProps {
  title?: string;              // from _props
  submitLabel?: string;        // from _props
  email?: string;              // from _bind on email-field
  onEmailChange?: (value: string) => void;
  password?: string;           // from _bind on password-field
  onPasswordChange?: (value: string) => void;
  onSubmit?: () => void;       // from _action on submit-btn
  className?: string;          // always present
  style?: React.CSSProperties; // always present
}
```

---

## 3. Code Generation Pipeline

### 3.1 How it differs from the rendering pipeline

The existing rendering pipeline:

```
Parse → Import Resolve → Ref Expand → Variable Resolve → Layout → Render
```

The code generation pipeline diverges after import resolution:

```
Parse → Import Resolve → Analyze → Emit
```

Three stages are deliberately **skipped**:

| Stage | Why skipped |
|---|---|
| **Ref Expansion** | Refs become component instantiations, not flattened clones. The whole point is to preserve the component boundary. |
| **Full Variable Resolution** | Theme-dependent variables must remain as runtime references (`var(--name)` in CSS, computed properties in SwiftUI) so theming works at runtime. Static variables (non-themed, no chains) *can* be resolved for cleaner output. |
| **Layout** | The target platform's layout engine handles positioning. We emit layout *instructions* (flex, gap, padding, sizing), not computed rectangles. |

### 3.2 The Analyze stage

Three analyzers operate on the import-resolved `PenDocument` and produce companion structures:

**ComponentAnalyzer** — walks the document and extracts:

```
ComponentDefinition
  ├─ sourceNode: PenNode          (the reusable node)
  ├─ name: String                  (from node name, sanitized for target)
  ├─ props: [PropDefinition]       (from _props → descendant type inference)
  │    └─ targetNodeID: String?    (resolved descendant node ID, for ref override matching)
  ├─ propByNodeID: [String: String] (computed: nodeID → propName lookup)
  ├─ actions: [ActionDefinition]   (from _role + _action on descendants)
  ├─ bindings: [BindingDefinition] (from _role + _bind on descendants)
  └─ slots: [SlotDefinition]       (designated content areas, if any)
```

**PageAnalyzer** — finds top-level pages:

```
PageDefinition
  ├─ id: String                    (source node ID)
  ├─ name: String                  (sanitized page name)
  └─ sourceNode: PenNode          (the page's root node)
```

A page is a top-level frame that is NOT `reusable: true`. Pages represent screens/routes and import child components, but do not themselves accept props.

**ThemeAnalyzer** — extracts:

```
ThemeManifest
  ├─ axes: [ThemeAxis]             (name + values, e.g. "mode": ["light", "dark"])
  ├─ variables: [VariableInfo]     (name, type, isThemed, dependencies)
  └─ contextNodes: [String]        (node IDs that create theme boundaries)
```

**PropMapper** bridges the gap between ref overrides and component props. When a ref node overrides descendants (keyed by node ID), PropMapper uses `ComponentDefinition.propByNodeID` to match those IDs to named props, then formats the override values as JSX attributes.

These structures are target-agnostic. Each emitter consumes `(PenDocument, [ComponentDefinition], [PageDefinition], ThemeManifest)` and produces target-specific output files.

### 3.3 The Emit stage

Each target has its own emitter. The emitter walks the node tree and produces files:

| Output | React + Tailwind | HTML/CSS + WC | SwiftUI |
|---|---|---|---|
| Theme tokens | `theme.css` (CSS custom properties) | `tokens.css` + `themes.css` | `Theme/` (EnvironmentKeys + computed properties) |
| Components | One `.tsx` per component | `.gen.js` + `.js` stub per component | One `View` struct per component |
| Pages/Screens | One `.tsx` per top-level frame | `.html` + `.css` per frame | One `View` per top-level frame |
| Utilities | `cn.ts` (class merge) | `reset.css` | `Extensions/` (Color+Hex, custom modifiers) |
| Shapes | Inline SVG in JSX | Inline SVG in HTML | `Shapes/` (custom Shape types) |

---

## 4. Per-Target Strategies

### 4.1 React + Tailwind (recommended first target)

**Layout**: 1:1 mapping. Tailwind's flex utilities cover every .pen layout property.

**Styling strategy**: Tailwind classes for layout, sizing, solid colors, typography, border-radius, shadows, transforms, opacity. Inline `style` for gradients, complex transforms, and `var()` references.

**Components**: Each `reusable: true` node → function component `.tsx`. Props typed via interface derived from `ComponentDefinition` (which reads `_props`, `_role`, `_action`, `_bind`). Every component accepts `className`, `style`, `children`.

**Theming**: CSS custom properties in `theme.css`. Theme axes as `data-*` attributes. A `ThemeProvider` component manages attributes on the root element. Variable references emit as `var(--name)` in either Tailwind arbitrary values or inline styles.

**Interactivity**: Callback props (`onSubmit`, `onEmailChange`). Developers pass handlers at the call site. No generated file ever needs editing.

**Icons**: Import from `lucide-react`, `@phosphor-icons/react`, `react-feather`, or Material Symbols web font.

See: [Full React+Tailwind report](2026-03-28-codegen-react-tailwind.md)

### 4.2 HTML/CSS + Web Components

**Layout**: Same CSS flexbox as React, just without Tailwind's class abstraction.

**Components**: Each `reusable: true` node → Web Component class with Shadow DOM. Two-file pattern: `.gen.js` (regenerated) extends into `.js` (user-owned, created once). Props as observed attributes.

**Theming**: Same CSS custom properties approach. `data-*` attribute selectors for theme switching.

**Interactivity**: Subclass pattern. Users extend the generated base class and add event listeners in `connectedCallback`. Less ergonomic than React props but avoids framework dependencies entirely.

**Trade-off**: Zero dependencies (not even a bundler), but Web Component ergonomics are rougher for complex interactivity.

See: [Full HTML/CSS report](2026-03-28-codegen-html-css.md)

### 4.3 SwiftUI

**Layout**: `HStack`/`VStack` for horizontal/vertical. `ZStack` + `.position()` for absolute. Custom `Layout` protocol types for `space_between`/`space_around`. `.frame(maxWidth: .infinity)` for `fill_container`.

**Components**: Each `reusable: true` node → `View` struct. Props as init parameters. Closures for actions: `onSubmit: (() -> Void)?`. `@Binding` for two-way bindings.

**Theming**: Custom `EnvironmentKey` per theme axis. `@Environment` to read. `.environment()` modifier on context nodes.

**Interactivity**: The most idiomatic target. Closure parameters and `@Binding` are exactly how SwiftUI components are designed to work.

**Unique advantage**: Native `MeshGradient` (iOS 18+), full `Shape` protocol for all geometry, `UnevenRoundedRectangle` for per-corner radius.

See: [Full SwiftUI report](2026-03-28-codegen-swiftui.md)

---

## 5. Interactivity Boundary

### The principle

Generated code is a **pure function of props**. It accepts data and callbacks, and renders a visual tree. It never owns state, never fetches data, never makes decisions. All behavior lives in user-authored code that composes the generated components.

### Three tiers of customization

| Tier | Mechanism | Coverage |
|---|---|---|
| **Content** | `_props` mappings (text, colors, images, visibility) | ~80% of overrides |
| **Slots** | `children` / named content areas | ~15% of overrides |
| **Style** | `className` / `style` override props | ~5% of overrides |

### What happens when a developer needs more?

If the generated prop interface doesn't expose what a developer needs, the workflow is:

1. Developer identifies the missing prop
2. Designer adds it to `_props` / `_role` / `_action` / `_bind` in the .pen file
3. Code is regenerated — the new prop appears in the component interface
4. Developer wires it up

This feedback loop keeps the .pen file as the single source of truth. If a developer bypasses this and edits the generated file directly, they've forked the component — it can no longer be regenerated. The system is designed so this should rarely be necessary.

### Navigation and app-level wiring

Out of scope for v1. A button with `_action: "goHome"` generates an `onGoHome` callback prop. What that callback does — navigate, dismiss, reset — is the developer's decision. Full prototyping support (screen navigation, toolbars, status bars) would require encoding app-level concerns in the .pen file, which is a fundamentally different product scope.

---

## 6. Known Gaps

### Universal (all targets)

- **linearBurn / linearDodge blend modes** — rare Photoshop-legacy modes. Approximate as multiply/screen.
- **Per-shadow blend modes** — workaround via wrapper elements with mix-blend-mode.

### Web targets (HTML/CSS, React)

- **Mesh gradients** — no CSS equivalent. Rasterize to image at generation time.
- **Shadow spread on SVG shapes** — `drop-shadow()` lacks spread. SVG filter chain workaround.
- **Gradient strokes on rounded rectangles** — `border-image` breaks `border-radius`. SVG fallback.

### SwiftUI

- **Shadow spread** — `.shadow()` has no spread parameter. Enlarged background shape workaround.
- **Inner shadow** — custom ViewModifier with inverted mask.
- **Background blur radius** — Material system doesn't expose precise radius. `UIViewRepresentable` workaround.
- **Text justify** — no SwiftUI equivalent. Fall back to leading alignment.
- **space_between / space_around** — custom Layout protocol types required.

### No severe gaps in any target

Every .pen feature has at least a workable representation.

---

## 7. Fixture Requirements

### Must-have (blocks validation)

These .pen files don't exist yet and are needed before implementation can be validated:

1. **Component with `_props` metadata** — a reusable component with 3+ mapped props covering text, color, and image overrides
2. **Component with `_role` + `_action` + `_bind` metadata** — a form-like component with a button, text input, and toggle
3. **Multi-axis themed design** — at least two theme axes (e.g., mode: light/dark, density: compact/default) with variables that respond to both
4. **Nested component instances** — a ref that contains another ref, with overrides at both levels
5. **UI widget showcase** — a single .pen file demonstrating all supported `_role` values with realistic styling

### Nice-to-have (improves confidence)

6. Full-page layout (header/sidebar/content/footer)
7. Data table with repetitive component instances
8. Form layout with labels, inputs, and validation states
9. Mesh gradient (for rasterization fallback testing)
10. Complex strokes (per-side, gradient, dashed, inside/outside on rounded shapes)

### Already covered by existing fixtures

Layout, shapes, fills, text, gradients, effects, transforms, simple components/refs, variables, basic theming.

---

## 8. Implementation Phases

Test fixtures are ready in `woodcase-app.pen` (see [fixture enhancement plan](2026-03-28-fixture-enhancement-plan.md)).

### Phase 1: Foundation — Analysis Layer + Emitter Skeleton

**Goal:** Parse a `.pen` file, extract component and theme structures, and emit a minimal but correct React component for a simple leaf component (e.g., Stat Card: two text nodes in a vertical frame with solid fills).

**Deliverables:**
- Output types: `ComponentDefinition`, `PropDefinition`, `ActionDefinition`, `BindingDefinition`, `ThemeManifest`, `ThemeAxis`, `VariableInfo`
- `ComponentAnalyzer` — walks `PenDocument`, finds `reusable: true` nodes, extracts `_props`/`_role`/`_action`/`_bind` from metadata, infers prop types from target nodes
- `ThemeAnalyzer` — extracts theme axes, classifies variables (themed vs static, type), identifies context nodes
- `ReactEmitter` skeleton — enough to emit a single component `.tsx` with correct structure, typed props interface, and basic layout classes
- `ThemeEmitter` — generates `theme.css` with CSS custom properties and theme axis selectors

**Testing strategy:**
- Unit tests for `ComponentAnalyzer`: feed `PenDocument` with known metadata → assert `ComponentDefinition` fields
- Unit tests for `ThemeAnalyzer`: feed themed documents → assert `ThemeManifest` contents
- Golden file tests for emitter output: compare generated `.tsx`/`.css` strings against checked-in snapshots
- Integration test: `woodcase-app.pen` → analyzers → verify all expected components and theme axes are found

**Source layout (planned, deviated — see notes):**
```
Sources/Woodcase/CodeGen/
  ComponentAnalyzer.swift      ThemeAnalyzer.swift     PageAnalyzer.swift
  ComponentDefinition.swift    ThemeManifest.swift     PageDefinition.swift
  ReactEmitter.swift           ThemeEmitter.swift      PropMapper.swift
  GeneratedFile.swift
```

**Implementation notes (2026-03-28):** Phase 1 is complete. Key deviations and lessons:

*Deviations from plan:*

- **Flat file layout instead of subdirectories.** The plan called for `Analysis/`, `Models/`, and `Emit/` subdirectories under `CodeGen/`. In practice, Phase 1 only has 7 files — splitting them across 3 folders felt like premature organization. All files live directly in `Sources/Woodcase/CodeGen/`. This can be revisited if the directory grows.
- **`SlotDefinition` not implemented.** The `ComponentDefinition` in the plan included `slots: [SlotDefinition]`. The fixture has no slot metadata, and the design for slots isn't fleshed out yet. Deferred to Phase 3 when `children` passthrough is addressed.
- **`_bind` generates a binding name from the node name, not from an explicit `_bind` value.** The fixture uses `_role: "textInput"` on nodes without an explicit `_bind` key. The analyzer infers binding names by camelCasing the node name (e.g., node named "Field" → binding name "field"). If `_bind` were present, it would take precedence — but no fixture exercises that path yet, so there's no test for it.
- **Props sorted alphabetically.** The plan showed `value` before `label` in the Stat Card interface, matching the `_props` declaration order. Since `_props` is a dictionary (unordered), the implementation sorts props alphabetically for deterministic output. The golden file was updated to match.
- **Inline styles over Tailwind arbitrary values.** The plan suggested mixing Tailwind arbitrary values (`bg-[#hex]`, `rounded-[Npx]`) with inline styles. The implementation uses Tailwind classes only for layout properties (flex, gap, alignment) where there's a clean 1:1 mapping, and inline `style` for everything else (colors, sizing, padding, border-radius, shadows). This is more idiomatic React — Tailwind arbitrary values with CSS variables (`bg-[var(--x)]`) don't work well, and mixing the two styles of value application creates inconsistency. Phase 2 can revisit if a `tailwind.config.js` with the design system's tokens is generated alongside the components.

*Interesting discoveries:*

- **`PenLayoutDirection.none` collides with `Optional.none`.** Swift's exhaustive switch checking treats `.none` on an optional enum as ambiguous. The fix is `case .some(.none)` to explicitly match the enum case. Minor but easy to miss.
- **`PenImageFill` and other fill subtypes are nested inside `PenFill`.** They're declared as `PenFill.PenImageFill`, not top-level types. The naming convention (`PenImageFill`) makes them *look* top-level, so tests that reference them need the qualified name.
- **The fixture has 20 reusable components, not 10+.** Several components lack `_props` metadata entirely (screens, tab bar variants). The analyzer still picks them up as components — they just have zero props. This is correct behavior: a component with no props is still a valid component (it's a static visual element). Phase 3's page generation will need to distinguish screens from leaf components, likely via the `metadata.type` field or naming convention.
- **Variable fills decode as `.shorthand("$var-name")`.** When a fill is just `"$bg-card"` (a string), it decodes as `PenFill.shorthand("$bg-card")` — the `$` prefix is preserved in the shorthand string, unlike `PenValue.variable` which strips it. The emitter handles this by checking `hasPrefix("$")` and stripping it when generating `var(--name)`.
- **Themed variables in the fixture always have exactly 2 values** (one per axis value), with no explicit default. The ThemeEmitter uses the first themed value as the `:root` default. This works for the current fixture but may need revisiting if a variable has a `theme: nil` default entry — those should probably win over "first value" ordering.
- **No `_bind` metadata exists in the fixture.** The Text Input and Toggle Row components have `_role` on their interactive descendants but no `_bind` keys. The analyzer still generates bindings for binding-type roles (`textInput` → string binding, `toggle` → boolean binding), using the node name as the binding name. This means `_bind` is an override mechanism for naming, not a required annotation.

### Phase 2: Core Node Translation (React + Tailwind)

**Goal:** Translate all node types to JSX + Tailwind, covering the full visual feature set.

**Status:** Complete (2026-03-28). All 11 chunks done, 56 tests passing (51 unit + 5 golden/integration). The `EmitContext` refactor (Chunk 5) threaded icon import tracking through all emission methods. `emitVisualStyles` was extracted (Chunk 3) and shared across frame/rectangle/ellipse.

**Completed chunks:**
1. ✅ Strokes — inside (`border`), outside (`outline`), center, per-side, dashed, fill-from-variable
2. ✅ Clip + Absolute positioning — `overflow: hidden`, `position: absolute` with x/y, parent `relative`
3. ✅ Rectangles + Ellipses — `<div>` with sizing, fills, cornerRadius; ellipse with `borderRadius: 50%`
4. ✅ Groups — layout container without fills/strokes, reuses frame layout logic
5. ✅ Icon fonts — Lucide `<IconName size={N} />`, kebab-to-PascalCase, `import { ... } from "lucide-react"`, non-lucide placeholder
6. ✅ Extended text — textAlign, fontStyle, underline/strikethrough, href→`<a>`, textGrowth sizing, rich text spans
7. ✅ Image fills + Gradients + Multi-fill — image (`backgroundImage`+`backgroundSize`), linear/radial/angular gradients, multi-fill layering with `backgroundBlendMode`, enabled flag
8. ✅ Effects — inner shadows (`inset`), spread, blur (`filter`), background blur (`backdropFilter`+`WebkitBackdropFilter`), enabled flag
9. ✅ Transforms + Opacity + Blend modes + Enabled — rotation, flipX/Y, combined transforms, opacity, `display: none`, `mixBlendMode`
10. ✅ Polygons + SVG shapes — regular polygon SVG points, donut/arc ellipses via SVG `<path>`, `<path>` with geometry, `<line>` with stroke

11. ✅ Integration golden files — ScreenLab, PencilListItem, ActionButton, TextInput golden files; all-component crash test (20 components, all non-empty)

**Implementation notes & deviations:**

- **EmitContext introduced earlier than planned.** The plan placed it in Chunk 5 (icon fonts), but it required refactoring every emission method from `inout [String]` to `ctx: EmitContext`. This was the largest single refactor — touching `emitFrame`, `emitText`, `emitRef`, `emitGroup`, `emitRectangle`, `emitEllipse`, and `emitNode`. If a similar context-threading change is needed in a future emitter, do it in Chunk 1 to avoid a mid-stream refactor.
- **`emitFillAsBackground` kept as a backward-compatible wrapper.** Chunk 7 introduced the full `emitFillStyles` (returning `[(String, String)]` pairs for gradient/image/multi-fill), but existing code paths (frame fills, `emitVisualStyles`) still called `emitFillAsBackground`. Rather than changing the call sites twice, `emitFillAsBackground` was kept as a thin wrapper that delegates to `emitFillStyles` and extracts the simple case. Both it and the visual styles helper were later pointed at `emitFillStyles` directly.
- **`emitShadow` also kept as wrapper.** Same pattern — `emitEffects` returns all effect styles (boxShadow, filter, backdropFilter), while `emitShadow` survives as a backward-compatible helper that extracts just boxShadow. Future emitters should start with `emitEffects` directly.
- **FrameData init argument order matters.** `PenNode.FrameData.init` has a specific parameter order (`width, height, cornerRadius, clip, fills, stroke, effects, blendMode, layout, gap, ...`). Tests that constructed FrameData with `layout:` before `stroke:` failed to compile. Lesson: when writing synthetic test data, check the init order or use named parameters in the right sequence.
- **`PenSizing.fillContainer` requires `(fallback: nil)`.** The enum case has an associated value, so `.fillContainer` alone doesn't work — must be `.fillContainer(fallback: nil)`.
- **Foundation import needed for trig.** `cos`/`sin` for polygon point computation require `import Foundation`. The original ReactEmitter had no Foundation import since it was pure string manipulation.
- **`emitFillValueRaw` (unquoted) vs `emitFillValue` (JS-quoted).** Two parallel helpers emerged: `emitFillValueRaw` returns raw CSS (`var(--accent)`) for embedding inside CSS strings (strokes, SVG attributes), while `emitFillValue` returns JS-quoted values (`"var(--accent)"`) for inline style objects. This duality is a bit awkward — a future cleanup could unify them with a parameter.

**Testing strategy:**
- Per-feature unit tests with synthetic documents (51 tests)
- Golden file comparison (StatCard; more in Chunk 11)
- Integration tests: full components from `woodcase-app.pen` → golden file comparison

### Phase 3: Component & Theme Generation

**Goal:** Generate complete, usable component files and theme infrastructure.

**Status:** Complete (2026-03-28). All 9 chunks done, 35 new tests (total suite: 671 tests across 53 suites). The generated output is now self-contained: `components/*.tsx`, `pages/*.tsx`, `lib/cn.ts`, `ThemeProvider.tsx`, and `theme.css`.

**Completed chunks:**
1. ✅ ID-to-name bridge — `PropDefinition.targetNodeID`, computed `ComponentDefinition.propByNodeID` for matching ref override keys
2. ✅ PropMapper — standalone type mapping `[nodeID: PenDescendantOverride]` → `[(propName, jsValue)]` for string, color, boolean, imageURL
3. ✅ Ref instantiation with props — component registry on `EmitContext`, `emitRef()` resolves names and passes props via PropMapper
4. ✅ Root overrides on refs — `rootOverrides` → inline `style` prop (width, height, cornerRadius), `fill_container` → `"100%"`
5. ✅ Page detection & emission — `PageAnalyzer` (non-reusable top-level frames), `emitPage()` with component imports, no props interface
6. ✅ Theme & utility files — `ThemeProvider.tsx` from `ThemeManifest` axes, `lib/cn.ts` (static), `theme.css` via `ThemeEmitter`
7. ✅ Complete file structure — `emit()` returns full file set, existing tests updated for expanded output
8. ✅ CLI integration — `woodcase generate react <input.pen> --output <dir>` with `--library` support
9. ✅ Integration golden files — HomeCollection (with refs), ScreenSettings (with refs), ThemeProvider, cn.ts golden files

**Deliverables:**
- Component file generation — one `.tsx` per `reusable: true` node, with typed props interface, default values, `className`/`style` passthrough
- Ref instantiation — `ref` nodes emit `<ComponentName prop={value} />` instead of flattened clones
- Descendant overrides → prop values at call sites
- Theme infrastructure — `theme.css`, `ThemeProvider.tsx`, variable-backed values as `var(--name)`
- Page/screen generation — top-level non-reusable frames as page components
- File structure generation — `components/`, `pages/`, `lib/`
- CLI integration — `woodcase generate react <input.pen> --output <dir>`

**Implementation notes & deviations (2026-03-28):**

*Deviations from plan:*

- **`propByNodeID` is computed, not stored.** The plan called for building this dictionary once during init and storing it. However, since `ComponentDefinition` conforms to `Friendly` (which includes `Codable`), a stored property would require either custom `CodingKeys` or a custom `Codable` implementation. A computed property sidesteps this entirely — it's derived from `props` which are already stored, and the dictionary is small enough that recomputation is negligible. This also keeps `Equatable` synthesis correct (two definitions with the same props are equal regardless of when `propByNodeID` was accessed).
> **Superseded 2026-09-02.** `propByNodeID: [String: String]` is now
> `propsByNodeID: [String: [PropDefinition]]`. The one-to-one dictionary was built with
> `Dictionary(uniqueKeysWithValues:)`, so a second `_props` entry naming a descendant
> another entry already named **trapped** the emitter (`Duplicate values for key`) the
> first time an instance overrode that descendant. One node legitimately carries several
> props — one per field it exposes — so the lookup is one-to-many; two props of the same
> type on one node are ambiguous, which `lint` reports under `codegen-prop-path` and the
> mapper resolves by keeping the first by prop name.

- **PropMapper sorts output by prop name.** The plan didn't specify ordering, but deterministic output is a project-wide principle. Sorting by name ensures golden files don't fluctuate when dictionary iteration order changes.
- **All fixture top-level frames are `reusable: true` — no pages detected.** The plan defined pages as "top-level frame that is NOT `reusable: true`." The `woodcase-app.pen` fixture marks all top-level frames as reusable, including screens like "Home - Collection" and "Component/Screen/Settings." This means `PageAnalyzer.analyze()` returns an empty list for the current fixture. This is correct behavior — these screens are components that reference other components, not application pages. True pages (non-reusable, representing routes) would appear in a larger fixture with an app shell. The `emitPage()` codepath is tested with synthetic documents instead.

  > Correction (2026-09-02): "tested with synthetic documents instead" was the whole of the
  > page coverage for five months, and it was not enough. No golden ever saw an emitted
  > page, so `pages/*.tsx` shipped referencing an undeclared `className` and `style` — every
  > emitted page failed to compile — and nothing went red. Pages now have golden coverage of
  > their own: `Tests/WoodcaseTests/Fixtures/pages.pen` is the small hand-readable document
  > this deviation said would be needed (two non-reusable top-level frames, one holding an
  > instance of a reusable `Card` with a descendant override that maps to a declared prop),
  > and `ReactEmitterPageGoldenTests` runs the four analyze-then-emit steps
  > `woodcase generate react` runs over it and pins `Fixtures/golden/pages/Home.tsx.golden`
  > and `About.tsx.golden`. `woodcase-app.pen` is unchanged and still detects no pages; the
  > answer was a second fixture, not a change to that one.
- **Old `emit()` overload preserved as delegation.** Rather than breaking all existing callers, the original `emit(document:components:theme:)` signature delegates to the new `emit(document:components:pages:theme:)` with an empty pages array. This maintains backward compatibility for Phase 2's golden tests without requiring them to supply a pages argument.
- **`capitalizingFirst` String extension added to ReactEmitter.swift.** The ThemeProvider generator needs `mode` → `Mode` for `setMode`/`setDensity` state setters. This is a module-internal extension (no `public` keyword), scoped to the code generation use case. If other emitters need it, it should move to a shared `String+CodeGen.swift` file.
- **ScreenLab golden file updated for root overrides.** The StatusBar ref in ScreenLab has `width: "fill_container"` as a root property. Phase 2's golden expected `<StatusBar />` (bare tag). Phase 3's root override handling correctly emits a `style` block with `width: "100%"`. The golden was updated to match.

*Interesting discoveries:*

- **Ref override keys are raw node IDs, not name paths.** The `descendants` dictionary on a ref uses short alphanumeric IDs like `"GVI65"`, `"f9B3c"`, `"qOnVZ"` — not the human-readable name paths from `_props` like `"Info/Name"`. This validated the plan's D1 decision (ID-to-name bridge): without `targetNodeID` on `PropDefinition`, there's no way to connect a ref's `"f9B3c": { "content": "Blackwing 602" }` override to the component's `name` prop (which maps to path `"Info/Name"` → resolved node ID `"f9B3c"`). The bridge is load-bearing.
- **Root overrides and descendant overrides live at different levels.** Root overrides (`width`, `height`, `x`, `y`) are top-level properties on the ref node itself, while descendant overrides are in the `descendants` dictionary. This is a clean separation: root overrides control the *container* (how the instance is sized/positioned in its parent), while descendant overrides control the *content* (text, colors, images inside the component).
- **Color overrides have multiple shapes.** A color fill override can be a shorthand string (`"#FF5500"`, `"$primary"`), a color fill object (`{ type: "color", color: "#hex" }`), or a variable reference inside a fill object (`{ type: "color", color: "$primary" }`). PropMapper handles all three forms, with variable references emitted as `var(--name)`.
- **Most descendant overrides are positional, not content.** In the real fixture, the majority of descendant overrides are `{ "x": N, "y": N }` position adjustments, not content changes. These don't match any props (they're layout tweaks for specific instances) and are correctly skipped by PropMapper. Only `"content"`, `"fill"`, and `"enabled"` keys produce mapped props.
- **`ThemeProvider.tsx` shape is fully deterministic from axes.** With two axes (`mode: [light, dark]`, `density: [default, compact]`), the ThemeProvider generates exactly two `useState` hooks, two context type entries, and two `data-*` attributes. If a fixture had a third axis (e.g., `contrast: [normal, high]`), the output scales linearly — no special handling needed.

**Testing strategy:**
- Unit tests for PropMapper: each prop type (string, color, boolean, imageURL), edge cases (no match, multiple overrides) — 8 tests
- Unit tests for PageAnalyzer: page detection, exclusion rules, ref collection — 6 tests
- Integration tests for ComponentAnalyzer: targetNodeID resolution, propByNodeID lookup, nested paths — 5 tests
- Integration tests for ReactEmitter: ref instantiation (bare, with props, multiple), root overrides (width/height, combined, fill_container), page emission (paths, imports, no interface), theme files, complete file manifest — 16 tests
- Golden file tests: HomeCollection, ScreenSettings (both contain refs with overrides), ThemeProvider, cn.ts

### Phase 4: Visual Regression via WebView

**Goal:** Render generated React code in a WebView and MAE-compare against Woodcase's own pixel render.

**Status:** In progress. Chunks 1–2 complete (harness + builder). Chunks 3–5 partially working — renders execute but visual fidelity issues in the generated code are surfacing.

**Full plan:** [Phase 4 Plan](2026-03-28-phase4-plan.md)

**Deliverables (implemented so far):**
- `WebViewTestHarness` (`Tests/WoodcaseTests/WebViewTestHarness.swift`) — `@MainActor` class that loads HTML into `WKWebView`, polls for `window.__READY__` signal, captures screenshot via `takeSnapshot`. 4 tests passing.
- `ReactHarnessBuilder` (`Sources/Woodcase/CodeGen/ReactHarnessBuilder.swift`) — assembles a self-contained HTML document from `[GeneratedFile]` output. Inlines React 18.3.1, ReactDOM, Babel standalone, and Tailwind 3.4.17 from local JS files in `Tests/WoodcaseTests/Fixtures/js/`. Uses `<script type="text/plain">` + `Babel.transform()` with TypeScript+React presets to compile TSX. Strips ES module imports/exports, exposes React hooks as globals, generates lucide-react icon stubs (empty SVGs). Optionally embeds `.ttf` fonts as base64 `@font-face` declarations. 5 tests passing.
- `WebViewRegressionTests` (`Tests/WoodcaseTests/WebViewRegressionTests.swift`) — 11 tests comparing Woodcase pixel render vs WebView render. Uses `.webViewRegression` tag for CI filtering.

**Key architectural decisions made during implementation:**

1. **No CDN/network — all JS bundled locally.** React 18.3.1, ReactDOM, Babel standalone 7.26.10, and Tailwind 3.4.17 are downloaded as pinned JS files into `Tests/WoodcaseTests/Fixtures/js/` (~3.5MB total). The existing `.copy("Fixtures")` resource bundle in Package.swift covers them automatically.

2. **`Babel.transform()` instead of `<script type="text/babel">`**. Babel standalone's auto-processing of `type="text/babel"` scripts fails silently in WKWebView (cross-origin error reporting). Instead, user code goes into a `<script type="text/plain" id="user-code">` block, and a regular `<script>` reads it via `.textContent` and compiles it with `Babel.transform(src, { presets: [Babel.availablePresets["typescript"], Babel.availablePresets["react"]], filename: "component.tsx" })`. Errors are caught and rendered as red text (with `__READY__` still signaled so tests don't hang).

3. **Polling instead of async continuation for `__READY__`.** Swift 6's region-based isolation checker rejects `withThrowingTaskGroup` + `@MainActor` closures. The harness polls `delegate.isReady` every 50ms with `ContinuousClock` deadline instead.

4. **Separate document pipelines for components vs screens.** `ComponentAnalyzer.analyze()` must run on the *raw parsed* document (before `PenRefExpander.expand()`) because expansion strips reusable component definitions. For component-level rendering, the Woodcase pixel renderer uses `PenVariableResolver.resolve(parsed)` (resolved but not expanded). For screen-level rendering, it uses the fully expanded+resolved document.

5. **Fonts embedded as base64 `@font-face`.** The test harness passes a `fontDir` URL to `ReactHarnessBuilder.buildHTML()`, which reads `.ttf` files, base64-encodes them, and emits `@font-face` CSS. This is a test-only concern — the generated React output references font families by name (e.g. `'IBM Plex Sans'`) as the user would load via Google Fonts in production.

6. **Lucide-react icon stubs.** The builder scans `import { X } from "lucide-react"` statements across all generated files and emits stub functions that render empty `<svg>` elements with the correct `size` and `color` props. This prevents runtime errors but produces blank icon areas.

**Current MAE results (as of 2026-03-28):**

| Component | MAE | Notes |
|-----------|-----|-------|
| StatusBar | 0.21 | Nearly identical |
| ActionButton | 1.07 | Solid fill, no variables — excellent |
| PencilListItem | 9.56 | Text differences |
| HomeCollection screen | 10.07 | Full page, good overall |
| Lab screen | 12.72 | Full page, good overall |
| FavoriteCard | 19.71 | Border/shadow differences |
| TabBarHomeActive | 26.43 | Icon stubs leave blank areas |
| TextInput | 49.44 | Border-radius unitless variable |
| StatCard | 80.35 | `box-shadow` + unitless `--card-radius` |

**Known issues to fix (all are code gen bugs, not threshold issues):**

1. **Unitless CSS variables.** `ThemeEmitter` emits raw numbers for sizing variables (e.g., `--card-radius: 16` without `px`). When referenced as `border-radius: var(--card-radius)`, browsers treat unitless values as invalid. This is the #1 source of visual mismatch. **Fix:** `ThemeEmitter.formatValue()` needs to append `px` for numeric values used in length contexts. This requires knowing which variables are lengths vs plain numbers — may need a type hint in the `ThemeManifest`.

2. **`box-shadow` rendering.** The `var(--shadow)` CSS variable is a color (e.g., `#C67A5215`), but the shadow itself needs x/y/blur values. Need to verify the emitted `boxShadow` style property includes the full shadow declaration.

3. **Icon rendering gaps.** Lucide-react icons render as empty SVGs. The icon font system in Woodcase uses a different mechanism. This creates blank areas where icons should be.

4. **Font rendering differences.** Core Text (Woodcase) vs WebKit font rendering produces subtle differences in glyph metrics, anti-aliasing, and line height. These are expected and should be handled with appropriate MAE thresholds once the above bugs are fixed.

5. **Two test components not found.** `"NavigationBar"` is not a valid component name in the fixture. Need to check actual names via `ComponentAnalyzer.analyze()` output.

6. **Settings screen timeout.** The Settings page references `SlidersHorizontal` icon which isn't stubbed because the page file imports are processed differently. Needs investigation.

**Remaining work:**
- Fix `ThemeEmitter` unitless CSS variables (Chunk 4 scope)
- Verify box-shadow emission
- Calibrate MAE thresholds after code gen bugs are fixed
- Complete Chunk 5 (full-screen tests) — HomeCollection and Lab already pass
- Chunk 6: documentation updates, `.webViewRegression` tag for CI filtering

**Testing strategy:**
- Per-component visual tests: render component in WebView → MAE vs Woodcase render
- Per-screen visual tests: render full pages → MAE vs Woodcase render
- Thresholds to be set after code gen bugs are fixed (target: MAE < 15 shapes, < 25 text-heavy)

### Phase 5: Additional Targets

**HTML/CSS + Web Components** — shares ~80% of CSS logic with React target. Different component model (Shadow DOM, observed attributes, subclass pattern).

**SwiftUI** — most divergent. Custom `Layout` types for `space_between`/`space_around`, `Shape` protocol for geometry, `@Environment` for theming. Benefits from lessons learned on web targets.

### Dependency Graph

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4
                                 ╲
                                  ──→ Phase 5
```

Phases 4 and 5 can proceed in parallel after Phase 3.
