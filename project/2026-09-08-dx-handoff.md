# Handoff after the DX round, 2026-09-08

*Handoff note. Status: point-in-time record; a fresh session starts from `job orient` plus this file. Supersedes [the trials handoff](2026-09-08-trials-handoff.md).*

## Where main is

`main` is at `dab3970`, pushed, clean; suite 4170 tests in 437 suites, 51.7 s on a quiet machine (`swift test`, verbose log at `local/suite-logs/2026-09-08-dx-combined.log`). No worktrees, no agents.

Root `RgmG2h`, "CLI DX from the trials", is closed: all seven leaves plus the font-cache one. Five agents ran in parallel worktrees (two Sonnet, three Opus); every branch was squash-merged with the whole diff read, and the suite ran once over the combined result.

| Commit | What |
|---|---|
| `9a1897f` | Prunes two gotchas the font-cache move settled |
| `a2f83d7` | `collapsed-text` lint check — keys on the declared sizing pair, not the settled rect, so the remedy is exact and a text inside a collapsed `fill_container` stays one finding |
| `75a25da` | Four CLI sentences from round two: `tree --props` on a bare instance says `--expand`; `apply`'s malformed-line refusal states the grammar and names a pretty-printed fragment; `find`'s bare expression says `r => …`, decided in the host; `get --help` names `node`/`revision` |
| `8123aaa` | Viewer suite hermetic: `RenderCache(fonts:images:)` defaults to the shared pair; every viewer test renders through offline resolvers; `HermeticNetworkTests` scans `Tests/` for the fetcher, the shared resolvers and any bare `RenderCache()`. Zero viewer tests depended on Inter |
| `ff8b232` | One `$` rule: `PenDollarEscape` (read anywhere, written only leading); the resolver forgives an undefined `$name` in `content` on both routes; lint untouched |
| `add24da` | `--` separator taught after a failed parse (parser-probed, never applied); `vars set` announces a displaced name with old value and reference count (`previous` in JSON); batch `var` registers the axes it pins through one `ThemeAxisRegistrar` shared with `vars set --theme`; `vars set` takes several pairs in one transaction |
| `7b2d988` | `cp`'s placement note names the copy, fixed at the source in `planCopyInsert` (an agent's CLI-layer patch was dropped for it) |
| `dab3970` | THE LOOP in `help design` hands a repeated write-then-measure to `js`; VALUES states the new `$` rule; budget 149 → 154 |

## What the agents corrected in the briefs

Worth carrying forward, because each is a premise a future brief could repeat:

- **The batch `var` op already decoded a themed value.** The trial's "refuses anything but `{type,value}`" was wrong; the real bug was that it never registered the axis it pinned, so a document could be conditioned on a `mode` its `themes` table did not have — silent, and worse than a refusal.
- **A "themed-away" variable is not a reachable state.** The resolver falls back to the first variant when no theme matches. The defined-but-unresolvable case is a circular chain.
- **`get` prints an override map raw by documented design**, so it is not a route with a `$` rule to unify; only render and lint are.
- **No viewer test depended on Inter**, so the "repoint fixtures or regenerate goldens" branch was empty work.
- **"Shipped in the repo" does not mean "free for a CLI test"**: `woodcase-app.pen` names IBM Plex Sans, which the repo ships, and the CLI child process still downloads it.

## Open threads

- **Issues filed today**: `e2iLwV` (CLI tests still fetch fonts through `shot`/`render`: 7 tests, 6 downloads per run; recommendation is to repoint the six `ShotComponentTests` cases at system-face fixtures), `ukfIU2` (`SettledTree` defaults to the shared resolver at four library call sites, so a library test's metrics depend on the user's cache), `j73Vz0` (split `BatchApplier+Divergence.swift`, 411 lines).
- **The suite wedge (`DpQmXu`)** did not recur today across seven full runs, five of them under four-way agent load. The timing note on it says the fourth wedge was not inside a font fetch; the hermetic change was made without a claim on it.
- **The `js` nudge (`5ZeH3J`)** is a stance, and only a third unprimed trial round says whether it worked. Round three would use the same method as `project/2026-09-08-scripting-host-trial-2.md`.
- **Penumbra**: unchanged from the trials handoff — `try GoogleFontCache()` warns, and its cache moves to `~/.woodcase` unless it injects a root. `RenderCache`'s new parameters have defaults, so it needs nothing for `8123aaa`. `VarsSet.Report.variable` became `variables` (a `--json` shape change; no consumer outside the verb).
- **Not in the tracker, deliberately**: the product-level items from the trials (a layout-aware `--dry-run` or measure verb, `override --each`, a grid fan-out, drawn `note` nodes, a collapsed `activity` view).

## Restart

`job orient` in `/Users/ben/git/Woodcase` — with the DX root closed it will pick from the issue tree only with `--issues`; the next plan is Ben's call. The saved memory in the assistant's project directory matches this file.
