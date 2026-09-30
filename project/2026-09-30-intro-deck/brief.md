# Brief: a deck that says what Woodcase is

## The deck

A short slide deck, 16:9, read alone as a PDF by someone who was sent it or found it in the repo. Nobody presents it. Seven to nine slides is the expected range; fewer is fine if the story survives.

It is designed in Woodcase and rendered by Woodcase: one `.pen` file, one 1920×1080 top-level frame per slide, exported with `woodcase render --format pdf`, which makes each top-level frame one vector page. The file, the scripts that build it and the PDF live together in the Woodcase repo.

Approach it as the strongest design studios would, and expect to be judged by that standard. Restraint and boldness are the two things to balance. Every element has to earn its place; less is more.

## The reader

A developer who already works with coding agents every day (Claude Code and its peers) and may already use an agentic design tool such as Pen or Paper. Technical, busy, skeptical of hype, fluent in terminals. They will give the deck a minute or two.

## The thesis

> Woodcase is the design layer for agents: a tight loop of command, view, iterate. It is headless, with a robust CLI, and embeddable anywhere from a CGContext to a SwiftUI project.

The call to action is `brew install bensyverson/tap/woodcase`.

## The story, as beats

The beats are content, not slides. A concept may merge, split or reorder them, as long as the story survives.

1. **The gap.** Agents can write the code, but they cannot see or shape a design. Visual work is the part of agentic development whose feedback loop is still broken.
2. **The loop.** Command, view, iterate. `tree` reads the settled layout as text (every node, its rect, its id); `set` changes one node, guarded by a revision token; `shot` renders a node to pixels for the last mile. Most questions a screenshot answers, `tree` answers first, as text an agent can read.
3. **JavaScript.** When what to write depends on what a read just said, `woodcase js` runs a program over the document in one transaction: nothing is written unless the script ends cleanly, and reads see the settled layout, so a script can measure after it writes and throw rather than commit. Agents reach for scripts constantly; this is the verb built for that habit.
4. **Built with its users.** The CLI was refined through user-centered design with agents as the users: agents ran real design tasks, and their friction became the grammar. Errors that teach, exit codes that mean one thing, a primer in `woodcase help design`, every write attributed (`--as`), every edit in an activity log that `woodcase undo` replays.
5. **One engine, many outlets.** The core is a Swift library, and the CLI is a thin consumer of it. It draws into any CGContext, renders PNG (raster) and PDF (vector), and generates code: React + Tailwind, or a SwiftPM package of SwiftUI views, as a live-updated library or the starting point of a project.
6. **Where it sits.** Woodcase lives in, and expands, the `.pen` ecosystem. Pen is the first-party tool, built for humans and agents collaborating, and useful as a purely human app. Woodcase is agent-first, with no human GUI at all: headless, or inside a larger app. The original use case was agentic title design inside a video editor.
7. **The reveal.** This deck is a `.pen` file an agent built through the Woodcase CLI, and it shows its own activity log. The deck proves the claim instead of stating it. (This beat is decided.)
8. **Install.** `brew install bensyverson/tap/woodcase`.

## Facts a slide may use

All true as of 0.1.2. Anything not here needs checking before it goes on a slide.

- Reads `.pen` files from 2.8 on; writes 2.19 (`woodcase --version` prints it). The format is JSON.
- Pipeline: parse → resolve variables (themes such as light/dark) → expand components (`ref` instances with overrides) → layout (flex: gap, padding, justify, align, fill/fit sizing, absolute) → render.
- Verbs: read (`tree`, `find`, `get`, `lint`, `vars`, `activity`, `schema`, `help`…), write (`new`, `add`, `set`, `replace`, `cp`, `mv`, `rm`, `override`, `apply` for a JSONL batch, `js`, `undo`…), render (`shot`, `render`, `generate react`, `generate swiftui`), viewer (`serve`, a local read-only live web view).
- Every read has `--json` carrying a revision; every write is attributed and logged; the exit code says what kind of thing went wrong (one table shared across verbs).
- Real `tree` output, from the repo's `banking.pen` fixture:

```text
$ woodcase tree banking.pen banking-home/header --props kind.content
rev 7cf8d84e7b6b9b23  5 rows
type   name          rect          clip  id     kind.content
frame  header        0,33 402×72         6m90O  -
frame    hdrG        24,20 95×52         CcYdb  -
text       hdrL      0,0 95×18           DhDsc  Good morning
text       hdrN      0,20 51×32          4YeMj  Alex
ref      bellBtn +2  336,25 42×42        E97qI  -
```

- The renderer draws rectangles, ellipses, polygons, paths, lines, text (Core Text), icon fonts (Lucide, Feather, Phosphor, Material Symbols), images; solid, linear, radial, angular and mesh gradient fills; strokes; outer and inner shadows; layer and background blur; opacity and blend modes; rotation and flips. Any Google Font resolves automatically.
- Swift 6, cross-platform library; macOS 15+ / iOS 18+ for rendering. MIT licensed.

## What the deck is not

It is not a feature list, a spec sheet or a changelog. It does not need every verb, every format or every number above; it needs the reader to leave knowing what Woodcase is, why it exists, and one command to try it.
