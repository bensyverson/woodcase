---
version: alpha
name: Woodcase
description: Design system for the Woodcase viewer — a local, read-only, live web view onto .pen files while agents edit them. Light-first, paper-warm, monospace-fluent.

colors:
  # Surface tiers, light. The viewer follows the OS scheme; each token has a
  # `-dark` counterpart below. In code these are the `--v-*` custom properties
  # in ViewerStylesheet.swift — the CSS is the source of truth for values.
  bg:              '#F6F5F1'
  chrome:          '#ECEAE3'
  panel:           '#FFFFFF'
  line:            '#E2DFD6'

  # Text tiers
  text:            '#1B1B18'
  muted:           '#65625A'
  faint:           '#A5A096'

  # The one accent — liveness and selection, nothing else
  accent:          '#2FBF6F'
  select:          'rgba(47, 191, 111, 0.12)'
  # Inks — what is legible *on* a fill (see Colors)
  accent-ink:      '#1D7745'   # the accent as readable text
  accent-fill-ink: '#1B1B18'   # a persistent word on the accent fill
  faint-ink:       '#1B1B18'   # the +N disc's figure

  # Attention — clipped nodes, lost connections, unread dots, broken files
  warn:            '#AC4C1B'

  # Component vocabulary — definition, instance, slot
  mark-component:  '#6A45FC'
  mark-instance:   '#1D68C8'
  mark-slot:       '#18766B'

  # Scrim behind the mobile bottom sheet (2026-08-31 mobile design;
  # denser in light than in dark, which is already dark)
  scrim:           '#00000066'

  # Dark counterparts
  bg-dark:             '#161615'
  chrome-dark:         '#232321'
  panel-dark:          '#1D1D1B'
  line-dark:           '#33322F'
  text-dark:           '#EDEBE4'
  muted-dark:          '#9E9991'
  faint-dark:          '#6A665E'
  accent-dark:         '#3ED483'
  select-dark:         'rgba(62, 212, 131, 0.16)'
  accent-ink-dark:     '#3ED483'
  accent-fill-ink-dark: '#161615'
  faint-ink-dark:      '#FFFFFF'
  warn-dark:           '#E08A4E'
  scrim-dark:          '#00000038'
  mark-component-dark: '#A594FF'
  mark-instance-dark:  '#6BA6F5'
  mark-slot-dark:      '#4FC8B8'

typography:
  # Sans carries human names and prose; mono carries anything an agent would
  # paste or a machine wrote. Both stacks resolve to the platform faces first
  # (SF Pro / SF Mono on a Mac); Inter and JetBrains Mono are fallbacks for
  # platforms whose system faces are weaker, not webfonts.
  body-md:
    fontFamily: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.45
  body-sm:
    fontFamily: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.45
  name:
    fontFamily: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1.45
  title-lg:
    fontFamily: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif
    fontSize: 20px
    fontWeight: 700
    lineHeight: 1.2
  title-xl:
    fontFamily: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif
    fontSize: 22px
    fontWeight: 700
    lineHeight: 1.2
  label-caps:
    fontFamily: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif
    fontSize: 10px
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: 0.09em
  brand:
    fontFamily: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1.45
  data-md:
    fontFamily: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace
    fontSize: 11px
    fontWeight: 400
    lineHeight: 1.4
  data-id:
    fontFamily: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace
    fontSize: 11px
    fontWeight: 500
    lineHeight: 1.4
  data-sm:
    fontFamily: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace
    fontSize: 10px
    fontWeight: 400
    lineHeight: 1.4
  data-xs:
    fontFamily: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace
    fontSize: 9px
    fontWeight: 600
    lineHeight: 1.5
    letterSpacing: 0.02em
  code:
    fontFamily: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace
    fontSize: 11px
    fontWeight: 400
    lineHeight: 1.55

rounded:
  xs: 2px       # map frames, swatches
  sm: 4px       # id chips, buttons, selects, step buttons
  md: 6px       # popover cards, the empty state's command block
  lg: 8px       # file cards, the keyboard popover
  full: 9999px  # kind marks, tabs, bool pills, the presentation hint

