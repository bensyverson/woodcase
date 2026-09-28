# Research: .pen to React + Tailwind CSS Code Generation

## 1. Can We Achieve 100% 1:1 Mapping?

**Short answer: No, but approximately 85-90% maps idiomatically to Tailwind, with the remaining 10-15% handled by inline styles or SVG.** The gaps are concentrated in gradients (inline style territory), exotic shapes (SVG), and mesh gradients (no CSS equivalent). None are showstoppers.

### Layout -- FULL COVERAGE

The .pen layout system is essentially CSS flexbox, which is Tailwind's strongest area.

- `layout: horizontal/vertical` -> `flex flex-row` / `flex flex-col`
- `layout: none` -> no flex; children use absolute positioning
- `gap` -> `gap-[{n}px]`
- `padding` -> `p-[{n}px]`, `px-[{h}px] py-[{v}px]`, or `pt/pr/pb/pl`
- All 5 `justifyContent` values -> `justify-start/center/end/between/around`
- All 3 `alignItems` values -> `items-start/center/end`
- `fixed(n)` -> `w-[{n}px]` / `h-[{n}px]`
- `fitContent` -> `w-fit` / `h-fit`
- `fillContainer` -> `flex-1` in flex context, or `w-full`/`h-full` outside
- `layoutPosition: absolute` -> `absolute left-[{x}px] top-[{y}px]` (parent needs `relative`)
- `clip: true` -> `overflow-hidden`

### Fills -- MOSTLY COVERED, some inline styles required

- **Solid color**: `bg-[#RRGGBB]` -- direct
- **Linear gradient**: Tailwind v4 has limited gradient support (axis-aligned only). Rotated gradients need inline style `background: linear-gradient(...)`.
- **Radial gradient**: Inline style only
- **Angular/conic gradient**: Inline style only
- **Image fill**: `object-fill`/`object-cover`/`object-contain`
- **Mesh gradient**: **No CSS equivalent**
- **Multiple fills**: CSS background stacking or absolutely-positioned elements
- **Per-fill blend mode**: Requires wrapping each fill in its own element with `mix-blend-mode`

