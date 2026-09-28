# Interactive Component States

**Date:** 2026-03-30\
**Status:** Design complete, implementation not started\
**Related:** [Codegen Design](2026-03-28-codegen-design.md)

---

## 1. Problem

Generated components are static — a button looks the same whether hovered, pressed, or disabled. For a component library tool, interactive states are table stakes. Without them, the output feels like a picture of a button, not a real button.

## 2. Three-Layer Design

### Layer 1: Smart Defaults (no designer input)

When a component has `_role: "button"` but no explicit state variants, the code generator auto-generates sensible interactive styling. The specific output depends on the target framework — for React/CSS, these are properties that don't conflict with inline styles:

| State | Example (React/CSS) |
|-------|---------------------|
| hover | `filter: brightness(0.95)` |
| pressed | `transform: scale(0.98)` |
| focused | `outline: 2px solid currentColor; outline-offset: 2px` |
| disabled | `opacity: 0.5; pointer-events: none` |

Smart defaults are applied per-role and serve as a gap-filler — they're only used for states the designer hasn't explicitly overridden.

### Layer 2: Designer Overrides

Designers create state variants using a naming convention. A reusable component named `StandardButton` can have sibling frames named:

- `StandardButton:hover`
- `StandardButton:pressed`
- `StandardButton:disabled`

The analyzer discovers these automatically by scanning for `{Name}:{state}` siblings. A node diffing engine compares the base and variant trees to extract only the properties that change, which the target emitter converts to state-specific styling.

The `_states` metadata provides a fallback for cases where the naming convention doesn't fit:

```json
{ "_states": { "hover": "node-id-of-hover-frame" } }
```

### Layer 3: Binding-Driven States

Same mechanism as Layer 2, but the trigger is a bound prop value rather than a user interaction. A toggle with `_bind: "enabled"` and a sibling `Toggle:on` produces a state definition whose trigger is the binding value. The target emitter decides how to implement this — for React/CSS, that's a data-attribute selector:

```css
.wc-toggle[data-enabled="true"] { --wc-toggle-bg: #34C759; }
```

From the designer's perspective, Layers 2 and 3 are identical — "here's what my component looks like in this other state." The emitter decides how to implement each state trigger based on the component's role and the state name.

## 3. Architecture

### Generic vs. React-Specific

The state system is designed to work across any code generation target (React, SwiftUI, vanilla HTML/CSS). The architecture splits cleanly:

**Generic layer** (`Sources/Woodcase/CodeGen/`):

| Module | Responsibility |
|--------|---------------|
| `StateDefinition` | Data model: state name, trigger type, source (smart/designer/binding), property deltas |
| `StateDelta` | Data model: node path + list of property changes (pen-level, not CSS-level) |
| `ComponentRole` | Enum of interactive roles (button, link, toggle, textInput, select) with known states per role |
| `RoleStateMapping` | Maps (role, state name) to trigger type; generates smart default deltas per role |
| `NodeDiffer` | Compares base and variant PenNode trees, produces platform-neutral `StateDelta` values; detects structural changes (added/removed/reordered children) |
| `ComponentAnalyzer` (modified) | Discovers state variants from `{Name}:{state}` siblings and `_states` metadata |
| `ComponentDefinition` (modified) | Gains `states: [StateDefinition]` and `role: ComponentRole?` fields |

**React-specific layer** (`Sources/Woodcase/CodeGen/React/`):

| Module | Responsibility |
|--------|---------------|
| `StateEmitter` | Maps pen-level deltas to CSS properties; generates `states.css` with CSS variables and pseudo-selector rules |
| `ReactEmitter` (modified) | Semantic HTML elements from roles; `var()` substitution for state-affected properties; data attributes for binding states |

The key distinction: `NodeDiffer` produces **pen-level property changes** (fills changed, opacity changed, cornerRadius changed). The React `StateEmitter` converts those to **CSS property changes** (backgroundColor, opacity, borderRadius). A future SwiftUI emitter would convert the same pen-level deltas to SwiftUI modifiers.

### CSS Variable Strategy (React-specific)

The React emitter faces a specificity challenge: components emit visual styles as inline `style={{}}`, and inline styles have the highest CSS specificity — `:hover` class rules can't override them.

**Solution**: For any CSS property that has a state variant, the React emitter replaces the literal inline value with a `var()` reference. The base and state values live in `states.css`:

```css
/* states.css */
.wc-action-button { --wc-action-button-bg: #007AFF; }
.wc-action-button:hover { --wc-action-button-bg: #0051D5; }
.wc-action-button:disabled { --wc-action-button-bg: #CCCCCC; opacity: 0.5; pointer-events: none; }
```

```tsx
/* Component JSX — only state-affected props use var() */
<button
  className={cn("wc-action-button flex items-center", className)}
  style={{ backgroundColor: "var(--wc-action-button-bg)", borderRadius: 12, ...style }}
>
```

