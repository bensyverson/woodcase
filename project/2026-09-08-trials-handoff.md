# Handoff after the trials, 2026-09-08

*Handoff note. Status: point-in-time record; a fresh session starts from `job orient` plus this file. Supersedes [the second scripting host handoff](2026-09-07-scripting-host-handoff-2.md).*

## Where main is

`main` is at `e446603`, pushed, clean; suite 4107 tests in 430 suites, ~94 s quiet (`swift test`, verbose into `local/suite-logs/`). No worktrees, no agents.

The scripting host plan (root `6vdq3j`) is closed: all fifteen leaves. Landed today, each squash-merged with the whole diff read:

| Commit | What |
|---|---|
| `30f264e` | WoodcaseScripting.md, held to `help js` by `ScriptingArticleTests` |
| `265d1eb` | One row view for `find` and `doc.tree`; root overlaps as `ScriptRun.Event.overlap` |
| `ed7df56` | Test PNGs to a per-process temporary directory |
| `c7e617e` | [Round one of the trial](2026-09-08-scripting-host-trial.md): primed Sonnet agent chose `js`, log accounts for every byte |
| `fe9265a` | Ben's ruling: `apply` and `cp --each` stay — the wire form for shell scripts and workflows that do not want JavaScript |
| `8019d81` | [Round two](2026-09-08-scripting-host-trial-2.md): three unprimed Sonnet agents chose verbs and `apply`, never `js`; the Opus greenfield run used every route by shape; DX synthesised; seven tasks imported |
| `e446603` | Font and image caches under `$WOODCASE_HOME` (`WoodcaseHome`); the fallback notice split into never-downloaded and cannot-read; `help design` names the cache |

The Nanoshoot mobile design — twelve screens, fourteen components, forty-one themed variables, lint clean in both themes — is at `/Users/ben/git/nanoshoot/design/` with `shots/`, uncommitted there.

## What is next

`job orient` picks from root `RgmG2h`, "CLI DX from the trials": seven leaves imported from round two's task block, in harm order — the collapsed-text lint check first (`kDul2M`), then the `$` rule, the `--` separator, `vars set` on an existing name, five message fixes, themed variables in a batch, and the `help design` sentence that hands a measure-and-fix loop to `js` (the one with a stance; a third unprimed round tells whether it worked). Each leaf's description carries the why and points at the finding.

## Open threads

- **The suite wedge (`DpQmXu`) happened a fourth time, on a quiet machine.** That breaks the contention-shaped reading. The verbose log named the tests still open — three browser tests among them — and the sample again shows only the activity follow loop. New hypothesis, filed as `CNDISf`: the viewer tests fetch Google fonts from GitHub in process through `GoogleFontResolver.shared`, and URLSession's resource timeout is seven days, so a stalled fetch is an await with no deadline of ours. Check whether the wedged runs were mid-fetch before believing it.
- **Penumbra**: `GoogleFontCache()` and `RemoteImageCache()` no longer throw, so a `try` there now warns. Its cache moves to `~/.woodcase` with the library default unless it injects a root.
- **Issues from the trials** not in the task block, deliberately: a layout-aware `--dry-run` or a measure verb, `override --each`, a grid fan-out, drawn `note` nodes on component sheets, a collapsed `activity` view for a script batch. They need a product conversation; the findings hold the arguments.
- **Ben's sandbox settings** now allow both cache paths; with the cache moved, the `com.bensyverson.woodcase` entry is dead and can go.

## Restart

`job orient` in `/Users/ben/git/Woodcase`. The saved memory in the assistant's project directory matches this file.