Key decision: Use Tailwind for solid colors. Use inline styles for gradients (the CSS gradient syntax is already a string expression; wrapping it in Tailwind's arbitrary value syntax is less readable).

### Shapes -- CSS for rectangles, SVG for everything else

- **Rectangle**: `<div>` with `rounded-[...]` classes. Per-corner: `rounded-tl-[{n}px]` etc.
- **Ellipse (simple)**: `<div>` with `rounded-full`
- **Ellipse (arc/donut)**: `<svg>` required
- **Polygon**: `<svg><polygon>` or `<svg><path>`
- **Line**: `<svg><line>`
- **Path**: `<svg><path d="...">`

### Text -- FULL COVERAGE

- `fontFamily`: `font-['{family}']` or inline `style.fontFamily`
- `fontSize`: `text-[{n}px]`
- `fontWeight`: `font-bold`, `font-[700]`, etc.
- `fontStyle: italic`: `italic` class
- `letterSpacing`: `tracking-[{n}px]`
- `lineHeight`: `leading-[{n}]` (unitless multiplier)
- `textAlign`: `text-left/center/right/justify`
- `textAlignVertical`: Wrapping flex container with `items-start/center/end`
- `underline`/`strikethrough`: `underline` / `line-through`
- `href`: Wrap in `<a href="...">`
- Rich text: Nested `<span>` elements with per-span styles
- Gradient text: `bg-clip-text text-transparent` + gradient background

### Effects -- NEAR-FULL COVERAGE

- **Outer shadow**: `shadow-[{x}px_{y}px_{blur}px_{spread}px_{color}]` or inline `boxShadow`
- **Inner shadow**: `shadow-[inset_...]`
- **Multiple shadows**: Comma-separated in single property
- **Blur**: `blur-[{radius}px]`
- **Background blur**: `backdrop-blur-[{radius}px]`

### Blend Modes -- 13 of 16

All standard CSS blend modes map to `mix-blend-{mode}`. Missing: `linearBurn`, `linearDodge`, `light` (map to nearest CSS equivalent).

### Transforms -- FULL COVERAGE

- `rotation`: `rotate-[{deg}deg]`
- `flipX`: `scale-x-[-1]`
- `flipY`: `scale-y-[-1]`
- `opacity`: `opacity-[{n}]`

### Strokes -- PARTIAL

- Uniform thickness: `border-[{n}px]`
- Per-side thickness: `border-t-[{n}px]` etc.
- Inside alignment: Approximated with `box-shadow: inset`
- Outside alignment: Approximated with `outline` or `box-shadow`
- Gradient stroke: `border-image` for rectangles (breaks border-radius); SVG for shapes
- Dash patterns: SVG only

### Icon Fonts -- FULL COVERAGE

| .pen Family | React Package |
|---|---|
| lucide | `lucide-react` |
| feather | `react-feather` |
| phosphor | `@phosphor-icons/react` |
| material-symbols | `@material-symbols/font-*` (web font) |

---

## 2. Complete Gap List

### Moderate Gaps

| Gap | Why | Mitigation |
|---|---|---|
| **Mesh gradients** | No CSS equivalent | Rasterize to image at build time |
| **Ellipse arcs and donuts** | No CSS equivalent for `startAngle`/`sweepAngle`/`innerRadius` | Emit inline SVG |
| **Inside/outside stroke alignment** | CSS `border` is always center-aligned | Approximate with `box-shadow` |
| **Multiple fills with different blend modes** | Requires stacking separate DOM elements | Generate extra wrapper elements |
| **linearBurn/linearDodge/light blend modes** | Not in CSS spec | Map to nearest equivalent |
| **Angular gradients with custom center/size** | CSS `conic-gradient()` has limited center support | `background-size`/`background-position` manipulation |
| **Per-fill opacity on gradient fills** | Can't set opacity on individual CSS background layers | Embed alpha or use stacked elements |

### Minor Gaps

| Gap | Mitigation |
|---|---|
| Shadow blend modes | Wrapper element with `mix-blend-mode` |
| Dashed borders on CSS elements | Use SVG overlay |
| Polygon corner radius | Pre-compute as `<path>` |
| Gradient-filled strokes | SVG gradient defs |
| Text vertical alignment | Extra flex wrapper div |

---

## 3. Proposed Translation Architecture

### 3.1 Node-to-Element Mapping

| .pen Node | React Element | Notes |
|---|---|---|
| frame | `<div>` | Always |
| group | `<div>` or `<Fragment>` | `<div>` if visual properties; Fragment if structural |
| text | `<p>` (block) or `<span>` (inline) | |
| rectangle | `<div>` | Corner radius via CSS |
| ellipse | `<div>` (simple) or `<svg>` (arc/donut) | |
| polygon | `<svg>` | Always |
| line | `<svg>` | Always |
| path | `<svg>` | Always |
| ref | `<ComponentName>` | Generated React component |
| iconFont | `<LucideIcon>` etc. | Library component |
| note/prompt | omitted | |
| context | Theme boundary via data attributes | |

When `metadata._role` is present, emit semantic HTML (`<button>`, `<input>`, `<a>`, `<nav>`, etc.).

### 3.2 Component Generation

Each `reusable: true` node becomes a React component `.tsx` file. Props derived from:

1. **`propMapping` metadata** (explicit): Each entry becomes a named, typed prop.
2. **`_role` metadata** (semantic): Drives HTML element choice and standard event props (`onClick`, `onChange`, `disabled`).
3. **Observed descendant overrides** (inferred): Any overridden descendant path becomes an optional prop.

Every component also gets: `className?: string`, `style?: React.CSSProperties`, and `children?: React.ReactNode`.

### 3.3 Theming

- Theme axes become data attributes: `<html data-mode="light">`
- Variables become CSS custom properties in `theme.css`
- Themed values use attribute selectors: `[data-mode="dark"] { --color-primary: #60A5FA }`
- A `ThemeProvider` React component manages the data attributes
- In JSX, variable-backed values use `var(--name)` via inline styles or Tailwind arbitrary values
- Tailwind v4's `@theme` directive can consume CSS custom properties directly

### 3.4 Tailwind vs. Inline Styles Decision Matrix

**Tailwind classes**: layout, sizing, solid backgrounds, typography, border-radius, shadows, simple transforms, opacity, overflow, blend modes.

**Inline styles**: gradients, complex transforms, SVG attributes, values using `var()`.

**Generated CSS file**: theme variable definitions, `@font-face` declarations.

### 3.5 Interactivity

Three complementary strategies:

1. **Semantic elements from `_role`**: Emit `<button>`, `<a>`, `<input>` etc. with appropriate ARIA attributes.
2. **Composition via props**: Every component accepts `className`, `style`, `children` for layering behavior.
3. **Callback props**: Components with interactive roles expose `onClick`, `onChange`, etc. as typed props.

### 3.6 File Structure

```
generated/
  theme.css                     # Variables, @font-face
  ThemeProvider.tsx              # Theme context + data attribute management
  components/
    Card.tsx                    # One per reusable node
    Button.tsx
  pages/
    HomePage.tsx                # Top-level non-reusable frames
  lib/
    types.ts                    # Shared types
    cn.ts                       # clsx + tailwind-merge utility
```

### 3.7 Code Generation Pipeline

```
.pen JSON
  -> PenParser.parse()
  -> PenVariableResolver.resolve()         (partial -- resolve non-themed vars only)
  -> ReactCodeGenerator.generate()         (NEW)
       -> ComponentExtractor               (identify reusable nodes, derive prop interfaces)
       -> ThemeEmitter                     (generate theme.css from variables + axes)
       -> NodeTranslator                   (walk nodes, emit JSX + classes)
       -> FileWriter                       (write .tsx / .css files)
```

Key: do NOT resolve theme-dependent variables. Emit `var(--name)` instead. Do NOT expand refs -- each ref becomes a JSX element.

---

## 4. Test Fixture Needs

### Missing Fixture Categories

**Layout**: Nested flex (3+ levels), mixed sizing modes, fillContainer fallback, absolute in flex parent, layout:none containers.

**Shapes/Fills**: All shape types, all gradient types, image fills (3 modes), multiple stacked fills, per-side stroke, gradient stroke, dashed stroke.

**Text**: Full typography, rich text, textAlignVertical, href, gradient text, all textGrowth modes.

**Components/Refs**: Text override, deep descendant overrides, multiple refs, nested components, `_role` metadata producing semantic HTML.

**Theming**: Single/multi-axis, themed variables, variable chains, all variable types, context nodes.

**Effects**: All shadow types, blur, background blur, combined effects.

**Transforms**: Rotation, flip, combined, opacity, blend modes, clipping.

**Integration**: Realistic card component, full page layout, themed design system.

---

## 5. Open Questions

1. **Image handling?** Recommend import statements for bundler consumption (Vite/Next.js).
2. **Responsive behavior?** Generate pixel-perfect fixed layouts; leave responsive to consumers.
3. **Incremental regeneration?** Treat generated code as ephemeral. Extension via props, className, composition.
4. **Tailwind config?** Tailwind v4 is CSS-first. A `theme.css` may suffice without `tailwind.config.ts`.