spacing:
  row-y: 2px          # vertical padding of a list row — the density the tool lives at
  gutter: 0.75rem     # horizontal padding of rows, panels and footers
  indent: 0.85rem     # one level of outline depth (`--v-indent`)
  stage-margin: 0.75rem
  map-pad: 1.75rem
  pane-left: 340px    # default; resizable via `--v-col-left`
  pane-right: 320px   # default; resizable via `--v-col-right`
  grip: 6px           # the drag seam between panes (`--v-grip`)
  thumb-height: 144px # the file card's render box

components:
  avatar-dot:
    size: 6px
    rounded: '{rounded.full}'
  avatar-small:
    size: 15px
    rounded: '{rounded.full}'
  avatar-medium:
    size: 20px
    rounded: '{rounded.full}'
  avatar-large:
    size: 28px
    rounded: '{rounded.full}'
  id-chip:
    backgroundColor: '{colors.line}'
    textColor: '{colors.muted}'
    rounded: '{rounded.sm}'
    padding: 2px 6px
    typography: '{typography.data-id}'
  kind-mark:
    rounded: '{rounded.full}'
    padding: 1px 5px
    typography: '{typography.data-xs}'
  button:
    backgroundColor: '{colors.panel}'
    textColor: '{colors.text}'
    rounded: '{rounded.sm}'
    padding: 2px 6px
    typography: '{typography.data-md}'
  button-affirm:
    backgroundColor: '{colors.select}'
    textColor: '{colors.text}'
    rounded: '{rounded.sm}'
    typography: '{typography.data-md}'
  tab:
    textColor: '{colors.muted}'
    rounded: '{rounded.full}'
    padding: 3px 9px
    typography: '{typography.data-md}'
  tab-current:
    backgroundColor: '{colors.chrome}'
    textColor: '{colors.text}'
  panel-title:
    textColor: '{colors.muted}'
    typography: '{typography.label-caps}'
  file-card:
    backgroundColor: '{colors.panel}'
    rounded: '{rounded.lg}'
    padding: 0.5rem
  step-button:
    size: 18px
    rounded: '{rounded.sm}'
  disclosure-glyph:
    size: 18px
  key-hint:
    size: 16px
    rounded: '{rounded.full}'
  swatch:
    size: 11px
    rounded: '{rounded.xs}'
  unread-dot:
    size: 6px
    backgroundColor: '{colors.warn}'
  ticker-slot:
    size: 22px
---

# Woodcase viewer design system

The normative values live in the frontmatter above and, ultimately, in
`Sources/WoodcaseViewer/Styles/ViewerStylesheet.swift` — a change to the CSS
tokens is a change to this document, and the two must move together. The prose
records the decisions and the reasons; the dated history is in `project/`
(the prototype: `project/2026-08-29-viewer-prototype-dx.md`; the map:
`project/2026-08-30-map-as-a-mode.md`; the review that shaped the current
chrome: `project/2026-08-30-viewer-review-feedback.md`).

## Overview

The viewer is `woodcase serve`: a local, read-only web page onto .pen files
while agents edit them through the CLI. The CLI serves agents; the viewer
serves the human watching them — a window onto work, not a tool for doing it.
Everything it shows derives from the file and the activity log; it adds no
state of its own.

The look is a quiet developer-tool surface: paper-warm neutrals, hairline
seams, one green accent that has to be earned. Dense the way a good inspector
is dense — 11px monospace facts, two-pixel row rhythm — but calm, because
almost everything is gray until something happens. The personality is a
precise instrument next to a workbench, not a dashboard: no status chrome, no
decoration, nothing that moves unless the file did.

Light-first, following the OS scheme (`prefers-color-scheme`), with a warm
near-black dark. The *site's* light and dark is the OS's business; the
*file's* theme axes (`mode=light/dark` and friends) are a separate control in
the top bar, and the two never share a switch.

## Colors

Five independent color axes; the discipline of the design is that they never
borrow from each other.

- **Surfaces** — `bg` (warm paper) is the canvas; `panel` (white) is where
  content lives; `chrome` sits *back* from panel on purpose: panels are where
  things happen — a row lighting up, a marker appearing — and they need a
  surround to happen against, or every in-action state is white on white.
  `line` draws the hairline seams between everything.
