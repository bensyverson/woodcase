# Experience report: designing with the Figma MCP and with Woodcase

An agent's account (Claude, in Claude Code) of one working session, 2026-10-13. The job was a set of static 1920 × 1080 concept screens for user research, built from a written design system (tokens, a serif/sans pairing, soft gradients, hard offset shadows). Five screens were built in Figma through the Figma MCP server and one in Woodcase, all in the same session and visual style, with a designer reviewing each round and asking for changes. The screens included stacked area charts, a dot grid, timeline lanes, tilted cards joined by curved arrows, and photo pins.

Counts below are approximate and come from reading back the session, not from a log.

## 1. The Figma MCP

### What worked well

- **No desktop app.** `use_figma` ran against the file by its key, through the web. The designer had the file open in a browser and edited copy in it while I worked; I picked up their edits from screenshots and built around them.
- **The full Plugin API.** Variables, linear and radial gradients, vectors from SVG path data, image fills, effects, auto layout: everything I needed was reachable, and the colors could be bound to a variable collection made from the design tokens.
- **Image generation into the file.** `generate_image` with a file key placed a generated photo in the document. I copied its `imageHash` into my placeholder ellipses and deleted the source frame. That was five photos for one screen, and a sixth when the designer asked for a better subject on one pin.
- **The skill doc.** The `figma-use` skill's rules (colors are 0–1, load fonts before touching text, one page per call, return every node ID) prevented a class of errors I would otherwise have hit. Reading it first was worth it.
- **Targeted edits.** Once a screen existed, small fixes were cheap: find nodes by name inside a frame, change a fill, move a label. Most review rounds were one short script.

### Papercuts

- **Looking at the result took three calls.** `get_screenshot` returns a short-lived URL. I had to `curl` it to disk and then open the file, so every look at a screen cost three tool calls. Late in the session I switched to `await node.screenshot()` inside `use_figma`, which returns the image inline in one call; I should have used it from the start.
- **A variable-bound fill drops its opacity.** `setBoundVariableForPaint` returns a paint; spreading `{ ...paint, opacity: 0.3 }` into `fills` renders at full opacity. Lane strips meant to be 6% ink came out solid charcoal. The fix is to assign the bound fill, then clone `node.fills`, set `opacity` and reassign. That cost one render-and-fix round.
- **A bound fill seeded black once rendered black.** I seeded the paint with `{r:0,g:0,b:0}` and bound it to a white variable. Everywhere else it resolved, but one card rendered black in a screenshot. Seeding with the variable's real value fixed it, and I did that from then on.
- **A vector's `x`/`y` is its bounding box.** A path that rises above its start point (negative y in path data) lands too low by that amount. Two mini-charts came out with their line below their end dot. The fix is `y = startY + minY`.
- **A frame's shadow draws overflowing children twice.** With `clipsContent = false` and a drop shadow on the frame, any child sticking out past the frame's edge gets a ghost copy offset by the shadow. I saw a doubled label twice before I recognized it.
- **No state between calls.** Every `use_figma` call re-pasted about 2 KB of helper functions (text, rectangle, vector and paint builders), and node IDs travel between calls as string literals copied from the previous result. That's workable, but it's boilerplate the agent pays for in every call.
- **`get_metadata` with no node ID listed one page when the file had three.** I had to list pages through `use_figma` instead.
- **`toLocaleString('en-US')` does not group thousands in the plugin sandbox.** It printed "$1200" on a chart label.
- **Gradient transforms are matrices.** I guessed `[[0,1,0],[-1,0,1]]` for top-to-bottom and identity for a centered radial. Both happened to be right, but nothing in the tool told me so before rendering.
- **Generated images land on the first page.** They arrive as new frames wherever Figma puts them, which was not the page I was building on.

### Gaps

- **No lint.** Nothing told me about text overflowing a card, overlapping tags, or a label running off a frame. Every one of those I found by looking at a screenshot.
- **No diff of the document.** When the designer edited text in the file, I found out only because the next screenshot showed different words. There was no way to ask "what changed since my last write".
- **Translucent fills do not survive copying into FigJam.** The designer reported strips "pasting into FigJam weird". We moved the whole design system to opaque gradients (a hue fading to white or to the canvas color) instead of hue-at-opacity. That's a design-system constraint the tool imposed, not one we chose.
- **The work lives only in the file.** A screen built across fifteen scripts exists only as the result. To rebuild it with different spacing I had to delete it and send a new script, assembled by hand from the earlier ones.

## 2. Woodcase

### What worked well

- **The help was enough.** `woodcase --help`, `help design`, `help schema <type>` and `help js` got me from nothing to a working generator. The schema output (every key, its shape, its default and its range) answered every property question. I also looked at an existing generator script in the repo, and that mostly taught me house conventions (header comment with the run command, palette constants) rather than anything the help lacked.
- **The design is a file in the repo.** The screen is `screens/scripts/<name>.js` plus the `.pen` it writes. It reruns cleanly (the script removes the root it made last time and adds a fresh one), it diffs in git, and the next person can read the layout as code.
- **`js` is one transaction.** One run, one write, one activity-log entry, and a printed name → id summary of what it made. A thrown error leaves the file untouched, so I never had to clean up a half-built screen.
- **`lint` runs on every write.** It flagged the ambient glow as partly outside its parent. In this case the overflow was intentional, but it's the class of finding I had no way to get from Figma.
- **`shot` is local and fast.** It writes a PNG I can open directly: no URL, no download.

