# 2026-09-26 — SwiftUI components and instances: the design choices

Leaf `FPHQQ5` under `n42KDh` ([the emitter plan](2026-09-26-swiftui-emitter-plan.md), task `components`). The SwiftUI
emitter now writes each reusable component as a view struct and each instance as a call to it or an inlined copy.
This note records the choices the brief left open, so a reviewer can overturn any of them. The reference is
[PenCodeGen.md](../Sources/Woodcase/Documentation.docc/PenCodeGen.md), *Components and instances*.

## What was built, and what was not

Built: component view structs with typed props, instance calls with typed arguments, inlining for every override a prop
cannot carry, pages that call components, goldens over `woodcase-app.pen` and `pages.pen`, and a render test of the six
light `woodcase-app` screens.

Not built — the second unit of this leaf: **slots as a `@ViewBuilder` API.** An instance that fills a slot is drawn
correctly, as an inlined copy (the copy is `PenRefExpander`'s, which applies slot content), but the component does not
yet take generic `Content: View` parameters. Neither fixture has a slot, so neither criterion needed it. What that API
needs to settle: one generic parameter per slot frame (named `<Slot>Content`, since `Body` is taken by `View`); the
default content when the slot frame has children of its own (a nested `struct <Slot>Default: View`, and a constrained
`extension … where <Slot>Content == <Slot>Default` init); and how a filled slot on a call maps to the trailing closure.

> **Updated 2026-09-27 (leaf `26chl8`):** slots are built — see PenCodeGen.md, *Slots*, and the `codegen-slots.pen`
> fixture. Two choices differ from the sketch above. The default view is **top level**, `<Component><Slot>Default`
> (`CardContentDefault`), not nested: a type nested in `Card<Content>` is itself generic over `Content`, so
> `where Content == Card.ContentDefault` would name the struct inside its own constraint. And a slot's generic is its
> name with `Content` after it (`HeaderContent`), except a slot named "Content", whose generic is `Content`. One
> extension passes *every* slot its default; a call that fills some slots passes the default view for the rest
> (`} footer: { PanelFooterDefault() }`) rather than one constrained init per subset, which would be 2ⁿ inits. A
> control's trailing closure goes to its slot, not its `action`, by Swift's forward-scan rule (SE-0286), which skips
> a defaulted closure parameter when a later one has no default — measured by rendering `UploadButton`, whose fill
> is drawn. MAE against Pen's exports, `swift test --filter SwiftUISlotRenderTests -j 3`: 0.22–1.08 on the eight
> boards drawn with Inter text, 1.62 on `SlotButton`, whose hugging width rounds to 179 points against Pen's 180.

## Choices

1. **Props are `public let` plus a public memberwise init with defaults.** `let`, not `var`: a view's inputs are values
   the parent passes, as SwiftUI's own views take them. Every parameter has a default, so `Card()` draws what Pen
   draws, and the `#Preview` is `Card()`.
2. **An image prop takes an `Image`, not a URL.** A caller can pass any image, bundled or not; that is the SwiftUI
   idiom. The parameter is `Image? = nil` and the default is applied in the init's body. **Found by compiling it:**
   SwiftPM's `Bundle.module` is internal, and Swift refuses an internal symbol in a public init's default argument
   (`static property 'module' is internal and cannot be referenced from a default argument value`). `Color(hex:)` and
   `Image(penResource:bundle:)` in the support files are public now, for the same reason and so callers can use them.
3. **A prop is declared only where the body reads it.** A `_props` entry whose node the body cannot bind (a text prop on
   a frame, a path that names nothing) is left out with a warning rather than declared and ignored. The prop's *type*
   is the analyzer's, shared with React, and it reads the component's own paint: `woodcase-app`'s Pencil List Item
   has an `image` prop typed `Color`, because its thumbnail's own fill is a colour and only the instances set images.
   Every instance of it is therefore a copy (an image fill is no colour argument). Fixing that is the document's
   (give the thumbnail an image) or the analyzer's (a type hint in `_props`), not the emitter's.
4. **A call only when the call draws what Pen draws; otherwise inline.** The decision is `InstanceOverrides`
   (target-neutral, in `CodeGen/`): every property of every override must be carried by a prop or change nothing (an
   `x`/`y` on a node its parent lays out — Pen writes these on nearly every override — a value equal to the node's, a
   size that sizes the node as before). This is **stricter than React**, which inlines only when a key names a node no
   prop reads, and silently drops the other properties of a key one does (an override that sets a text's `fill`
   beside its `content` loses the fill in React). React was left as it is: its goldens must not move, and whether to
   adopt the stricter rule there is a separate call.
5. **A root size override inlines.** `.frame(width:)` at the call site cannot resize a view whose body frames itself,
   so an instance whose `width`/`height` sizes the root differently — `woodcase-app`'s rows are `fill_container`
   instances of 354-point components — is a copy. The alternative, exposing the root's size as init parameters, is an
   API no SwiftUI view has; the other, dropping a component's fixed root size, loses the component's own size in its
   preview. Revisit if copies prove too many: most `woodcase-app` copies are exactly this case, where the fill and the
   fixed size agree.
6. **A turned or flipped instance inlines**, because the turn is framed to the node's box, which the call site does
   not know.
7. **A component's root is sized as its instances are placed** (`Container.component`): `fill_container` is
   `maxWidth: .infinity`, not the fallback a page root would take. An instance where the root would take its fallback
   (in a `ZStack`, or as a page root) inlines.
8. **Names.** Components keep React's names (`ComponentAnalyzer`). A name that would shadow a SwiftUI type is suffixed
   `View` (`Toggle` → `ToggleView`); duplicates are numbered; a page that shares a component's name is suffixed `Page`.
9. **States draw the default state**, with a notice; a `ref` to a state variant (`TabBar:home`, not an analyzed
   component) is inlined. States and roles are leaf `wXirUH`.

   > **Updated 2026-09-27 (leaf `wXirUH`):** roles and states are emitted now — see
   > [SwiftUI roles and states](2026-09-27-swiftui-roles-and-states.md). A `ref` to a state variant is still inlined.

## Measured

> **Updated 2026-09-27 (leaf `PhTQsf`):** the screens are no longer resolved to the default theme before emitting; they
> read their variables through the emitted `PenTheme`, and the light figures below are unchanged to the third decimal.
> Dark and compact screens are measured too — see [the themes note](2026-09-27-swiftui-themes.md).

`swift test --filter SwiftUIScreenRenderTests` (Xcode 27.0, macOS 27.0), each light screen rendered from its component
with the default theme's variables resolved, against Pen's `woodcase-app-*.png`: wishlist 3.02, usage-log 3.21,
home-collection 3.42, lab 3.83, settings 5.16, ratings 5.42. The Core Graphics renderer scores 0.60–2.90 on the same
references (`PenWoodcaseAppTests`). Read side by side, the component structure is right on every screen; the gap is
layout:

- **A `fill_container` frame has no zero minimum.** The frame emitter writes `.frame(maxWidth: .infinity)`; SwiftUI then
  takes the child's ideal size as the frame's minimum, so content larger than its room grows the frame. Pen's flex item
  shrinks to its room and lets the content overflow (React writes `flex: 1; minHeight: 0` for the same reason). On
  Home, the favourites row (three 160-point cards in 354 points) widens the whole screen and pushes the bell, the badge
  and the stars out of view; on Ratings the content column grows and pushes the tab bar below the screen. The likely fix
  is `minWidth: 0` / `minHeight: 0` beside `max…: .infinity` in `frameModifiers`; it touches every layout golden, so it
  is not in this leaf.
- **Line heights.** SwiftUI's 1× Inter lines run a point taller than Pen's (already recorded for `render-text`), which
  drifts every row below.

One text bug was found and fixed here: `Text("you@example.com")` is a `LocalizedStringKey`, whose Markdown links and
tints an email address or URL — the Settings email placeholder came out blue. Such copy is now `Text(verbatim:)`.