- **Text** — three tiers: `text` for content, `muted` for supporting facts,
  `faint` for scaffolding (glyphs, unnamed nodes, dimmed counts).
- **Accent** (`accent`, blue-green — Ben's pick over the first draft's orange)
  means exactly two things: *liveness* (the live badge, the follow-resume
  pill) and *selection* (outline boxes, focused rows via `select`, the
  focused map frame, the copied-state flash). It never decorates.
- **Warn** (`warn`, burned orange) is the attention axis: clipped nodes, a lost
  connection, unread dots, a file that failed to parse. It is a fact color,
  not an error state — the viewer has nothing to enforce.
- **Marks** — the component vocabulary: purple for a reusable component
  definition, blue for an instance, teal for a slot. Same three hues light
  and dark, always paired with a glyph (◈ ◇ ▥) and, where there is room, the
  word.

**Actor identity** is the sixth color, and it is not a token: each identity's
color is hashed from its name (FNV-1a over `name+"u"` for hue, fixed 48%
lightness — `ActorColor.swift`, ported byte-for-byte from the Jobs dashboard
so an agent is the same color in both tools). It arrives as `--v-actor` on
the element that needs it, never as a class. It may appear in exactly two
places: the avatar disc and the edit markers (touched-row bars, edit boxes
and tags over the render). Never in text or chrome — a hashed hue lands on
the accent green often enough (`claude-a` and `ben` both do) that colored
text would read as a link or as liveness.

What is drawn *on* that hue is Woodcase's own, not the dashboard's:
`--v-actor-ink` rides beside `--v-actor` and is **black above a relative
luminance of 0.179, white below**. At a fixed 48% lightness a hashed hue can
be `#12E281` or `#150AEB`, and white reads on only one of them; 0.179 is the
two-way crossing point, where both inks land on 4.58:1, so every hue on the
wheel clears AA with the hash — hue, saturation and lightness — untouched.
The disc, its initial and the edit tag's words all pivot together.

**Contrast.** AA (4.5:1) is the bar for text that carries meaning (Ben's
ruling, 2026-09-02). `faint` is **exempt**: it is scaffolding — glyphs,
unnamed nodes, dimmed counts — and being quiet is the whole of its job. The
palette moved to meet the bar rather than the components restyling around it.
Measured with `scripts/viewer-contrast`, which walks every state in both
schemes with `sleepy contrast --min wcag-aa`:

```bash
woodcase preview --port 7423 &
woodcase preview --list | scripts/viewer-contrast --base http://127.0.0.1:7423
```

| pair | before | after | what moved |
|---|---|---|---|
| avatar initial on a hashed hue | 1.72 | ≥ 4.58 | `ActorColor.ink` |
| edit tag's words on the same hue | 1.72 | ≥ 4.58 | the same pivot |
| `+N` disc on `faint` | 2.60 | 6.63 / 5.71 | new `--v-faint-ink` |
| `live` on chrome, light | 1.98 | 4.62 | new `--v-accent-ink` |
| `disconnected` on chrome, light | 3.69 | 4.59 | `warn` `#C4571F` → `#AC4C1B` |
| crumb, presence note, key hint on chrome, light | 3.92 | 5.06 | `muted` `#77736A` → `#65625A` |
| id chip on `line`, light / dark | 3.55 / 3.88 | 4.57 / 4.53 | `muted` (dark `#928D83` → `#9E9991`) |
| preview note on bg, light | 4.33 | 5.58 | `muted` |
| kind label, instance on panel, light | 4.08 | 5.43 | `mark-instance` `#2F7DE1` → `#1D68C8` |
| kind label, component / slot on panel, light | 4.38 / 3.96 | 5.43 / 5.47 | `#7C5CFC` → `#6A45FC`, `#1D8F82` → `#18766B` |
| true bool pill, light (2026-09-26) | 2.39 | 7.24 | new `--v-accent-fill-ink` |
| selection box tag, light / dark (2026-09-26) | 2.39 / 1.92 | 7.24 / 9.44 | the same |

