# 2026-09-26 — Handoff, wave three: format 2.19, imports, paints everywhere, SwiftUI research

The third integrator session of the day, following [wave two](2026-09-26-wave-two-handoff.md). Start with `job orient`,
then this doc. **Ben's plan for the next session: dispatch the SwiftUI emitter wave** (after the rulings below), with
the parallel work listed under "Next wave".

## What landed (all pushed)

Woodcase, in order:

| Commit | Leaf | What |
|---|---|---|
| `c808149` | `smbv2z` | stale mesh claims corrected; March SwiftUI mesh claim corrected in place; mesh rounding recorded as deliberate |
| `e6e1a7b` | `j73Vz0`, `KjvK46` | `BatchApplier+Divergence` split; read-side reports moved to `Sources/Woodcase/Reports/` |
| `64f73d2` | `LCDPXr`, `kKIf7C` | React: gradient/image/mesh/stacked paints on text (`background-clip:text`) and strokes (masked overlay child; SVG paint servers). Also fixed for shapes: gradient opacity was ignored; radial used `farthest-corner` (Pen = `closest-side`) |
| `d7a8d37` | `DIkwEJ` | `PenMeshPoint.malformed` preserves a malformed point; drawn by Pen's measured rule; lint split dropped/distorted. **Breaking:** `position`/`handles` optional |
| `5c36701` | `koyac9`, `ukfIU2` | every read loads the document's own `imports` (Pen's rules: [finding](2026-09-26-pen-import-resolution.md)) into `EditableDocument.readContext`; `--library` and `LibraryResolver` retired; font resolver rides the read context, no library code defaults to `.shared` |
| `b921d59` | `dH7FN6` | [SwiftUI codegen feasibility report](2026-09-26-swiftui-codegen-feasibility.md); `scripts/swiftui-fixture-probe.swift` |
| `19c8b06` | — | `scripts/swiftui-api`: stamped per-SDK copies in `local/swiftui-docs/<sdk>/` (gitignored), `diff`, `list` |
| `5e8b32d` | `lebBvI`, `gArj6O` | writes format 2.19: `spread` gone; pre-2.19 inner shadows migrate to outer (as Pen); typed root `fonts`, wired ahead of Google Fonts; `connection` node (drawn as a plain segment — Pen draws none); authoring refuses unknown node types; `migrate`/`new` write under the lock and log `migrate`/`new` rows |

RapidPro: `32793ae` (mesh fills, stroke paint stacks, image decals), `cb7744f` (docs), and `0dce59a` (spread
gone, connection as a line, **line `flipX`/`flipY` fixed** — every flipped line drew the wrong diagonal). Penumbra: `f2b87d6`, the
2.19 follow-up (connection named, iconed, inspected). All three build and pass against Woodcase main.

## Rulings this session (Ben)

1. Imports load automatically from the file's own `imports`, no CLI flag; a missing library is a lint finding.
2. Malformed mesh points are preserved, drawn as Pen does, linted.
3. Authoring input refuses unknown node types loudly.
4. **Where Woodcase is more correct than Pen, keep it and accept the small MAE** (mesh rounding is the instance).
5. Viewer: the badge reads `connecting…`; the selection bar's shed gets a pinned-width (~520 px) preview state; the
   viewer agent's reversible choices stay. Integrator adds: fix preview renders served as SVG at a `.png` URL.
6. **MAE standardizes on PixelPeeper across repos, reported in 8-bit steps (0–255)** — leaf `dklpu4`.
7. SwiftUI docs: the script is committed, the corpus lives in `local/` and is never committed (Apple's text).

## Next wave

**SwiftUI first.** `bpfpVZ` (decision) — settle with Ben: OS floor (report recommends iOS 18 / macOS 15), native
`MeshGradient` vs baked raster, output package shape, layout policy (idiomatic stacks vs a support `Layout` porting
`PenLayoutEngine`). Then import the report's §6 plan under `n42KDh`. Its two refactor leaves (an intermediate
representation; CSS out of the shared analysis — `StateTrigger`, `PropMapper.jsValue`; CoreGraphics out of the path
parser/shape builder) come first and must keep every React golden byte-identical.

