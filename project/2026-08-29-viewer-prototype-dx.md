# Viewer prototype in Pen, and a second agent-DX note (2026-08-29)

Author: Claude (Fable 5), unattended, for leaf A80Hf. The first DX note is
[2026-08-29-pen-mcp-tire-kick.md](2026-08-29-pen-mcp-tire-kick.md); this one records
what a second, design-shaped session found, and the prototype it produced.

## The prototype

Four states of `woodcase serve`, 1440×900, in
[2026-08-29-viewer-prototype/](2026-08-29-viewer-prototype/):

1. `1-dashboard.png` — the cross-file dashboard: one row per file the activity log has
   seen (thumbnail, name, path, artboard count, last change and by whom), and a recent
   activity feed beneath.
2. `2-artboard.png` — one artboard: outline panel left (type glyph, name, rect in the
   parent's space, id; a `⚠` rect for a clipped node; unnamed nodes as `#id` in muted
   text; the document revision in the header), the render center with a scale line,
   activity feed right, filtered to this file.
3. `3-selected-node.png` — a row selected: the node outlined in the render with a name
   tag, and a footer line with the name path, id, rect, clip note, revision and a
   "copy address" affordance — the exact string an agent takes.
4. `4-empty.png` — no files yet: the two commands that make something appear.

5. `5-concurrent-edits.png` — the same artboard while three identities work on it (Ben
   asked whether concurrent edits should be visible; yes): a presence strip in the top
   bar (one color per identity, last-seen age), an identity-colored bar on every
   outline row touched in the last 30 s, and a labeled outline (`claude-a · set 4s`)
   on the render for each recent edit, fading out; click pins one. All of it derives
   from the activity log's identity and node ids — no new server state.

Each state also exists as `*-dark.png`: the same screens copied with `theme: {mode: "dark"}`
pinned on the root frame, which is all a themed token set needs (Ben asked for dark
mid-session; it cost one `Copy` per screen).

Design: quiet developer-tool surface, one accent (blue-green `#2FBF6F`, Ben's pick over
the first draft's orange) reserved for liveness and selection; identities use the Jobs
dashboard's actor primitive — a round avatar whose color is `hsl(fnv1a32(name+"u") % 360,
fnv1a32(name+"zzzzzzzz") % 50 + 50, 48%)` with the name's initial at 20 px+ and a 6 px dot
below that (`jobs/internal/web/render/actor_color.go`, `DESIGN.md` § Actor identity), so an
agent is the same color in both tools. Because a hashed hue can land on the accent's green
(`claude-a` and `ben` both do), the Jobs rule applies here too: identity color lives only
in the avatar disc and the edit markers, never in text or chrome; Inter for prose, JetBrains Mono for anything an agent would
paste. Tokens are themed (`mode=light/dark`) on `v-*` variables. Built from three
components (`FileRow`, `OutlineRow`, `ActivityRow`) instanced with `descendants`
overrides. The `.pen` lives in Pen.app's memory on `local/tirekick.pen` until Ben
presses ⌘S (Pen never saves — see `project/gotchas.md`); the PNGs are the record.

**Sign-off is Ben's** (leaf A80Hf). Things to look at: whether the outline's rect
column should be optional (`--props`-style) to give names more room; whether the
activity feed belongs in the artboard view at all or only on the dashboard; the
render is a clipped 1:1 copy here, the real page scales it to fit.

## What this session found (rules for the CLI)

- **Globals do not persist across `execute` calls, again.** `compsId` from call 1 was
  undefined in call 2, despite the docs' `myNodeId = Insert(...)` promise. Recovered
  from the printed name → id map, as before. *Rule (reinforced): the id map is the
  contract; print it on every mutation.*
- **Schema errors teach, but only one layer at a time.** `stroke: {fill, thickness}`
  → "`/stroke/type` expected one of color, gradient…" → `{type, color, thickness}` →
  "`/stroke/thickness` unexpected" → `stroke` + `strokeWidth` → "`strokeWidth`
  expected number, $variable, object, got array" → `{top,right,bottom,left}`. Four
  round trips for one border. Each message was precise, none said what the right shape
  was. *Rule: a type-mismatch error names the expected shape with an example
  (`strokeWidth: 1 or {top,right,bottom,left}`), not just the type name.* This is
  exactly what `EditingError.propertyTypeMismatch(expected:)` must carry.
- **`edits` retry is the right ergonomics.** Every fix above was a one-line patch
  against the failed snippet; nothing was resent. *Rule: `apply --retry` should accept
  an edited report, not just re-run it.*
- **Same-call reads are pre-layout, confirmed a second time.** The problems check in
  the creating call reported every node "fully clipped"; the next call reported none.
  *Rule: settled state in the same invocation (already decision 7).*
- **A `Copy` of a screen plus name-based edits works when done through a visitor**
  (`Get(copy, n => n.name === "Customers" && Update(n.id, …))`), which is the
  workaround for `Copy` ignoring name-keyed `descendants`. *Rule: `cp` resolves
  name-path overrides against the copy itself, never silently (already in SLVVe).*
- **Names that are not unique inside a component are a footgun.** `FileRow` and
  `OutlineRow` both have a child `Name`; `descendants` by name would have been
  ambiguous, so ids were used throughout. *Rule: the ambiguity error (RIHeb) must
  list candidates with full paths so the agent can switch to ids in one step.*
- **The mock render inside a smaller frame clips rather than scales** — Pen has no
  scale-to-fit. Not a CLI concern; noted so nobody reads the clipped render in state 2
  as a layout bug.