The accent itself did **not** move: it is a fill as much as an ink (the dot,
the selection box, the copied flash), and darkening it to be readable would
have dragged every one of those with it. `--v-accent-ink` is the accent dark
enough to be *read*; `--v-accent` stays the accent that is *seen*; and
`--v-accent-fill-ink` is what a *persistent* word on the accent fill is
lettered in — near-black in both schemes, because the accent is bright in
both, which is the answer the avatar's 0.179 pivot gives too.

Two families still sit under 4.5:1 on purpose. Every `faint` pair, by the
ruling above. And white ink on the accent fill **during a flash** — the
copied id chip and the footer's copied button, 1.2 s after a click (2.39:1
light, 1.92:1 dark). Ben's ruling of 2026-09-02 narrows the old exception to
exactly that: a transient state may keep white; a persistent one (the true
bool pill, the selection box's tag) must reach AA, and does through
`--v-accent-fill-ink`.

## Typography

Two voices, split by who the text is for:

- **Sans** (system stack) — human names and prose: node names, file names,
  panel prose, empty-state ledes.
- **Mono** (system mono stack) — anything an agent would paste or a machine
  wrote: ids, rects, revisions, activity verbs, key names, timestamps, the
  brand, tabs, chips, code. When a *name* is missing, its stand-in `#id` is
  mono and faint — the font says "this is an address, not a name."

An identity is one of those addresses, not a name: it is the `--as` handle a
writer typed on a command line, so it is set in **mono** wherever it is
spelled out, never in sans as if it were a person's name. It appears in two
places — the activity row's identity column (`.v-activity-identity`) and the
presence line, both the summary's "2 active · ben editing" and the expanded
list, where the handle is a `.v-presence-name` span set in mono. The avatar's
single initial is the standing exception, and it is sans because a letter
alone in a 15px disc is a mark, not a word.

The scale is small and dense: 13px base prose, 12px list rows, 11px mono as
the workhorse for every chrome fact, 10px letter-spaced caps for panel
titles, 9px caps inside kind-mark pills. Titles (20/22px) appear only on the
dashboard and empty states — inside a working view, nothing is bigger than
the content it describes.

Inter and JetBrains Mono sit in the stacks as fallbacks behind the platform
faces; nothing is embedded or fetched. On a Mac the viewer renders SF Pro and
SF Mono.

## Layout

Three panes on a desktop artboard view — outline left (340px), canvas center,
right pane (320px) — separated by 1px `line` seams (a grid with `line` as its
background showing through the gaps) and draggable 6px grips; each track is a
custom property (`--v-col-left`, `--v-col-right`, `--v-row-lower`), so a
resize is one property write. The left column stacks Outline over Variables.
The map page swaps the node outline for an artboard list; the dashboard and
empty layouts are single-column.

The canvas is sized by the pane, never by its content — one explicit
`minmax(0, 1fr)` track each way, so a 40,000-point map plane scrolls inside
it rather than stretching the page. In presentation mode (`f`) the canvas
leaves the grid entirely and fixes to the viewport.

Rhythm comes from row density, not a spacing grid: 2px vertical padding on
list rows, 0.75rem gutters, 0.85rem per outline depth. There is deliberately
no 4/8px scale — gaps are tuned per component in rem fractions.

When a row runs out of room it **sheds its least essential facts rather than
clipping or wrapping**, via container queries: the selection footer drops the
rect and revision below 560px (both live in the Details pane — the same
reasoning that removed rect columns from outline rows), or below 720px when
the clip warning takes a slot of its own, and a map label hides
entirely below the size it can be read at (the name survives in the box's
`title` and the outline), and the map page's artboard row drops its rect
below 420px (on the map beside it, and in Details) before it would cut a
letter of the name. An edit tag capped at the artboard's edge shortens its
handles — the discs carry them — and keeps its verb and age. Paths truncate from the *front* (an RTL box around
a `<bdi>` isolate), so the tail that names the node is what survives.

**The phone breakpoint** (decided in the 2026-08-31 mobile design; the values
land in `ViewerStylesheet.swift` with the implementation). On a phone the
panes become one bottom sheet (tabs: Outline / Details / Activity; Variables
a section under Details; Export and Code do not make the cut), the render
goes full-bleed, and the chrome recedes on a stage tap — presentation is the
resting state, not a mode. Chrome is the last thing shed, and it sheds by
receding, never by shrinking. List rows step up to a 7pt vertical rhythm —
the desktop's 2pt is not tappable — and the artboard ticker's slots are 22pt
touch targets.

## Elevation & Depth

Depth is tonal and drawn, not cast. Panels sit on `bg` separated by hairline
`line` seams; hovers step a surface to `chrome`; selection tints with
`select`. The one shadow token is a whisper (`0 1px 2px` at 6% ink) on cards,
the stage and popovers — and in dark mode it is `none`: dark layers by tone
alone. Sticky panel headers float over their scrolling lists on the same
panel color, held by a z-index, not a shadow.

## Shapes

Small radii, engineered rather than friendly: 2px on map frames and swatches,
4px on chips and buttons, 6–8px on cards and popovers. Pills (999px) are
reserved for *badges* — kind marks, tabs, bool pills, the presentation hint —
things read as a unit, not clicked as a surface. Avatars are the only
circles. Overlay boxes on the render are square-cornered: they trace
geometry, and geometry has no radius.

Two strays exist in the CSS and are candidates to normalize, not precedent:
the box tag's 3px top corners and the file thumb's 5px.

## Components

**Top bar.** One 44px-ish strip of `chrome`: mono brand ("woodcase", links to
the root), breadcrumb (file name links back to the map, wearing a map glyph
and the file-wide unread dot), live badge, presence stack, follow picker,
file-theme picker, keyboard-hint popover, presentation button. Every control
in it is 11px mono.

**Live badge.** A dot plus a word — `live` in accent, `connecting…` muted,
`disconnected` in warn. Every label is server-rendered and the state picks
one, so the badge can never go amber while still reading "live."

**Avatar.** The canonical identity atom, shared with the Jobs dashboard: a
disc filled with the identity's hashed color, three sizes (15/20/28px), and
an initial in whichever ink that disc can be read in — black on a bright hue,
white on a dark one, pivoting at 0.179 relative luminance (see *Colors*). An
empty identity renders `?` — an unattributed write is a real state, not a
rendering bug. The presence stack overlaps discs by 7px with a 2px `chrome`
ring, and its `+N` disc is filled with `faint` and lettered in
`--v-faint-ink`.

**Id chip.** A node's 5-char id as a mono chip on `line`; click copies, and
the copied state flashes accent. This is the handoff point to an agent. Both
words — the id and `copied` — are server-rendered in every chip, and the
script only toggles `is-copied`; `copied` is laid over the id, so the chip
keeps its resting width and the flash moves nothing beside it. The footer's
copy button flashes the same way.

**Kind mark.** The component-vocabulary pill: glyph + word, tinted by its
mark color at 12% fill and 45% border. On the map there is no room for the
word: the mark collapses to a 15px circle around the glyph alone and lends
its color to the artboard's name.

**Disclosure glyph.** One shared 18px SVG triangle for every expand/collapse
control (Variables, Outline). It carries no direction of its own — each
caller rotates it. Leaf rows reserve the same 18px so names align. Do not
introduce a second disclosure control.

**Outline row.** 12px sans name, depth-indented, mono glyph column; unnamed
nodes as faint mono `#id`; a warn `⚠` for clipped nodes. Selected rows tint
`select`; rows touched in the last 30s carry a 3px left bar in the actor's
color. Rect and id columns were removed — they live in Details.

**Artboard map.** The landing view for a multi-artboard file: real low-res
renders placed in layout points under one zoom, names *under* the boxes
(11px mono, never scaling with the map), focus as an accent outline drawn
outside the frame so it never eats a pixel of thumbnail, touched frames
border-tinted by actor. Keyboard: arrows move, Enter drills in, Esc walks
back up.

**File card.** Panel card with a 144px render box (the render keeps its own
aspect inside the fixed box — a grid of cards each sized to its artboard
would be a staircase), name, path, artboard count, last change with its
avatar. A broken file tints the card toward warn and says why in mono.

**Activity row.** A five-column grid: mono time, avatar, identity, verb,
path; expands to the node list and details. The verb is the row's one bold
mono word. The path column front-truncates like every path, so the node's
name and the `+N` survive. A write with no `--as` reads `unattributed` in
faint mono wherever a name is written as text (the identity column, the
presence line) — the stand-in for a missing name, like `#id`, never a blank.

**Variables pane.** Swatches for colors, right-aligned mono for numbers, a
bool pill (accent when true), and per-axis variant tables that reuse the
Details pane's two-column grid — a themed variable and a node's detail read
the same way.

**Render stage and overlay.** The artboard PNG on a `panel` stage, scaled by
one `--v-scale` custom property that every overlay box multiplies through.
Selection boxes are 2px accent; edit markers borrow the actor color, fade
over 1.2s, and pin on click — and an edit tag's words take that color's ink,
the same pivot the disc inside it makes. Box tags cap their width at the
artboard's edge and front-truncate like the footer.

**Selection footer.** The agent handoff line: front-truncated name path, id
chip, rect, revision, copy button, `‹ 3 of 5 ›` steppers. Only the path
shrinks; everything else is a fixed fact, and the rect and revision are shed
first when the pane narrows.

**Right pane.** Pill tabs — Details / Export / Activity / Code — with the
code split toggle beside them as a control, not a tab. Every panel is
rendered and the tab decides which is shown, so a fragment can land in a pane
nobody is looking at and switching is instant. Details rows carry origin
pills (`variable` in mark-purple, `override` in mark-blue) and the
grid-aligned key/value shape the variant tables reuse.

**Presentation mode.** `f` or the top-bar button: the canvas fixes to the
viewport, everything else hides, an exit hint flashes once in a mono pill and
fades. Arrow keys keep working.

**Unread dot.** A 6px warn dot with a panel ring, hung on
`data-unread="1"` — an attribute, not a class, so every view of the artboards
(map boxes, artboard rows, the breadcrumb's map crumb) inherits it by
carrying the same attribute.

**Empty state.** A centered title, one muted lede, and the two commands that
make something appear, in a `chrome` command block — the tool teaching its
own first step. The block scrolls sideways rather than the page; a real path
is longer than the 34rem card. A 2rem `chrome` gradient fades its right edge
as the scroll affordance — always drawn, not only on overflow, because CSS
cannot ask whether a box overflows and a gradient is not worth a line of
script; over a block that fits it tints an empty margin and reads as nothing.
Two of them, one atom: nothing served yet
(the dashboard), and a file with no artboards yet — every `woodcase new`
passes through the second for as long as its first frame takes. Both carry
`data-empty-file` (a file id, or empty for "any file at all"), which is how
the stream replaces them: the page that answers next is a *different* page,
so the update is a reload, not a fragment swap.

**Loading shimmer.** A slow `chrome` band traveling across a `panel` ground,
on the frame of a map thumbnail whose render has not arrived. It is a
background *behind* the image, so a loaded PNG covers it with no help from
JavaScript; the script drops the class when the image lands or fails, so
nothing animates for the rest of the session, and it stops entirely under
`prefers-reduced-motion`. An empty box says "this artboard is blank"; a
shimmering one says "not here yet", which is the truth.

**Previews.** The `/preview` pages — an index of components, a canvas per
component, a page per state. They wear the same layout the dashboard does
(one centered column, `1.6rem 2rem` gutters) and are typed as prose, not as
chrome: the state's name is a 13px sans heading, its note the 13px muted
caption under it (capped at 46rem, so a caption is read in one column), and
the permalink under that is 11px `faint` mono — an address, not a name, and
the one thing on the page meant to be copied — and the drawing sits on its own
line below it, never beside it. A `#` anchor sits ahead of each
name in `faint` mono. The source path in the header is the same 11px mono, on
the right where a panel note sits everywhere else.

Each state sits in a **frame**: a 6px-radius hairline `line` box carrying
`data-frame`, given the *production* surface's geometry — the panes are
`--v-col-left` / `--v-col-right`, the exact custom properties the artboard
grid uses, so widening a pane in production widens the preview too. The
render column is what a 1280px reference window (`--v-preview-window`, the
size the review loop shoots at) has left after both panes and their grips.
A state that exists to show a narrower pane — the selection bar's 560px
shed — pins its frame's width (`pinnedWidth`) and keeps its surface's ground.
Frames paint the ground their surface really has — panel for the two panes,
`bg` for the render column and the dashboard body, chrome for a `strip` atom
(the presence stack's rings are drawn in chrome and read as holes on
anything else) and chrome for the top bar too — the whole bar paints its
own, but a bare control from it (a picker, the keyboard hint) would
otherwise sit on paper it never sits on. An overlay a frame cannot open —
the keyboard popover, the presentation hint — is drawn in place, at rest.
A state that sits in a grid in production (a file card) is framed inside
that grid, so it is drawn at a cell's width. The catalog's own top bar is
the trail alone (`TopBar.Subject.previews`): nothing on these pages is live,
the script opens no stream on a `/preview` URL, and a state's badge,
presence and dots stay exactly as it declared them. Captions are rendered
from a small Markdown subset — code spans and DocC symbol links as mono
`<code>`, `*emphasis*` — never shown as source. The render in every
preview is a placeholder the catalog carries (`PreviewFixtures.render`,
the fixture layout drawn as boxes), so an overlay sits over what it names.
`strip`
shrinks to its content on one line; a whole `page` gets no frame at all,
because a document cannot nest a document: the canvas links to it instead.
States are spaced 2rem apart, which is far enough that two frames never read
as one component.

**Mobile atoms** (decided in the 2026-08-31 mobile design;
`project/2026-08-31-mobile-viewer/` holds the drawn reference).

- *Artboard ticker.* A strip of 22pt slots above the sheet grabber, one per
  artboard in document order: a plain `faint` dot is an artboard, the current
  one wears an accent ring, an unread one the 6px warn dot, and an artboard
  an agent is working in wears that agent's 6px avatar disc in place of its
  dot. Multiple actors on one artboard **coalesce** — an overlapped
  two-disc stack with a `+N` — and a slot never widens: one artboard, one
  slot, always. The current ring means "you are here"; actor discs mark who
  is *elsewhere* — who is here is already on the render as edit markers and
  in the presence stack.
- *Bottom sheet.* A `panel` sheet with a grabber and the tab row; the body
  scrolls under a pinned chrome strip. The scrim behind it is the `scrim`
  token — denser in light than in dark.
- *Status strip.* The top bar reduced to its glanceable core: back glyph,
  front-truncated name, live dot, coalesced presence.
- *Selection pill.* The selection footer reduced to its point: front-
  truncated name tail, id chip, copy — floating above the sheet.

## Do's and Don'ts

- **Do** make the accent earn its place: liveness and selection only. A
  screen should show a handful of green marks at most.
- **Don't** put identity color in text or chrome — discs and edit markers
  only. A hashed hue can land on the accent.
- **Do** pair every colored state with a word or a glyph; the color is never
  the only carrier (live badge labels, kind marks, `⚠` on clipped rows).
- **Do** set anything an agent would paste in mono; names and prose in sans.
- **Don't** layer surfaces with shadows — hairlines and tonal steps do it;
  dark mode has no shadows at all.
- **Do** server-render every state and let script *choose* between them;
  script never writes a word of text.
- **Do** shed the least essential fact when a row narrows (container
  queries), and front-truncate paths so the specific tail survives.
- **Don't** clip or wrap chrome text as an overflow strategy; shedding and
  front-truncation are the two affordances for a *row of facts*. A command
  block is the one thing that scrolls instead, and its right-edge fade is
  that scroll's only affordance.
- **Don't** introduce a second disclosure control, a second identity
  primitive, or a fourth way to handle overflow.
- **Don't** let the site's OS theme and the file's theme axes share a
  switch — they are different questions about different things.
- **Do** size the canvas from the pane, never from its content.
- **Don't** hand-place color literals in component CSS; the token block,
  `--v-actor` and `--v-actor-ink` are the only sources. (White ink on the
  accent fill *for a flash* — the copied chip and copy button — is the one
  exception. A persistent word on the accent takes `--v-accent-fill-ink`, and
  a hashed fill pivots.)
- **Do** put text that carries meaning at 4.5:1 or better, and check it with
  `scripts/viewer-contrast` before calling a change done. `faint` is the one
  exemption, because scaffolding is meant to recede.