In parallel (file-disjoint from the SwiftUI refactor unless noted):

| Leaf | What | Notes |
|---|---|---|
| `dklpu4` | MAE on PixelPeeper, 0–255 | Woodcase + RapidPro (Penumbra has none); Woodcase's printed MAEs must not move |
| `Gusv9b`, `W91Yf0` | blur and inner-shadow fidelity | unblocked by 2.19; fit sigma on a plain edge |
| `VaJSI3` | nested unknown keys still dropped | unblocked; touches the same Codable types 2.19 did |
| `ILYyZi` | bare-id overrides on slot-injected nodes | Pen applies them, `PenRefExpander` doesn't; flips `BankingImportsLintTests` (banking.pen's last 8 errors) |
| `jNpws2`, `4GVELx`, `sGWNUd` | viewer | rulings above; plus the `.png`-that-is-SVG fix |
| `5jQhdY` | viewer code panel omits imported components | same resolved document as `generate` |
| `9xn91l` | Penumbra resolves imports by its own rules | switch to `PenLibraries` |
| `k759GF` | `pen-validate` passes documents Pen rejects | the 2.19 agent's workaround grepped the error list |
| `U7wvkV`, `gh42Xb` | measurements | quiet machine only |

## Decisions made under standing permission

1. **The SwiftUI docs script** was finished from the research agent's last uncommitted draft (it had been restarted by
   a late message, see Traps) after every verb was exercised by hand; the cache moved from `~/.woodcase` to `local/`.
2. **Nested imports are not followed** (brief said "handle nested and cyclic"): Pen resolves one level, so following
   them would draw what Pen shows as invalid. A library's own import is an `import-not-followed` warning.
3. **The font resolver rides the document's read context** rather than a parameter on `DocumentLinter`/`TreeView`
   (`ukfIU2`'s suggested fix): a defaulted parameter is the same leak; two source scans hold the rule.
4. **Connection draws a plain stroked segment**, no stroke → nothing. Pen's validator knows the node but neither
   engine draws it, so there is no reference; Ben's ruling was "draw it".
5. **Inner shadows in pre-2.19 fixtures now render as outer** — a visible change, matching Pen's migration.
6. `scripts/rename-font-family` uses fontTools (a Python dev-tool dependency, used to make the two OFL fixture fonts);
   not a package dependency.
7. RapidPro's mesh MAE looked better than Woodcase's; it isn't — different scales (see `dklpu4`). The leaf note on
   `3DsfB1` is corrected.

## Traps hit this session

- **A message to a finished agent restarts it.** The SwiftUI researcher had reported; a queued addendum resumed it
  after its worktree was removed, and it began rewriting files in a recreated folder. Send nothing to a finished agent
  unless you want it back; stop it with `TaskStop` if you did.
- **Cross-repo agents need a sibling layout.** RapidPro's `../Woodcase` and `../PixelPeeper`, and Penumbra's
  `../../Woodcase` and `../../RapidPro`, are relative; put an agent's worktrees side by side in one folder
  (`<base>/{Woodcase,RapidPro,Penumbra}` plus a `PixelPeeper` symlink) and they build against each other. See gotchas.
- **An unquoted heredoc eats backquoted words** in a Python or Markdown body (`<<EOF` ran `` `fetch` `` as a command).
  Quote the delimiter (`<<'EOF'`).
- **`mae-check` records every new MAE id as a baseline on the next commit** (33 this session: `mesh-malformed-*`,
  `react-paint-*`); that is expected, not drift.
- The `/tmp/design.pen is locked` line appears in passing suite logs — a test's expected output, not a failure.
