# Research: .pen to Vanilla HTML/CSS/Web Components Code Generation

## 1. Can We Achieve 100% 1:1 Mapping?

Short answer: **No, but we can get to approximately 95% fidelity.** The gaps are concentrated in a few specific areas (mesh gradients, angular gradients, some stroke behaviors, and exotic blend modes). For the vast majority of real-world .pen designs, the HTML/CSS output will be pixel-accurate.

### Layout (Flexbox, Absolute, Sizing) -- PERFECT

Every layout feature maps directly:

- `layout: horizontal/vertical` -> `display: flex; flex-direction: row/column`
- `layout: none` -> `position: relative` with absolutely-positioned children
- `gap`, `padding` (all forms), `justifyContent`, `alignItems` all have direct CSS equivalents
- `fixed(px)` -> explicit `width`/`height`
- `fit_content` -> `width: fit-content`
- `fill_container` -> `flex: 1 1 0; min-width: 0` in flex context, or `width: 100%` otherwise
- `layoutPosition: absolute` with `x`/`y` -> `position: absolute; left; top`
- `clip: true` -> `overflow: hidden`

One minor nuance: `fit_content(200)` and `fill_container(300)` have fallback values. These are design-time conveniences for when there are no children or no parent layout. In generated code, real content will be present, so fallbacks can be emitted as `min-width`/`min-height` or simply ignored.

### Fills

| Feature | CSS Approach | Fidelity |
|---|---|---|
| Solid color | `background-color` | Perfect |
| Linear gradient | `linear-gradient()` | Perfect |
| Radial gradient | `radial-gradient()` | Perfect (rotation workaround needed if rotated) |
| Angular/conic gradient | `conic-gradient()` | Near-perfect |
| Image fill (stretch/fill/fit) | `background-image` + `background-size: 100% 100%/cover/contain` | Perfect |
| Multiple fills | CSS multiple backgrounds | Perfect |
| Per-fill blend mode | `background-blend-mode` (comma-separated) | Perfect |
| Per-fill opacity | `rgba()` for solid; layered for gradients | Perfect |
| **Mesh gradient** | **No CSS equivalent** | **GAP** |

Mesh gradients are the one fill type with no CSS support. Workaround: rasterize to a PNG/WebP at generation time and emit as `background-image`.

### Shapes

| Shape | HTML/CSS Approach | Fidelity |
|---|---|---|
| Rectangle | `<div>` with `border-radius` (uniform or per-corner) | Perfect |
| Full ellipse | `<div>` with `border-radius: 50%` | Perfect |
| Ellipse arc/pie | Inline `<svg>` | Perfect |
| Ellipse donut | Inline `<svg>` with even-odd fill | Perfect |
| Polygon | Inline `<svg>` | Perfect |
| Line | Inline `<svg>` or `<hr>` | Perfect |
| Path (SVG geometry) | Inline `<svg>` with `<path d="...">` | Perfect |
| Path fill rule | SVG `fill-rule` attribute | Perfect |

Key decision: Rectangles and full ellipses stay as CSS `<div>` elements. All other shapes emit inline `<svg>`.

### Text -- PERFECT

Every text feature has a direct CSS mapping:

- `fontFamily`/`fontSize`/`fontWeight`/`fontStyle`/`letterSpacing`/`lineHeight` are 1:1 CSS properties
- `textAlign` -> `text-align`
- `textAlignVertical` -> `display: flex; align-items: flex-start/center/flex-end` on the text container
- `underline`/`strikethrough` -> `text-decoration`
- `href` wraps in `<a>`
- Rich text spans map to nested `<span>` elements with per-span styles
- `textGrowth: auto` = intrinsic sizing; `fixed-width` = explicit width, auto height; `fixed-width-height` = explicit both + `overflow: hidden`
- Text with gradient fill: `background: linear-gradient(...); -webkit-background-clip: text; color: transparent`

Google Fonts loaded via `<link>` tag referencing the Google Fonts CSS API.

### Effects

| Effect | CSS Approach | Fidelity |
|---|---|---|
| Blur | `filter: blur(Xpx)` | Perfect |
| Background blur | `backdrop-filter: blur(Xpx)` | Perfect |
| Outer shadow (on rectangles) | `box-shadow` | Perfect |
| Inner shadow (on rectangles) | `box-shadow: inset` | Perfect |
| Shadow on SVG shapes | `filter: drop-shadow()` | **No spread support** |
| Shadow blend mode | Not directly supported per-shadow | Minor gap |
| Multiple effects | Multiple values in `filter`/`box-shadow` | Perfect |

For SVG shapes, `filter: drop-shadow()` has no spread parameter. Workaround: use SVG `<feDropShadow>` with `<feMorphology>` to simulate spread.

### Blend Modes -- NEAR-PERFECT

All 16 standard modes map to `mix-blend-mode`. Two rare Photoshop-legacy modes (`linearBurn`, `linearDodge`) have no CSS equivalent.

### Transforms -- PERFECT

- `rotation` -> `transform: rotate(Xdeg)`
- `flipX` -> `transform: scaleX(-1)`
- `flipY` -> `transform: scaleY(-1)`
- `opacity` -> `opacity`

### Strokes

| Feature | CSS/SVG Approach | Fidelity |
|---|---|---|
| Uniform thickness | `border` / SVG `stroke-width` | Perfect |
| Per-side thickness | CSS `border-top/right/bottom/left` | Perfect for rectangles |
| Align: center | SVG default stroke behavior | Perfect |
| Align: inside | `box-sizing: border-box` + `border`, or SVG clip trick | Near-perfect |
| Align: outside | `outline` or SVG doubled-width + clip | Near-perfect |
| Gradient stroke fill | `border-image` (breaks border-radius) | **Moderate gap** |
| Join/Cap/Dash | SVG attributes | Perfect |

