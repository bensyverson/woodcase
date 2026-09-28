# The viewer's phone face — design and build protocol

*2026-08-31. Author: Claude (Fable 5) with Ben. The design for a mobile
(phone-portrait) version of `woodcase serve`, drawn as a .pen file in this
directory by multiple agents working in the same file simultaneously — which is
itself the point: the build is a dogfood run of concurrent CLI editing.
Aesthetic ground truth is [DESIGN.md](../../DESIGN.md); this doc decides only
what mobile adds. Decisions below were made with Ben in-session.*

## Decisions (Ben, 2026-08-31)

- **Use case: glance & follow, plus presentation.** Watch agents work while
  away from the desk; hand the phone over to show someone. Full review
  (details, copy-address) is present but folded behind the sheet.
- **Target: responsive web** — the same served page below a breakpoint, same
  routes, progressive enhancement. Not a sibling app.
- **Frames: phone portrait only**, 402×874 (the house phone frame — the size
  the Jobs mobile dashboard and the file-card CSS already assume).
- **Fresh .pen file**, not a renovation of `2026-08-29-viewer-prototype/`
  (that file predates map-as-a-mode, card files, and the right-pane tabs).
- **Ticker coalescing rule:** when multiple actors touch one artboard, the
  ticker dot coalesces them — a tight overlap stack that collapses to
  `disc +N` past two — and never spills horizontally. A dot is one slot wide,
  always.

## The direction

**Most .pen files here are phone designs, and a 402-wide artboard on a phone
is 1:1** — the phone is the better viewing instrument. So at artboard level
the render is full-bleed and the chrome nearly disappears:

- A thin **status strip** floats at the top: back-to-map glyph, front-truncated
  artboard name, live dot, coalesced presence. All 11px mono on `chrome`.
- A **bottom sheet grabber** floats at the bottom, with the **ticker** above it.
- **Tap the stage background to toggle the chrome.** Presentation stops being
  a mode and becomes the resting state — the one aesthetic risk, and the
  signature restraint: the tool's mobile face is almost no face.

**Navigation keeps the desktop's three levels** — Files → Map → Artboard —
same routes. Swipe left/right steps artboards (the ←/→ keys); back and
sheet-swipe-down do Esc's walk-up. The map is pinch-out's destination and the
breadcrumb's, both.

**The signature element: the artboard ticker.** A thin strip of page dots
above the grabber, one per artboard in document order. A plain dot is an
artboard; the current one is accent-ringed; an unread one carries the 6px
warn dot; and an artboard an agent is *currently working in* wears that
agent's 6px avatar disc (new `avatar-dot` size, matching Jobs') in place of
its dot — coalescing per the rule above. One glance at a 20px strip answers
"who is working, where, and what haven't I seen."

## What earns the screen

| Always visible | In the sheet | Cut from mobile |
|---|---|---|
| The render, full-bleed | Outline (tab) | Export tab |
| Status strip (liveness, presence) | Details of selection (tab), Variables as a section under it | Code tab |
| Ticker (position, unread, actors) | Activity (tab) | Pane resizing, key hints |
| Selection pill when a node is tapped | | Theme picker (sheet overflow row) |

