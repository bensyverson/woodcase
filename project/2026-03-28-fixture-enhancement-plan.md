# woodcase-app.pen Enhancement Plan

**Date:** 2026-03-28\
**Goal:** Extend the existing Woodcase app fixture into a comprehensive code gen validation file by componentizing existing elements, adding metadata conventions, and creating two new screens.

---

## Current State

### Screens (4)
- **Home - Collection** (`ydnjs`) — status bar, header, favorites horizontal scroll, collection list
- **Usage Log** (`tcjjA`) — status bar, header, stats row (3x Stat Card refs), recent activity list
- **Ratings** (`ifBcZ`) — status bar, header, overall rating card, rating distribution, top rated section
- **Wishlist** (`XQ4l7`) — status bar, header, summary row, pencil list items

### Existing Components (12)
- 4x Tab Bar variants (Home/Log/Ratings/Wishlist Active)
- Stat Card (`oqIlX`) — value + label
- Pencil List Item (`CTtGi`) — thumbnail, name, meta, trailing star/score
- Collection Row (`ibZOK`) — name, meta, star rating text
- Activity Log Row (`v59pI`) — colored dot, name, detail, duration

### Theming
- Single axis: `mode` → `[light, dark]`
- 15 color variables, all themed

### What's missing for code gen validation
- No `_props` metadata on any component
- No `_role` / `_action` / `_bind` metadata anywhere
- No interactive widgets (buttons, inputs, toggles, selects)
- Only one theme axis
- Favorites cards are inline (not componentized)
- Status bar is duplicated inline on every screen
- Several repeated patterns could be components (section headers, divider rows)

---

## Proposed Changes

### Phase 1: Componentize & Add `_props`

#### 1a. New component: **Favorite Card**

The three favorites cards on the Home screen (`EJrW5`, `3UXjP`, `lfA5I`) are identical in structure but inline. Extract to a component:

```
Component/Favorite Card
├── Pencil Image (frame, image fill)
├── Card Content
│   ├── Name (text)
│   └── Brand (text)
└── Heart Row
    └── Heart icon
```

**`_props`:**
```json
{
  "_props": {
    "name": "cardContent/Name",
    "brand": "cardContent/Brand",
    "image": "Pencil Image"
  }
}
```

#### 1b. Add `_props` to existing components

**Stat Card** (`oqIlX`):
```json
{
  "_props": {
    "value": "Value",
    "label": "Label"
  }
}
```

**Pencil List Item** (`CTtGi`):
```json
{
  "_props": {
    "name": "Info/Name",
    "meta": "Info/Meta",
    "score": "Trailing/Score",
    "image": "Thumbnail"
  }
}
```

**Collection Row** (`ibZOK`):
```json
{
  "_props": {
    "name": "Info/Name",
    "meta": "Info/Meta",
    "stars": "Stars"
  }
}
```

**Activity Log Row** (`v59pI`):
```json
{
  "_props": {
    "name": "Info/Name",
    "detail": "Info/Detail",
    "duration": "Duration"
  }
}
```

#### 1c. New component: **Section Header**

Repeated pattern: title + optional trailing element (badge, "See all" link). Used in Favorites, My Collection, Recent Activity, Top Rated.

```
Component/Section Header
├── Title (text)
└── Trailing (text, optional)
```

**`_props`:**
```json
{
  "_props": {
    "title": "Title",
    "trailing": "Trailing"
  }
}
```

#### 1d. New component: **Status Bar**

Currently duplicated on every screen. Extract once, ref everywhere.

```
Component/Status Bar
└── Time Label (text)
```

**`_props`:**
```json
{ "_props": { "time": "Time Label" } }
```

#### 1e. New component: **Screen Header**

The title + icon header also repeats on every screen with minor variations.

```
Component/Screen Header
├── Title (text)
└── Icon (icon_font)
```

**`_props`:**
```json
{
  "_props": {
    "title": "Title",
    "icon": "Icon"
  }
}
```

**`_role` + `_action` on Icon:**
```json
{ "_role": "button", "_action": "headerAction" }
```

---

### Phase 2: Settings Screen

A new screen showcasing interactive widgets. Natural for a "pencil collection" app:

```
Settings Screen (402 x 874)
├── Status Bar (ref)
├── Screen Header: "Settings" + gear icon
├── Content (scrollable vertical)
│   ├── Profile Section
│   │   ├── Section Header: "Profile"
│   │   ├── Text Input: Display Name         ← _role: textInput, _bind: displayName
│   │   └── Text Input: Email                ← _role: textInput, _bind: email
│   ├── Preferences Section
│   │   ├── Section Header: "Preferences"
│   │   ├── Toggle Row: Dark Mode            ← _role: toggle, _bind: darkMode
│   │   ├── Toggle Row: Notifications        ← _role: toggle, _bind: notifications
│   │   └── Select Row: Default Grade        ← _role: select, _bind: defaultGrade
│   ├── Collection Section
│   │   ├── Section Header: "Collection"
│   │   ├── Toggle Row: Show Ratings         ← _role: toggle, _bind: showRatings
│   │   └── Toggle Row: Auto-sort            ← _role: toggle, _bind: autoSort
│   ├── Danger Zone Section
│   │   ├── Section Header: "Danger Zone"
│   │   ├── Button: Export Data              ← _role: button, _action: exportData
│   │   └── Button: Delete Account           ← _role: button, _action: deleteAccount
│   └── App Info
│       ├── Version label
│       └── "About" link                     ← _role: link, _action: openAbout
└── Tab Bar (ref, no tab active — or add 5th "settings" tab)
```

**New components needed:**