### Icon Fonts -- PERFECT

- **Material Symbols**: Google Fonts CDN. Emit `<span class="material-symbols-outlined">icon_name</span>`.
- **Lucide/Feather/Phosphor**: Emit inline `<svg>` elements from published assets.

---

## 2. Complete Gap List

### Moderate Gaps (degraded but functional)

1. **Mesh gradients** -- No CSS support. Emit rasterized fallback image at 2x.
2. **Shadow spread on SVG shapes** -- CSS `drop-shadow()` filter lacks spread. Workaround: SVG filter chain.
3. **Gradient strokes on rounded rectangles** -- `border-image` breaks `border-radius`. Workaround: emit as SVG or use pseudo-element technique.
4. **linearBurn/linearDodge blend modes** -- No CSS equivalent. Extremely rare in practice.

### Minor Gaps (workaround exists, near-perfect)

5. **Rotated radial gradients** -- Workaround: rotate the gradient container.
6. **Sizing fallbacks** -- Emit as `min-width` or ignore.
7. **Shadow blend modes** -- Workaround: pseudo-element with `mix-blend-mode`.
8. **Stroke align inside/outside** -- Solvable with box-sizing/clip-path tricks.

**No severe gaps exist.**

---

## 3. Proposed Translation Architecture

### 3.1 Node-to-Element Mapping

| Node Type | HTML Element | Notes |
|---|---|---|
| `frame` | `<div>` | Flexbox container |
| `group` | `<div>` | Visual grouping |
| `text` | `<p>` or `<span>` | `<span>` children for rich text |
| `rectangle` | `<div>` | border-radius, background |
| `ellipse` (full) | `<div>` | `border-radius: 50%` |
| `ellipse` (arc/donut) | `<svg>` | `<path>` with arc commands |
| `polygon` | `<svg>` | `<polygon>` or `<path>` |
| `line` | `<svg>` | `<line>` |
| `path` | `<svg>` | `<path d="...">` from `geometry` |
| `ref` | `<pen-component-name>` | Web Component custom element |
| `iconFont` | `<span>` or `<svg>` | Font glyph or inline SVG |
| `note`/`prompt` | omitted | |
| `context` | `<div data-theme-*>` | Theme boundary |

When `metadata._role` is present, emit semantic HTML instead (`<button>`, `<input>`, `<a>`, `<nav>`, etc.).

### 3.2 Components as Web Components

Each `reusable: true` node becomes a Web Component class:

- **Naming**: Node `name` kebab-cased with `pen-` prefix. "Primary Button" becomes `<pen-primary-button>`.
- **Shadow DOM**: `mode: 'open'` for style encapsulation.
- **Props from `propMapping`**: Each mapped prop becomes an observed attribute. `attributeChangedCallback` updates the corresponding descendant.

**Subclass pattern for interactivity:**
- `pen-button.gen.js` -- Generated, overwritten on every regeneration. Contains structure, styles, prop wiring.
- `pen-button.js` -- Created once as a stub extending the generated base. Users add event handlers here. Never overwritten.

### 3.3 Theming via CSS Custom Properties

- **tokens.css**: All variables as CSS custom properties with default values.
- **themes.css**: Overrides scoped by `[data-theme-axis="value"]` attribute selectors.
- **Multi-axis composition**: Attribute selectors compose naturally: `:root[data-theme-mode="dark"][data-theme-density="compact"]`.
- Variable references emit as `var(--varName)` in CSS.
- Theme switching: `document.documentElement.dataset.themeMode = 'dark'`.
- Context nodes emit `<div>` with appropriate `data-theme-*` attributes.

### 3.4 File/Module Structure

```
output/
  index.html
  styles/
    reset.css
    tokens.css                # CSS custom properties (regenerated)
    themes.css                # Theme overrides (regenerated)
  components/
    pen-card.gen.js           # Generated base (regenerated)
    pen-card.js               # User extension (created once)
  pages/
    home.html                 # Each top-level frame = a page
    home.css                  # Scoped styles (regenerated)
  assets/
    images/                   # Image fills, mesh gradient fallbacks
```

ES modules import chain: `index.html` -> individual component `.js` files -> `.gen.js` bases. No bundler needed.

---

## 4. Test Fixture Needs

### Layout
- All 5 `justifyContent` x 2 orientations x 3 `alignItems`
- `fill_container` in flex (single, multiple, mixed with fixed)
- Absolute positioned child in flex parent
- Nested layouts (3+ levels)
- Frame with `clip: true` and overflowing children

### Shape/Fill
- Rectangle with uniform and per-corner radius
- Full ellipse, arc, donut
- Polygon with and without corner radius
- SVG path with nonzero and evenodd fill rules
- Each fill type including multiple fills with blend modes
- Mesh gradient (for fallback verification)

### Text
- All typography properties, all textGrowth modes, textAlignVertical
- Rich text with mixed styles, href spans, gradient fill

### Component/Ref
- Simple component, multiple instances with different overrides
- Nested refs, component with `propMapping` and `_role` metadata

### Theme
- Single and multi-axis themes, all variable types, context nodes

### Effects/Transforms/Strokes
- All shadow types, blur/background blur, rotation, flip, combined effects
- Uniform/per-side stroke, all alignments, dash patterns, gradient stroke
