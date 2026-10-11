# Gotchas

Project-specific traps that cost real time and that no general rule predicts. Read at session start; append when you hit one.

- **Fix at the source when you can.** A gotcha is a bug report on our tooling, not a permanent fact — if it can be fixed in code, file it in `job` and fix it instead of recording it here.
- **Delete anything that becomes obvious, gets fixed, or stops recurring.** Keep this list short; a long list is one nobody reads.
- **Feedback about `AGENTS.md` itself** — a rule that was wrong, misread, or cost time — goes here too, prefixed `rule:`. It is harvested when the shared rules are reviewed.

Format: one dated H2 headline, then one paragraph. If an entry needs more than that, it's a finding — write it as a dated doc under `project/` and link it from the paragraph.

> **Pruned 2026-10-10 (leaf `0j0AE2`)** from 74 entries to the shared budget. Most traps now live as a doc comment at their code site (search the symbol the old entry named); the rest became `job` issues or were harvested into the shared rules. `git log -p project/gotchas.md` has every removed entry.

---

## 2026-08-29 — Pen.app never saves for you; the `pen` CLI does

The Pen MCP (`execute`) mutates the open document in memory only; Pen.app has no autosave, and `osascript … keystroke "s"` is refused (no Accessibility grant). `printf 'save()\nexit()\n' | pen interactive --app desktop` saves the app's active document to its own path (sandbox off; a one-time interactive `pen login` — ask Ben). `execute`'s `filePath` does not open a file either: `open -a Pen <file>` first, or `Get` silently reads whichever document is active. For anything scripted, run the engine headless instead (`pen interactive --in <file> --out <file>`, or `scripts/pen-oracle`); see [the pen CLI finding](2026-08-29-pen-cli.md).

## 2026-09-26 — A cross-repo agent needs its worktrees side by side

RapidPro depends on `../Woodcase` and `../PixelPeeper`, and Penumbra's Xcode project on `../../Woodcase` and `../../RapidPro`, all relative. A RapidPro worktree under `RapidPro/.claude/worktrees/` resolves `../Woodcase` through the symlink there to Woodcase **main**, so it cannot build against an agent's unmerged Woodcase change. Make one folder per agent holding sibling worktrees — `git -C <repo> worktree add <base>/<Repo> -b wt/<leaf> main` for each — plus `ln -s /Users/ben/git/PixelPeeper <base>/PixelPeeper`; without the symlink RapidPro's resolve fails with a missing-package error.

## 2026-09-26 — Under load, these suites fail and pass alone

With several agents building (load 90–200) the same suites fail in full runs and pass re-run alone: `ReactPaintWebViewTests`, `WebViewTestHarnessTests` ("Icon font renders glyphs via file URL"), `WebViewRegressionTests` (StatCard), `ReactTransformStateWebViewTests`, `ViewerBrowserTests` scroll, WebKit `__READY__` timeouts and frame-load interruptions, the `tree`/`set` `PerformanceBudgets` at 3–5×, and `SwiftUIRenderBatchRunAsyncTests` (issue `1nZPfP`). Re-run the suite alone (`--filter` on its Swift type name) before believing a failure there; one that fails on a quiet machine is real. A test failing only under load can still be a real race — `ActivityCommandTests`' follower was one (leaf `55P02C`) — so a failure that recurs alone gets a leaf, not a shrug.

## 2026-09-27 — Pen's own drawing code is readable, and settles "what does Pen do" faster than probing

`/Applications/Pen.app/Contents/Resources/app.asar` holds the editor's JavaScript (`out/editor/assets/index.js`); read it straight from the archive, read-only — never modify the app. The Material agent (`6vLFNQ`) found there that Pen draws icons via `getIconPath` at 14 pt with only `wght` set and fetches Material Symbols from fonts.gstatic.com, which probing exports had only hinted at. Treat it as evidence of intent and still confirm against an export (`scripts/pen-oracle`).

## 2026-10-11 — `nil` in an `AnyCodable` dictionary write can store `.null`

`AnyCodable` is `ExpressibleByNilLiteral`, so on a `[String: AnyCodable]`, `object[key] = cond ? nil : value` — where `value` is a variable typed `AnyCodable` — infers the ternary as `AnyCodable` and stores `.null` instead of removing the key (with a leading-dot literal such as `.dictionary(x)` in the other branch it removes, as meant). Peers then disagree on whether the key exists (leaf `dHZuBK`, the CRDT metadata entries). Remove with `removeValue(forKey:)`.

## 2026-10-11 — `scripts/mae-check` after a filtered test run checks only that run

**A `swift test --filter …` rerun rewrites `performance/mae-test.csv` with its few rows, so the commit hook's `mae-check` then lists every other id as MISSING and prints "MAE baseline updated".** The tracked baseline did not change on 2026-10-11 (`git status` clean), but the check covered 11–12 rows, not the suite. To gate a commit on MAE, run the full `swift test --quiet` last, after any filtered reruns of load flakes.