- **Component/Text Input** — label + input field frame
  - `_role: "textInput"`, `_bind` on the field
  - `_props: { "label": "Label" }`

- **Component/Toggle Row** — label + toggle indicator
  - `_role: "toggle"`, `_bind` on the toggle
  - `_props: { "label": "Label" }`

- **Component/Select Row** — label + current value + chevron
  - `_role: "select"`, `_bind` on the row
  - `_props: { "label": "Label", "value": "Value" }`

- **Component/Button** — styled button (primary and destructive variants, or two separate components)
  - `_role: "button"`, `_action` per instance
  - `_props: { "label": "Label" }`

---

### Phase 3: Easter Egg Screen

A "junk drawer" screen exercising drawing primitives and visual features not covered elsewhere. Accessed conceptually via a hidden gesture (but for our purposes, just another screen in the .pen file).

```
Easter Egg Screen (402 x 874)
├── Status Bar (ref)
├── Header: "✏️ Lab" (or just "Lab")
├── Content (vertical scroll)
│   ├── Shapes Section
│   │   ├── Rectangle (uniform radius)
│   │   ├── Rectangle (per-corner radius: 0, 20, 0, 20)
│   │   ├── Ellipse (full)
│   │   ├── Ellipse (donut — innerRadius: 0.4)
│   │   ├── Ellipse (arc — startAngle: 0, sweepAngle: 270)
│   │   ├── Polygon (hexagon, cornerRadius: 4)
│   │   ├── Polygon (triangle)
│   │   ├── Line (with dashed stroke)
│   │   └── Path (SVG heart or pencil icon outline)
│   ├── Fills Section
│   │   ├── Solid color rectangle
│   │   ├── Linear gradient (diagonal)
│   │   ├── Radial gradient
│   │   ├── Angular/conic gradient
│   │   ├── Image fill (fit mode)
│   │   ├── Multiple fills stacked (solid + gradient with blend mode)
│   │   └── Mesh gradient (if supported in Pencil)
│   ├── Strokes Section
│   │   ├── Uniform stroke (inside alignment)
│   │   ├── Uniform stroke (outside alignment)
│   │   ├── Per-side stroke (top + bottom only)
│   │   ├── Dashed stroke
│   │   └── Gradient stroke on rectangle
│   ├── Effects Section
│   │   ├── Outer shadow (with spread)
│   │   ├── Inner shadow
│   │   ├── Blur
│   │   ├── Background blur (over an image)
│   │   └── Multiple shadows stacked
│   ├── Transforms Section
│   │   ├── Rotated rectangle (45°)
│   │   ├── Flipped text (flipX)
│   │   ├── Rotated + flipped ellipse
│   │   └── Low opacity rectangle over solid background
│   ├── Text Section
│   │   ├── Rich text (mixed families, sizes, weights in one block)
│   │   ├── Text with gradient fill
│   │   ├── Justified text (textAlign: justify)
│   │   ├── Vertical-centered text in fixed box
│   │   ├── Underline + strikethrough
│   │   └── Text with href
│   └── Blend Modes Section
│       ├── Grid of rectangles demonstrating: multiply, screen, overlay, difference
│       └── Each over a common background image
└── (no tab bar — this is a hidden screen)
```

---

### Phase 4: Theme Enhancement

Add a second theme axis to exercise multi-axis theming:

```json
"themes": {
  "mode": ["light", "dark"],
  "density": ["default", "compact"]
}
```

New/updated variables:
- `spacing-sm`: 8 (default) / 4 (compact)
- `spacing-md`: 16 (default) / 10 (compact)
- `spacing-lg`: 20 (default) / 14 (compact)
- `font-size-body`: 14 (default) / 12 (compact)
- `card-radius`: 16 (default) / 10 (compact)

Apply these to components so they respond to density changes. This exercises multi-axis theme resolution in code gen.

---

## Summary of What This Exercises

| Code Gen Feature | Where Exercised |
|---|---|
| `_props` (content mapping) | All existing + new components |
| `_role: "button"` | Settings (export, delete), Screen Header icon |
| `_role: "textInput"` | Settings (display name, email) |
| `_role: "toggle"` | Settings (dark mode, notifications, etc.) |
| `_role: "select"` | Settings (default grade) |
| `_role: "link"` | Settings (about link) |
| `_action` | All interactive widgets in Settings |
| `_bind` | All input/toggle/select widgets in Settings |
| Multi-axis theming | density axis (compact/default) × mode (light/dark) |
| Nested component instances | Tab bar refs inside screen refs |
| Component with image prop | Favorite Card, Pencil List Item |
| Shapes (all types) | Easter Egg shapes section |
| Gradients (all types) | Easter Egg fills section |
| Strokes (all variants) | Easter Egg strokes section |
| Effects (all types) | Easter Egg effects section |
| Transforms | Easter Egg transforms section |
| Rich text | Easter Egg text section |
| Blend modes | Easter Egg blend modes section |
| Per-corner radius | Easter Egg shapes section |
| Arc/donut ellipse | Easter Egg shapes section |
| SVG path | Easter Egg shapes section |
| Dashed stroke | Easter Egg strokes section |
| Gradient fill on text | Easter Egg text section |
| href on text | Easter Egg text section |

---

## Implementation Order

1. **Phase 1** — Componentize existing screens, add `_props`. This is the lowest-risk change and immediately validates the most common code gen path.
2. **Phase 2** — Settings screen. Exercises all interactive roles.
3. **Phase 3** — Easter Egg screen. Exercises drawing primitives.
4. **Phase 4** — Add density theme axis. Exercises multi-axis theming.

Each phase can be reviewed independently.
