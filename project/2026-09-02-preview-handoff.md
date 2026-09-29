# Handoff: the viewer previews, after round one

2026-09-02, end of session. Read this before the second review round. The design is
[viewer previews](2026-09-02-viewer-previews.md); this is where it stands and what is
decided.

## State of main

`721aa5a`, clean, pushed. 3748 tests in 388 suites, two known issues (the `tree` budget
advisories). `swiftformat . --lint` clean. No worktrees.

What landed today, newest first:

| commit | what |
|---|---|
| `721aa5a` | presence handle in mono (`.v-presence-name` span in the summary) |
| `0fe87f4` | a preview's drawing on its own line below the permalink (HCnzVi) |
| `01524fd` | avatar ink pivot, AA tokens, command-block fade, two catalog drops, `--list` paths |
| `0b695df` | dropped the three states that render nothing |
| `e684ab0` | `/preview` routes on `serve`, `woodcase preview`, frames, `ViewerHosting` |
| `3d88905` | every component previewed: 35 components, the script-only states declared |
| `cbfe522` | catalog moved out of the tests; goldens at `<component>/<state>.html` |
| `94eeaa4` | the design doc and plan |
| `3abb54c` | page goldens (`Fixtures/pages.pen`, `ReactEmitterPageGoldenTests`) |
| `c4f67f2` | address walk follows a ref chain into an instance |
| `0e917b6` | injected slot children resolve everywhere |
| `6fe978a` | `--dry-run` on vars/undo/new |
| `e4683c7` | emitter: props per node one-to-many; pages get a signature |

The catalog: 38 components, 83 states (`woodcase preview --list | wc -l`). Every
component under `Sources/WoodcaseViewer/Components/` that renders is in it, and
`PreviewCatalogTests` fails the day one is added without an entry.

## How to look

```bash
swift build -c release
rm ~/.swiftpm/bin/woodcase && cp .build/release/woodcase ~/.swiftpm/bin/woodcase   # rm first: gotchas.md
woodcase preview --open                 # the index
woodcase preview avatar                 # one canvas
woodcase preview --list                 # every state as a path
woodcase preview --port 7423 &
sleepy shot http://127.0.0.1:7423/preview/avatar/small --size 1280x800 --theme light --theme dark --out avatar-small-.png
woodcase preview --list | scripts/viewer-contrast --base http://127.0.0.1:7423
```

`sleepy shot --theme` repeats and sweeps, naming the files itself. A `strip` atom is ~20 px
in a 1280×800 page: crop with `--selector '.v-preview-frame' --scale 2` before judging
one. The first review pass's shots, per-state verdicts and contact sheets are in
`local/viewer-shots/preview/` (`REVIEW.md` is the table); `round-one/` under it has the
after-shots for the ink pivot, the fade and the permalink.

## Rulings made today, so nobody re-argues them

- **A state that renders nothing is not a preview.** A markup fact wants a behavior
  test, not a picture. (`0b695df`; in the design doc as a block quote.)
- **Representative, not exhaustive.** Eight booleans are 256 states; the catalog shows
  the ones a reviewer can grade. A state that differs from its neighbor only by an
  attribute with no visible effect is dropped (id-chip/outline, pane-grip/rows).
- **AA (4.5:1) for text that carries meaning; `faint` exempt as scaffolding.** The palette
  moved, not the components. DESIGN.md § Colors carries the before/after table and
  `scripts/viewer-contrast` reproduces it.
- **Avatar ink pivots** at relative luminance 0.179; the hash and 48% lightness are the
  Go dashboard's and do not move.
- **White on a fixed accent fill is fine for a flash, not for a persistent element.**
  The copied chip keeps it; the true pill and the selection box tag must reach AA
  (issue `wRxjaB`, with the DESIGN.md exception to narrow in the same commit).
- **Handles are mono.** An identity is an `--as` address; the presence line now honors
  it (`721aa5a`).
- **`preview --list` prints paths.** It binds no port, so it has no URL to name; join with
  the base the running verb's `--json` reports.
- **The drawing sits on its own line below the permalink.**
- **The captions are `note` strings, not DocC comments.** They were written in DocC's
  dialect and render verbatim (`iblXjP`). The fix that makes them read well is a small
  Markdown subset for notes: code spans at least.

## Open: 26 issues under `BMjsh`, all from the previews