Tap-to-select stays: tap a node → accent outline + a floating **selection
pill** (front-truncated name tail + id chip + copy) docked above the ticker.
Details are one tap deeper (opens the sheet's Details tab). Follow mode is a
pill at the ticker's end; when on, the pager auto-advances to whatever was
just touched.

## The eight artboards

| Name | Shows |
|---|---|
| `Files` | Mobile card list: thumbnail, name, path, count, last change + avatar; one broken-file card |
| `Map` | The bird's-eye as a vertical-scroll grid; unread dots; touched frames tinted; one coalesced actor stack on a busy board |
| `Quiet` | Artboard view, chrome visible: status strip, ticker, grabber |
| `Immersive` | Same artboard, chrome receded — the render and nothing else (presentation/resting state) |
| `Following` | Three agents mid-edit: edit boxes + actor tags on the render, ticker wearing actor discs (one coalesced), follow pill active |
| `Outline Sheet` | Sheet at ⅔ height over dimmed render: outline tree, kind marks, touched rows |
| `Details Sheet` | A node selected: selection pill, sheet on Details tab — origin pills, rect, revision, Variables section |
| `Activity` | Sheet on Activity tab, full height: the five-column feed made two-line rows for a phone |

Dark costs no artboards: every color rides `mode=light/dark` theme variables,
and `shot --theme mode=dark` renders the second set.

## The kit (setup pass, single writer)

Built before any fan-out, because components and variables are the contended
surface. Theme variables carry DESIGN.md's color tokens verbatim (`v-bg`,
`v-chrome`, `v-panel`, `v-line`, `v-text`, `v-muted`, `v-faint`, `v-accent`,
`v-select`, `v-warn`, `v-mark-*`), plus three illustrative actor colors
(`actor-a/b/c` — hashed hues in real life; fixed here). Components, all
`reusable`, instanced with overrides, never forked:

`MockApp` (the sample phone design the viewer is "viewing" — one clean card
screen), `StatusStrip`, `Ticker` + `TickerDot` (variants: plain / current /
unread / actor / actor-stack+N), `SheetGrabber`, `Sheet` (head + tab row),
`TabPill`, `AvatarDot` (6px) / `AvatarSmall` (15px), `IdChip`, `KindMark`,
`SelectionPill`, `OutlineRowM`, `ActivityRowM`, `FileCardM`, `FollowPill`,
`EditTag`. Eight named empty frames at 402×874, laid out in one row with
120px gaps, in the table's order.

## Build protocol — the experiment

- One shared file: `project/2026-08-31-mobile-viewer/mobile-viewer.pen`,
  edited through `woodcase` only, by parallel agents each passing a unique
  `--as`. **No worktrees** — a deliberate deviation from
  `project/agents/delegation.md`: the agents change no code, the shared file
  *is* the experiment, and isolation is semantic (each agent writes only
  inside its own artboard frames) and mechanical (revision tokens, file
  transactions, `apply` batches).
- Four agents after the kit lands: `Files`+`Map` / `Quiet`+`Immersive`+
  `Following` / `Outline Sheet`+`Details Sheet` / `Activity`. Grouped by
  shared design surface, not one-per-artboard — the three artboard states
  must be one hand's work.
- Every agent's loop is `tree → apply → lint → shot`; every report carries a
  woodcase experience note (what taught, what fought) — those notes are half
  the deliverable, filed on the leaves and harvested into a dated DX doc at
  integration.
- Integration: lint clean, shots in both themes into this directory,
  review renders to `local/viewer-shots/` per the usual flow, then the
  DESIGN.md amendments below.

## Proposed DESIGN.md amendments (fold in at sign-off)

- `avatar-dot` (6px) joins the avatar sizes; identity discs remain the only
  identity-color carriers — the ticker complies by *being* discs.
- The ticker, sheet, status strip and selection pill join Components.
- A Layout paragraph for the phone breakpoint: panes become the sheet;
  chrome recedes on tap; shedding order gains "chrome itself sheds last."

## Tasks

