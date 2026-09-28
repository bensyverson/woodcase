# 2026-09-27 — SwiftUI themes: the design choices

Leaf `PhTQsf` under `n42KDh` ([the emitter plan](2026-09-26-swiftui-emitter-plan.md), task `themes`). The SwiftUI
emitter now writes the document's themes and variables as a typed `PenTheme` value carried in the environment; views
read every variable through it, a node with a `theme` sets it on its subtree, and a light/dark axis is SwiftUI's colour
scheme. This note records the choices the brief left open, so a reviewer can overturn any of them. The reference is
[PenCodeGen.md](../Sources/Woodcase/Documentation.docc/PenCodeGen.md), *Themes*.

## Choices

1. **A struct of typed tokens, not a dictionary lookup.** `PenTheme` holds one enum-typed stored property per axis
   (`mode: Mode`, `density: Density`) and one computed property per variable (`var bgPage: Color`), which `switch`es
   on the axes its value depends on. A misspelt token or option is a compile error, Xcode completes them, and the
   switch is exhaustive, so a new option is a compile error where it is not handled. A dictionary keyed by strings
   would give none of that.
2. **Multi-axis themes compose as a product.** Every variable is evaluated under every combination of options with the
   renderer's own rule (`PenVariableResolver.buildTable`, made internal for this: a specific match before the
   unconditional default, the last specific match winning, chains followed). The token then switches only on the axes
   its value actually varies along — one axis is `switch mode`, two are `switch (contrast, mode)` over every pair.
   Evaluating rather than translating Pen's matching rules means a token reads exactly what Pen draws under every
   theme, chains included; the cost is a switch whose size is the product of the options it depends on (banking's
   16 combinations are the largest fixture).
3. **The environment value is `\.penTheme`**, stored through `@Entry` (`penThemeAxes`) behind a public computed
   property. A view whose body reads a variable declares `@Environment(\.penTheme) private var theme` and writes
   `theme.bgPage`.
4. **A context node is `.penTheme(mode: .dark)`**, a generated `View` extension with one optional parameter per axis
   that sets only the axes it names (`transformEnvironment`). Because a view's own `theme` property reads the
   environment *around* the view, a context node whose subtree reads the theme inside the same body wraps that subtree
   in `PenThemeReader { theme in … }`, whose closure parameter shadows the property; the reads inside are the
   reader's, so a body whose every read is in a reader declares no `theme` at all. A context node whose subtree reads
   nothing (it only calls components) is just the modifier. An instance with a `theme` is the call with the modifier,
   its arguments inside the reader when they read the theme.
5. **The colour-scheme bridge: a light/dark axis *is* `colorScheme`.** When an axis's options are exactly `light` and
   `dark` (case-insensitive), `penTheme`'s getter reads that axis from `colorScheme` and its setter writes
   `colorScheme`. So an app in dark mode draws the dark theme with no code, `.environment(\.colorScheme, .dark)` or
   `.preferredColorScheme(.dark)` selects it, and `.penTheme(mode: .dark)` darkens SwiftUI's own controls and
   materials in that subtree too. The alternative — a pinned mode stored beside the scheme — lets the two disagree.
   Only the first such axis bridges. Banking's `scheme: day/night` is not bridged: guessing that "night" is dark is a
   naming heuristic, and a wrong guess would be invisible.
6. **A colour prop that defaults to a variable is optional.** A public init's default argument cannot read the
   environment, so `tint: Color? = nil` and the body reads `tint ?? theme.accent`. A caller that passes a variable
   passes its own read (`Swatch(tint: theme.ink)`).
7. **Text content `$name` that names no variable is the literal** (`$186`, a price), as the resolver reads it.
8. **Numbers read through the theme** wherever the emitter writes the number into the source: gap, padding, corner
   radius, uniform stroke width, font size, line height, letter spacing, opacity, and a font family string. Where a
   decision needs a number (is a corner at least half the stroke width? how far does a stroke reach?) the emitter
   takes the value under every theme and decides for all of them. Sizes, per-side stroke widths, effect geometry,
   rotation and gradient stop positions still warn: sizes are the layout leaf's (`HjUFQT`), and no fixture themes the
   rest.

## What is not done

- **Unfilled text under a dark scheme.** A text node with no `fill` is drawn black by Pen and the renderer, but the
  emitter writes no `foregroundStyle`, so SwiftUI draws it `.primary` — white under a dark colour scheme. That was
  already true for any app in dark mode; the bridge makes it reachable from a `.penTheme(mode: .dark)` subtree. No
  fixture has such a text (every `woodcase-app` text is filled). The fix is a `.foregroundStyle(Color(hex: 0x000000))`
  on unfilled text, which rewrites every layout golden, so it is left for its own change.

  > **Corrected 2026-09-27 (leaves PlHnG2, PRFPX5):** the premise was wrong. Pen draws a text or icon with no enabled
  > fill as *nothing*, not black (Pen's exports of `swiftui-color-scheme.pen`'s `unfilled` board and of
  > `render-text-unfilled.pen`). The SwiftUI emitter now writes `.foregroundStyle(.clear)`, and the Core Graphics
  > renderer draws nothing too; a `Color(hex: 0x000000)` fix would have been wrong.

## Measured

See the screen table in PenCodeGen.md, *How it is verified*.
