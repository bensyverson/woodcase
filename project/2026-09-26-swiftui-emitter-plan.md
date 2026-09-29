# 2026-09-26 — Plan: the SwiftUI emitter

The implementation plan of [the feasibility report](2026-09-26-swiftui-codegen-feasibility.md) §6, amended by Ben's four
rulings (leaf `bpfpVZ`, recorded as a marked block in that report):

- **Floor iOS 26 / macOS 26 by default.** `SwiftUIEmitter.Options.deploymentFloor` is a typed enum. iOS 18 / macOS 15 is
  a supported lower floor only through `#available` branches in the emitted `PenSupport.swift`; component code is
  written for 26 and never bent to serve the lower floor.
- **Mesh: always native `MeshGradient`.** No baked-raster path in this emitter.
- **Output: a SwiftPM package** — `Sources/<Name>/{Components,Pages,Theme,Support}`, fonts and icon fonts as resources.
- **Layout: always idiomatic stacks.** Intent over pixel-perfection. No `PenFlex`/`PenLayoutEngine` port. Where
  flexbox and stack negotiation differ, the render test records the board's MAE as its baseline instead of gating it at
  CG + 1.0; boards of fixed boxes and paints still gate at CG + 1.0, because there the two agree exactly.

The emitter lives in `Sources/Woodcase/CodeGen/SwiftUI/`, is Foundation-only (it never imports SwiftUI) and its golden
tests run on Linux. The render test is macOS-only and shells out to `xcrun swiftc` (report §4.3–4.4). Refactor leaves 1
and 2 must leave every React golden and every renderer snapshot byte-identical.

```yaml
tasks:
  - title: "Neutral codegen seams: state triggers, typed prop values, a Paint layer"
    ref: seams
    desc: |
      Report §1.2 items 1–3 and 5. StateTrigger names the state (.hover, .pressed, .disabled, .focused, attribute name/value), not a CSS selector; React maps it to its selector. PropMapper returns a typed value (string, color literal or variable, bool, image URL) and each emitter formats it (jsValue moves into React). ManifestEmitter moves out of React/. A CodeGen/Paint/ home for the target-neutral decisions compiled into React extensions today: PaintRoute, Pen unit-box gradient geometry (one map that yields CSS's angle and SwiftUI's UnitPoints), mesh theme resolution, stroke outsets per alignment, FillBox. Rule of two: extract only what the SwiftUI emitter will need.
    criteria:
      - Every React golden (component and page) is byte-identical
      - No CSS selector or JSX formatting remains in a type outside CodeGen/React/
      - DocC coverage stays at 100% for moved and new types
  - title: "CG-free geometry: path command model and shape geometry without CoreGraphics"
    ref: geometry
    desc: |
      Report §1.2 item 4. Split PenSVGPathParser into a CoreGraphics-free command model (the parse) and a CG builder (the render); the same split for PenShapeBuilder's polygon and arc/donut geometry. The emitter needs the commands to write SwiftUI Path code, and must build on Linux.
    criteria:
      - The path parse and shape geometry compile without importing CoreGraphics
      - Every renderer snapshot and MAE is unchanged
  - title: "SwiftUI thin slice: emitter skeleton, support template, render test, generate swiftui"
    ref: slice
    blockedBy: [seams, geometry]
    desc: |
      Report §6 leaf 3 under the rulings. SwiftUIEmitter (mirrors ReactEmitter.emit's signature), Options.deploymentFloor (typed; default iOS 26 / macOS 26), a PenSupport.swift template resource, `woodcase generate swiftui`. Frames as HStack/VStack/ZStack with padding, gap, sizing, justify, align, clip; rectangles and ellipses with solid fills and radii; text (font with optical sizing pinned off, weight, size, color, align, growth, line height). The render test batches every emitted view into one `xcrun swiftc` child, renders with ImageRenderer, compares in-process with the shared MAE helper.
    criteria:
      - Goldens over the layout-*.pen fixtures and render-text.pen, passing on Linux (no SwiftUI import in the library)
      - The emitted goldens compile at the default floor and at iOS 18 / macOS 15
      - The render test records an MAE per board; fixed-box boards within CG + 1.0
  - title: "SwiftUI paints: gradients, images, stacks, blend, opacity, paints on text"
    ref: paints
    blockedBy: [slice]
    criteria:
      - render-gradients, render-gradient-geometry and render-text-fills within CG + 1.0
  - title: "SwiftUI strokes: alignments, per-side, dash, caps, joins, stroke paints"
    ref: strokes
    blockedBy: [slice]
    criteria:
      - render-per-side-strokes and render-stroke-fills within CG + 1.0
  - title: "SwiftUI effects and transforms"
    ref: effects
    blockedBy: [slice]
    desc: Shadows (radius = blur/2), spread, inner shadow via ShadowStyle, layer blur, background blur as a Material plus a diagnostic, clip, rotation in its bbox frame, flips, node blend modes.
    criteria:
      - render-transforms-and-effects within 1.0 (inner-shadow item excluded until re-exported); blur1–3 compared
  - title: "SwiftUI shapes and icons"
    ref: shapes
    blockedBy: [slice]
    desc: Polygon, arc/donut, path, line and viewBox from the CG-free commands; icon fonts as package resources.
    criteria:
      - render-arc-donut, render-strokes-and-paths, render-fill-domains and an icon fixture compared
  - title: "SwiftUI components and pages: view structs, typed props, refs, overrides, slots"
    ref: components
    blockedBy: [paints, strokes, effects, shapes]
    criteria:
      - Goldens over woodcase-app.pen and pages.pen
      - The woodcase-app screens render and record an MAE
  - title: "SwiftUI themes: a PenTheme environment value, context nodes, the colorScheme bridge"
    ref: themes
    blockedBy: [components]
    criteria:
      - The light and dark references render with their themes
  - title: "SwiftUI roles and states: Button styles, Toggle, TextField, Picker, tab bar"
    ref: states
    blockedBy: [components]
    criteria:
      - Goldens over the state fixtures; pressed and disabled renders compared with their :state siblings
  - title: "SwiftUI mesh: native MeshGradient"
    ref: mesh
    blockedBy: [components]
    desc: Always native, per the ruling, folds included; lint's mesh-gradient-distorted is the warning.
    criteria:
      - The render-mesh-gradients boards within 3.5, the folded one recorded
  - title: "SwiftUI packaging and docs"
    ref: packaging
    blockedBy: [themes, states, mesh]
    desc: SwiftPM scaffold, font and icon resources and registration, the PenCodeGen.md SwiftUI section, `woodcase help codegen`.
    criteria:
      - A generated package swift-builds on macOS
      - DocC coverage 100%
  - title: "SwiftUI churn guard: vocabulary list, audit at both floors, yearly checklist"
    ref: churn
    blockedBy: [packaging]
    criteria:
      - scripts/swiftui-api audit exits 0 at the default floor
      - The yearly checklist is in DocC
```