### Papercuts

- **Fonts were the main cost.**
  - The design system's serif is not in Google Fonts' catalog, so `shot` fell back to SF Pro, with a clear warning.
  - My stand-in, Nanum Myeongjo, downloaded into the cache on the first `shot`, but the next render still could not resolve "Nanum Myeongjo". It resolved only as `NanumMyeongjo`, the file's internal family name. The warning text names the catalog spelling, so it points the wrong way.
  - The `js` run then still warned about "Nanum Myeongjo" being unmeasured, probably from the root it was about to remove.

  This took about five commands to untangle, more than any layout issue.
- **Gradient direction is not documented.** `rotation` is listed with a default of 0, but not which way 0 points. A render showed that 180 runs top to bottom.
- **No dashed strokes.** The schema has no dash pattern. The design system uses dashed lines for ghost routes and connectors, which I drew freely in Figma. Here I dropped the connectors, which also turned out to be the better design.
- **Frames lay out horizontally by default.** "Flex first" is documented, so I put `layout: 'none'` on every absolutely positioned frame. That's correct, but it's a key on nearly every frame in a poster-style composition.
- **`$` in text content is a variable reference.** Dollar amounts need `\$`, which inside a JS string literal becomes `'\\$'`. The help says so; it's still an easy one to forget.
- **An intentional overflow is a permanent warning.** I didn't find a way to mark the glow's overflow as intended, so every run reports it.

### Gaps

- **No image generation.** A screen needing photos would mean generating them elsewhere and embedding them in a bundle.
- **The designer wasn't in the file.** In Figma the designer watched and edited the same file; here they saw only the renders I showed them. That was this session's setup, not a limit of the tool: Woodcase has `serve` and `preview`, and Penumbra edits the same `.pen` live. I used none of them.
- **Fonts are limited to Google's catalog and the cache.** A design system built around a font that isn't on Google Fonts can't be matched without supplying the TTF.

## 3. The design cycle, compared

| | Figma MCP | Woodcase |
|---|---|---|
| **One look at the result** | 3 calls (`get_screenshot`, `curl`, open), or 1 with `node.screenshot()` | 2 calls (`js` + `shot` in one shell command, then open) |
| **A small fix** | a short targeted script by node name or ID | edit one line of the generator, rerun the whole screen |
| **A structural change** (move a section, resize the grid) | rebuild the section: delete the nodes, resend builders with new numbers | change constants, rerun |
| **What the agent re-sends each time** | about 2 KB of helpers per call | nothing; the helpers live in the script file |
| **Finding mistakes** | only by eye, from screenshots | `lint` on every write, then by eye |
| **Working alongside a human** | live: they edited the same file and I built around their changes, with nothing telling me what they had changed | built for it: per-node revision tokens, a lock per write, an attributed activity log, detection of edits made outside Woodcase, and a three-way merge behind Penumbra. My script didn't use any of it, because it rebuilt its root on every run |
| **Reproducibility** | the file is the only record | the script is the record; the `.pen` is output |
| **Fonts** | everything the designer has | Google's catalog and the local cache |

**Making changes.** Figma is better at the small edit inside a living document: "make the photos bigger", "this timeline should start in 2026", "swap this photo". A short script found the nodes and changed them, and nothing else moved. Woodcase is better at the change that touches many coordinates at once. Moving every card down 20 points or resizing a grid is one constant and a rerun, where in Figma I deleted and rebuilt a panel three times on one screen.

**Viewing.** Woodcase's loop was shorter and more predictable: write, render, look, with the render on disk. In Figma, the first half of the session spent a third of its tool calls just fetching images. The inline `node.screenshot()` closes most of that gap. Woodcase's `lint` catches overflow and clipping before I look, and that's the class of bug I found most often in Figma by eye: a label off a card edge, two tags overlapping, a curve running off the chart.

**Iterating with a person.** In Figma the designer edited headlines and labels while I restyled the same screen, and both sets of changes survived. That worked only because my scripts made targeted edits. Figma gave me no record of what the designer had changed; I noticed from screenshots.

Woodcase has more of the machinery for this, not less. Each node carries a revision token, so a write against a node someone else changed exits 3 instead of overwriting it. Every write is attributed in the activity log, so "what changed since my last write" is `woodcase activity`. An edit made outside Woodcase is detected and recorded as such. Undo refuses to reverse past another writer's edit. Penumbra uses a three-way merge for live editing.

> **Corrected 2026-10-13:** this section first said Figma "was clearly ahead" for working with a person, and that hand edits "would be lost" on a rerun. That was wrong. The data loss came from my generator, which removes and re-adds its root on every run. The editor guide warns against exactly that for live content ("edit in place instead"). The right workflow was to generate once and then edit in place with `set`, guarded by revision tokens. I also never put the designer in the `.pen` file, so this session did not test Woodcase's collaboration at all.

**Net.** Both tools can share a file with a person. What decides it is my workflow: a generator that rebuilds its root suits a family of screens nobody edits by hand, and once someone does, the work should move to guarded edits in place. Woodcase supports that directly, and it can show me what changed. Figma's MCP route did not show me what changed. Woodcase's remaining gap for this work is fonts. In both tools the slowest steps were not layout. They were fetching or rendering the result, and fonts.