`job ls --issues`. A proposed carve for round two, by file surface, with a severity each.
Not imported — Ben strikes what should wait, then `job import` this file with
`--parent BMjsh` or as its own root.

```yaml
tasks:
  - title: Preview review, round two
    desc: |
      The 26 issues the first review pass filed, carved by the files they touch.
      Read project/2026-09-02-preview-handoff.md first for the rulings.
    labels: [viewer, previews]
    children:
      - title: The script must not undo what the server rendered
        desc: |
          HIGH. ViewerScript.applyUnread deletes data-unread on load when localStorage
          has nothing for the file, so the unread dot can never render (wNhNQp); the
          live stream wipes the server-rendered presence and live badge on page
          previews, so two shots of one state disagree (GqUQys); the script writes the
          word "copied" instead of toggling a class (ymsE0s). One rule: the script owns
          a class or a data attribute, never text, and never removes what the server
          wrote unless it knows better. Files: Client/ViewerScript.swift, the stylesheet
          rules those attributes key, browser tests.
        criteria:
          - top-bar/unread and artboard-row/unread show the dot with the script on
          - two shots of artboard-page/default agree
      - title: Production defects the previews revealed
        desc: |
          HIGH. Activity rows truncate the path from the end (eJcZJU); the edit tag's
          verb and age spill outside the pill and vanish in light (vHmA5e); unattributed
          writers render as a blank name outside the avatar (JFazoq); the theme picker
          with no axes emits an empty flex item (MqMUlS); the Export and Code panels ship
          literal backticks (MwBN6D); every non-color variable row draws an empty swatch
          (ZIaKPF) and numbers are not right-aligned (NMfyci); the Export number field is
          wider than its selects (7ga8KN); the artboard row truncates the name rather
          than shedding the rect (lg6hBh); the live badge reads "connecting" not
          "connecting…" (jNpws2, decide which side is right); persistent white on accent
          must reach AA (wRxjaB, ruling in the issue). Files: Components/, the
          stylesheet, DESIGN.md.
      - title: Preview-host defects
        desc: |
          MEDIUM. State notes render DocC markup verbatim — render a Markdown subset,
          code spans at least (iblXjP); eleven state pages carry duplicate DOM ids so
          the script drives the chrome's copy (teQIgm — likely a second top bar inside a
          top-bar state; give framed states their ids or the chrome its own); the
          top-bar frame paints no ground (gtuww7); the file card's states sit on the
          canvas frame not body (KKPpCv); the selection bar is framed full-window so its
          truncation cannot be seen (4GVELx — a narrower frame or a second state at
          560px); the artboard render is a broken image in every preview that draws one
          (4FmPKE — the preview host serves no files; either a placeholder image the
          catalog carries, or the frame says why). Files: Pages/Preview*.swift,
          ViewerStylesheet+Previews.swift, PreviewFrame.
      - title: States whose picture cannot show what the note asks for
        desc: |
          LOW. The keyboard hint's panel is display:none until opened (2DwWCD); the
          presentation hint is display:none outside presentation (1sewyf); the map's
          third artboard is 30x12 so its mark and name are hidden (8fo7Gf); the artboard
          page shows an empty Details panel while a node is selected (nqnnV9, a fixture
          mismatch); the avatar small state says 16 px, the disc is 15 (kB57Fs, fix the
          note or DESIGN.md). For a state only the script can open, set the attribute
          the script would set (the design's rule) or drop the state (the ruling). Files:
          the affected +Previews.swift files and goldens only.
```

## Things that cost time today, for the next brief

- **"Canvas" is overloaded**: a `PreviewFrame` case and the `/preview/{component}` page.
  Say which.
- **Briefs that list issues by id only** make the agent re-read them all; paste the
  bodies, or say "read them".
- **The three-way prior trap**: the unread dot was neither a preview bug, a stylesheet
  bug nor a shot artifact; it was the client script. Ask "what else could undo this?"
- **The Go dashboard shares `ActorColor`'s formula.** Anything that changes hue,
  saturation or lightness changes an agent's color across tools; the ink is ours.
- **Merge order for two agents editing `PreviewCatalog.all`**: one inserts into groups,
  the other appends at the end under a comment. It merged clean twice.
- The `agents` repo has three uncommitted module edits (`modules/web.md`,
  `modules/evidence.md`) that make this practice standard; Ben reviews, commits and
  `make sync`s them.
