# Experience report: drawing the Jobs mobile dashboard with `woodcase`

*2026-08-30. Written by the agent (Claude, Claude Code) that spent one session building a five-screen phone design for the Jobs dashboard in `Jobs/project/designs/2026-08-30-mobile-dashboard.pen`, from an empty file to lint-clean artboards in both themes, with the human following along on `woodcase serve`. First contact with the tool; no prior knowledge of the `.pen` format. Every command below was actually run. Write counts come from the two activity logs the session left behind (one in the sandbox scratchpad, one in `~/.woodcase` — see item 3); reads were not logged and are estimated from the transcript.*

## What the session looked like

43 logged write operations — 27 `set`, 9 `rm`, 7 `add` (most `add`s and many `set`s arrived inside 7 `apply` batches) — plus ~48 `vars set` calls that were applied but never logged, and roughly 40 reads: ~12 `get`/`tree`/help calls before the first write, ~10 `lint`, ~12 `shot`. Screens were generated as JSON subtrees by a throwaway Python script and fed to `add`/`apply`; nearly all follow-up edits were by path (`Log/Content/Filters/Events/chips`) rather than id.

## What worked

- **`tree` as the front door.** One row per node with the settled rectangle answered most "why does this look wrong" questions without a render. When lint said a chip strip overflowed by 11px, `tree` showed the axis label was 54 wide and the fix was one `set`. Reading structure is cheaper than reading pixels, exactly as the help says.
- **Lint is precise and actionable.** Every finding named the node, the id, the rect, and the parent rect, and the `fill-in-fit-parent` message even proposed the fix. It caught a real class of bug — an underline set to `fill_container` inside a fit-content tab — that would have rendered as nothing and been mistaken for a missing feature.
- **`apply` with batch tags and per-line reports.** Three full screens went in as one JSONL file; the report told me exactly which line made which node. Failed lines not aborting the batch meant a typo cost one retry, not a re-run.
- **Names as addresses.** Being *forced* to name every node paid off within minutes: fixes were `set FILE 'Plan/Content/Tree/r10/t/title' kind.content=…` with no lookup. The "matches 2 nodes — say `#PyVLA`" error when `Now` collided with a tab called `Now` was the right kind of failure: loud, listing the candidates.
- **The read-write-verify loop is real.** `apply → lint → shot` became a reflex; the artboards were clean in both themes before the human saw them.
- **Theme variables via `vars set --theme`.** Registering `mode=dark` / `mode=light` implicitly, one call per value, made a 24-token palette a 48-line shell loop. `shot --theme mode=light` then rendered the light variant with no edits.
- **`serve` doing nothing but watching** meant the human's browser updated on every `apply` while the file stayed a plain `.pen` the whole time. That division — no daemon, no session — is what made the "follow along" workflow possible at all.

## What didn't

1. **No way to learn the format from the tool.** The vocabulary — `fill` is a string, `stroke` + `strokeWidth` + `strokeAlignment` are siblings, `effect` is an object, `icon` needs `library`, `textGrowth` governs wrapping, `layoutPosition: "absolute"` exists, `cornerRadius` takes an array — was reverse-engineered by running `get` on a dozen nodes of an unrelated file (`woodcase-stitch/woodcase-app.pen`) and grepping for the property I wanted. Four of the first twelve calls were that. The pencil MCP's `read_skill("pen-schema")` returned the overview page instead of the schema, so it was no help. **A `woodcase schema [type]` verb** — node types, their properties, enums, which accept `$vars` — would have removed that entire phase. The `set` error that lists "accepts `common.name`, `kind.fills`, …" proves the information is already in the binary.
2. **No `new`.** `add … document` on a missing file is refused with a "check the path" hint; the workaround was `printf '{"version":"2.17","children":[]}' > file.pen`, which `tree` accepted. Worth a verb, or letting a root-level `add` create the file.
3. **The sandbox.** Claude Code runs commands in a sandbox that permits writes only under the project, `$TMPDIR` and a few dotfiles. Three things broke: the activity log at `~/.woodcase` could not be created (every write printed a 6-line NSCocoaError, though the edit landed); `serve` could not bind a port ("Operation not permitted", reported as "something else may be using it"); and `shot` died with exit 133 reaching `~/Library/Caches/woodcase`. The activity-log failure had a second-order cost: I redirected `WOODCASE_HOME` to the scratchpad, which silently hid the file from the *human's* already-running `serve` on 7333 — that server lists "every file the activity log has seen," and the log it watched never saw mine. The human noticed before I did. Suggestions: honour a project-local log (`.woodcase/` next to the file, or `$WOODCASE_HOME` defaulting to `$XDG_STATE_HOME`), print the log-write failure once per process rather than per edit, distinguish `EPERM` from `EADDRINUSE` in the `serve` message, and make `shot` survive a missing cache directory. All three are one-line environment facts an agent would handle if the errors named them.
4. **Silent icon misses.** `check-circle-2` (an older lucide name) rendered nothing — no lint finding, no stderr. The done-glyphs in the Plan tree and the passed criterion in the sheet were simply absent until I read the PNG. Lint declines to check fonts because that needs the network; an unknown icon name in a bundled library is fully offline and should be a finding.
5. **Clipping is the only truncation.** There is no single-line ellipsis, so a phone row's title is a `clip: true` frame around auto-growth text, and lint then reports every such title as "clipped" — a warning I had to `grep -v` on every run. Either a `textOverflow: ellipsis`-style property or a way to mark a clip as intentional (`clip: "truncate"`?) would keep lint's signal clean.
6. **Floating-point overflow on distributed children.** Sixty `fill_container` bars at gap 2 in a 350-wide frame: the last bar landed at 346.13 + 3.87 = 350.00 and lint called it clipped; at gap 1 the 59th bar did the same. I ended up deleting a bar. A tolerance of a fraction of a point in the clipped check, or rounding the distribution, would avoid a false positive that is only ever produced by correct layouts.
7. **Small paper cuts.** `set … kind.content=3` was refused because the value was typed as a number — correct per the documented typing rule, but the common case (a text node) wants a string and the fix (`'kind.content="3"'`) needs shell quoting. `activity` takes `--file`, not a positional, unlike every other verb. A node named `Now` that is both a root and a tab label is an easy trap when generating screens from a shared tab-bar function.

