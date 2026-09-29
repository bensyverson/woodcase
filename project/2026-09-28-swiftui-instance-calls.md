# SwiftUI instance calls: a fixed root is an ideal size

2026-09-28, leaf `RNSV2z`. Ben asked whether a SwiftUI export uses its components' view structs where one component
nests another. In `woodcase-app` it mostly did not: 10 instances were calls and 30 were inlined copies
(`woodcase generate swiftui Tests/WoodcaseTests/Fixtures/woodcase-app.pen --output <dir> --name WoodcaseApp`, then
`grep -c "woodcase: inlined from"` over `Components/`). The warnings named three causes:

1. **A root size override** (about 20 of the 26 warnings). Nearly every row, status bar and button in a screen is a
   `fill_container` instance of a fixed-width (354 or 402) component. The component body framed its root
   `.frame(width: 354)`, which a call site cannot widen, so choice 5 of
   [SwiftUI components](2026-09-26-swiftui-components.md) inlined it.
2. **A ref to a tab bar's variant** (4). `TabBar:home` is a reusable frame the analyzer folds into `TabBar`'s states,
   not a component of its own, so the emitter found no view to call — though `TabBar(selected: .home)` draws it.
   These also resized the root, so they needed cause 1 too.
3. **Overrides no prop carries** (the rest). `PencilListItem`'s thumbnail image (its `image` prop is typed `Color`,
   from the component's own fill), its icon and score; the status bars' page fill and the Delete button's red, both
   root `fill`s. Out of scope here: the fix is the document's or the analyzer's.

## Ruling

Ben agreed to reverse choice 5 (the original was an unattended two-way decision). A component's fixed root size is
its **ideal** size: the body frames the root `.frame(minWidth: 0, idealWidth: W, maxWidth: .infinity, …)` on each
fixed axis, so the parent sizes the component as it sizes SwiftUI's own views, and the zero minimum keeps Pen's
overflow rather than growing to the content. Every call states the size its instance sits at:

| Instance, on an axis the root fixes | The call |
|---|---|
| the component's own size | `.frame(width: W)` |
| another fixed size | `.frame(width: N)` |
| `fill_container` in a stack | no frame: the body already fills |
| `fill_container(N)` in a `ZStack` or page root | `.frame(width: N)` |
| `fit_content` | a copy (no frame says "your content's size" of a flexible view) |

A root that is content-sized or filling is unchanged: its instance must size it as its body does, since a frame
outside the view would not carry its paint (a resized `fit_content` swatch's fill would stay at the content's size).

Previews and catalog specimens frame the component to its own size the same way (`Card().frame(width: 140,
height: 80)`), since a preview offers a flexible view the whole screen. That was the objection choice 5 recorded
against dropping the fixed size; the frame answers it.

A ref to a state variant is a call pinning that state (`SwiftUIEmitter.pinnedCall`, the one the previews use). Its
overrides are judged against the variant's own tree with no props — a prop names a node of the base tree — so an
override that changes anything but the root size and in-flow `x`/`y` still inlines. In practice only tab bars have
reusable variants: other `{Name}:{state}` frames are not reusable and cannot be referenced.

`InstanceOverrides` (target-neutral) now reports a root `width`/`height` that resizes the root as `rootWidth` and
`rootHeight` instead of listing it unmapped; whether a call can place the resized root is the target's call
(`SwiftUINodeEmitter.callSize`).

## Measured

- `woodcase-app`: 26 inlining warnings → 10, all cause 3 (same command as above). The screens call `StatusBar()`,
  `TabBar(selected: .home)`, `ToggleRow(label: …)`, `TextInput(…)`, `SelectRow(…)`, `ActionButton(label: "Export
  Data")`, `StatCard`, `ActivityLogRow`, `FavoriteCard(…).frame(width: 160)`.
- The SwiftUI screen render test (`swift test --filter SwiftUIScreenRenderTests`, Xcode 27.0, macOS 27.0) measures
  every `woodcase-app` screen and theme at exactly its recorded baseline (home 0.875, usage log 0.692, ratings 1.048,
  wishlist 1.822, settings 0.412, lab 1.669): the calls draw the pixels the copies drew. The state and slot render
  suites pass unchanged.
