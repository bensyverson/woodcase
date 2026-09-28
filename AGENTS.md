IMPORTANT: As you implement features, keep the [DocC documentation](./Sources/Woodcase/Documentation.docc/) up to date; update [README.md](README.md) only when a doc file is added or new users must know.

## Overview

You are working on Woodcase, a Swift library which allows users to parse and render Pen.dev [.pen](https://docs.pencil.dev/for-developers/the-pen-format) files. It is a cross-platform SwiftPM package: the document model, layout engine, variable resolution, code generation, and a reference CoreGraphics renderer. Penumbra (`../Penumbra/`, the macOS editor) and RapidPro (`../RapidPro/`, the Metal renderer) are sibling repos that consume it.

## Documentation

- [README.md](README.md) — project overview and quick start
- [DocC documentation](./Sources/Woodcase/Documentation.docc/) — in-depth documentation of the architecture, models and concepts; generated with `swift package generate-documentation --target Woodcase`
- [WoodcaseEditor.md](./Sources/Woodcase/Documentation.docc/WoodcaseEditor.md) — how to drive the `woodcase` CLI: the read–write–verify loop, addressing, property paths, batches, revision tokens and undo. Read it before editing a .pen file from a shell; `woodcase help design` is the same primer in the terminal
- [WoodcaseScripting.md](./Sources/Woodcase/Documentation.docc/WoodcaseScripting.md) — the JavaScript host: the contract a `woodcase js` program runs under, the TypeScript declaration of `doc`, the `ScriptHost` API a Swift caller uses, the watchdog and the platform boundary. Read it before touching `Sources/WoodcaseScripting/`, the `js` or `find` verbs; `woodcase help js` is the same contract in the terminal
- [DESIGN.md](DESIGN.md) — the viewer's design system (design.md format): tokens, color axes, typography, component atoms, do's and don'ts. Read it before styling anything in `WoodcaseViewer`; it must move together with `ViewerStylesheet.swift`
- [project/](project/) — dated design documents, findings and past plans
- [project/gotchas.md](project/gotchas.md) — project traps and rule feedback; read it at session start
- [project/backlog.md](project/backlog.md) — work decided against, and what would revive it
- [project/agents/harness.md](project/agents/harness.md) — facts about the agent harness (sandbox, `$TMPDIR`, worktrees)
- [project/agents/delegation.md](project/agents/delegation.md) — how to carve, brief and integrate subagent work
- [project/agents/jobs.md](project/agents/jobs.md) — the `job` tracker: tree shape, criteria, agent identities
- [project/agents/cli-design.md](project/agents/cli-design.md) — how to design a CLI for agents: grammar, output, exit codes, errors that teach

## Build and test

- `swift test --quiet` is the full suite; `swiftformat . --lint` (then `swiftformat .`) is the lint.
- **The pre-commit hook does not run the tests.** It formats staged Swift files and runs `scripts/mae-check`; run the suite yourself before every commit.
- The Swift toolchain fails inside the Bash sandbox (`sandbox_apply: Operation not permitted`); re-run `swift build`, `swift test` and `swiftformat` with the sandbox disabled, one call at a time — see `project/agents/harness.md`.
- If you change the React output format, regenerate the golden fixtures: `UPDATE_GOLDEN=1 swift test --filter "ReactEmitter.*Tests"` — component goldens live in `ReactEmitterTests`, page goldens in `ReactEmitterPageGoldenTests`, and `--filter` is a regex over the Swift type names, so `"ReactEmitterTests"` alone silently skips the pages. Read the rewritten goldens before committing them.

## Working with .pen files

- To look at a .pen file, read it directly (it's JSON) rather than using the Pencil MCP.
- The .pen format specification is at `./local/Pen-Format.md`; the schema is at `./local/Pen-Schema-2.17.md` — the app's own 2.17 schema, with a section on what Pen writes beyond it. Older copies: `./local/Pen-Schema.js` (2.10) and `./local/Pen-Schema-v2.js` (2.17 dev docs). Read them only when you need to.

<!-- agents:begin core@3a7a5e -->
## Working rules

**Understand the why.** If the goal behind a request isn't clear, ask before solving — beware the XY problem.

**Diverge, then converge.** First brainstorm options (create choices), weigh them against the user's goals, recommend one (make choices), confirm, then execute.

**Ambiguity.** If the *code* could go several ways, choose the idiomatic one for the language. If the *requirement* is ambiguous or the question is architectural, stop and ask — don't decide.

**Dependencies.** Avoid them unless re-implementing would be unreasonable; ask before adding one; each is security and maintenance surface.

**TDD, strictly red/green.** Write tests for every case and every new method first, watch them *all* fail, then implement. A test that is green during red tests nothing — remove or rewrite it. If an existing test must change to pass because the behavior or expectation has changed, explain why clearly. Every bug fix starts with a regression test.

**Plans and tasks live in `job`.** Open every session with `job orient` (no arguments), then read `project/gotchas.md` — while reading, prune it: delete any entry that's now fixed, obvious, or a general rule, marking it `rule:` first if it's general. Don't use Plan Mode or ad-hoc todo lists.

**Don't tour the codebase.** Start from the README and the docs (an Explore agent is fine); dig only where the task leads — once you have a specific need, read as much as that need requires.

**Scripts.** Analysis tooling goes in `scripts/` so it can be re-run — check there before writing one.

**Critique before declaring done.** Re-read the original request: is the need actually met? Do lint and tests pass? Are docs updated? What would an expert flag? Fix serious flaws before reporting.

**Tidiness.** No stray files in the repo root; delete transients, and file valuable artifacts (reports, scripts) where they belong.

**Documentation.** Keep the project docs current as you build. Touch the README only when a doc file is added or new users must know.

**Gotchas.** When a project quirk costs you time and no rule predicts it, append it to `project/gotchas.md`. If a rule in this file was wrong or misled you, record that there too, prefixed `rule:`.

**Where these rules come from.** The marked regions are generated and shared across repos via a CLI tool named `agents`; don't edit inside them. If a rule here is wrong or cost you time, say so in `project/gotchas.md` prefixed `rule:`; that is how shared rules get reviewed.

**Local rulings.** A repo-local ruling, or an override of a shared rule, lives in the project-owned head of `AGENTS.md`, above the generated regions — say plainly that it overrides, and link a dated project doc for the why.

## Git

- Offer to commit when a unit of work is complete and accepted. Rebase onto upstream; ask on real conflicts, explaining the conflict in plain terms first.
- Commit all uncommitted files together — later changes usually depend on earlier ones, and a half-working state helps nobody. Never amend.
- The subject completes "This commit…": present-tense verb first — "Adds…", "Fixes…", "Retires…". Detail goes in the body.
- Pass the message with `-F <file>`, not inline `-m`; the shell interprets `-m` first. Same for `job`: `note`, `done`, `add` and `edit` all take `-F <file>` (`-F -` reads stdin).
- Pre-commit hooks run the formatter and tests. Run them yourself first (see the stack rules).
- Never pipe a gating command (`git commit … | tail`) — the pipe swallows its exit status, so a following `&&` runs even after a failure.
<!-- agents:end core -->

<!-- agents:begin principles@7a5b19 -->
## Principles

Defaults, not laws. When we break one, we do it consciously and say so in the report and the docs.

- **Pragmatism.** Builders, not purists. Practical choices that serve the near-term goal and protect the long-term one.
- **Eat the frog.** No band-aids. Given an easy-but-compromised path and a correct one, take the correct one; fix problems at the source. Keep YAGNI in mind, but when a need is obvious, don't underdeliver.
- **Composability.** Simple, strong components composed into systems — never a monolith.
- **Library + thin executable.** Core logic in a library; the app or CLI is a light consumer, so the core can be reused elsewhere. An adapter that holds a decision rather than wiring one is a bug.
- **Decoupling.** Tight coupling makes testing, debugging and refactoring hard — separate concerns. Separating a model, its storage and its UI is the everyday case: databases and UI frameworks change; today's web app may grow a CLI or mobile app.
- **Just enough abstraction.** One layer around an LLM provider is prudent; a `TextGenerationProvider` above it is not.
- **Readable file sizes.** Aim for files a reader can hold in their head (a few hundred lines; ~400 is the comfortable ceiling). Past ~2k lines, navigation degrades and errors accumulate; splitting also makes functionality discoverable by filename.
- **Comments say why, not what.** Doc comments state *what* concisely; other comments only explain the non-obvious. No change history in comments. Most code needs none.
- **Strongly typed.** Prefer enums, named constants and config over magic strings and numbers; prefer typed structs over dictionaries, even for wire types. Two packages exchanging data across a serialization seam share **one** struct that both import, never a hand-written twin on each side — the type checker cannot see across encode/decode, and two definitions drift. Given a bool and a typed constant, take the typed constant: a bool named for one consequence gets reused to gate the others until it means several things, so name the underlying *fact* as a type and let the behaviors follow.
- **Previews.** Give each UI component a way to render in its various states — a SwiftUI `#Preview`, a demo page, a story — the foundation for tests and for human review.
- **Async by default.** Keep the app interactive during heavy work; surface loading and error states. On the web, prefer progressive enhancement over full reloads.
- **Event streams where they fit.** Append-only logs are auditable, undoable, and time-travelable.
<!-- agents:end principles -->

<!-- agents:begin stage-build@3d5d83 -->
## Stage: BUILD

Pre-launch, zero users, no existing data. Never spend effort on backward compatibility — assume every use is green-field — but flag breaking changes and update the affected tests. Be ambitious: if a feature is important, build it fully now rather than an MVP; balance that against over-engineering and future-proofing.
<!-- agents:end stage-build -->

<!-- agents:begin swift@d751b4 -->
## Swift

- Keep DocC coverage at 100% for any code you add or change.
- Before committing: `swiftformat . --lint` (then `swiftformat .` if needed) and the full suite (`swift test --quiet`, or the project's `xcodebuild` invocation named in the head). Both should be pre-commit hooks; if the repo has none, run them yourself.
- Swift 6 strict concurrency; resolve warnings as you go. No `nonisolated(unsafe)` without permission. Prefer async/await.
- Prefer `struct` for data; `final class` for durable shared-reference objects; `actor` for shared mutable state or a single access point (DB connection, queue).
- New types conform to `Friendly` (`Codable & Hashable & Equatable & Sendable`) even without current plans to serialize or compare.
- **Library packages are cross-platform by default**: stay in Foundation so they build on Linux; wrap Apple-only APIs in `@available` and cover at least macOS and iOS. App targets state their platforms in the head.
- Modern Swift Regex, not the legacy APIs.
- Help the type checker: annotate the type when an initializer's expression is generic, chained, or overloaded (`let output: String = …`), and spell out `Type(...)` rather than `.init(...)` where the type would otherwise be inferred — but where swiftformat's `redundantType` rule disagrees, the formatter's output is the rule.
- **One type per file.** Nest small enums/structs inside their owner. Extensions go in `BaseType+Purpose.swift` (third-party types too). A file over ~200–300 lines wants splitting (tighter than the general guidance, on purpose).
- Sources and Tests organized in folders, at most one level deep. New test suites (new struct) get their own file.
- **A new combined library + CLI package** `FooBar` = library target `FooBarCore` + CLI target `FooBarCommand`.
<!-- agents:end swift -->

<!-- agents:begin docs@7ba2fd -->
## Documentation practice

- **Plans, findings, designs and decisions go in `project/` as dated documents** (`YYYY-MM-DD-title.md`) — the written history of the project. They are point-in-time records: correct an earlier one *in place*, as a marked block quote, rather than silently editing a number or leaving a stale claim standing.
- **Every figure names the tool and flags that reproduce it.**
- **Work decided against goes in `project/backlog.md`**, not into silence: one dated H2 per item — what it is, why it's parked, and *what would un-park it*. Nothing there is scheduled or blocking; active work lives in `job`. Check it before proposing something that sounds novel.
- **When a finding overturns a premise, edit the premise.** Readers act on the title and opening; a correction appended underneath doesn't reach them.
- **A wrong documented cause is worse than none** — it stops the next reader looking. Correcting one means saying it was wrong, not quietly rewording.
- **Open the note before you cite it**, and check whether a recorded ruling has been superseded before passing it on.
- **Every repo has a README; if none exists, write one (delegate it if you can).** It is tight: the project's name and a one-line description a non-technical reader understands (6th-grade reading level); one short paragraph of what it is; how to install or consume it; a crisp Quick Start with an example or two; links out to the specific docs for anything more; authorship and license at the end.
- **The head of `AGENTS.md` lists where the docs live; keep that list current.**
<!-- agents:end docs -->

<!-- agents:begin index@6272fe -->
## Situational instructions

These files carry instructions for specific situations. When one applies, read the file before acting and follow it.

| Situation | File |
|---|---|
| The first time a tool call is refused or denied, and before briefing a subagent | `project/agents/harness.md` |
| Before dispatching any subagent | `project/agents/delegation.md` |
| Before filing or claiming work in job, and when running as a subagent | `project/agents/jobs.md` |
| Before building or extending a command-line tool | `project/agents/cli-design.md` |
<!-- agents:end index -->