Properties without state variants remain as direct inline values. Layer 1 smart defaults use `filter`, `transform`, `outline` — properties that are never set as inline styles — so they work as simple additive CSS rules without needing the var() approach at all.

Other emitters (SwiftUI, etc.) won't face this specificity issue and can implement state styling using their platform's native mechanisms (e.g., `.buttonStyle` modifiers, `@State` property wrappers).

### Node Matching & Structural Detection

The differ walks both base and variant trees in parallel, matching children by `common.name`. For each state variant, it classifies the diff as one of two kinds:

**Property-only diff**: The tree structure is identical — same children in the same order, just different visual properties (colors, opacity, corners, text styles, etc.). This is the common case (hover, pressed, disabled). The emitter handles this with CSS-only mechanisms (CSS variables, pseudo-selectors).

**Structural diff**: The variant has added, removed, or reordered children compared to the base. Examples: a loading spinner appears in a `:loading` state, or a checkmark icon is added in a toggle's `:on` state. CSS can't express this.

The differ detects structural changes automatically during name-matching — if any children exist in one tree but not the other, or the child order differs, the state is flagged as structural. The `StateDefinition` carries an `isStructural: Bool` flag.

### Structural State Emission (React-specific)

When a state is structural, the React emitter generates the variant as a **separate internal render function** and conditionally switches at runtime:

```tsx
function ButtonDefault({ label, className, style }: ButtonProps) {
  return <button style={{ ... }}>{ label }</button>;
}

function ButtonLoading({ label, className, style }: ButtonProps) {
  return <button style={{ ... }}><Spinner /> { label }</button>;
}

export function Button({ loading, ...props }: ButtonProps) {
  return loading ? <ButtonLoading {...props} /> : <ButtonDefault {...props} />;
}
```

This is idiomatic React and gives designers full flexibility — they don't need to know whether a state change is CSS-only or structural. The differ decides automatically based on the tree comparison.

In practice, structural diffs should be rare. Most hover/pressed/disabled variants just change colors and opacity. The common case stays lightweight (CSS-only), and the component swap is an automatic fallback for the uncommon case.

If names are ambiguous (two siblings with the same name), the differ emits a diagnostic warning and skips the ambiguous nodes.

### Role Mappings

**Known states per role:**

| Role | Known States | Trigger Type |
|------|-------------|--------------|
| button | hover, pressed, disabled, focused | interaction (pseudo-selector in CSS targets) |
| link | hover, active, focused | interaction |
| toggle | on, disabled, focused | on = binding value; disabled/focused = interaction |
| textInput | focused, filled, disabled | focused/disabled = interaction; filled = binding non-empty |
| select | focused, open, disabled | open = internal state; focused/disabled = interaction |

Each emitter maps these generic trigger types to its platform's mechanism. For React/CSS:

| Trigger Type | CSS Mechanism |
|-------------|---------------|
| hover | `:hover` pseudo-class |
| pressed | `:active` pseudo-class |
| disabled | `:disabled` pseudo-class |
| focused | `:focus-visible` or `:focus-within` pseudo-class |
| binding value | `[data-{name}="value"]` attribute selector |

**Semantic elements** (React/web — currently everything emits as `<div>`):

| Role | Element |
|------|---------|
| button | `<button type="button">` |
| link | `<a>` |
| toggle | `<button role="switch" aria-checked={value}>` |
| textInput | `<div>` (wrapper; actual `<input>` is deeper) |
| select | `<div>` (wrapper; actual `<select>` is deeper) |

A future SwiftUI emitter would map the same roles to `Button`, `Link`, `Toggle`, `TextField`, and `Picker`.

## 4. Discovery Priority

When resolving states for a component, the analyzer applies this priority:

1. **Explicit `_states` metadata** — highest priority, always wins
2. **`{Name}:{state}` naming convention** — auto-discovered from siblings
3. **Smart defaults from role** — gap-filler for states not covered by 1 or 2

If a designer specifies `StandardButton:hover`, the smart default hover is suppressed. If they don't, it's applied. This is progressive disclosure: zero configuration gets you working interactivity; explicit variants give you precise control.

## 5. Implementation Plan

### Part A: Generic Infrastructure (Phases 1–4)

Self-contained, testable without any React emission changes. Establishes the data models, diffing engine, and analyzer extensions.

**Phase 1 — Data Models**

Create:
- `Sources/Woodcase/CodeGen/StateDefinition.swift` — `StateDefinition` (name, trigger, source, deltas, `isStructural: Bool`), `StateTrigger`, `StateSource`
- `Sources/Woodcase/CodeGen/StateDelta.swift` — `StateDelta` with pen-level property changes (not CSS); for structural states, also carries the full variant `PenNode` for re-emission
- `Sources/Woodcase/CodeGen/ComponentRole.swift` — role enum with known states and semantic element mappings

Modify:
- `Sources/Woodcase/CodeGen/ComponentDefinition.swift` — add `states: [StateDefinition]`, `role: ComponentRole?`

