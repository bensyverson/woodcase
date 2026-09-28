# Viewer page as components, not pages (2026-08-29)

Author: Claude (Fable 5), at Ben's request: "investigate how you might use the
principles of React / SwiftUI to build components rather than a bunch of hardcoded
pages" — with a pointer to [Plot](https://github.com/JohnSundell/Plot). The plan's
decision 10 said "one HTML page, plain JS, no framework"; this revises *how that page
is made*, not what it is.

## The principle we actually want

Three ideas from React/SwiftUI carry over to a server-rendered page; the rest (a VDOM,
client state, hooks) does not, because the viewer is read-only and the server already
holds the truth:

1. **A component is a value with a `body`.** `AvatarView(identity:)`, `OutlineRow(row:)`,
   `ActivityRow(event:)`, `PresenceStack(identities:)`, `ThemePicker(axes:)`,
   `VariablesPanel(vars:)` — each a Swift struct whose body composes smaller ones. Pages
   are components too (`DashboardPage`, `ArtboardPage`, `EmptyPage`); there are no
   hand-written pages, only compositions.
2. **Props in, markup out, no hidden state.** A component renders from typed inputs
   that already exist: `TreeRow`, `ActivityEvent`, `NodeAddressCandidate`, the file list.
   The same struct the CLI prints as rows is what the page renders — one model, two
   formatters (strongly-typed principle: "one struct that both import").
3. **Previews are tests.** Each component renders to a string with fixed props, so a
   golden HTML fixture per component/state *is* its preview and its regression test —
   the "Previews" principle, and the way `ReactEmitterTests` already works here.

Live updates keep the components server-side: an SSE event names what changed
(`{file, nodes, identity, revision}`), the page fetches the affected **fragment**
(`GET /files/{id}/outline`, `/activity`, `/presence`) and swaps its `innerHTML` — the
htmx pattern, hand-written in ~40 lines of JS. So the only client-side JS is the swap
loop, the theme-picker/expand clicks, and the **overlay** — the identity-coloured edit
outlines and click-to-outline, positioned from the tree's layout rects over the PNG,
which must live in JS to fade and pin without a re-render. Nothing is rendered twice;
there is no JS twin of any component.

Rendering is a `MainActor`-free pure function of props, so the server handles a
fragment request without touching the document actor beyond one `PenFileTransaction.read`.

## What exists

- Nothing in Woodcase builds HTML for the viewer today (`CodeGen/ViewerScaffolder`
  writes a *React* app for generated components — a different product; `ViewerTemplates`
  are its Vite files). The React emitter builds JSX by string concatenation — fine for
  codegen, not a model for composable UI.
- SleepyHollow has no HTML DSL; the Jobs dashboard is Go templates.

## Options for the DSL

| | Plot (Sundell) | Elementary (sliemeobn) | Hand-rolled result builder |
|---|---|---|---|
| Shape | `Component` with `body`, `.div(.p("…"))` nodes, `@EnvironmentValue`, `.class()` modifiers | `HTML` protocol with `content`, `div(.class("x")) { … }` result builder, attribute merging, streaming render | `HTMLBuilder` + `Node` enum, our own escaping and attributes |
| Type safety | Strong: attribute/element contexts checked at compile time | Strong, generic (no existentials), attributes checked per tag | Whatever we write |
| Swift / platforms | tools 5.4, macOS 11+, Linux; existential nodes | tools 6.1, macOS 14+, Linux, Swift 6 concurrency; async streaming | ours |
| Activity | 0.14.0 May 2023; last push Jul 2024; 10 open PRs | 0.8.1 released 2026-08-24; active | n/a |
| Deps / license | none / MIT | none / Apache-2.0 | none |
| Cost to us | old toolchain baseline; API pre-dates result-builder idioms; `.if/.unwrap/.forEach` instead of plain control flow | a dependency on a 0.x package; macOS 14 floor (we are already there for the renderer) | ~250 lines: builder, escaping, attributes, void tags, a `Component` protocol, a render-to-string — plus every bug those 250 lines have |

Checked 2026-08-29 with `gh api repos/<r>` and `releases`.

## Recommendation

**Elementary**, as a dependency of the viewer only (a `WoodcaseViewer` target so the
library stays free of it). **Approved by Ben 2026-08-29** ("Elementary works"). It is Plot's idea with the modern shape
(result builders, generics, Swift 6, streaming, attribute merging), tiny, active, and
zero-dependency; Plot is the reference design but its API and toolchain are a
generation behind and it has not shipped in two years. Hand-rolling is the fallback if
Ben would rather own it: the surface we need is small and a `Component` protocol over a
`Node` enum is a day's work, but it is a day spent on escaping and void tags rather than
on the viewer.

Either way the structure is the same and is what the leaf builds to:

```
Sources/WoodcaseViewer/           (Apple-only like render; Elementary lives here only)
  Components/  AvatarView, PresenceStack, OutlineRow, OutlinePanel, ActivityRow,
               ActivityFeed, VariablesPanel, ThemePicker, TopBar, FileRow, FileList
  Pages/       DashboardPage, ArtboardPage, EmptyPage   (compositions, no markup of their own)
  Styles/      Theme.css as a Swift string with the v-* tokens (light/dark via prefers-color-scheme)
  Client/      viewer.js — SSE loop, fragment swap, overlay (outlines, fade, pin)
  Server/      the Network.framework HTTP/SSE server, routes → pages and fragments
Tests/WoodcaseViewerTests/  golden HTML per component × state (the previews)
```

`ActorColor` (the Jobs hash) is a Swift function in `Components/` with the two pinned
values from the viewer leaf's note. Endpoints: `/` (dashboard), `/files/{id}` (artboard
page), fragments `/files/{id}/outline|activity|variables|presence`, data
`/files/{id}/tree.json` (the `TreeFormatter.json` form, for the overlay), image
`/files/{id}/artboards/{id}.png`, and `/events` (SSE).

## What this changes in the plan

Decision 10's "no framework" stands for the *client*; the server side gains a component
DSL. The "Viewer page" leaf (ExnBl) is built as components with golden previews; the
"Server and file watching" leaf (EnTjY) serves fragments as well as JSON. Recorded on
both leaves.

## Routes ship hydrated (Ben, 2026-08-29)

Relying on JS for liveness is an accepted deviation from the house "no SPA" default —
this is a dev tool — but it is not an SPA: the viewer has **real routes, each served
complete**. `/` (dashboard), `/files/{id}` (artboard view, first artboard),
`/files/{id}/artboards/{id}`; view state lives in the query so a URL describes what
you see and back/forward work — `?node=Vr7Kd` (selection), `?theme=mode:dark`,
`?expand=1`, `?depth=3`. Every route returns the whole page from the page component —
outline, activity, variables, presence, the selected node already outlined (the
overlay's initial rects are inline JSON) — so it is correct with JS off. Outline rows
are `<a href="?node=…">`, the theme picker is a GET `<form>`; the JS intercepts those,
swaps fragments and `pushState`s, and falls back to a plain navigation. Progressive
enhancement, as `AGENTS.md` already asks.
