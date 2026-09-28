# 2026-09-27 — SwiftUI roles and states: the design choices

Leaf `wXirUH` under `n42KDh` ([the emitter plan](2026-09-26-swiftui-emitter-plan.md), task `states`). The SwiftUI
emitter now writes a component with a `_role` or states as the SwiftUI control its role becomes, draws each state the
designer drew, and spells each smart default (``StateEffect``) as modifiers. This note records the choices the brief
left open, so a reviewer can overturn any of them. The reference is
[PenCodeGen.md](../Sources/Woodcase/Documentation.docc/PenCodeGen.md), *Roles and states*.

## What was built

- **Shared layer.** A transform delta is typed: `PropertyChange.value` is a `DeltaValue` — `.encoded(AnyCodable)`, the
  diff's pen-level encoding as before, or `.transform(DeltaTransform)` (rotation, `flipX`, `flipY`). React spells it
  exactly as the diff's string was (`DeltaTransform+CSS.swift`); `DeltaTransformTests` pins that. The analyzer keeps
  `StateDefinition.variantNode` for every designer's state, not only structural ones (React reads it only for
  structural states, so its output does not move). `PageAnalyzer` no longer treats a frame a component's `_states`
  names as a page (it already skipped `{Name}:{state}` siblings; the `_states` frame was a stray page in React too).