## Follow-up, same day

Discussed with Ben after the first draft.

**The sandbox, resolved on the harness side.** Ben asked whether `job` gets an exception — it does not need one: it writes `.jobs.db` inside the repo, which the sandbox already allows, and `job serve` cannot bind a port sandboxed either (`bind: operation not permitted`, verified) — an agent runs it with the sandbox off, the same as `woodcase serve`. So the port is not fixable by allow-list for either tool; the state directories are. Added to `~/.claude/settings.json → sandbox.filesystem`: `~/.woodcase` and `~/Library/Caches/woodcase` (read + write) and `~/.swiftpm/bin` (read, so `which woodcase` stops lying). With those, every read and write verb and `shot` run sandboxed; only `serve` still needs the sandbox off, and in practice the human runs it. The `WOODCASE_HOME` redirect I reached for is exactly what the Jobs harness notes forbid ("never invent cache or `HOME` redirects to make a toolchain work in-sandbox") — the rule was right and I should have re-read it when the first activity-log error appeared.

**Icons: a query, then a lint finding.** Asked whether I would want an icon list or query: a query. Lucide has ~1,500 names that drift between versions (`check-circle-2` → `circle-check`), and an agent guesses from memory, so the failure is *wrong name*, never *wrong library*. The shape I would use:

    woodcase icons lucide check        # fuzzy: check, circle-check, square-check, check-check…
    woodcase icons lucide --all        # the full list, for grep

The query prevents the mistake; a lint finding for an unresolvable name catches what slips through, and is what tells you *before* reading a PNG. If only one ships, the query.

**Why I generated nodes with a script, and how verbs-only would feel.** Ben noticed that nearly every node came from a throwaway Python generator fed to `add`/`apply`. Three causes: the format has no cascade, so a phone screen is ~150 nodes each carrying every property, and a `caps()` function was the only place "label-caps is 11/600/0.66" could live once; `apply` takes a subtree per line, and a 150-node subtree is generated, not typed; and rebuilding a screen with its id pinned was cheaper than patching eight nodes. The cost: the script became a second source of truth (a `set` I forgot to mirror was lost on the next rebuild), and it hid the tool's own shape from me — I never used `cp` or `override`, so the file has no components and a tab-bar change is five edits. Restricted to verbs, the first screen would take roughly 3× longer (~30–40 calls of hand-written nested JSON in heredocs), but the file would come out right: one row, card and tab marked `reusable` and `cp`'d everywhere with `props`, every edit in the activity log and undoable, lint between steps rather than 14 findings after a dump, and the human watching it build in `serve`. What would make verbs-only the natural path: components cheaper than fresh subtrees (`cp` as the default move), named text styles (variables exist for colors but not type — seven properties per label is why a script wins), and a repeat (`cp … --times 59` for histogram bars). The script was the right call for a first session on an unknown format with a human waiting, and the wrong shape for the file that came out of it.

## Suggestions, ranked by how much session time each would have saved

1. `woodcase schema` (or `help schema`) — the property vocabulary, from the binary.
2. `woodcase icons <library> <query>`, and icon-name validation in `lint`.
3. Sandbox-aware errors and a project-local activity log (the state dirs are now allow-listed on this machine; see the follow-up).
4. `woodcase new`, or `add … document` creating the file.
5. An intentional-truncation mode so lint stays quiet on designed clips.
6. Tolerance in the clipped check for sub-point overflow.
7. Number-vs-string coercion for `kind.content` (it is always text).
8. Named text styles and a repeat/count on `cp`, so a screen can be built from verbs without a generator script.

## What I'd keep exactly as it is

The verb set, the no-daemon model, mandatory names, the per-line `apply` report, and the tone of the errors — they name the node, the id, the rect and the next command. Most of the session's friction was learning the file format, not learning the tool.