```yaml
tasks:
  - title: Mobile viewer design in .pen (2026-08-31)
    desc: |
      The phone face of woodcase serve, drawn as a .pen by parallel agents in one shared file. Direction, screens, kit and protocol in project/2026-08-31-mobile-viewer/design.md; aesthetic ground truth in DESIGN.md. Read both first.
    labels: [mobile-viewer, dogfood]
    children:
      - title: Setup pass — file, theme variables, component kit, eight frames
        ref: kit
        desc: Single writer creates mobile-viewer.pen, the mode-themed variables from DESIGN.md tokens, every reusable component in the doc's kit list, and eight named empty 402x874 frames in a row. Components must lint clean and shot legibly in both themes before any fan-out.
        criteria:
          - Every kit component renders in both themes without lint findings
          - Eight frames exist, named per the doc, non-overlapping
          - Variables mirror DESIGN.md color tokens by name
      - title: Files and Map screens
        ref: nav-screens
        blockedBy: [kit]
        desc: The two navigation screens, built from FileCardM and kit atoms inside the Files and Map frames only.
        criteria:
          - Both artboards lint clean and read in both themes
          - Only kit instances and frame-local nodes; no forked components
      - title: Artboard states — Quiet, Immersive, Following
        ref: core-screens
        blockedBy: [kit]
        desc: The core full-bleed screens, one hand for all three so the states read as one design. Following shows three actors with one coalesced ticker dot.
        criteria:
          - The three states differ only by chrome and markers, never by the render
          - Ticker states cover plain, current, unread, actor, coalesced stack
      - title: Sheet screens — Outline Sheet, Details Sheet
        ref: sheet-screens
        blockedBy: [kit]
        desc: The bottom sheet at two depths over a dimmed render, with the selection pill on Details.
        criteria:
          - Sheet chrome is identical across both artboards
          - Details shows origin pills, rect, revision and a Variables section
      - title: Activity screen
        ref: activity-screen
        blockedBy: [kit]
        desc: The feed as two-line phone rows in a full-height sheet.
        criteria:
          - Rows carry time, avatar, identity, verb and path without truncating the verb
      - title: Integration — lint, themed shots, review renders, DX harvest
        ref: integration
        blockedBy: [nav-screens, core-screens, sheet-screens, activity-screen]
        desc: Fan-out results merged in review; lint clean across the file; shots of all eight artboards in both themes into project/2026-08-31-mobile-viewer/ and local/viewer-shots/; agents' experience notes harvested into a dated DX doc; DESIGN.md amendments applied.
        criteria:
          - Sixteen shots exist and are legible
          - A dated DX findings doc records the concurrent-editing experience
          - DESIGN.md carries the amendments or the doc says why not
```

## Integration decisions (2026-08-31, post-fan-out)

Recorded by the integrator after merging the four screen leaves; the agents'
full reports live on the leaves under job root `iR2OM`, and the tool findings
in [the concurrent DX report](../2026-08-31-woodcase-concurrent-dx.md).

- **The fictional file is `field-notes.pen`.** The kit's MockApp was already
  "Field Notes"; the Files top card, Map strip and the map's eight artboard
  names (Home, Entry, Photo, Search, You, Settings, Onboarding, Empty) were
  unified to it, so Files → Map → artboard reads as one drill-in.
- **Ticker semantics, as shipped:** the accent ring marks *this* artboard;
  actor discs mark agents *elsewhere*; who is here shows on the render (edit
  markers) and in the presence stack. This was the core agent's resolution of
  a kit gap (no current+stack dot variant) and it is better than the
  original sketch — adopted, and written into DESIGN.md.
- **Kit fixes applied:** `OutlineRowM` now ships `OR-TouchBar`/`OR-Mark`
  disabled; `TDS-More` widened so the documented `+N` override fits;
  `AvatarDot`'s context now says identity is literal hex; `Ticker`'s context
  says screens compose from `TickerDot-*` (a ref's target cannot vary per
  instance). `v-scrim` added (light `#00000066`, dark `#00000038`) and both
  sheet scrims moved onto it.
- **Accepted deviations** (over the doc's original numbers): 7pt phone row
  rhythm, 22pt ticker slots, 44/64pt chrome bands sized to the mock's seams
  with a chrome plate behind the bottom band, the map as a fixed 2×4 grid
  (the linter's clipped rule cannot yet express a scrolling grid — dN6XF),
  and composed per-screen ticker strips instead of instancing `Ticker`.
- **One integrator fix after the fan-out:** the Activity screen's tab row
  showed Outline current — residue of the nested-ref repoint corruption
  (`"ref": null` stored in the override map changes how sibling overrides
  render; appended to SWr75). Rewriting the map to the sheet leaf's pattern
  fixed it.
- The final file lints clean — zero findings — under the fixed linter
  (bec675d), with every themed override on `$v-*` variables.