- **SwiftUI.** `SwiftUIControl` (the role → control decision and the face precedence), `SwiftUIEmitter+States.swift`
  (the file), `StateEffect+SwiftUI.swift` (the effect spellings, `StateEffectSwiftUITests`),
  `SwiftUINodeEmitter+TextField.swift`, `SwiftUIComponentScope+Faces.swift` (props bound on a designer's frame), and the
  support template `PenSupport+States.swift` (`PenControlState`, `penControlState(_:)`, `PenStateReader`,
  `penFocusRing`).
- **Fixture.** `codegen-states.pen` holds a button with `pressed`, `disabled` and `hover` siblings, a switch with an
  `off` sibling, a text field with `focused` and `disabled`, a select with `open`, a link, and a role-less chip with a
  `_states` frame; Pen's exports come from `scripts/pen-oracle Tests/WoodcaseTests/Fixtures/codegen-states.pen`. No
  fixture before this one had a pressed or disabled sibling: the brief's "state fixtures" did not exist (the React state
  tests build their components in code, and `woodcase-app.pen` has only `Toggle:off` and the tab bar's variants).

## Measured

`swift test --filter SwiftUIStateRenderTests` (Xcode 27.0, macOS 27.0, Inter from `~/.woodcase/fonts`), each render
against Pen's 2x export of the matching frame:

| Board | SwiftUI render | MAE |
|---|---|---|
| `StatesButton` | `StatesButton()` | 2.384 |
| `StatesButton:pressed` | `StatesButton().penControlState(.pressed)` | 2.635 |
| `StatesButton:disabled` | `StatesButton().disabled(true)` | 1.727 |
| `StatesButton:hover` | `StatesButton().penControlState(.hovered)` | 2.009 |
| `Switch` / `Switch:off` | `Switch()` / `Switch(isOn: .constant(false))` | 0.894 / 0.882 |
| `SortSelect` / `SortSelect:open` | `SortSelect()` / `SortSelect(variant: .open)` | 0.888 / 0.585 |
| `Chip` / `Chip selected` | `Chip()` / `Chip(variant: .selected)` | 3.128 / 4.682 |
| `MoreLink` | `MoreLink()` | 5.961 |

The error is the text, not the state: Inter's antialiasing, and for the `fit_content` chip and link a frame one
pixel narrower at 2x, which shifts every glyph — most visibly in the chip's selected state, white on near-black. Each is baselined with
tolerance 0.5. The text field compiles at both floors but is not rendered: `ImageRenderer` draws a platform-backed
`TextField` as a placeholder symbol (probed 2026-09-27; a `Menu` with `.menuStyle(.button)` and a custom
`ButtonStyle`, a `Toggle` with a custom `ToggleStyle` and a `Button` with one all render their label).

## Choices

1. **A designer's state is drawn from its whole frame, as a branch.** Each is a private `…Face` property built by the
   same node emitter as the default, and the style or body draws the first whose state holds. The alternative —
   applying `StateDelta`s as conditional modifier arguments, `.background(isPressed ? a : b)`, which SwiftUI would
   animate between — needs every delta typed (fills, strokes and effects are still lossy summaries such as
   `"multi-fill"` and `"effects"`) and a hook in every paint and frame writer. The branch is exact and needs neither;
   what it costs is animation between states (SwiftUI cross-fades a branch swap) and a longer file. **Revisit** when
   deltas are typed throughout, which would also let React draw a designer's fill stack.
2. **Which face wins:** disabled, then pressed, hovered, focused, then the attribute states in the analyzer's order.
   CSS applies every matching rule at once; a whole frame cannot be merged, so one must win, and the one a user acts on
   last wins. The smart defaults of states the designer did not draw apply on top, each an identity modifier while its
   state does not hold.
3. **A link is a `Button(action:)`, not a `Link(destination:)`.** `woodcase-app`'s links carry in-app actions
   (`seeAllTopRated`, `openAbout`), not URLs, and a `Link` needs a URL no design gives. React gives its `<a>` an `href`.
4. **A select is a `Menu` holding an inline `Picker`, its label the component.** A `Picker` with `.pickerStyle(.menu)`
   draws the system's chrome, not the design; a `Menu` whose label is the design and whose content is the `Picker` is
   the known idiom for a custom-looking picker. The component takes `selection: Binding<String>` and
   `options: [String]`; its text props stay separate, so a caller passes the chosen value's label too. Mapping a text
   prop to the selection would need the design to say which text is the value.
5. **A text input's `TextField` replaces its first text**, the copy its prompt, drawn in the text's colour — the design
   gives one colour, so typed text and placeholder share it. A designer's `focused` or `filled` frame is drawn as the
   smart default instead, with a warning: a branch swap makes a new `TextField`, which drops the focus the swap was
   reacting to. **Open:** drawing those frames would need the field kept outside the branch (an overlay placed by an
   anchor preference from each face's text) — worth it only if designs draw focus as more than a border.
6. **A toggle's `isOn` defaults to `true`**: the component's frame is its on state and `Toggle:off` its off state, as
   React's `checked = true`. `ToggleRow`'s `ToggleView()` call therefore draws what Pen draws.
7. **An attribute state no control reports is a case of a typed enum** — `Variant`, or `Tab` for a tab bar — and one
   optional property picks it (`variant: Variant? = nil`). The cases are exclusive because each is a whole frame. A
   select's `open` is one: a `Menu` reports no open state.
8. **A tab bar takes `selected: Tab?`, a value, not a binding.** Which tab item a tap lands on is not in the design
   (each variant is a whole bar), so the bar cannot select on a tap; the caller drives it, as React's `selected` prop.
   A `TabView` would draw the system's bar, not the design's. Screens that place `TabBar:home` still inline it: their
   instances resize the bar's root (`fill_container` against the variant's fixed 402), which only a copy can draw.
9. **States are pinned through the environment.** `.penControlState(.pressed)` pins hovered, pressed and focused for
   every generated control below it; `.disabled(true)` stays SwiftUI's own. That is what the previews and the render
   test use, and it is public, so an app's snapshot tests can use it too.
10. **An inlined copy of a role component is its default face, without the control** — the copy exists because a
    call cannot carry the instance's overrides, and a control around a copy would be a second component.
11. **Member names are fixed** (`action`, `isOn`, `text`, `selection`, `options`, `variant`, `selected`); a prop that
    takes one is warned about (rename it in `_props`) rather than renamed.

## Found

- React's transform delta was never valid CSS: `rotate(45.0)` has no unit and `flipX` is no transform function. Kept
  byte-identical, as the brief required; typed now, so fixing React is a change to `DeltaTransform+CSS.swift` alone.