Tests: `StateDefinitionTests.swift`, `ComponentRoleTests.swift`

**Phase 2 — Role-State Mapping**

Create:
- `Sources/Woodcase/CodeGen/RoleStateMapping.swift` — smart defaults per role (pen-level deltas), trigger resolution

Tests: `RoleStateMappingTests.swift`

**Phase 3 — Node Differ**

Create:
- `Sources/Woodcase/CodeGen/NodeDiffer.swift` — recursive tree diff producing `DiffResult`
  - `DiffResult` contains `deltas: [StateDelta]` and `isStructural: Bool`
  - Matches children by name; detects added/removed/reordered children → structural
  - Compares: fills, stroke, effects, cornerRadius, opacity, dimensions, text styles, padding, gap
  - Returns only changed properties with pen-level identifiers
  - When structural, also preserves the full variant node for re-emission by target emitters

Tests: `NodeDifferTests.swift` — identical trees (empty), single property change, nested changes, text changes, name-based matching, added child → structural, removed child → structural, reordered children → structural

**Phase 4 — Analyzer State Discovery**

Modify:
- `Sources/Woodcase/CodeGen/ComponentAnalyzer.swift`:
  - Two-pass approach: first collect reusable components, then scan for `{Name}:{state}` siblings
  - Parse role from `_role` metadata
  - Run `NodeDiffer.diff()` for each variant, build `StateDefinition`
  - Merge with `_states` metadata fallback
  - Fill gaps with `RoleStateMapping.smartDefaults()`

Tests: Extend `ComponentAnalyzerTests.swift`

**Part A delivers**: `ComponentDefinition` instances now carry a `role` and a fully-resolved `states` array. No generated output changes yet — existing tests unaffected.

---

### Part B: React Emission (Phases 5–7)

Builds on Part A. Changes generated output — golden tests will need regeneration.

**Phase 5 — State CSS Emission**

Create:
- `Sources/Woodcase/CodeGen/React/StateEmitter.swift`:
  - Converts pen-level deltas from `StateDelta` to CSS property changes
  - Generates `states.css` with scoped CSS classes (`wc-{kebab-name}`)
  - Emits CSS custom property declarations and pseudo-selector/data-attribute overrides
  - Exposes `stateAffectedProperties(for:)` for ReactEmitter to know which inline properties need `var()` substitution

Tests: `StateEmitterTests.swift`

**Phase 6 — ReactEmitter Integration**

Modify:
- `ReactEmitter.swift` — include `states.css` in output, extend `EmitContext` with state tracking
- `ReactEmitter+Frame.swift` — semantic element tags from roles, `wc-*` CSS classes, data attributes; for structural states, emit separate internal render functions and a conditional switch at the component root
- `ReactEmitter+Styles.swift` — `var()` substitution for state-affected properties via `maybeVar()` helper
- `ReactEmitter+Interface.swift` — `disabled?: boolean` prop for applicable roles; state-trigger props (e.g., `loading?: boolean`) for structural states
- `PackageScaffolder.swift` — keep `states.css` at root, import in `theme.css` preamble
- `ManifestEmitter.swift` — include states in manifest for viewer

Regenerate golden fixtures: `UPDATE_GOLDEN=1 swift test --filter "ReactEmitterTests"`

**Phase 7 — Documentation & Viewer**

Modify:
- `PenCodeGen.md` — state discovery, NodeDiffer, StateEmitter, ComponentRole, semantic elements
- `WoodcaseCLI.md` — `states.css` in output structure
- Viewer `App.tsx` template — optional: state toggle buttons in component preview

---

## 6. Open Questions

- **Transform conflicts**: Smart default "pressed" uses `transform: scale(0.98)`, but some components may already have inline transforms (rotation, flip). Need to detect this and either merge transforms or skip the smart default.
- **Node matching ambiguity**: Two children with the same name can't be distinguished. Should emit diagnostic and skip.
- **Nested state variants**: Can a component inside a page have its own state variants? Current plan: yes, but only top-level reusable components are scanned for `{Name}:{state}` siblings.

## 7. Metadata Convention Extension

This extends the existing metadata conventions from the [codegen design doc](2026-03-28-codegen-design.md). New conventions:

### `_states` — Explicit State Variant Mapping

Maps state names to node IDs of variant frames. Used when the `{Name}:{state}` naming convention isn't sufficient.

```json
{
  "metadata": {
    "_role": "button",
    "_states": {
      "hover": "node-id-of-hover-variant",
      "disabled": "node-id-of-disabled-variant"
    }
  }
}
```

### `{ComponentName}:{stateName}` — Naming Convention

Any non-reusable frame whose name matches `{ReusableComponentName}:{stateName}` is treated as a state variant. The state name is parsed from the suffix after the colon. Well-known state names are mapped to platform-appropriate triggers by the role; unknown state names are passed through as generic data-driven triggers (e.g., data-attribute selectors in CSS targets, custom state properties in SwiftUI).
